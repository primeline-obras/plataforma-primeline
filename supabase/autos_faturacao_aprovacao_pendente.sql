-- PRIMELINE | Aprovação de faturas originadas em Autos de Medição
-- Migração aditiva e idempotente. Não elimina faturação existente.

begin;

alter table public.faturacao
  add column if not exists estado_aprovacao text not null default 'pendente',
  add column if not exists aprovado_por uuid references public.utilizadores(id) on delete set null,
  add column if not exists data_aprovacao timestamptz,
  add column if not exists estado_pagamento text not null default 'por_pagar',
  add column if not exists pago_por uuid references public.utilizadores(id) on delete set null,
  add column if not exists data_pagamento date;

update public.faturacao
set estado_aprovacao = case
      when estado = 'emitida' and estado_aprovacao = 'pendente' then 'aprovado'
      else estado_aprovacao
    end,
    estado_pagamento = case when data_recebimento is not null then 'pago' else estado_pagamento end,
    data_pagamento = coalesce(data_pagamento, data_recebimento)
where (estado = 'emitida' and estado_aprovacao = 'pendente')
   or (data_recebimento is not null and estado_pagamento <> 'pago')
   or (data_recebimento is not null and data_pagamento is null);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'faturacao_estado_aprovacao_check') then
    alter table public.faturacao add constraint faturacao_estado_aprovacao_check
      check (estado_aprovacao in ('pendente', 'aprovado', 'recusado'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'faturacao_estado_pagamento_check') then
    alter table public.faturacao add constraint faturacao_estado_pagamento_check
      check (estado_pagamento in ('por_pagar', 'pago'));
  end if;
end;
$$;

create or replace function public.fn_decidir_faturacao_auto(
  p_faturacao_id uuid,
  p_decisao text
)
returns public.faturacao
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_faturacao public.faturacao;
begin
  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select * into v_faturacao from public.faturacao
  where id = p_faturacao_id for update;

  if not found or v_faturacao.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;
  if not public.fn_pode_editar_obra(v_faturacao.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;

  update public.faturacao
  set estado_aprovacao = p_decisao,
      estado = case when p_decisao = 'aprovado' then 'emitida' else 'rascunho' end,
      aprovado_por = public.fn_utilizador_atual_id(),
      data_aprovacao = now()
  where id = p_faturacao_id
  returning * into v_faturacao;
  return v_faturacao;
end;
$$;

create or replace function public.fn_marcar_faturacao_auto_paga(
  p_faturacao_id uuid,
  p_data_pagamento date,
  p_valor_pago numeric
)
returns public.faturacao
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_faturacao public.faturacao;
begin
  if not public.fn_e_financeiro() then
    raise exception 'O pagamento está reservado ao papel Financeiro.';
  end if;

  select * into v_faturacao from public.faturacao
  where id = p_faturacao_id for update;

  if not found or v_faturacao.estado_aprovacao <> 'aprovado'
     or v_faturacao.estado_pagamento <> 'por_pagar' then
    raise exception 'A fatura não está aprovada ou já foi paga.';
  end if;
  if coalesce(p_valor_pago, 0) <= 0 then
    raise exception 'O valor pago tem de ser superior a zero.';
  end if;

  update public.faturacao
  set estado_pagamento = 'pago',
      pago_por = public.fn_utilizador_atual_id(),
      data_pagamento = coalesce(p_data_pagamento, current_date),
      data_recebimento = coalesce(p_data_pagamento, current_date),
      valor_recebido = p_valor_pago
  where id = p_faturacao_id
  returning * into v_faturacao;
  return v_faturacao;
end;
$$;

revoke update on table public.faturacao from authenticated;
revoke all on function public.fn_decidir_faturacao_auto(uuid, text) from public, anon;
revoke all on function public.fn_marcar_faturacao_auto_paga(uuid, date, numeric) from public, anon;
grant execute on function public.fn_decidir_faturacao_auto(uuid, text) to authenticated;
grant execute on function public.fn_marcar_faturacao_auto_paga(uuid, date, numeric) to authenticated;

commit;
