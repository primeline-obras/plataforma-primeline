-- PRIMELINE | Mapa de Gestão de Obras — lançamentos pagos detalhados
begin;

create or replace function public.fn_mapa_gestao_obras()
returns table (
  origem_id uuid,
  obra_id uuid,
  obra_numero text,
  obra_nome text,
  categoria text,
  data_lancamento date,
  entidade_nome text,
  descricao text,
  documento text,
  valor numeric
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_atual public.utilizadores;
  v_linha record;
  v_json jsonb;
  v_obra public.obras;
  v_sub public.subempreitadas;
  v_uuid uuid;
  v_nome text;
  v_data_text text;
  v_estado text;
begin
  if not (public.fn_e_admin() or public.fn_e_financeiro()) then
    raise exception 'O Mapa de Gestão de Obras está reservado à Gerência e ao Financeiro.';
  end if;

  select * into v_atual
  from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id()
    and coalesce(u.ativo, true);

  if not found then
    raise exception 'Utilizador autenticado sem perfil ativo.';
  end if;

  -- Materiais: usa lancamentos_materiais quando a tabela existe.
  if to_regclass('public.lancamentos_materiais') is not null then
    for v_linha in execute 'select to_jsonb(t) as dados from public.lancamentos_materiais t'
    loop
      v_json := v_linha.dados;
      v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
      if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
      if v_json ? 'pago' and lower(coalesce(v_json ->> 'pago', 'false')) not in ('true', 't', '1') then continue; end if;
      if v_json ? 'data_pagamento' and nullif(v_json ->> 'data_pagamento', '') is null then continue; end if;

      begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
      select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id;
      if not found then continue; end if;

      v_nome := null;
      begin
        v_uuid := nullif(v_json ->> 'fornecedor_id', '')::uuid;
        select f.nome into v_nome from public.fornecedores f where f.id = v_uuid;
      exception when others then v_nome := null; end;
      v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'data_fatura',''), nullif(v_json ->> 'criado_em',''));

      origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome;
      categoria := 'materiais'; data_lancamento := left(v_data_text, 10)::date; entidade_nome := coalesce(v_nome, v_json ->> 'fornecedor', 'Fornecedor não identificado');
      descricao := coalesce(v_json ->> 'designacao', v_json ->> 'descricao', 'Material'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
      valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, nullif(v_json ->> 'valor','')::numeric, nullif(v_json ->> 'total','')::numeric, 0); return next;
    end loop;
  else
    -- Compatibilidade com o fluxo atual, que regista materiais em faturas.
    for v_linha in
      select f.*, o.numero as numero_obra, o.nome as nome_obra, fr.nome as nome_fornecedor
      from public.faturas f
      join public.obras o on o.id = f.obra_id
      left join public.fornecedores fr on fr.id = f.fornecedor_id
      where o.empresa_id = v_atual.empresa_id
        and f.tipo_origem = 'material'
        and f.estado_pagamento = 'pago'
    loop
      origem_id := v_linha.id; obra_id := v_linha.obra_id; obra_numero := v_linha.numero_obra::text; obra_nome := v_linha.nome_obra;
      categoria := 'materiais'; data_lancamento := v_linha.data_pagamento; entidade_nome := coalesce(v_linha.nome_fornecedor, 'Fornecedor não identificado');
      descricao := 'Fatura de material'; documento := v_linha.numero_doc; valor := coalesce(v_linha.valor, 0); return next;
    end loop;
  end if;

  -- Despesas de estaleiro.
  for v_linha in execute 'select to_jsonb(t) as dados from public.despesas_estaleiro t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    if nullif(v_json ->> 'estado_aprovacao','') is not null and lower(v_json ->> 'estado_aprovacao') not in ('aprovado','aprovada') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
    select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null;
    begin v_uuid := nullif(v_json ->> 'fornecedor_id', '')::uuid; select f.nome into v_nome from public.fornecedores f where f.id = v_uuid; exception when others then v_nome := null; end;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'estaleiro';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, v_json ->> 'fornecedor', 'Estaleiro');
    descricao := coalesce(v_json ->> 'designacao', v_json ->> 'descricao', 'Despesa de estaleiro'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
    valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, nullif(v_json ->> 'valor','')::numeric, 0); return next;
  end loop;

  -- Pessoal em obra / mão de obra: cada lançamento é custo realizado.
  for v_linha in execute 'select to_jsonb(t) as dados from public.lancamentos_mao_obra t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'obra_id', '')::uuid; exception when others then continue; end;
    select * into v_obra from public.obras o where o.id = v_uuid and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null;
    begin v_uuid := nullif(v_json ->> 'colaborador_id', '')::uuid; select c.nome into v_nome from public.colaboradores c where c.id = v_uuid; exception when others then v_nome := null; end;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'mao_obra';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, 'Colaborador não identificado');
    descricao := concat_ws(' · ', nullif(v_json ->> 'horas','') || case when nullif(v_json ->> 'horas','') is not null then ' h' end, case when nullif(v_json ->> 'valor_hora','') is not null then nullif(v_json ->> 'valor_hora','') || ' €/h' end, nullif(v_json ->> 'percentual_afetacao','') || case when nullif(v_json ->> 'percentual_afetacao','') is not null then ' afetação' end);
    documento := null; valor := coalesce(nullif(v_json ->> 'valor_total','')::numeric, (nullif(v_json ->> 'horas','')::numeric * nullif(v_json ->> 'valor_hora','')::numeric), 0); return next;
  end loop;

  -- Pagamentos de subempreitadas.
  for v_linha in execute 'select to_jsonb(t) as dados from public.pagamentos_subempreitada t'
  loop
    v_json := v_linha.dados; v_estado := lower(coalesce(v_json ->> 'estado_pagamento', ''));
    if v_json ? 'estado_pagamento' and v_estado not in ('pago', 'paga') then continue; end if;
    if nullif(v_json ->> 'estado_aprovacao','') is not null and lower(v_json ->> 'estado_aprovacao') not in ('aprovado','aprovada') then continue; end if;
    begin v_uuid := nullif(v_json ->> 'subempreitada_id', '')::uuid; exception when others then continue; end;
    select * into v_sub from public.subempreitadas s where s.id = v_uuid; if not found then continue; end if;
    select * into v_obra from public.obras o where o.id = v_sub.obra_id and o.empresa_id = v_atual.empresa_id; if not found then continue; end if;
    v_nome := null; select f.nome into v_nome from public.fornecedores f where f.id = v_sub.fornecedor_id;
    v_data_text := coalesce(nullif(v_json ->> 'data_pagamento',''), nullif(v_json ->> 'data',''), nullif(v_json ->> 'criado_em',''));
    origem_id := (v_json ->> 'id')::uuid; obra_id := v_obra.id; obra_numero := v_obra.numero::text; obra_nome := v_obra.nome; categoria := 'subempreitadas';
    data_lancamento := left(v_data_text,10)::date; entidade_nome := coalesce(v_nome, 'Subempreiteiro não identificado');
    descricao := coalesce(v_sub.especialidade, v_json ->> 'descricao', 'Pagamento de subempreitada'); documento := coalesce(v_json ->> 'numero_doc', v_json ->> 'documento');
    valor := coalesce(nullif(v_json ->> 'valor','')::numeric, nullif(v_json ->> 'valor_total','')::numeric, 0); return next;
  end loop;

  -- Faturação emitida ao cliente: receita, recebida ou ainda por receber.
  for v_linha in
    select f.*, o.numero as numero_obra, o.nome as nome_obra
    from public.faturacao f
    join public.obras o on o.id=f.obra_id
    where o.empresa_id=v_atual.empresa_id
  loop
    origem_id:=v_linha.id; obra_id:=v_linha.obra_id; obra_numero:=v_linha.numero_obra::text; obra_nome:=v_linha.nome_obra;
    categoria:='faturacao'; data_lancamento:=coalesce(v_linha.data_recebimento,v_linha.data_emissao_fatura);
    entidade_nome:='Cliente'; descricao:=concat_ws(' · ','Emitida '||coalesce(v_linha.data_emissao_fatura::text,'—')||' · '||coalesce(v_linha.valor,0)::text||' €','Recebida '||coalesce(v_linha.data_recebimento::text,'—')||' · '||coalesce(v_linha.valor_recebido,0)::text||' €','Estado '||coalesce(v_linha.estado,'—'));
    documento:=v_linha.numero_fatura; valor:=coalesce(v_linha.valor_recebido,v_linha.valor,0); return next;
  end loop;
end;
$function$;

revoke all on function public.fn_mapa_gestao_obras() from public, anon;
grant execute on function public.fn_mapa_gestao_obras() to authenticated;

-- Insere apenas as chaves que realmente existem na tabela de destino. Assim a
-- importação continua compatível com instalações anteriores sem escrever em
-- colunas geradas, como valor_total da mão de obra.
create or replace function public.fn_mgo_inserir_json_compativel(p_tabela regclass,p_dados jsonb)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_colunas text; v_valores text; v_schema text; v_tabela text;
begin
  select n.nspname,c.relname into v_schema,v_tabela from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.oid=p_tabela;
  select string_agg(format('%I',col.column_name),',' order by col.ordinal_position),
         string_agg(format('nullif($1->>%L,'''')::%s',col.column_name,col.udt_name),',' order by col.ordinal_position)
  into v_colunas,v_valores
  from information_schema.columns col
  where col.table_schema=v_schema and col.table_name=v_tabela
    and col.column_name<>'id' and col.is_generated='NEVER' and col.is_identity='NO'
    and p_dados ? col.column_name and nullif(p_dados->>col.column_name,'') is not null;
  if v_colunas is null then raise exception 'Nenhuma coluna compatível para importar em %.',p_tabela; end if;
  execute format('insert into %s (%s) select %s',p_tabela,v_colunas,v_valores) using p_dados;
end;$function$;

revoke all on function public.fn_mgo_inserir_json_compativel(regclass,jsonb) from public,anon,authenticated;

create or replace function public.fn_importar_mapa_gestao(p_linhas jsonb,p_confirmar boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $function$
declare
  v_atual public.utilizadores; v_linha jsonb; v_obra public.obras; v_fornecedor public.fornecedores;
  v_colaborador public.colaboradores; v_sub public.subempreitadas; v_categoria text; v_documento text;
  v_entidade text; v_chave text; v_valor numeric; v_criar integer:=0; v_criados integer:=0;
  v_duplicados integer:=0; v_erros jsonb:='[]'::jsonb; v_chaves text[]:=array[]::text[];
  v_chaves_existentes text[]:=array[]::text[]; v_dados jsonb;
begin
  if not (public.fn_e_admin() or public.fn_e_financeiro()) then raise exception 'Sem permissão para importar o Mapa de Gestão.' using errcode='42501'; end if;
  select * into v_atual from public.utilizadores u where u.id=public.fn_utilizador_atual_id() and coalesce(u.ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  if jsonb_typeof(p_linhas)<>'array' then raise exception 'Formato de importação inválido.'; end if;

  -- Calcula o universo de duplicados uma única vez. Em ficheiros grandes isto
  -- evita executar o mapa completo novamente por cada linha importada.
  select coalesce(array_agg(lower(concat_ws('|',m.categoria,m.obra_id,
    coalesce(m.documento,m.data_lancamento::text,''),coalesce(m.entidade_nome,''),round(coalesce(m.valor,0),2)))),array[]::text[])
  into v_chaves_existentes
  from public.fn_mapa_gestao_obras() m;

  for v_linha in select value from jsonb_array_elements(p_linhas)
  loop
    v_categoria:=v_linha->>'categoria'; v_documento:=coalesce(v_linha->>'numero_documento',v_linha->>'numero_fatura');
    if regexp_replace(btrim(coalesce(v_linha->>'obra_numero','')), '^0+', '') in ('79','85','127') then
      v_erros:=v_erros||jsonb_build_array(format(
        'Linha %s: Obra %s não aceita importação por este caminho — usar Saldo de Abertura.',
        v_linha->>'linha',coalesce(v_linha->>'obra_numero','—')
      ));
      continue;
    end if;
    select * into v_obra from public.obras o where o.empresa_id=v_atual.empresa_id and o.numero::text=btrim(v_linha->>'obra_numero') limit 1;
    if not found then v_erros:=v_erros||jsonb_build_array(format('Linha %s: obra %s não encontrada.',v_linha->>'linha',coalesce(v_linha->>'obra_numero','—'))); continue; end if;

    if v_categoria='mao_obra' then
      select * into v_colaborador from public.colaboradores c where c.empresa_id=v_atual.empresa_id and lower(btrim(c.nome))=lower(btrim(v_linha->>'colaborador')) limit 1;
      if not found then v_erros:=v_erros||jsonb_build_array(format('Linha %s: colaborador %s não encontrado.',v_linha->>'linha',coalesce(v_linha->>'colaborador','—'))); continue; end if;
      if nullif(v_linha->>'data','') is null or nullif(v_linha->>'horas','') is null or nullif(v_linha->>'valor_hora','') is null then v_erros:=v_erros||jsonb_build_array(format('Linha %s: data, horas e valor/hora são obrigatórios.',v_linha->>'linha')); continue; end if;
      v_entidade:=v_colaborador.nome; v_valor:=(v_linha->>'horas')::numeric*(v_linha->>'valor_hora')::numeric; v_documento:=v_linha->>'data';
    elsif v_categoria='faturacao' then
      if nullif(v_documento,'') is null or nullif(v_linha->>'data_emissao','') is null or nullif(v_linha->>'valor','') is null then v_erros:=v_erros||jsonb_build_array(format('Linha %s: nº fatura, data de emissão e valor são obrigatórios.',v_linha->>'linha')); continue; end if;
      v_entidade:='Cliente'; v_valor:=coalesce(nullif(v_linha->>'valor_recebido','')::numeric,(v_linha->>'valor')::numeric);
    else
      if v_categoria not in ('materiais','estaleiro','subempreitadas') then v_erros:=v_erros||jsonb_build_array(format('Linha %s: categoria inválida.',v_linha->>'linha')); continue; end if;
      select * into v_fornecedor from public.fornecedores f where f.empresa_id=v_atual.empresa_id and lower(btrim(f.nome))=lower(btrim(v_linha->>'fornecedor')) limit 1;
      if not found then v_erros:=v_erros||jsonb_build_array(format('Linha %s: fornecedor %s não encontrado.',v_linha->>'linha',coalesce(v_linha->>'fornecedor','—'))); continue; end if;
      if nullif(v_documento,'') is null or nullif(v_linha->>'valor_total','') is null then v_erros:=v_erros||jsonb_build_array(format('Linha %s: documento e valor total são obrigatórios.',v_linha->>'linha')); continue; end if;
      v_entidade:=v_fornecedor.nome; v_valor:=(v_linha->>'valor_total')::numeric;
    end if;

    v_chave:=lower(concat_ws('|',v_categoria,v_obra.id,v_documento,v_entidade,round(v_valor,2)));
    if v_chave=any(v_chaves) or v_chave=any(v_chaves_existentes) then
      v_duplicados:=v_duplicados+1; continue;
    end if;
    v_chaves:=array_append(v_chaves,v_chave); v_criar:=v_criar+1;
    if not p_confirmar then continue; end if;

    if v_categoria='mao_obra' then
      v_dados:=jsonb_build_object('empresa_id',v_atual.empresa_id,'obra_id',v_obra.id,'colaborador_id',v_colaborador.id,'data',v_linha->>'data','horas',v_linha->>'horas','valor_hora',v_linha->>'valor_hora','criado_por',v_atual.id);
      perform public.fn_mgo_inserir_json_compativel('public.lancamentos_mao_obra'::regclass,v_dados);
    elsif v_categoria='faturacao' then
      v_dados:=jsonb_build_object('empresa_id',v_atual.empresa_id,'obra_id',v_obra.id,'numero_fatura',v_documento,'data_emissao_fatura',v_linha->>'data_emissao','valor',v_linha->>'valor','data_recebimento',v_linha->>'data_recebimento','valor_recebido',v_linha->>'valor_recebido','estado',coalesce(nullif(v_linha->>'estado',''),'recebida'));
      perform public.fn_mgo_inserir_json_compativel('public.faturacao'::regclass,v_dados);
    elsif v_categoria='subempreitadas' then
      select * into v_sub from public.subempreitadas s where s.obra_id=v_obra.id and s.fornecedor_id=v_fornecedor.id order by s.criado_em desc limit 1;
      if not found then raise exception 'Não existe subcontrato da obra % para o fornecedor %.',v_obra.numero,v_fornecedor.nome; end if;
      v_dados:=jsonb_build_object('empresa_id',v_atual.empresa_id,'subempreitada_id',v_sub.id,'numero_doc',v_documento,'documento',v_documento,'data',v_linha->>'data','data_pagamento',v_linha->>'data_pagamento','valor',v_valor,'valor_total',v_valor,'estado_aprovacao','aprovado','estado_pagamento','pago','criado_por',v_atual.id);
      perform public.fn_mgo_inserir_json_compativel('public.pagamentos_subempreitada'::regclass,v_dados);
    else
      v_dados:=jsonb_build_object('empresa_id',v_atual.empresa_id,'obra_id',v_obra.id,'fornecedor_id',v_fornecedor.id,'numero_doc',v_documento,'documento',v_documento,'data',v_linha->>'data','fornecedor',v_fornecedor.nome,'designacao',v_linha->>'designacao','descricao',v_linha->>'designacao','unidade',v_linha->>'unidade','quantidade',v_linha->>'quantidade','valor_unitario',v_linha->>'valor_unitario','valor_total',v_valor,'valor',v_valor,'data_pagamento',v_linha->>'data_pagamento','estado_aprovacao','aprovado','estado_pagamento','pago','criado_por',v_atual.id);
      perform public.fn_mgo_inserir_json_compativel(case when v_categoria='materiais' then 'public.lancamentos_materiais'::regclass else 'public.despesas_estaleiro'::regclass end,v_dados);
    end if;
    v_criados:=v_criados+1;
  end loop;
  if p_confirmar and jsonb_array_length(v_erros)>0 then raise exception 'Importação cancelada: %',v_erros::text; end if;
  return jsonb_build_object('linhas',jsonb_array_length(p_linhas),'criar',v_criar,'criados',v_criados,'duplicados',v_duplicados,'erros',v_erros);
end;$function$;

revoke all on function public.fn_importar_mapa_gestao(jsonb,boolean) from public,anon;
grant execute on function public.fn_importar_mapa_gestao(jsonb,boolean) to authenticated;

commit;

select
  to_regprocedure('public.fn_mapa_gestao_obras()') is not null as rpc_mapa_gestao,
  to_regprocedure('public.fn_importar_mapa_gestao(jsonb,boolean)') is not null as rpc_importacao_mgo,
  to_regclass('public.lancamentos_materiais') is not null as tabela_lancamentos_materiais;
