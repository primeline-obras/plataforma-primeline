-- PRIMELINE GO | Controlo contratual de subempreitadas
-- Contrato + aditamentos aprovados versus faturado validado e pago.
-- Um TEE do cliente só entra no teto do subempreiteiro quando for ligado
-- explicitamente a um aditamento aprovado.
begin;

create table if not exists public.subempreitada_aditamentos (
  id uuid primary key default gen_random_uuid(),
  subempreitada_id uuid not null references public.subempreitadas(id) on delete cascade,
  obra_id uuid not null references public.obras(id) on delete cascade,
  alteracao_tee_id uuid references public.alteracoes_tee(id) on delete set null,
  descricao text not null,
  valor numeric not null check (valor > 0),
  estado text not null default 'pendente' check (estado in ('pendente','aprovado','rejeitado')),
  criado_por uuid references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  decidido_por uuid references public.utilizadores(id),
  decidido_em timestamptz,
  observacao_decisao text
);

create index if not exists subempreitada_aditamentos_sub_idx
  on public.subempreitada_aditamentos(subempreitada_id, estado);
create unique index if not exists subempreitada_aditamentos_tee_uidx
  on public.subempreitada_aditamentos(subempreitada_id, alteracao_tee_id)
  where alteracao_tee_id is not null and estado <> 'rejeitado';

alter table public.subempreitada_aditamentos enable row level security;
revoke all on public.subempreitada_aditamentos from anon;
revoke insert, update, delete on public.subempreitada_aditamentos from authenticated;
grant select on public.subempreitada_aditamentos to authenticated;

drop policy if exists subempreitada_aditamentos_select on public.subempreitada_aditamentos;
create policy subempreitada_aditamentos_select
on public.subempreitada_aditamentos for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_admin()
  or public.fn_e_administrativo()
  or public.fn_e_financeiro()
);

create or replace function public.fn_registar_aditamento_subempreitada(
  p_subempreitada_id uuid,
  p_descricao text,
  p_valor numeric,
  p_alteracao_tee_id uuid default null
) returns public.subempreitada_aditamentos
language plpgsql security definer set search_path=public,pg_temp as $function$
declare
  v_sub public.subempreitadas;
  v_result public.subempreitada_aditamentos;
begin
  select * into v_sub from public.subempreitadas where id=p_subempreitada_id;
  if not found then raise exception 'Subempreitada não encontrada.' using errcode='P0002'; end if;
  if not (public.fn_pode_editar_obra(v_sub.obra_id) or public.fn_e_administrativo() or public.fn_e_admin()) then
    raise exception 'Sem permissão para registar aditamentos nesta obra.' using errcode='42501';
  end if;
  if nullif(btrim(p_descricao),'') is null or p_valor is null or p_valor<=0 then
    raise exception 'Descrição e valor positivo são obrigatórios.';
  end if;
  if p_alteracao_tee_id is not null and not exists (
    select 1 from public.alteracoes_tee t where t.id=p_alteracao_tee_id and t.obra_id=v_sub.obra_id
  ) then
    raise exception 'O TEE indicado não pertence à mesma obra.';
  end if;
  insert into public.subempreitada_aditamentos(
    subempreitada_id,obra_id,alteracao_tee_id,descricao,valor,criado_por
  ) values (
    v_sub.id,v_sub.obra_id,p_alteracao_tee_id,btrim(p_descricao),p_valor,public.fn_utilizador_atual_id()
  ) returning * into v_result;
  return v_result;
end;$function$;

create or replace function public.fn_decidir_aditamento_subempreitada(
  p_aditamento_id uuid,
  p_estado text,
  p_observacao text default null
) returns public.subempreitada_aditamentos
language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_result public.subempreitada_aditamentos;
begin
  if not (public.fn_e_admin() or exists (
    select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
      and u.funcao in ('gerencia','gestao_plataforma') and coalesce(u.ativo,true)
  )) then
    raise exception 'A aprovação de aditamentos está reservada à Gerência/Gestão da Plataforma.' using errcode='42501';
  end if;
  if p_estado not in ('aprovado','rejeitado') then raise exception 'Decisão inválida.'; end if;
  update public.subempreitada_aditamentos
  set estado=p_estado,observacao_decisao=nullif(btrim(p_observacao),''),
      decidido_por=public.fn_utilizador_atual_id(),decidido_em=now()
  where id=p_aditamento_id and estado='pendente'
  returning * into v_result;
  if not found then raise exception 'Aditamento pendente não encontrado.' using errcode='P0002'; end if;
  return v_result;
end;$function$;

create or replace function public.fn_resumo_controle_subempreitadas_obra(p_obra_id uuid)
returns table (
  subempreitada_id uuid,
  valor_contratual numeric,
  aditamentos_aprovados numeric,
  total_aprovado numeric,
  total_faturado numeric,
  total_pago numeric,
  saldo numeric,
  ultrapassagem_faturada numeric,
  ultrapassagem_paga numeric,
  aditamentos jsonb
)
language plpgsql stable security definer set search_path=public,pg_temp as $function$
begin
  if not (public.fn_pode_ver_obra(p_obra_id) or public.fn_e_admin() or public.fn_e_administrativo() or public.fn_e_financeiro()) then
    raise exception 'Sem permissão para consultar o controlo contratual desta obra.' using errcode='42501';
  end if;
  return query
  with base as (
    select s.id,coalesce(s.valor_adjudicado,0)::numeric contrato
    from public.subempreitadas s where s.obra_id=p_obra_id
  ), ad as (
    select a.subempreitada_id,
      coalesce(sum(a.valor) filter(where a.estado='aprovado'),0)::numeric aprovados,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',a.id,'descricao',a.descricao,'valor',a.valor,'estado',a.estado,
        'alteracao_tee_id',a.alteracao_tee_id,'criado_em',a.criado_em,
        'observacao_decisao',a.observacao_decisao
      ) order by a.criado_em desc),'[]'::jsonb) lista
    from public.subempreitada_aditamentos a
    where a.obra_id=p_obra_id group by a.subempreitada_id
  ), fat as (
    select f.subempreitada_id,
      coalesce(sum(f.valor) filter(where f.estado_fluxo in ('aprovada_tecnicamente','enviada_financeiro','paga')),0)::numeric faturado,
      coalesce(sum(f.valor) filter(where f.estado_fluxo='paga' or f.estado_pagamento='pago'),0)::numeric pago
    from public.faturas f
    where f.obra_id=p_obra_id and f.subempreitada_id is not null
    group by f.subempreitada_id
  ), legado as (
    select p.subempreitada_id,coalesce(sum(p.valor),0)::numeric valor
    from public.pagamentos_subempreitada p
    join public.subempreitadas s on s.id=p.subempreitada_id
    where s.obra_id=p_obra_id and not exists (
      select 1 from public.faturas f
      where f.subempreitada_id=p.subempreitada_id
        and (f.estado_fluxo='paga' or f.estado_pagamento='pago')
        and nullif(lower(btrim(coalesce(f.numero_doc,''))),'') is not null
        and lower(btrim(f.numero_doc))=lower(btrim(coalesce(to_jsonb(p)->>'numero_doc',to_jsonb(p)->>'documento','')))
    ) group by p.subempreitada_id
  )
  select b.id,b.contrato,coalesce(ad.aprovados,0),
    (b.contrato+coalesce(ad.aprovados,0))::numeric,
    (coalesce(fat.faturado,0)+coalesce(legado.valor,0))::numeric,
    (coalesce(fat.pago,0)+coalesce(legado.valor,0))::numeric,
    greatest(b.contrato+coalesce(ad.aprovados,0)-coalesce(fat.faturado,0)-coalesce(legado.valor,0),0)::numeric,
    greatest(coalesce(fat.faturado,0)+coalesce(legado.valor,0)-b.contrato-coalesce(ad.aprovados,0),0)::numeric,
    greatest(coalesce(fat.pago,0)+coalesce(legado.valor,0)-b.contrato-coalesce(ad.aprovados,0),0)::numeric,
    coalesce(ad.lista,'[]'::jsonb)
  from base b left join ad on ad.subempreitada_id=b.id
  left join fat on fat.subempreitada_id=b.id
  left join legado on legado.subempreitada_id=b.id
  order by b.id;
end;$function$;

create or replace function public.fn_verificar_limite_fatura_subempreitada(
  p_fatura_id uuid,
  p_etapa text
) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $function$
declare v_fatura public.faturas; v_res record; v_proj_faturado numeric; v_proj_pago numeric;
begin
  select * into v_fatura from public.faturas where id=p_fatura_id;
  if not found then raise exception 'Fatura não encontrada.' using errcode='P0002'; end if;
  if v_fatura.subempreitada_id is null then return jsonb_build_object('aplicavel',false); end if;
  select * into v_res from public.fn_resumo_controle_subempreitadas_obra(v_fatura.obra_id) r
  where r.subempreitada_id=v_fatura.subempreitada_id;
  if not found then return jsonb_build_object('aplicavel',false); end if;
  v_proj_faturado:=v_res.total_faturado+
    case when p_etapa='aprovada_tecnicamente' and v_fatura.estado_fluxo not in ('aprovada_tecnicamente','enviada_financeiro','paga') then v_fatura.valor else 0 end;
  v_proj_pago:=v_res.total_pago+
    case when p_etapa='paga' and v_fatura.estado_fluxo<>'paga' and v_fatura.estado_pagamento<>'pago' then v_fatura.valor else 0 end;
  return jsonb_build_object(
    'aplicavel',true,'valor_contratual',v_res.valor_contratual,
    'aditamentos_aprovados',v_res.aditamentos_aprovados,'total_aprovado',v_res.total_aprovado,
    'total_faturado_atual',v_res.total_faturado,'total_pago_atual',v_res.total_pago,
    'total_faturado_projetado',v_proj_faturado,'total_pago_projetado',v_proj_pago,
    'ultrapassa_faturacao',v_proj_faturado>v_res.total_aprovado,
    'ultrapassa_pagamento',v_proj_pago>v_res.total_aprovado,
    'excesso_faturacao',greatest(v_proj_faturado-v_res.total_aprovado,0),
    'excesso_pagamento',greatest(v_proj_pago-v_res.total_aprovado,0)
  );
end;$function$;

create or replace function public.fn_sincronizar_alerta_limite_subempreitada(p_subempreitada_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_sub public.subempreitadas; v_obra public.obras; v_res record; v_excesso numeric;
begin
  select * into v_sub from public.subempreitadas where id=p_subempreitada_id;
  if not found then return; end if;
  select * into v_obra from public.obras where id=v_sub.obra_id;
  select
    coalesce(v_sub.valor_adjudicado,0)::numeric as valor_contratual,
    coalesce((select sum(a.valor) from public.subempreitada_aditamentos a
      where a.subempreitada_id=v_sub.id and a.estado='aprovado'),0)::numeric as aditamentos_aprovados,
    (coalesce(v_sub.valor_adjudicado,0)+coalesce((select sum(a.valor)
      from public.subempreitada_aditamentos a
      where a.subempreitada_id=v_sub.id and a.estado='aprovado'),0))::numeric as total_aprovado,
    (coalesce((select sum(f.valor) from public.faturas f
      where f.subempreitada_id=v_sub.id
        and f.estado_fluxo in ('aprovada_tecnicamente','enviada_financeiro','paga')),0)
      + coalesce((select sum(p.valor) from public.pagamentos_subempreitada p
        where p.subempreitada_id=v_sub.id and not exists (
          select 1 from public.faturas f
          where f.subempreitada_id=p.subempreitada_id
            and (f.estado_fluxo='paga' or f.estado_pagamento='pago')
            and nullif(lower(btrim(coalesce(f.numero_doc,''))),'') is not null
            and lower(btrim(f.numero_doc))=lower(btrim(coalesce(to_jsonb(p)->>'numero_doc',to_jsonb(p)->>'documento','')))
        )),0))::numeric as total_faturado,
    (coalesce((select sum(f.valor) from public.faturas f
      where f.subempreitada_id=v_sub.id
        and (f.estado_fluxo='paga' or f.estado_pagamento='pago')),0)
      + coalesce((select sum(p.valor) from public.pagamentos_subempreitada p
        where p.subempreitada_id=v_sub.id and not exists (
          select 1 from public.faturas f
          where f.subempreitada_id=p.subempreitada_id
            and (f.estado_fluxo='paga' or f.estado_pagamento='pago')
            and nullif(lower(btrim(coalesce(f.numero_doc,''))),'') is not null
            and lower(btrim(f.numero_doc))=lower(btrim(coalesce(to_jsonb(p)->>'numero_doc',to_jsonb(p)->>'documento','')))
        )),0))::numeric as total_pago
  into v_res;
  v_excesso:=greatest(
    coalesce(v_res.total_faturado-v_res.total_aprovado,0),
    coalesce(v_res.total_pago-v_res.total_aprovado,0),
    0
  );
  if v_excesso>0 then
    insert into public.alertas(
      empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,
      data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado
    ) select v_obra.empresa_id,v_sub.obra_id,'subempreitada_limite_contratual','subempreitadas',v_sub.id,
      'Limite contratual da subempreitada ultrapassado',
      coalesce(v_sub.especialidade,'Subempreitada')||' · Obra '||coalesce(v_obra.numero::text,'—')||
      ' · aprovado '||to_char(v_res.total_aprovado,'FM999G999G990D00')||' € · faturado '||
      to_char(v_res.total_faturado,'FM999G999G990D00')||' € · excesso '||to_char(v_excesso,'FM999G999G990D00')||' €',
      current_date,0,current_date,'diretor_obra','pendente'
    where not exists (
      select 1 from public.alertas a where a.tipo='subempreitada_limite_contratual'
      and a.entidade_tipo='subempreitadas' and a.entidade_id=v_sub.id and a.estado='pendente'
    );
  else
    update public.alertas set estado='resolvido'
    where tipo='subempreitada_limite_contratual' and entidade_tipo='subempreitadas'
      and entidade_id=v_sub.id and estado='pendente';
  end if;
end;$function$;

create or replace function public.fn_trigger_alerta_limite_subempreitada()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $function$
declare v_subempreitada_id uuid;
begin
  v_subempreitada_id:=case when tg_op='DELETE' then old.subempreitada_id else new.subempreitada_id end;
  if v_subempreitada_id is not null then perform public.fn_sincronizar_alerta_limite_subempreitada(v_subempreitada_id); end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;$function$;

drop trigger if exists trg_alerta_limite_fatura_subempreitada on public.faturas;
create trigger trg_alerta_limite_fatura_subempreitada
after insert or update of estado_fluxo,estado_pagamento,valor,subempreitada_id or delete on public.faturas
for each row execute function public.fn_trigger_alerta_limite_subempreitada();

drop trigger if exists trg_alerta_limite_pagamento_subempreitada on public.pagamentos_subempreitada;
create trigger trg_alerta_limite_pagamento_subempreitada
after insert or update of valor,subempreitada_id or delete on public.pagamentos_subempreitada
for each row execute function public.fn_trigger_alerta_limite_subempreitada();

drop trigger if exists trg_alerta_limite_aditamento_subempreitada on public.subempreitada_aditamentos;
create trigger trg_alerta_limite_aditamento_subempreitada
after insert or update of valor,estado,subempreitada_id or delete on public.subempreitada_aditamentos
for each row execute function public.fn_trigger_alerta_limite_subempreitada();

-- O gatilho protege movimentos futuros. Esta passagem inicial garante que
-- contratos que já estavam ultrapassados antes da migração também aparecem
-- imediatamente na Visão Geral dos responsáveis da obra.
do $backfill$
declare v_subempreitada_id uuid;
begin
  for v_subempreitada_id in select id from public.subempreitadas loop
    perform public.fn_sincronizar_alerta_limite_subempreitada(v_subempreitada_id);
  end loop;
end;
$backfill$;

-- A aprovação técnica passa a refletir-se imediatamente no faturado do pacote.
-- O custo realizado continua corretamente separado: só muda quando há pagamento.
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
      coalesce(ctrl.valor_contratual,s.valor_adjudicado,0) valor_adjudicado,
      coalesce(ctrl.aditamentos_aprovados,0) aditamentos_aprovados,
      coalesce(ctrl.total_aprovado,s.valor_adjudicado,0) total_aprovado,
      lower(coalesce(s.estado,'')) sub_estado,
      coalesce(ctrl.total_pago,0) sub_pago,coalesce(ctrl.total_faturado,0) sub_faturado
    from public.planeamento_itens pi join public.fases f on f.id=pi.fase_id
    left join public.subempreitadas s on s.id=pi.subempreitada_id
    left join public.fn_resumo_controle_subempreitadas_obra(p_obra_id) ctrl
      on ctrl.subempreitada_id=s.id
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
        v_sub_compromisso:=v_sub_compromisso+greatest(v_row.total_aprovado-v_row.sub_pago,0);
      else v_sub_estimado:=v_sub_estimado+v_row.total_aprovado; end if;
    end if;
    v_pacotes:=v_pacotes||jsonb_build_array(jsonb_build_object(
      'planeamento_item_id',v_row.id,'codigo',v_row.codigo,'descricao',v_row.descricao,'executado_por',v_row.executado_por,
      'valor_orca_pl',v_row.valor_orca_pl,'valor_real_pl',case when v_row.custo_pl_confirmado then v_row.valor_real_pl else 0 end,
      'pl_confirmacao_pendente',(v_row.executado_por in ('PL','misto') and v_row.estado='concluido' and not v_row.custo_pl_confirmado),
      'valor_adjudicado',v_row.valor_adjudicado,'aditamentos_aprovados',v_row.aditamentos_aprovados,
      'total_aprovado',v_row.total_aprovado,'sub_faturado',v_row.sub_faturado,
      'sub_real',case when v_row.compromisso_confirmado then v_row.sub_pago else 0 end,
      'sub_compromisso',case when v_row.compromisso_confirmado then greatest(v_row.total_aprovado-v_row.sub_pago,0) else 0 end,
      'sub_confirmacao_pendente',(v_row.executado_por in ('subempreitada','misto') and v_row.subempreitada_id is not null and not v_row.compromisso_confirmado and v_row.sub_estado in ('adjudicada','adjudicado','em_execucao','concluida','concluido')),
      'percentual_faturado',case when v_row.total_aprovado>0 then round(v_row.sub_faturado/v_row.total_aprovado*100,2) else 0 end,
      'percentual_pago',case when v_row.total_aprovado>0 then round(v_row.sub_pago/v_row.total_aprovado*100,2) else 0 end));
  end loop;
  return jsonb_build_object(
    'formula','Custo Real = PL confirmado + pagamentos; Faturado = faturas validadas; Compromisso = contrato + aditamentos aprovados - pagamentos',
    'pl',jsonb_build_object('estimado',v_pl_estimado,'real',v_pl_real),
    'subempreitadas',jsonb_build_object('estimado',v_sub_estimado,'real',v_sub_real,'compromisso',v_sub_compromisso),
    'pl_estimado',v_pl_estimado,'pl_real',v_pl_real,'sub_estimado',v_sub_estimado,'sub_real',v_sub_real,
    'custo_real_total',v_pl_real+v_sub_real,'custos_estimados_total',v_pl_estimado+v_sub_estimado,
    'compromisso_total',v_sub_compromisso,'pacotes',v_pacotes);
end;$function$;

revoke all on function public.fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid) from public,anon;
revoke all on function public.fn_decidir_aditamento_subempreitada(uuid,text,text) from public,anon;
revoke all on function public.fn_resumo_controle_subempreitadas_obra(uuid) from public,anon;
revoke all on function public.fn_verificar_limite_fatura_subempreitada(uuid,text) from public,anon;
grant execute on function public.fn_registar_aditamento_subempreitada(uuid,text,numeric,uuid) to authenticated;
grant execute on function public.fn_decidir_aditamento_subempreitada(uuid,text,text) to authenticated;
grant execute on function public.fn_resumo_controle_subempreitadas_obra(uuid) to authenticated;
grant execute on function public.fn_verificar_limite_fatura_subempreitada(uuid,text) to authenticated;
grant execute on function public.fn_resumo_componentes_custo_obra(uuid) to authenticated;
revoke all on function public.fn_sincronizar_alerta_limite_subempreitada(uuid) from public,anon,authenticated;
revoke all on function public.fn_trigger_alerta_limite_subempreitada() from public,anon,authenticated;

-- A pesquisa de semelhança recebe a obra atual para destacar primeiro
-- documentos do mesmo fornecedor e valor lançados noutra obra.
create or replace function public.fn_verificar_fatura_semelhante(
  p_fornecedor_id uuid,
  p_valor numeric,
  p_numero_doc text,
  p_obra_id uuid,
  p_excluir_fatura_id uuid
) returns table (
  id uuid,obra_id uuid,obra_numero text,numero_doc text,valor numeric,
  data_fatura date,estado_aprovacao text,estado_pagamento text,
  tipo_correspondencia text,outra_obra boolean
)
language plpgsql security definer set search_path=public stable as $function$
declare v_atual public.utilizadores; v_tolerancia numeric;
begin
  select * into v_atual from public.utilizadores u
  where u.id=public.fn_utilizador_atual_id() and coalesce(u.ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  if p_fornecedor_id is null or p_valor is null or p_valor<0 then
    raise exception 'Fornecedor e valor são obrigatórios para verificar duplicados.';
  end if;
  v_tolerancia:=greatest(1.00,abs(p_valor)*0.005);
  return query
  select f.id,f.obra_id,o.numero::text,f.numero_doc,f.valor,f.data_fatura,
    f.estado_aprovacao,f.estado_pagamento,
    case when lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) then 'exata' else 'semelhante' end::text,
    (f.obra_id is distinct from p_obra_id)
  from public.faturas f join public.obras o on o.id=f.obra_id
  where o.empresa_id=v_atual.empresa_id and f.fornecedor_id=p_fornecedor_id
    and f.id is distinct from p_excluir_fatura_id
    and (lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) or abs(f.valor-p_valor)<=v_tolerancia)
  order by
    case when lower(btrim(f.numero_doc))=lower(btrim(coalesce(p_numero_doc,''))) then 0 else 1 end,
    (f.obra_id is distinct from p_obra_id) desc,abs(f.valor-p_valor),f.data_fatura desc
  limit 5;
end;$function$;

revoke all on function public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid) from public,anon;
grant execute on function public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid) to authenticated;

commit;

select
  to_regclass('public.subempreitada_aditamentos') is not null as aditamentos_ativos,
  to_regprocedure('public.fn_resumo_controle_subempreitadas_obra(uuid)') is not null as controlo_contratual_ativo,
  to_regprocedure('public.fn_verificar_limite_fatura_subempreitada(uuid,text)') is not null as alerta_limite_ativo,
  to_regprocedure('public.fn_sincronizar_alerta_limite_subempreitada(uuid)') is not null as alerta_persistente_ativo,
  to_regprocedure('public.fn_verificar_fatura_semelhante(uuid,numeric,text,uuid,uuid)') is not null as semelhanca_entre_obras_ativa;
