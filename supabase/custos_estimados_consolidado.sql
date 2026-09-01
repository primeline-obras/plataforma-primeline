-- PRIMELINE | Custos estimados — especificação final consolidada
-- Executar depois de custos_estimados_especificacao_final.sql.
begin;

alter table public.planeamento_itens
  add column if not exists valor_orca_pl numeric,
  add column if not exists valor_real_pl numeric,
  add column if not exists custo_pl_confirmado boolean not null default false,
  add column if not exists custo_pl_confirmado_por uuid references public.utilizadores(id),
  add column if not exists custo_pl_confirmado_em timestamptz;

update public.planeamento_itens
set valor_orca_pl=valor_estimado
where valor_orca_pl is null and valor_estimado is not null
  and coalesce(executado_por,'PL') in ('PL','misto');

alter table public.planeamento_itens
  drop constraint if exists planeamento_itens_executado_por_check,
  add constraint planeamento_itens_executado_por_check
    check (executado_por is null or executado_por in ('PL','subempreitada','misto')),
  drop constraint if exists planeamento_itens_valor_orca_pl_check,
  add constraint planeamento_itens_valor_orca_pl_check check (valor_orca_pl is null or valor_orca_pl>=0),
  drop constraint if exists planeamento_itens_valor_real_pl_check,
  add constraint planeamento_itens_valor_real_pl_check check (valor_real_pl is null or valor_real_pl>=0);

create or replace function public.fn_confirmar_custo_real_pl(
  p_planeamento_item_id uuid,
  p_valor_real numeric default null
) returns public.planeamento_itens
language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_item public.planeamento_itens; v_obra_id uuid; v_utilizador_id uuid; v_valor numeric;
begin
  select pi.* into v_item from public.planeamento_itens pi
  where pi.id=p_planeamento_item_id for update;
  if not found then raise exception 'Tarefa/pacote PL não encontrado.'; end if;
  select f.obra_id into v_obra_id from public.fases f where f.id=v_item.fase_id;
  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception 'Só a equipa técnica responsável pode confirmar o custo PL.' using errcode='42501';
  end if;
  if coalesce(v_item.executado_por,'PL') not in ('PL','misto') then
    raise exception 'Esta tarefa não possui uma componente executada pela Primeline.';
  end if;
  if v_item.estado<>'concluido' then
    raise exception 'A componente PL só pode passar a Custo Real quando a tarefa estiver concluída.';
  end if;
  v_valor:=coalesce(p_valor_real,v_item.valor_orca_pl,v_item.valor_estimado);
  if v_valor is null or v_valor<0 then raise exception 'Indique um Valor Real PL válido.'; end if;
  select id into v_utilizador_id from public.utilizadores where auth_user_id=auth.uid() limit 1;
  update public.planeamento_itens set valor_real_pl=v_valor,custo_pl_confirmado=true,
    custo_pl_confirmado_por=v_utilizador_id,custo_pl_confirmado_em=now(),custo_estado='concluido'
  where id=p_planeamento_item_id returning * into v_item;
  return v_item;
end;$function$;

revoke all on function public.fn_confirmar_custo_real_pl(uuid,numeric) from public,anon;
grant execute on function public.fn_confirmar_custo_real_pl(uuid,numeric) to authenticated;

create or replace function public.fn_resumo_componentes_custo_obra(p_obra_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare
  v_row record; v_pacotes jsonb:='[]'::jsonb;
  v_pl_estimado numeric:=0; v_pl_real numeric:=0; v_sub_estimado numeric:=0;
  v_sub_real numeric:=0; v_sub_compromisso numeric:=0;
begin
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then
    raise exception 'Sem permissão para consultar custos desta obra.' using errcode='42501';
  end if;
  for v_row in
    select pi.id,pi.codigo,pi.descricao,pi.estado,coalesce(pi.executado_por,'PL') executado_por,
      coalesce(pi.valor_orca_pl,pi.valor_estimado,0) valor_orca_pl,
      coalesce(pi.valor_real_pl,0) valor_real_pl,pi.custo_pl_confirmado,
      pi.subempreitada_id,pi.compromisso_confirmado,
      coalesce(s.valor_adjudicado,0) valor_adjudicado,
      lower(coalesce(s.estado,'')) sub_estado,
      coalesce((select sum(p.valor) from public.pagamentos_subempreitada p where p.subempreitada_id=s.id),0) sub_pago,
      coalesce((select sum(fat.valor) from public.faturas fat where fat.subempreitada_id=s.id and coalesce(fat.fluxo_estado,'recebida') in ('aprovada_tecnicamente','enviada_financeiro','paga')),0) sub_faturado
    from public.planeamento_itens pi join public.fases f on f.id=pi.fase_id
    left join public.subempreitadas s on s.id=pi.subempreitada_id
    where f.obra_id=p_obra_id and pi.custo_estado<>'cancelado'
    order by pi.codigo,pi.criado_em
  loop
    if v_row.executado_por in ('PL','misto') then
      if v_row.custo_pl_confirmado then v_pl_real:=v_pl_real+v_row.valor_real_pl;
      else v_pl_estimado:=v_pl_estimado+v_row.valor_orca_pl; end if;
    end if;
    if v_row.executado_por in ('subempreitada','misto') and v_row.subempreitada_id is not null then
      if v_row.compromisso_confirmado then
        v_sub_real:=v_sub_real+v_row.sub_pago;
        v_sub_compromisso:=v_sub_compromisso+greatest(v_row.valor_adjudicado-v_row.sub_pago,0);
      else v_sub_estimado:=v_sub_estimado+v_row.valor_adjudicado; end if;
    end if;
    v_pacotes:=v_pacotes||jsonb_build_array(jsonb_build_object(
      'planeamento_item_id',v_row.id,'codigo',v_row.codigo,'descricao',v_row.descricao,'executado_por',v_row.executado_por,
      'valor_orca_pl',v_row.valor_orca_pl,'valor_real_pl',case when v_row.custo_pl_confirmado then v_row.valor_real_pl else 0 end,
      'pl_confirmacao_pendente',(v_row.executado_por in ('PL','misto') and v_row.estado='concluido' and not v_row.custo_pl_confirmado),
      'valor_adjudicado',v_row.valor_adjudicado,'sub_real',case when v_row.compromisso_confirmado then v_row.sub_pago else 0 end,
      'sub_compromisso',case when v_row.compromisso_confirmado then greatest(v_row.valor_adjudicado-v_row.sub_pago,0) else 0 end,
      'sub_confirmacao_pendente',(v_row.executado_por in ('subempreitada','misto') and v_row.subempreitada_id is not null and not v_row.compromisso_confirmado and v_row.sub_estado in ('adjudicada','adjudicado','em_execucao','concluida','concluido')),
      'percentual_faturado',case when v_row.valor_adjudicado>0 then round(v_row.sub_faturado/v_row.valor_adjudicado*100,2) else 0 end,
      'percentual_pago',case when v_row.valor_adjudicado>0 then round(v_row.sub_pago/v_row.valor_adjudicado*100,2) else 0 end));
  end loop;
  return jsonb_build_object(
    'formula','Custo Real = PL confirmado + pagamentos de subempreitada; Custos Estimados = PL por concluir + adjudicações por confirmar; Compromisso = adjudicado confirmado − pagamentos',
    'pl',jsonb_build_object('estimado',v_pl_estimado,'real',v_pl_real),
    'subempreitadas',jsonb_build_object('estimado',v_sub_estimado,'real',v_sub_real,'compromisso',v_sub_compromisso),
    'pl_estimado',v_pl_estimado,'pl_real',v_pl_real,
    'sub_estimado',v_sub_estimado,'sub_real',v_sub_real,
    'custo_real_total',v_pl_real+v_sub_real,
    'custos_estimados_total',v_pl_estimado+v_sub_estimado,
    'compromisso_total',v_sub_compromisso,'pacotes',v_pacotes);
end;$function$;

revoke all on function public.fn_resumo_componentes_custo_obra(uuid) from public,anon;
grant execute on function public.fn_resumo_componentes_custo_obra(uuid) to authenticated;

commit;

select
  to_regprocedure('public.fn_confirmar_custo_real_pl(uuid,numeric)') is not null as rpc_confirmar_pl,
  to_regprocedure('public.fn_resumo_componentes_custo_obra(uuid)') is not null as rpc_resumo_componentes,
  (select count(*) from information_schema.columns where table_schema='public' and table_name='planeamento_itens' and column_name in ('valor_orca_pl','valor_real_pl','custo_pl_confirmado'))=3 as colunas_pl;
