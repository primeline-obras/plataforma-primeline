-- PRIMELINE | Observação no lançamento/aprovação de faturas
begin;

alter table public.faturas
  add column if not exists observacao text;

comment on column public.faturas.observacao is
  'Observação editável no lançamento e no momento da aprovação da fatura.';

-- Mantém a RPC de edição já existente e acrescenta a observação ao mesmo fluxo.
create or replace function public.fn_editar_fatura_pendente(
  p_fatura_id uuid,
  p_obra_id uuid,
  p_tipo_origem text,
  p_fornecedor_id uuid,
  p_subempreitada_id uuid,
  p_numero_doc text,
  p_data_fatura date,
  p_valor numeric,
  p_condicao_pagamento text,
  p_data_vencimento date,
  p_observacao text,
  p_itens jsonb default '[]'::jsonb
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
begin
  v_fatura := public.fn_editar_fatura_pendente(
    p_fatura_id,
    p_obra_id,
    p_tipo_origem,
    p_fornecedor_id,
    p_subempreitada_id,
    p_numero_doc,
    p_data_fatura,
    p_valor,
    p_condicao_pagamento,
    p_data_vencimento,
    p_itens
  );

  update public.faturas
  set observacao = nullif(btrim(p_observacao), '')
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;

revoke all on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, text, jsonb
) from public, anon;

grant execute on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, text, jsonb
) to authenticated;

-- A assinatura com observação substitui a decisão anterior. O terceiro
-- argumento tem default para manter compatibilidade com chamadas antigas.
drop function if exists public.fn_decidir_fatura(uuid, text, text);
drop function if exists public.fn_decidir_fatura(uuid, text);

create function public.fn_decidir_fatura(
  p_fatura_id uuid,
  p_decisao text,
  p_observacao text default null
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
  v_sem_guia boolean := false;
  v_bloquear_sem_guia constant boolean := false;
begin
  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;

  if not public.fn_pode_editar_obra(v_fatura.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;

  if p_decisao = 'aprovado' then
    v_sem_guia := not exists (
      select 1
      from public.faturas_guias
      where fatura_id = p_fatura_id
    );
  end if;

  if v_bloquear_sem_guia
    and p_decisao = 'aprovado'
    and v_sem_guia then
    raise exception 'É obrigatório anexar pelo menos uma guia antes da aprovação.';
  end if;

  update public.faturas
  set estado_aprovacao = p_decisao,
      aprovado_por = null,
      data_aprovacao = now(),
      observacao = case
        when p_observacao is null then v_fatura.observacao
        else nullif(btrim(p_observacao), '')
      end,
      aprovada_sem_guia = case
        when p_decisao = 'aprovado' then v_sem_guia
        else false
      end
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;

revoke all on function public.fn_decidir_fatura(uuid, text, text)
from public, anon;

grant execute on function public.fn_decidir_fatura(uuid, text, text)
to authenticated;

commit;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'faturas'
      and column_name = 'observacao'
  ) as campo_observacao,
  to_regprocedure(
    'public.fn_decidir_fatura(uuid,text,text)'
  ) is not null as rpc_decisao_com_observacao,
  to_regprocedure(
    'public.fn_editar_fatura_pendente(uuid,uuid,text,uuid,uuid,text,date,numeric,text,date,text,jsonb)'
  ) is not null as rpc_edicao_com_observacao;
