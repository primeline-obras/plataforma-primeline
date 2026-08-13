-- PRIMELINE | Custos automáticos, apropriação rastreável e ajustes justificados
begin;

create table if not exists public.ajustes_custo_obra (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  valor numeric not null,
  motivo text not null check (length(btrim(motivo)) >= 3),
  criado_por uuid not null references public.utilizadores(id),
  criado_em timestamptz not null default now()
);

create index if not exists ajustes_custo_obra_obra_idx
  on public.ajustes_custo_obra(obra_id, criado_em desc);

alter table public.ajustes_custo_obra enable row level security;
revoke all on public.ajustes_custo_obra from anon;
grant select, insert, update, delete on public.ajustes_custo_obra to authenticated;

drop policy if exists ajustes_custo_obra_select on public.ajustes_custo_obra;
create policy ajustes_custo_obra_select on public.ajustes_custo_obra
for select to authenticated using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()
);

drop policy if exists ajustes_custo_obra_insert on public.ajustes_custo_obra;
create policy ajustes_custo_obra_insert on public.ajustes_custo_obra
for insert to authenticated with check (
  public.fn_pode_editar_obra(obra_id)
  and criado_por = public.fn_utilizador_atual_id()
);

drop policy if exists ajustes_custo_obra_update on public.ajustes_custo_obra;
create policy ajustes_custo_obra_update on public.ajustes_custo_obra
for update to authenticated using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id) and criado_por = public.fn_utilizador_atual_id());

drop policy if exists ajustes_custo_obra_delete on public.ajustes_custo_obra;
create policy ajustes_custo_obra_delete on public.ajustes_custo_obra
for delete to authenticated using (public.fn_pode_editar_obra(obra_id));

-- Ligações opcionais necessárias para retirar custos reais do saldo estimado
-- do respetivo TEE/artigo sem inferências por texto ou por fase.
do $$
declare v_table text;
begin
  foreach v_table in array array['lancamentos_materiais','lancamentos_mao_obra','despesas_estaleiro'] loop
    if to_regclass('public.' || v_table) is not null then
      execute format('alter table public.%I add column if not exists tee_id uuid references public.alteracoes_tee(id) on delete set null', v_table);
      execute format('alter table public.%I add column if not exists item_orcamento_id uuid references public.itens_orcamento(id) on delete set null', v_table);
    end if;
  end loop;
end $$;

create or replace function public.fn_valor_lancamento_custo(p_row jsonb)
returns numeric language sql immutable as $$
  select coalesce(
    nullif(p_row ->> 'valor_total','')::numeric,
    nullif(p_row ->> 'valor','')::numeric,
    nullif(p_row ->> 'total','')::numeric,
    nullif(p_row ->> 'custo','')::numeric,
    nullif(p_row ->> 'custo_direto','')::numeric,
    nullif(p_row ->> 'custo_previsto','')::numeric,
    nullif(p_row ->> 'compra_prevista','')::numeric,
    nullif(p_row ->> 'preco_custo','')::numeric,
    nullif(p_row ->> 'valor_custo','')::numeric,
    nullif(p_row ->> 'custo_total','')::numeric,
    coalesce(nullif(p_row ->> 'horas','')::numeric,0)
      * coalesce(nullif(p_row ->> 'valor_hora','')::numeric,0),
    0
  );
$$;

create or replace function public.fn_custo_real_ligado(
  p_obra_id uuid,
  p_tee_id uuid default null,
  p_item_id uuid default null
) returns numeric
language plpgsql stable security definer set search_path=public as $$
declare v_table text; v_total numeric := 0; v_part numeric;
begin
  foreach v_table in array array['lancamentos_materiais','lancamentos_mao_obra','despesas_estaleiro'] loop
    if to_regclass('public.' || v_table) is null then continue; end if;
    execute format(
      'select coalesce(sum(public.fn_valor_lancamento_custo(to_jsonb(t))),0) from public.%I t '
      || 'where t.obra_id=$1 and ($2 is null or t.tee_id=$2) and ($3 is null or t.item_orcamento_id=$3)',
      v_table
    ) into v_part using p_obra_id, p_tee_id, p_item_id;
    v_total := v_total + coalesce(v_part,0);
  end loop;
  return v_total;
end $$;

create or replace function public.fn_resumo_custos_obra(p_obra_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_work public.obras%rowtype; v_table text; v_part numeric; v_row record;
  v_material numeric:=0; v_labor numeric:=0; v_site numeric:=0; v_sub_paid numeric:=0;
  v_sub_remaining numeric:=0; v_tee_remaining numeric:=0; v_budget_remaining numeric:=0;
  v_adjustments numeric:=0; v_fixed numeric:=0; v_staff_future numeric:=0;
  v_labor_start date; v_elapsed integer:=0; v_remaining_days integer:=0;
  v_unallocated integer:=0; v_actual numeric:=0; v_etc numeric:=0; v_eac_direct numeric:=0; v_eac_total numeric:=0;
  v_adjustment_rows jsonb := '[]'::jsonb;
begin
  select * into v_work from public.obras where id=p_obra_id;
  if not found then raise exception 'Obra não encontrada.'; end if;
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then
    raise exception 'Sem permissão para consultar custos desta obra.' using errcode='42501';
  end if;

  foreach v_table in array array['lancamentos_materiais','lancamentos_mao_obra','despesas_estaleiro'] loop
    if to_regclass('public.' || v_table) is null then continue; end if;
    execute format('select coalesce(sum(public.fn_valor_lancamento_custo(to_jsonb(t))),0), count(*) filter (where t.tee_id is null and t.item_orcamento_id is null) from public.%I t where t.obra_id=$1', v_table)
      into v_part, v_elapsed using p_obra_id;
    if v_table='lancamentos_materiais' then v_material:=coalesce(v_part,0);
    elsif v_table='lancamentos_mao_obra' then v_labor:=coalesce(v_part,0);
    else v_site:=coalesce(v_part,0); end if;
    v_unallocated := v_unallocated + coalesce(v_elapsed,0);
  end loop;

  select coalesce(sum(p.valor),0) into v_sub_paid
  from public.pagamentos_subempreitada p join public.subempreitadas s on s.id=p.subempreitada_id
  where s.obra_id=p_obra_id;

  select coalesce(sum(greatest(coalesce(s.valor_adjudicado,0)-coalesce(p.paid,0),0)),0) into v_sub_remaining
  from public.subempreitadas s
  left join (select subempreitada_id,sum(valor) paid from public.pagamentos_subempreitada group by subempreitada_id) p on p.subempreitada_id=s.id
  where s.obra_id=p_obra_id and lower(coalesce(s.estado,'')) in ('adjudicado','em_execucao');

  for v_row in select id,coalesce(valor,0) valor from public.alteracoes_tee
    where obra_id=p_obra_id and lower(coalesce(estado_aprovacao_cliente,''))='aprovado'
  loop
    v_tee_remaining := v_tee_remaining + greatest(v_row.valor-public.fn_custo_real_ligado(p_obra_id,v_row.id,null),0);
  end loop;

  for v_row in
    select i.id, public.fn_valor_lancamento_custo(to_jsonb(i)) valor
    from public.itens_orcamento i join public.fases f on f.id=i.fase_id
    where f.obra_id=p_obra_id
      and nullif(to_jsonb(i)->>'tee_substituta_id','') is null
      and not exists (
        select 1 from public.consultas_subempreitada_itens ci
        join public.subempreitadas s on s.consulta_id=ci.consulta_subempreitada_id
        where ci.item_orcamento_id=i.id
          and lower(coalesce(s.estado,'')) in ('adjudicado','em_execucao','concluido')
      )
  loop
    v_budget_remaining := v_budget_remaining + greatest(v_row.valor-public.fn_custo_real_ligado(p_obra_id,null,v_row.id),0);
  end loop;

  select coalesce(sum(valor),0), coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'valor',a.valor,'motivo',a.motivo,'criado_por',a.criado_por,
    'autor',u.nome,'criado_em',a.criado_em) order by a.criado_em desc),'[]'::jsonb)
  into v_adjustments,v_adjustment_rows
  from public.ajustes_custo_obra a left join public.utilizadores u on u.id=a.criado_por
  where a.obra_id=p_obra_id;

  select coalesce(custo_direto_efetivo,custo_direto_inicial,0)*0.085 into v_fixed
  from public.contratos where obra_id=p_obra_id order by atualizado_em desc nulls last limit 1;
  v_fixed:=coalesce(v_fixed,0);

  if to_regclass('public.lancamentos_mao_obra') is not null then
    execute 'select min(data)::date from public.lancamentos_mao_obra where obra_id=$1' into v_labor_start using p_obra_id;
  end if;
  v_elapsed:=greatest(current_date-coalesce(v_labor_start,v_work.data_inicio,current_date),1);
  v_remaining_days:=greatest(coalesce(v_work.data_fim_prevista,current_date)-current_date,0);
  v_staff_future := case when v_labor>0 then (v_labor/v_elapsed)*v_remaining_days else 0 end;

  v_actual:=v_material+v_labor+v_site+v_sub_paid;
  v_etc:=v_sub_remaining+v_tee_remaining+v_budget_remaining;
  v_eac_direct:=v_actual+v_etc;
  v_eac_total:=v_eac_direct+v_fixed+v_staff_future+v_adjustments;
  return jsonb_build_object(
    'obra_id',p_obra_id,
    'real',jsonb_build_object('materiais',v_material,'mao_obra',v_labor,'estaleiro',v_site,'subempreitadas',v_sub_paid,'total',v_actual),
    'por_concluir',jsonb_build_object('subempreitadas',v_sub_remaining,'tees',v_tee_remaining,'orcamento_nao_contratado',v_budget_remaining,'total',v_etc),
    'estimativa_terminus_direta',v_eac_direct,'custos_fixos',v_fixed,
    'pessoal_viatura_estimado',v_staff_future,'ajustes_total',v_adjustments,
    'estimativa_terminus_total',v_eac_total,'lancamentos_sem_apropriacao',v_unallocated,
    'ajustes',v_adjustment_rows
  );
end $$;

revoke all on function public.fn_resumo_custos_obra(uuid) from public,anon;
grant execute on function public.fn_resumo_custos_obra(uuid) to authenticated;

do $$ begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_ajustes_custo_obra on public.ajustes_custo_obra;
    create trigger trg_auditoria_ajustes_custo_obra after insert or update or delete on public.ajustes_custo_obra
      for each row execute function public.fn_registar_log_auditoria('id');
  end if;
end $$;

commit;

select
  to_regclass('public.ajustes_custo_obra') is not null as ajustes,
  to_regprocedure('public.fn_resumo_custos_obra(uuid)') is not null as resumo_automatico;
