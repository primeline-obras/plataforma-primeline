-- PRIMELINE | Validação técnica consistente das faturas
-- Guarda a observação e a indicação de aprovação sem guia na mesma transação
-- que avança o fluxo, evitando estados parciais.
begin;

drop function if exists public.fn_avancar_estado_fluxo_fatura(uuid, text);
drop function if exists public.fn_avancar_estado_fluxo_fatura(uuid, text, date);
drop function if exists public.fn_avancar_estado_fluxo_fatura(uuid, text, date, text);

create function public.fn_avancar_estado_fluxo_fatura(
  p_fatura_id uuid,
  p_novo_estado text,
  p_data_pagamento date default null,
  p_observacao text default null
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
  v_ordem constant text[] := array[
    'recebida',
    'em_validacao',
    'aprovada_tecnicamente',
    'enviada_financeiro',
    'paga'
  ];
  v_sem_guia boolean := false;
begin
  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found then
    raise exception 'Fatura não encontrada.';
  end if;

  if array_position(v_ordem, p_novo_estado) is null
     or array_position(v_ordem, p_novo_estado)
        <> array_position(v_ordem, v_fatura.estado_fluxo) + 1 then
    raise exception 'A fatura deve seguir os cinco estados pela ordem definida.';
  end if;

  if p_novo_estado = 'paga' then
    if not public.fn_e_financeiro() then
      raise exception 'Só o Financeiro pode marcar a fatura como paga.' using errcode = '42501';
    end if;
  elsif not (public.fn_pode_editar_obra(v_fatura.obra_id) or public.fn_e_admin()) then
    raise exception 'Sem permissão para avançar a validação desta fatura.' using errcode = '42501';
  end if;

  if p_novo_estado = 'aprovada_tecnicamente' then
    v_sem_guia := not exists (
      select 1
      from public.faturas_guias
      where fatura_id = p_fatura_id
    );
  end if;

  update public.faturas
  set estado_fluxo = p_novo_estado,
      estado_aprovacao = case
        when p_novo_estado in ('aprovada_tecnicamente', 'enviada_financeiro', 'paga') then 'aprovado'
        else 'pendente'
      end,
      estado_pagamento = case when p_novo_estado = 'paga' then 'pago' else 'por_pagar' end,
      data_aprovacao = case
        when p_novo_estado = 'aprovada_tecnicamente' then now()
        else data_aprovacao
      end,
      aprovado_por = case
        when p_novo_estado = 'aprovada_tecnicamente' then public.fn_utilizador_atual_id()
        else aprovado_por
      end,
      observacao = case
        when p_novo_estado = 'aprovada_tecnicamente' and p_observacao is not null
          then nullif(btrim(p_observacao), '')
        else observacao
      end,
      aprovada_sem_guia = case
        when p_novo_estado = 'aprovada_tecnicamente' then v_sem_guia
        else aprovada_sem_guia
      end,
      data_pagamento = case
        when p_novo_estado = 'paga' then coalesce(p_data_pagamento, data_pagamento, current_date)
        else data_pagamento
      end
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;

revoke all on function public.fn_avancar_estado_fluxo_fatura(uuid, text, date, text)
from public, anon;

grant execute on function public.fn_avancar_estado_fluxo_fatura(uuid, text, date, text)
to authenticated;

commit;

select
  to_regprocedure('public.fn_avancar_estado_fluxo_fatura(uuid,text,date,text)') is not null
    as fluxo_faturas_consistente;
