-- PRIMELINE | Custos estimados — modelo final por pacote/especialidade
-- Migração aditiva. Mantém os dados históricos e substitui apenas o cálculo do resumo.
begin;

create table if not exists public.planeamento_custos_componentes (
  id uuid primary key default gen_random_uuid(),
  planeamento_item_id uuid not null references public.planeamento_itens(id) on delete cascade,
  especialidade_id uuid references public.especialidades(id) on delete set null,
  tipo text not null check (tipo in ('PL', 'subempreitada')),
  item_orcamento_id uuid references public.itens_orcamento(id) on delete set null,
  subempreitada_id uuid references public.subempreitadas(id) on delete set null,
  valor_orcamentado numeric not null default 0 check (valor_orcamentado >= 0),
  valor_real_pl numeric check (valor_real_pl is null or valor_real_pl >= 0),
  estado_custo text not null default 'orcamentado_nao_comprometido'
    check (estado_custo in (
      'orcamentado_nao_comprometido', 'em_consulta', 'adjudicado',
      'em_execucao', 'concluido', 'cancelado'
    )),
  remocao_estimado_confirmada_em timestamptz,
  remocao_estimado_confirmada_por uuid references public.utilizadores(id),
  concluido_confirmado_em timestamptz,
  concluido_confirmado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint planeamento_custo_tipo_campos_check check (
    (tipo = 'PL' and subempreitada_id is null)
    or tipo = 'subempreitada'
  )
);

create unique index if not exists planeamento_custos_pacote_uidx
  on public.planeamento_custos_componentes (planeamento_item_id, tipo)
  where item_orcamento_id is null;
create unique index if not exists planeamento_custos_linha_uidx
  on public.planeamento_custos_componentes (planeamento_item_id, tipo, item_orcamento_id)
  where item_orcamento_id is not null;
create index if not exists planeamento_custos_obra_indireto_idx
  on public.planeamento_custos_componentes (planeamento_item_id, especialidade_id, tipo);

alter table public.planeamento_custos_componentes enable row level security;
revoke all on public.planeamento_custos_componentes from anon;
grant select on public.planeamento_custos_componentes to authenticated;

drop policy if exists planeamento_custos_select on public.planeamento_custos_componentes;
create policy planeamento_custos_select on public.planeamento_custos_componentes
for select to authenticated using (
  exists (
    select 1 from public.planeamento_itens pi
    join public.fases f on f.id = pi.fase_id
    where pi.id = planeamento_item_id and public.fn_pode_ver_obra(f.obra_id)
  )
  or public.fn_e_admin() or public.fn_e_administrativo()
);

create or replace function public.fn_e_diretor_obra(p_obra_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.fn_e_admin() or exists (
    select 1 from public.obra_responsaveis r
    join public.utilizadores u on u.id = r.utilizador_id
    where r.obra_id = p_obra_id
      and r.utilizador_id = public.fn_utilizador_atual_id()
      and u.funcao = 'diretor_obra'
      and coalesce(u.ativo, true)
  );
$$;
revoke all on function public.fn_e_diretor_obra(uuid) from public, anon;
grant execute on function public.fn_e_diretor_obra(uuid) to authenticated;

create or replace function public.fn_sincronizar_componente_subempreitada()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_obra_id uuid;
  v_orcamento numeric := 0;
begin
  if new.subempreitada_id is null then return new; end if;
  select f.obra_id into v_obra_id
  from public.fases f where f.id = new.fase_id;

  select coalesce(sum(public.fn_valor_lancamento_custo(to_jsonb(io))), 0)
  into v_orcamento
  from public.subempreitadas s
  join public.consultas_subempreitada_itens ci
    on ci.consulta_subempreitada_id = s.consulta_id
  join public.itens_orcamento io on io.id = ci.item_orcamento_id
  where s.id = new.subempreitada_id;

  insert into public.planeamento_custos_componentes (
    planeamento_item_id, especialidade_id, tipo, subempreitada_id,
    valor_orcamentado, estado_custo
  ) values (
    new.id, new.especialidade_id, 'subempreitada', new.subempreitada_id,
    v_orcamento, case when new.estado = 'concluido' then 'concluido'
                      when new.estado = 'em_execucao' then 'em_execucao'
                      else 'adjudicado' end
  )
  on conflict (planeamento_item_id, tipo) where item_orcamento_id is null
  do update set
    especialidade_id = excluded.especialidade_id,
    subempreitada_id = excluded.subempreitada_id,
    valor_orcamentado = case
      when planeamento_custos_componentes.valor_orcamentado = 0 then excluded.valor_orcamentado
      else planeamento_custos_componentes.valor_orcamentado end,
    estado_custo = excluded.estado_custo,
    atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists trg_sincronizar_componente_subempreitada on public.planeamento_itens;
create trigger trg_sincronizar_componente_subempreitada
after insert or update of subempreitada_id, especialidade_id, estado on public.planeamento_itens
for each row execute function public.fn_sincronizar_componente_subempreitada();

-- Reconstrói componentes das adjudicações já existentes sem confirmar a remoção.
update public.planeamento_itens set subempreitada_id = subempreitada_id
where subempreitada_id is not null;

create or replace function public.fn_guardar_componente_custo(
  p_planeamento_item_id uuid,
  p_tipo text,
  p_valor_orcamentado numeric,
  p_estado_custo text,
  p_valor_real_pl numeric default null
) returns public.planeamento_custos_componentes
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_obra_id uuid; v_item public.planeamento_itens%rowtype; v_row public.planeamento_custos_componentes%rowtype;
begin
  select pi.* into v_item from public.planeamento_itens pi where pi.id = p_planeamento_item_id;
  if not found then raise exception 'Tarefa de planeamento não encontrada.'; end if;
  select f.obra_id into v_obra_id from public.fases f where f.id = v_item.fase_id;
  if not public.fn_e_diretor_obra(v_obra_id) then
    raise exception 'A composição do custo só pode ser alterada pelo Diretor de Obra ou Gerência.' using errcode='42501';
  end if;
  if p_tipo not in ('PL','subempreitada') then raise exception 'Tipo de componente inválido.'; end if;
  insert into public.planeamento_custos_componentes (
    planeamento_item_id, especialidade_id, tipo, subempreitada_id,
    valor_orcamentado, valor_real_pl, estado_custo
  ) values (
    v_item.id, v_item.especialidade_id, p_tipo,
    case when p_tipo='subempreitada' then v_item.subempreitada_id else null end,
    greatest(coalesce(p_valor_orcamentado,0),0),
    case when p_tipo='PL' then p_valor_real_pl else null end,
    p_estado_custo
  )
  on conflict (planeamento_item_id, tipo) where item_orcamento_id is null
  do update set especialidade_id=excluded.especialidade_id,
    subempreitada_id=excluded.subempreitada_id,
    valor_orcamentado=excluded.valor_orcamentado,
    valor_real_pl=excluded.valor_real_pl,
    estado_custo=excluded.estado_custo, atualizado_em=now()
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.fn_confirmar_remocao_custo_estimado_subempreitada(p_subempreitada_id uuid)
returns public.planeamento_custos_componentes
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_obra_id uuid; v_row public.planeamento_custos_componentes%rowtype;
begin
  select obra_id into v_obra_id from public.subempreitadas where id=p_subempreitada_id;
  if not found then raise exception 'Subempreitada não encontrada.'; end if;
  if not public.fn_e_diretor_obra(v_obra_id) then
    raise exception 'A confirmação está reservada ao Diretor de Obra ou Gerência.' using errcode='42501';
  end if;
  update public.planeamento_custos_componentes
  set remocao_estimado_confirmada_em=now(),
      remocao_estimado_confirmada_por=public.fn_utilizador_atual_id(),
      estado_custo=case when estado_custo='orcamentado_nao_comprometido' then 'adjudicado' else estado_custo end,
      atualizado_em=now()
  where subempreitada_id=p_subempreitada_id and tipo='subempreitada'
  returning * into v_row;
  if not found then raise exception 'Componente de custo da subempreitada não encontrado.'; end if;
  return v_row;
end;
$$;

create or replace function public.fn_concluir_custo_pl(p_componente_id uuid, p_valor_real numeric default null)
returns public.planeamento_custos_componentes
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_obra_id uuid; v_row public.planeamento_custos_componentes%rowtype;
begin
  select f.obra_id into v_obra_id
  from public.planeamento_custos_componentes c
  join public.planeamento_itens pi on pi.id=c.planeamento_item_id
  join public.fases f on f.id=pi.fase_id
  where c.id=p_componente_id and c.tipo='PL';
  if not found then raise exception 'Componente PL não encontrado.'; end if;
  if not public.fn_e_diretor_obra(v_obra_id) then
    raise exception 'A conclusão está reservada ao Diretor de Obra ou Gerência.' using errcode='42501';
  end if;
  update public.planeamento_custos_componentes
  set valor_real_pl=greatest(coalesce(p_valor_real,valor_orcamentado),0),
      estado_custo='concluido', concluido_confirmado_em=now(),
      concluido_confirmado_por=public.fn_utilizador_atual_id(), atualizado_em=now()
  where id=p_componente_id returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric) from public,anon;
revoke all on function public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) from public,anon;
revoke all on function public.fn_concluir_custo_pl(uuid,numeric) from public,anon;
grant execute on function public.fn_guardar_componente_custo(uuid,text,numeric,text,numeric) to authenticated;
grant execute on function public.fn_confirmar_remocao_custo_estimado_subempreitada(uuid) to authenticated;
grant execute on function public.fn_concluir_custo_pl(uuid,numeric) to authenticated;

-- Os cinco estados acompanham a fatura sem eliminar o fluxo legado de aprovação/pagamento.
alter table public.faturas add column if not exists estado_fluxo text;
update public.faturas set estado_fluxo = case
  when estado_pagamento='pago' then 'paga'
  when estado_aprovacao='aprovado' then 'enviada_financeiro'
  else 'recebida' end
where estado_fluxo is null;
alter table public.faturas alter column estado_fluxo set default 'recebida';
alter table public.faturas alter column estado_fluxo set not null;
alter table public.faturas drop constraint if exists faturas_estado_fluxo_check;
alter table public.faturas add constraint faturas_estado_fluxo_check check (estado_fluxo in (
  'recebida','em_validacao','aprovada_tecnicamente','enviada_financeiro','paga'
));

create or replace function public.fn_sincronizar_estado_fluxo_fatura()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.estado_pagamento='pago' then new.estado_fluxo='paga';
  elsif new.estado_aprovacao='aprovado' then new.estado_fluxo='enviada_financeiro';
  elsif new.estado_fluxo is null then new.estado_fluxo='recebida'; end if;
  return new;
end;
$$;
drop trigger if exists trg_sincronizar_estado_fluxo_fatura on public.faturas;
create trigger trg_sincronizar_estado_fluxo_fatura
before insert or update of estado_aprovacao, estado_pagamento, estado_fluxo on public.faturas
for each row execute function public.fn_sincronizar_estado_fluxo_fatura();

create or replace function public.fn_resumo_custos_obra(p_obra_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public, pg_temp as $$
declare
  v_real_pl numeric:=0; v_real_sub numeric:=0; v_est_pl numeric:=0;
  v_est_sub_orca numeric:=0; v_comp_sub numeric:=0; v_ajustes numeric:=0;
  v_componentes jsonb:='[]'::jsonb; v_ajustes_rows jsonb:='[]'::jsonb;
  v_faturado numeric:=0; v_pago numeric:=0;
begin
  if not exists (select 1 from public.obras where id=p_obra_id) then raise exception 'Obra não encontrada.'; end if;
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_administrativo() or public.fn_e_financeiro()) then
    raise exception 'Sem permissão para consultar custos desta obra.' using errcode='42501';
  end if;

  with base as (
    select c.*, pi.descricao, e.nome especialidade, s.valor_adjudicado,
      coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id),0) pago_sub
    from public.planeamento_custos_componentes c
    join public.planeamento_itens pi on pi.id=c.planeamento_item_id
    join public.fases f on f.id=pi.fase_id
    left join public.especialidades e on e.id=c.especialidade_id
    left join public.subempreitadas s on s.id=c.subempreitada_id
    where f.obra_id=p_obra_id
  )
  select
    coalesce(sum(case when tipo='PL' and estado_custo='concluido' then coalesce(valor_real_pl,valor_orcamentado) else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' then pago_sub else 0 end),0),
    coalesce(sum(case when tipo='PL' and estado_custo not in ('concluido','cancelado') then valor_orcamentado else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' and remocao_estimado_confirmada_em is null and estado_custo<>'cancelado' then valor_orcamentado else 0 end),0),
    coalesce(sum(case when tipo='subempreitada' and remocao_estimado_confirmada_em is not null and estado_custo<>'cancelado' then greatest(coalesce(valor_adjudicado,0)-pago_sub,0) else 0 end),0),
    coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'planeamento_item_id',planeamento_item_id,'descricao',descricao,
      'especialidade',coalesce(especialidade,'Sem especialidade'),'tipo',tipo,
      'valor_orcamentado',valor_orcamentado,'valor_adjudicado',coalesce(valor_adjudicado,0),
      'valor_real',case when tipo='PL' then coalesce(valor_real_pl,0) else pago_sub end,
      'compromisso_remanescente',case when tipo='subempreitada' and remocao_estimado_confirmada_em is not null then greatest(coalesce(valor_adjudicado,0)-pago_sub,0) else 0 end,
      'estado_custo',estado_custo,'subempreitada_id',subempreitada_id,
      'remocao_confirmada',remocao_estimado_confirmada_em is not null
    ) order by especialidade,tipo),'[]'::jsonb)
  into v_real_pl,v_real_sub,v_est_pl,v_est_sub_orca,v_comp_sub,v_componentes from base;

  select coalesce(sum(a.valor),0), coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'valor',a.valor,'motivo',a.motivo,'autor',u.nome,'criado_em',a.criado_em
  ) order by a.criado_em desc),'[]'::jsonb)
  into v_ajustes,v_ajustes_rows
  from public.ajustes_custo_obra a left join public.utilizadores u on u.id=a.criado_por
  where a.obra_id=p_obra_id;

  select coalesce(sum(valor),0), coalesce(sum(valor) filter (where estado_pagamento='pago'),0)
  into v_faturado,v_pago from public.faturas where obra_id=p_obra_id;

  return jsonb_build_object(
    'obra_id',p_obra_id,
    'formula','Custo Real + Custos Estimados = Estimativa Final',
    'real',jsonb_build_object('pl',v_real_pl,'subempreitadas',v_real_sub,'total',v_real_pl+v_real_sub),
    'por_concluir',jsonb_build_object('pl',v_est_pl,'sub_orcamento_aguarda_confirmacao',v_est_sub_orca,'sub_compromisso_remanescente',v_comp_sub,'total',v_est_pl+v_est_sub_orca+v_comp_sub),
    'estimativa_terminus_direta',v_real_pl+v_real_sub+v_est_pl+v_est_sub_orca+v_comp_sub,
    'custos_fixos',0,'pessoal_viatura_estimado',0,
    'ajustes_total',v_ajustes,
    'estimativa_terminus_total',v_real_pl+v_real_sub+v_est_pl+v_est_sub_orca+v_comp_sub+v_ajustes,
    'percentagem_faturado',case when v_real_pl+v_real_sub+v_est_pl+v_est_sub_orca+v_comp_sub>0 then round(v_faturado*100/(v_real_pl+v_real_sub+v_est_pl+v_est_sub_orca+v_comp_sub),2) else 0 end,
    'percentagem_pago',case when v_faturado>0 then round(v_pago*100/v_faturado,2) else 0 end,
    'componentes',v_componentes,'ajustes',v_ajustes_rows
  );
end;
$$;

revoke all on function public.fn_resumo_custos_obra(uuid) from public,anon;
grant execute on function public.fn_resumo_custos_obra(uuid) to authenticated;

do $$ begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_planeamento_custos on public.planeamento_custos_componentes;
    create trigger trg_auditoria_planeamento_custos after insert or update or delete
    on public.planeamento_custos_componentes for each row
    execute function public.fn_registar_log_auditoria('id');
  end if;
end $$;

commit;

select to_regclass('public.planeamento_custos_componentes') is not null as componentes_ativos,
       to_regprocedure('public.fn_resumo_custos_obra(uuid)') is not null as resumo_ativo;
