begin;

-- Correção incremental para bases onde o controlo contratual já foi
-- instalado: o alerta pertence ao Diretor de Obra e deve abranger também os
-- excessos que existiam antes da criação dos gatilhos.
create or replace function public.fn_sincronizar_alerta_limite_subempreitada(p_subempreitada_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $function$
declare
  v_sub public.subempreitadas;
  v_obra public.obras;
  v_res record;
  v_excesso numeric;
begin
  select * into v_sub from public.subempreitadas where id=p_subempreitada_id;
  if not found then return; end if;

  select * into v_obra from public.obras where id=v_sub.obra_id;
  -- Cálculo interno, sem chamar a RPC de consulta. A RPC mantém a sua
  -- validação de auth.uid(), enquanto esta função também pode ser executada
  -- por gatilhos e pelo Editor SQL, onde não existe sessão da aplicação.
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
    update public.alertas
    set destinatario_role='diretor_obra',
        titulo='Limite contratual da subempreitada ultrapassado',
        descricao=coalesce(v_sub.especialidade,'Subempreitada')||' · Obra '||coalesce(v_obra.numero::text,'—')||
          ' · aprovado '||to_char(v_res.total_aprovado,'FM999G999G990D00')||' € · faturado '||
          to_char(v_res.total_faturado,'FM999G999G990D00')||' € · excesso '||to_char(v_excesso,'FM999G999G990D00')||' €',
        data_evento_referencia=current_date,
        data_gatilho=current_date
    where tipo='subempreitada_limite_contratual'
      and entidade_tipo='subempreitadas'
      and entidade_id=v_sub.id
      and estado='pendente';

    if not found then
      insert into public.alertas(
        empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,
        data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado
      ) values (
        v_obra.empresa_id,v_sub.obra_id,'subempreitada_limite_contratual','subempreitadas',v_sub.id,
        'Limite contratual da subempreitada ultrapassado',
        coalesce(v_sub.especialidade,'Subempreitada')||' · Obra '||coalesce(v_obra.numero::text,'—')||
          ' · aprovado '||to_char(v_res.total_aprovado,'FM999G999G990D00')||' € · faturado '||
          to_char(v_res.total_faturado,'FM999G999G990D00')||' € · excesso '||to_char(v_excesso,'FM999G999G990D00')||' €',
        current_date,0,current_date,'diretor_obra','pendente'
      );
    end if;
  else
    update public.alertas
    set estado='resolvido'
    where tipo='subempreitada_limite_contratual'
      and entidade_tipo='subempreitadas'
      and entidade_id=v_sub.id
      and estado='pendente';
  end if;
end;
$function$;

do $backfill$
declare v_subempreitada_id uuid;
begin
  for v_subempreitada_id in select id from public.subempreitadas loop
    perform public.fn_sincronizar_alerta_limite_subempreitada(v_subempreitada_id);
  end loop;
end;
$backfill$;

commit;

select
  count(*) filter (where estado='pendente') as alertas_limite_pendentes,
  count(*) filter (where estado='pendente' and destinatario_role='diretor_obra') as alertas_para_diretor
from public.alertas
where tipo='subempreitada_limite_contratual';
