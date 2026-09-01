-- PRIMELINE | Gestão da Plataforma + Mapa consolidado + 0_Orçamento por fase
-- Migração aditiva. Não elimina lançamentos históricos.
begin;

-- 1. Papel próprio de administração integral da plataforma.
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid='public.utilizadores'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%funcao%'
  loop execute format('alter table public.utilizadores drop constraint %I',r.conname); end loop;
end $$;

alter table public.utilizadores add constraint utilizadores_funcao_check check (funcao in (
  'gestao_plataforma','gerencia','administrativo','financeiro','diretor_obra','adjunto','preparador','encarregado'
));

create or replace function public.fn_e_gestao_plataforma()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.utilizadores u
    where u.id=public.fn_utilizador_atual_id() and u.funcao='gestao_plataforma' and coalesce(u.ativo,true));
$$;

create or replace function public.fn_e_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select public.fn_e_gestao_plataforma()
    or exists(select 1 from public.administradores_plataforma a join public.utilizadores u on u.id=a.utilizador_id
      where a.utilizador_id=public.fn_utilizador_atual_id() and coalesce(u.ativo,true))
    or exists(select 1 from public.utilizadores u
      where u.id=public.fn_utilizador_atual_id() and u.funcao='gerencia' and coalesce(u.ativo,true));
$$;

revoke all on function public.fn_e_gestao_plataforma() from public,anon;
grant execute on function public.fn_e_gestao_plataforma() to authenticated;

update public.utilizadores set ativo=true,funcao='gestao_plataforma'
where lower(email)='primeline.gestao@gmail.com';

insert into public.administradores_plataforma(utilizador_id)
select id from public.utilizadores u where lower(u.email)='primeline.gestao@gmail.com'
  and not exists(select 1 from public.administradores_plataforma a where a.utilizador_id=u.id);

-- 2. Mapa consolidado: leitura técnica global; escrita apenas Administrativo/Gestão da Plataforma.
create or replace function public.fn_pode_ver_mapa_gestao_obras()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
    and coalesce(u.ativo,true) and u.funcao in ('gestao_plataforma','administrativo','diretor_obra','adjunto','preparador'));
$$;

create or replace function public.fn_pode_editar_mapa_gestao_obras()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
    and coalesce(u.ativo,true) and u.funcao in ('gestao_plataforma','administrativo'));
$$;

revoke all on function public.fn_pode_ver_mapa_gestao_obras() from public,anon;
revoke all on function public.fn_pode_editar_mapa_gestao_obras() from public,anon;
grant execute on function public.fn_pode_ver_mapa_gestao_obras() to authenticated;
grant execute on function public.fn_pode_editar_mapa_gestao_obras() to authenticated;

-- Conserva a lógica histórica já publicada, alterando somente a guarda de acesso.
do $$
declare original text; adjusted text;
begin
  select pg_get_functiondef('public.fn_mapa_gestao_obras()'::regprocedure) into original;
  adjusted:=replace(original,
    'if not (public.fn_e_admin() or public.fn_e_financeiro()) then
    raise exception ''O Mapa de Gestão de Obras está reservado à Gerência e ao Financeiro.'';
  end if;',
    'if not public.fn_pode_ver_mapa_gestao_obras() then
    raise exception ''Sem acesso ao Mapa de Gestão de Obras.'' using errcode = ''42501'';
  end if;');
  if adjusted=original then raise exception 'Não foi possível atualizar a guarda da função fn_mapa_gestao_obras.'; end if;
  execute adjusted;
end $$;

create table if not exists public.gestao_obras_lancamentos(
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete restrict,
  categoria text not null check(categoria in ('materiais','mao_obra','estaleiro')),
  data_lancamento date not null,
  entidade_nome text not null check(length(btrim(entidade_nome))>0),
  descricao text not null check(length(btrim(descricao))>0),
  documento text,
  valor numeric not null check(valor>=0),
  criado_por uuid not null default public.fn_utilizador_atual_id() references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  atualizado_por uuid references public.utilizadores(id),
  atualizado_em timestamptz not null default now()
);
create index if not exists gestao_obras_lancamentos_filtros_idx on public.gestao_obras_lancamentos(obra_id,categoria,data_lancamento desc);
alter table public.gestao_obras_lancamentos enable row level security;
revoke all on public.gestao_obras_lancamentos from anon;
grant select on public.gestao_obras_lancamentos to authenticated;
drop policy if exists gestao_obras_lancamentos_select on public.gestao_obras_lancamentos;
create policy gestao_obras_lancamentos_select on public.gestao_obras_lancamentos for select to authenticated
using(public.fn_pode_ver_mapa_gestao_obras());

create or replace function public.fn_guardar_lancamento_gestao_obras(
  p_id uuid,p_obra_id uuid,p_categoria text,p_data_lancamento date,p_entidade_nome text,p_descricao text,p_documento text,p_valor numeric
) returns public.gestao_obras_lancamentos language plpgsql security definer set search_path=public,pg_temp as $$
declare row_out public.gestao_obras_lancamentos;
begin
  if not public.fn_pode_editar_mapa_gestao_obras() then raise exception 'Só o Administrativo e a Gestão da Plataforma podem alterar lançamentos.' using errcode='42501'; end if;
  if p_categoria not in ('materiais','mao_obra','estaleiro') then raise exception 'Categoria não editável neste ecrã.'; end if;
  if not exists(select 1 from public.obras where id=p_obra_id) then raise exception 'Obra não encontrada.'; end if;
  if p_id is null then
    insert into public.gestao_obras_lancamentos(obra_id,categoria,data_lancamento,entidade_nome,descricao,documento,valor)
    values(p_obra_id,p_categoria,p_data_lancamento,btrim(p_entidade_nome),btrim(p_descricao),nullif(btrim(p_documento),''),greatest(coalesce(p_valor,0),0)) returning * into row_out;
  else
    update public.gestao_obras_lancamentos set obra_id=p_obra_id,categoria=p_categoria,data_lancamento=p_data_lancamento,
      entidade_nome=btrim(p_entidade_nome),descricao=btrim(p_descricao),documento=nullif(btrim(p_documento),''),valor=greatest(coalesce(p_valor,0),0),
      atualizado_por=public.fn_utilizador_atual_id(),atualizado_em=now() where id=p_id returning * into row_out;
    if not found then raise exception 'Lançamento não encontrado.'; end if;
  end if;
  return row_out;
end $$;

create or replace function public.fn_apagar_lancamento_gestao_obras(p_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare deleted_id uuid;
begin
  if not public.fn_pode_editar_mapa_gestao_obras() then raise exception 'Sem permissão para apagar este lançamento.' using errcode='42501'; end if;
  delete from public.gestao_obras_lancamentos where id=p_id returning id into deleted_id;
  if deleted_id is null then raise exception 'Lançamento não encontrado.'; end if;
  return deleted_id;
end $$;
revoke all on function public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,numeric) from public,anon;
revoke all on function public.fn_apagar_lancamento_gestao_obras(uuid) from public,anon;
grant execute on function public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,numeric) to authenticated;
grant execute on function public.fn_apagar_lancamento_gestao_obras(uuid) to authenticated;

-- 3. Fonte PL ao nível da fase, espelhando a estrutura da folha 0_Orçamento.
create table if not exists public.orcamento_fases(
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  fase_id uuid not null references public.fases(id) on delete cascade,
  descricao text,
  venda_prevista numeric not null default 0 check(venda_prevista>=0),
  custo_total_estimado numeric not null default 0 check(custo_total_estimado>=0),
  margem_prevista numeric not null default 0,
  deslocacoes numeric not null default 0 check(deslocacoes>=0),
  mao_obra numeric not null default 0 check(mao_obra>=0),
  maquinas numeric not null default 0 check(maquinas>=0),
  materiais numeric not null default 0 check(materiais>=0),
  mao_obra_sub numeric not null default 0 check(mao_obra_sub>=0),
  subempreitada numeric not null default 0 check(subempreitada>=0),
  estado_custo text not null default 'orcamentado_nao_comprometido' check(estado_custo in ('orcamentado_nao_comprometido','em_consulta','adjudicado','em_execucao','concluido','cancelado')),
  valor_real_pl numeric check(valor_real_pl is null or valor_real_pl>=0),
  nome_ficheiro_origem text,
  importado_por uuid references public.utilizadores(id),
  importado_em timestamptz not null default now(),
  concluido_por uuid references public.utilizadores(id),
  concluido_em timestamptz,
  unique(fase_id)
);
alter table public.orcamento_fases enable row level security;
revoke all on public.orcamento_fases from anon;
grant select on public.orcamento_fases to authenticated;
drop policy if exists orcamento_fases_select on public.orcamento_fases;
create policy orcamento_fases_select on public.orcamento_fases for select to authenticated using(public.fn_pode_ver_obra(obra_id) or public.fn_e_admin());

create or replace function public.fn_importar_orcamento_fases(p_obra_id uuid,p_linhas jsonb,p_nome_ficheiro text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare linha jsonb; total integer:=0; fase_obra uuid;
begin
  if not (public.fn_e_gestao_plataforma() or public.fn_e_diretor_obra(p_obra_id)) then raise exception 'Importação reservada à Gestão da Plataforma ou Diretor de Obra.' using errcode='42501'; end if;
  for linha in select * from jsonb_array_elements(coalesce(p_linhas,'[]'::jsonb)) loop
    select obra_id into fase_obra from public.fases where id=(linha->>'fase_id')::uuid;
    if fase_obra is distinct from p_obra_id then raise exception 'A fase indicada não pertence à obra.'; end if;
    insert into public.orcamento_fases(obra_id,fase_id,descricao,venda_prevista,custo_total_estimado,margem_prevista,deslocacoes,mao_obra,maquinas,materiais,mao_obra_sub,subempreitada,nome_ficheiro_origem,importado_por,importado_em)
    values(p_obra_id,(linha->>'fase_id')::uuid,linha->>'descricao',coalesce((linha->>'venda_prevista')::numeric,0),coalesce((linha->>'custo_total_estimado')::numeric,0),coalesce((linha->>'margem_prevista')::numeric,0),coalesce((linha->>'deslocacoes')::numeric,0),coalesce((linha->>'mao_obra')::numeric,0),coalesce((linha->>'maquinas')::numeric,0),coalesce((linha->>'materiais')::numeric,0),coalesce((linha->>'mao_obra_sub')::numeric,0),coalesce((linha->>'subempreitada')::numeric,0),p_nome_ficheiro,public.fn_utilizador_atual_id(),now())
    on conflict(fase_id) do update set descricao=excluded.descricao,venda_prevista=excluded.venda_prevista,custo_total_estimado=excluded.custo_total_estimado,margem_prevista=excluded.margem_prevista,deslocacoes=excluded.deslocacoes,mao_obra=excluded.mao_obra,maquinas=excluded.maquinas,materiais=excluded.materiais,mao_obra_sub=excluded.mao_obra_sub,subempreitada=excluded.subempreitada,nome_ficheiro_origem=excluded.nome_ficheiro_origem,importado_por=excluded.importado_por,importado_em=now();
    total:=total+1;
  end loop;
  return jsonb_build_object('importadas',total);
end $$;

create or replace function public.fn_concluir_custo_pl_fase(p_orcamento_fase_id uuid,p_valor_real numeric default null)
returns public.orcamento_fases language plpgsql security definer set search_path=public,pg_temp as $$
declare row_out public.orcamento_fases;
begin
  select * into row_out from public.orcamento_fases where id=p_orcamento_fase_id;
  if not found then raise exception 'Orçamento de fase não encontrado.'; end if;
  if not (public.fn_e_gestao_plataforma() or public.fn_e_diretor_obra(row_out.obra_id)) then raise exception 'Conclusão reservada à Gestão da Plataforma ou Diretor de Obra.' using errcode='42501'; end if;
  update public.orcamento_fases set valor_real_pl=greatest(coalesce(p_valor_real,custo_total_estimado),0),estado_custo='concluido',concluido_por=public.fn_utilizador_atual_id(),concluido_em=now()
  where id=p_orcamento_fase_id returning * into row_out; return row_out;
end $$;
revoke all on function public.fn_importar_orcamento_fases(uuid,jsonb,text) from public,anon;
revoke all on function public.fn_concluir_custo_pl_fase(uuid,numeric) from public,anon;
grant execute on function public.fn_importar_orcamento_fases(uuid,jsonb,text) to authenticated;
grant execute on function public.fn_concluir_custo_pl_fase(uuid,numeric) to authenticated;

-- O resumo usa 0_Orçamento quando a fase foi importada; componentes antigos permanecem como fallback.
create or replace function public.fn_resumo_custos_obra(p_obra_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_real_pl numeric:=0;v_real_sub numeric:=0;v_est_pl numeric:=0;v_est_sub numeric:=0;v_comp_sub numeric:=0;v_adjudicado numeric:=0;
  v_componentes jsonb:='[]';v_ajustes jsonb:='[]';v_ajustes_total numeric:=0;v_faturado_cliente numeric:=0;v_venda numeric:=0;
begin
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_administrativo() or public.fn_e_financeiro()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  select coalesce(sum(case when estado_custo='concluido' then coalesce(valor_real_pl,custo_total_estimado) else 0 end),0),
    coalesce(sum(case when estado_custo not in ('concluido','cancelado') then custo_total_estimado else 0 end),0)
  into v_real_pl,v_est_pl from public.orcamento_fases where obra_id=p_obra_id;
  select v_real_pl+coalesce(sum(case when c.estado_custo='concluido' then coalesce(c.valor_real_pl,c.valor_orcamentado) else 0 end),0),
    v_est_pl+coalesce(sum(case when c.estado_custo not in ('concluido','cancelado') then c.valor_orcamentado else 0 end),0)
  into v_real_pl,v_est_pl from public.planeamento_custos_componentes c join public.planeamento_itens pi on pi.id=c.planeamento_item_id join public.fases f on f.id=pi.fase_id
  where f.obra_id=p_obra_id and c.tipo='PL' and not exists(select 1 from public.orcamento_fases ofa where ofa.fase_id=f.id);
  with subs as(select c.*,s.valor_adjudicado,coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id and lower(coalesce(to_jsonb(p)->>'estado_pagamento',to_jsonb(p)->>'estado_aprovacao','pago')) in ('pago','aprovado','aprovada')),0) pago_sub
    from public.planeamento_custos_componentes c join public.planeamento_itens pi on pi.id=c.planeamento_item_id join public.fases f on f.id=pi.fase_id left join public.subempreitadas s on s.id=c.subempreitada_id where f.obra_id=p_obra_id and c.tipo='subempreitada')
  select coalesce(sum(pago_sub),0),coalesce(sum(case when remocao_estimado_confirmada_em is null and estado_custo<>'cancelado' then valor_orcamentado else 0 end),0),coalesce(sum(case when remocao_estimado_confirmada_em is not null and estado_custo<>'cancelado' then greatest(coalesce(valor_adjudicado,0)-pago_sub,0) else 0 end),0),coalesce(sum(coalesce(valor_adjudicado,0)),0)
  into v_real_sub,v_est_sub,v_comp_sub,v_adjudicado from subs;
  with rows as(
    select ofa.id,null::uuid planeamento_item_id,ofa.descricao,coalesce(f.descricao,'Fase') especialidade,'PL'::text tipo,ofa.custo_total_estimado valor_orcamentado,0::numeric valor_adjudicado,coalesce(ofa.valor_real_pl,0) valor_real,0::numeric compromisso_remanescente,ofa.estado_custo,null::uuid subempreitada_id,true remocao_confirmada,'0_Orçamento'::text fonte,
      ofa.venda_prevista,ofa.margem_prevista,ofa.deslocacoes,ofa.mao_obra,ofa.maquinas,ofa.materiais,ofa.mao_obra_sub,ofa.subempreitada
    from public.orcamento_fases ofa join public.fases f on f.id=ofa.fase_id where ofa.obra_id=p_obra_id
    union all
    select c.id,c.planeamento_item_id,pi.descricao,coalesce(e.nome,'Sem especialidade'),c.tipo,c.valor_orcamentado,coalesce(s.valor_adjudicado,0),case when c.tipo='PL' then coalesce(c.valor_real_pl,0) else coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id),0) end,
      case when c.tipo='subempreitada' and c.remocao_estimado_confirmada_em is not null then greatest(coalesce(s.valor_adjudicado,0)-coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id),0),0) else 0 end,c.estado_custo,c.subempreitada_id,c.remocao_estimado_confirmada_em is not null,'Composição manual',null,null,null,null,null,null,null,null
    from public.planeamento_custos_componentes c join public.planeamento_itens pi on pi.id=c.planeamento_item_id join public.fases f on f.id=pi.fase_id left join public.especialidades e on e.id=c.especialidade_id left join public.subempreitadas s on s.id=c.subempreitada_id
    where f.obra_id=p_obra_id and (c.tipo='subempreitada' or not exists(select 1 from public.orcamento_fases ofa where ofa.fase_id=f.id))
  ) select coalesce(jsonb_agg(to_jsonb(rows) order by especialidade,tipo),'[]') into v_componentes from rows;
  select coalesce(sum(a.valor),0),coalesce(jsonb_agg(jsonb_build_object('id',a.id,'valor',a.valor,'motivo',a.motivo,'autor',u.nome,'criado_em',a.criado_em) order by a.criado_em desc),'[]') into v_ajustes_total,v_ajustes from public.ajustes_custo_obra a left join public.utilizadores u on u.id=a.criado_por where a.obra_id=p_obra_id;
  select coalesce(max(c.venda_contratual_efetiva),max(c.venda_contratual_inicial),0) into v_venda from public.contratos c where c.obra_id=p_obra_id;
  if to_regclass('public.faturacao') is not null then execute $q$select coalesce(sum(coalesce(nullif(j->>'valor_fatura','')::numeric,nullif(j->>'valor_a_faturar','')::numeric,nullif(j->>'valor','')::numeric,0)),0) from(select to_jsonb(f) j from public.faturacao f where f.obra_id=$1)x where lower(coalesce(j->>'estado_aprovacao',j->>'estado','aprovado')) in('aprovado','aprovada','emitida','paga')$q$ into v_faturado_cliente using p_obra_id; end if;
  return jsonb_build_object('obra_id',p_obra_id,'formula','Custo Real + Custos Estimados = Estimativa Final','real',jsonb_build_object('pl',v_real_pl,'subempreitadas',v_real_sub,'total',v_real_pl+v_real_sub),'por_concluir',jsonb_build_object('pl',v_est_pl,'sub_orcamento_aguarda_confirmacao',v_est_sub,'sub_compromisso_remanescente',v_comp_sub,'total',v_est_pl+v_est_sub+v_comp_sub),'estimativa_terminus_direta',v_real_pl+v_real_sub+v_est_pl+v_est_sub+v_comp_sub,'custos_fixos',0,'pessoal_viatura_estimado',0,'ajustes_total',v_ajustes_total,'estimativa_terminus_total',v_real_pl+v_real_sub+v_est_pl+v_est_sub+v_comp_sub+v_ajustes_total,'percentagem_faturado',case when v_venda>0 then round(v_faturado_cliente*100/v_venda,2) else 0 end,'percentagem_pago',case when v_adjudicado>0 then round(v_real_sub*100/v_adjudicado,2) else 0 end,'componentes',v_componentes,'ajustes',v_ajustes);
end $$;

do $$ begin if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
  drop trigger if exists trg_auditoria_gestao_obras_lancamentos on public.gestao_obras_lancamentos;
  create trigger trg_auditoria_gestao_obras_lancamentos after insert or update or delete on public.gestao_obras_lancamentos for each row execute function public.fn_registar_log_auditoria('id');
  drop trigger if exists trg_auditoria_orcamento_fases on public.orcamento_fases;
  create trigger trg_auditoria_orcamento_fases after insert or update or delete on public.orcamento_fases for each row execute function public.fn_registar_log_auditoria('id');
end if; end $$;

commit;

select
  public.fn_e_gestao_plataforma() is not null as papel_gestao_plataforma,
  to_regclass('public.gestao_obras_lancamentos') is not null as mapa_gestao_editavel,
  to_regclass('public.orcamento_fases') is not null as orcamento_por_fase;
