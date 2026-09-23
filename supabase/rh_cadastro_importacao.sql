-- Aplicar antes do frontend. Não preenche nem altera cadastros existentes.
begin;
create table if not exists public.colaboradores_rh_privado (
  colaborador_id uuid primary key references public.colaboradores(id),
  niss text check (niss is null or niss ~ '^[0-9]{11}$')
);
alter table public.colaboradores_rh_privado enable row level security;
revoke all on public.colaboradores_rh_privado from anon, authenticated;
create table if not exists public.rh_cadastro_auditoria (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  colaborador_id uuid not null references public.colaboradores(id),
  utilizador_id uuid not null references public.utilizadores(id),
  criado_em timestamptz not null default now(), origem text not null,
  antes jsonb, depois jsonb
);
alter table public.rh_cadastro_auditoria enable row level security;
revoke all on public.rh_cadastro_auditoria from anon, authenticated;

create or replace function public.fn_rh_empresa(p_importacao boolean default false)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa uuid;
begin
  select empresa_id into v_empresa from public.utilizadores
  where id=public.fn_utilizador_atual_id() and ativo is true
    and case when p_importacao then funcao='gestao_plataforma'
      else funcao in ('gestao_plataforma','gerencia','administrativo') end;
  if v_empresa is null then raise exception 'Sem permissão para gerir estes dados de RH.'; end if;
  return v_empresa;
end $$;

create or replace function public.fn_rh_consultar(p_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa uuid:=public.fn_rh_empresa(); v_result jsonb;
begin
  select coalesce(jsonb_agg(dados||jsonb_build_object('versao',md5(dados::text)) order by nome),'[]')
  into v_result from (
    select c.nome,jsonb_build_object('colaborador',to_jsonb(c),'niss',r.niss,'contratos',
      coalesce((select jsonb_agg(to_jsonb(cc) order by cc.data_inicio,cc.id)
        from public.colaboradores_contratos cc where cc.colaborador_id=c.id),'[]')) dados
    from public.colaboradores c left join public.colaboradores_rh_privado r on r.colaborador_id=c.id
    where c.empresa_id=v_empresa and (p_id is null or c.id=p_id)
  ) s;
  return v_result;
end $$;

create or replace function public.fn_rh_guardar(p_dados jsonb,p_simular boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_empresa uuid:=public.fn_rh_empresa(); v_id uuid:=nullif(p_dados->>'id','')::uuid;
  v_antes jsonb; v_patch jsonb:=coalesce(p_dados->'campos','{}'); v_result jsonb;
  v_c public.colaboradores%rowtype; v_ct public.colaboradores_contratos%rowtype;
  v_cp jsonb:=p_dados->'contrato'; v_niss text; v_count integer; v_alterado boolean;
  v_novo boolean:=v_id is null; v_original_ct jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('rh:'||v_empresa::text,0));
  if jsonb_typeof(v_patch) is distinct from 'object' then raise exception 'Campos inválidos.'; end if;
  if exists(select 1 from jsonb_object_keys(v_patch) k where k not in
    ('nome','funcao','nivel','valor_hora','nif','email','contacto','morada','data_admissao',
     'data_nascimento','data_saida','codigo_rh','observacoes','seguranca_social_ok','seguro_ok','registo_trabalhador_ok')) then
    raise exception 'Campos de RH desconhecidos.';
  end if;
  if not v_novo then
    perform 1 from public.colaboradores where id=v_id and empresa_id=v_empresa for update;
    if not found then raise exception 'Colaborador não encontrado nesta empresa.'; end if;
    perform 1 from public.colaboradores_contratos where colaborador_id=v_id for update;
    v_antes:=public.fn_rh_consultar(v_id)->0;
  end if;
  v_c:=jsonb_populate_record(null::public.colaboradores,coalesce(v_antes->'colaborador','{}')||v_patch);
  if nullif(btrim(v_c.nome),'') is null or nullif(btrim(v_c.funcao),'') is null or v_c.data_admissao is null then
    raise exception 'Nome, função e admissão são obrigatórios.';
  end if;
  if v_c.valor_hora<0 then raise exception 'Valor/hora não pode ser negativo.'; end if;
  if v_c.data_saida<v_c.data_admissao or v_c.data_nascimento>v_c.data_admissao then raise exception 'Datas incompatíveis.'; end if;
  if nullif(v_c.nif,'') is not null and v_c.nif !~ '^[0-9]{9}$' then raise exception 'NIF deve ter 9 algarismos.'; end if;
  if nullif(v_c.email,'') is not null and v_c.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email inválido.'; end if;
  if exists(select 1 from public.colaboradores c where c.empresa_id=v_empresa and c.id is distinct from v_id
    and ((nullif(v_c.nif,'') is not null and c.nif=v_c.nif) or
      (nullif(v_c.codigo_rh,'') is not null and c.codigo_rh=v_c.codigo_rh))) then
    raise exception 'NIF ou código RH já pertence a outro colaborador.';
  end if;
  v_niss:=case when p_dados ? 'niss' then nullif(p_dados->>'niss','') else v_antes->>'niss' end;
  if v_niss is not null and v_niss !~ '^[0-9]{11}$' then raise exception 'NISS deve ter 11 algarismos.'; end if;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if jsonb_typeof(v_cp)<>'object' then raise exception 'Contrato inválido.'; end if;
    if exists(select 1 from jsonb_object_keys(v_cp) k where k not in ('tipo_contrato','data_inicio','data_fim_prevista')) then
      raise exception 'Campos de contrato desconhecidos.';
    end if;
    select count(*) into v_count from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    if v_count>1 then raise exception 'Existem vários contratos ativos; rever antes de editar.'; end if;
    select * into v_ct from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    v_original_ct:=to_jsonb(v_ct);
    v_ct:=jsonb_populate_record(v_ct,v_cp);
    if v_ct.tipo_contrato is null or v_ct.tipo_contrato not in ('a_prazo','tempo_indeterminado') or v_ct.data_inicio is null then
      raise exception 'Tipo e início do contrato são obrigatórios.';
    end if;
    if v_ct.tipo_contrato='a_prazo' and v_ct.data_fim_prevista is null then raise exception 'Indique o fim previsto.'; end if;
    if v_ct.tipo_contrato='tempo_indeterminado' and v_ct.data_fim_prevista is not null then raise exception 'Tempo indeterminado não tem fim previsto.'; end if;
    if v_ct.data_fim_prevista<v_ct.data_inicio then raise exception 'Fim contratual anterior ao início.'; end if;
  end if;
  v_alterado:=v_novo or to_jsonb(v_c) is distinct from v_antes->'colaborador'
    or v_niss is distinct from v_antes->>'niss'
    or (v_cp is not null and v_cp<>'null'::jsonb and to_jsonb(v_ct) is distinct from v_original_ct);
  -- Reimportar o mesmo conteúdo é um no-op, mesmo com a versão antiga do Excel.
  if not v_novo and v_alterado and p_dados->>'versao' is distinct from v_antes->>'versao' then
    raise exception 'Cadastro alterado entretanto. Reabra ou exporte novamente o modelo.';
  end if;
  if v_novo then
    if coalesce(p_dados->>'alocacao_tipo','') not in ('obra','escritorio') then raise exception 'Indique a alocação inicial.'; end if;
    if p_dados->>'alocacao_tipo'='obra' and not exists(select 1 from public.obras
      where id=nullif(p_dados->>'obra_id','')::uuid and empresa_id=v_empresa and situacao in ('preparacao','em_curso')) then
      raise exception 'Selecione uma obra ativa da empresa.';
    end if;
    if p_dados->>'alocacao_tipo'='escritorio' and nullif(p_dados->>'obra_id','') is not null then raise exception 'Escritório não tem obra.'; end if;
    perform nullif(p_dados->>'epi_data','')::date;
    perform nullif(p_dados->>'medicina_data','')::date;
  end if;
  if p_simular or not v_alterado then return jsonb_build_object('alterado',v_alterado,'id',v_id); end if;
  if v_novo then
    v_id:=(public.fn_criar_colaborador_com_alocacao(v_c.nome,v_c.funcao,v_c.data_admissao,v_c.data_nascimento,
      p_dados->>'alocacao_tipo',nullif(p_dados->>'obra_id','')::uuid,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada)
      ->'colaborador'->>'id')::uuid;
  end if;
  update public.colaboradores set nome=v_c.nome,funcao=v_c.funcao,nivel=v_c.nivel,valor_hora=v_c.valor_hora,
    nif=v_c.nif,email=v_c.email,contacto=v_c.contacto,morada=v_c.morada,data_admissao=v_c.data_admissao,
    data_nascimento=v_c.data_nascimento,data_saida=v_c.data_saida,codigo_rh=v_c.codigo_rh,observacoes=v_c.observacoes,
    seguranca_social_ok=v_c.seguranca_social_ok,seguro_ok=v_c.seguro_ok,registo_trabalhador_ok=v_c.registo_trabalhador_ok
    where id=v_id and empresa_id=v_empresa;
  if v_novo then
    if nullif(p_dados->>'epi_data','') is not null then
      insert into public.epis(colaborador_id,tipo_epi,data_entrega,data_validade)
      values(v_id,'Entrega inicial',(p_dados->>'epi_data')::date,null);
    end if;
    if nullif(p_dados->>'medicina_data','') is not null then
      insert into public.medicina_trabalho(colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta)
      values(v_id,(p_dados->>'medicina_data')::date,'Consulta inicial registada na admissão',null);
    end if;
  elsif (v_antes->'colaborador'->>'data_saida') is distinct from v_c.data_saida::text then
    perform public.fn_atualizar_colaborador_ciclo_vida(v_id,v_c.nome,v_c.funcao,v_c.data_admissao,
      v_c.data_nascimento,v_c.data_saida,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada);
  end if;
  insert into public.colaboradores_rh_privado(colaborador_id,niss) values(v_id,v_niss)
    on conflict(colaborador_id) do update set niss=excluded.niss;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if v_ct.id is null then
      insert into public.colaboradores_contratos(colaborador_id,tipo_contrato,data_inicio,data_fim_prevista,estado)
      values(v_id,v_ct.tipo_contrato,v_ct.data_inicio,v_ct.data_fim_prevista,'ativo');
    else
      update public.colaboradores_contratos set tipo_contrato=v_ct.tipo_contrato,data_inicio=v_ct.data_inicio,
        data_fim_prevista=v_ct.data_fim_prevista where id=v_ct.id;
    end if;
  end if;
  v_result:=public.fn_rh_consultar(v_id)->0;
  insert into public.rh_cadastro_auditoria(empresa_id,colaborador_id,utilizador_id,origem,antes,depois)
    values(v_empresa,v_id,public.fn_utilizador_atual_id(),'cadastro',v_antes,v_result);
  return jsonb_build_object('alterado',true,'id',v_id);
end $$;

create or replace function public.fn_rh_importar(p_linhas jsonb,p_confirmar boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_empresa uuid:=public.fn_rh_empresa(true); v_row jsonb; v_result jsonb:='[]';
  v_validado jsonb; v_erros integer:=0; v_seen uuid[]:='{}'; v_id uuid; v_patch jsonb;
begin
  p_confirmar:=coalesce(p_confirmar,false);
  if jsonb_typeof(p_linhas) is distinct from 'array' then raise exception 'Lista inválida.'; end if;
  if octet_length(p_linhas::text)>4194304 then raise exception 'Lote demasiado grande (máximo 4 MB).'; end if;
  if jsonb_array_length(p_linhas) not between 1 and 1000 then raise exception 'Importe entre 1 e 1000 linhas.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('rh:'||v_empresa::text,0));
  for v_row in select value from jsonb_array_elements(p_linhas) loop
    begin
      v_id:=nullif(v_row->>'id','')::uuid;
      if v_id is null or v_id=any(v_seen) then raise exception 'ID ausente ou repetido.'; end if;
      v_seen:=array_append(v_seen,v_id);
      if coalesce(v_row->'campos','{}') ? 'data_saida' then raise exception 'Excel não altera ativo/inativo.'; end if;
      select coalesce(jsonb_object_agg(key,value),'{}') into v_patch from jsonb_each(coalesce(v_row->'campos','{}'))
        where value<>'null'::jsonb and btrim(value#>>'{}')<>'';
      v_row:=v_row||jsonb_build_object('campos',v_patch);
      if coalesce(v_row->>'niss','')='' then v_row:=v_row-'niss'; end if;
      if jsonb_typeof(v_row->'contrato')='object' then
        select coalesce(jsonb_object_agg(key,value),'{}') into v_patch from jsonb_each(v_row->'contrato')
          where value<>'null'::jsonb and btrim(value#>>'{}')<>'';
        v_row:=v_row-'contrato';
        if v_patch<>'{}'::jsonb then v_row:=v_row||jsonb_build_object('contrato',v_patch); end if;
      end if;
      v_validado:=public.fn_rh_guardar(v_row,not p_confirmar);
      v_result:=v_result||jsonb_build_array(v_validado||jsonb_build_object('id',v_id,'ok',true));
    exception when others then
      v_erros:=v_erros+1;
      v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_row->>'id','ok',false,'erro',sqlerrm));
    end;
  end loop;
  if p_confirmar and v_erros>0 then raise exception 'Lote cancelado; nenhuma alteração guardada. %',v_result; end if;
  return jsonb_build_object('linhas',v_result,'erros',v_erros,'confirmado',p_confirmar);
end $$;
revoke all on function public.fn_rh_empresa(boolean),public.fn_rh_consultar(uuid),
  public.fn_rh_guardar(jsonb,boolean),public.fn_rh_importar(jsonb,boolean) from public,anon;
grant execute on function public.fn_rh_consultar(uuid),public.fn_rh_guardar(jsonb,boolean),
  public.fn_rh_importar(jsonb,boolean) to authenticated;
commit;

select
  to_regprocedure('public.fn_rh_consultar(uuid)') is not null as consulta_rh_ativa,
  to_regprocedure('public.fn_rh_guardar(jsonb,boolean)') is not null as cadastro_rh_unificado,
  to_regprocedure('public.fn_rh_importar(jsonb,boolean)') is not null as importacao_rh_ativa;
