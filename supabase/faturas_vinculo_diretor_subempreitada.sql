-- PRIMELINE | O Diretor confirma o trabalho/orçamento da fatura de subempreitada
begin;

-- O Administrativo pode lançar ou corrigir a fatura sem conhecer o contrato.
-- Se indicar um contrato, continua a ser obrigatório que obra e fornecedor coincidam.
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
  p_itens jsonb default '[]'::jsonb
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_item jsonb;
  v_quantidade numeric;
  v_valor_unitario numeric;
  v_valor_total numeric;
  v_desconto_percentual numeric;
  v_valor_desconto numeric;
  v_foi_devolvida boolean;
begin
  select * into v_fatura from public.faturas where id = p_fatura_id for update;
  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente e não pode ser editada.';
  end if;
  v_foi_devolvida := v_fatura.estado_fluxo = 'devolvida_administrativo';

  if not public.fn_e_admin()
     and not (public.fn_e_administrativo() and (
       v_foi_devolvida or (v_fatura.criado_por is not null and v_fatura.criado_por = v_utilizador_id)
     )) then
    raise exception 'Só o Administrativo responsável pela correção ou a Gerência pode editar esta fatura.';
  end if;

  if p_obra_id is null or p_fornecedor_id is null
     or nullif(btrim(p_numero_doc), '') is null or p_data_fatura is null
     or p_valor is null or p_valor <= 0 then
    raise exception 'Preencha obra, fornecedor, número, data e valor da fatura.';
  end if;
  if p_tipo_origem not in ('subempreitada', 'material', 'estaleiro') then
    raise exception 'Tipo de despesa inválido.';
  end if;
  if p_condicao_pagamento not in ('imediato', '15_dias', '30_dias', 'outra_data') then
    raise exception 'Condição de pagamento inválida.';
  end if;
  if p_condicao_pagamento = 'outra_data' and p_data_vencimento is null then
    raise exception 'Indique a data de vencimento para a opção Outra data.';
  end if;
  if p_condicao_pagamento <> 'outra_data' and p_data_vencimento is not null then
    raise exception 'A data manual só pode ser usada com a opção Outra data.';
  end if;
  if p_tipo_origem = 'subempreitada' and p_subempreitada_id is not null and not exists (
    select 1 from public.subempreitadas s
    where s.id = p_subempreitada_id and s.obra_id = p_obra_id
      and s.fornecedor_id = p_fornecedor_id
  ) then
    raise exception 'A subempreitada não corresponde à obra e ao fornecedor selecionados.';
  elsif p_tipo_origem <> 'subempreitada' and p_subempreitada_id is not null then
    raise exception 'Faturas de material ou estaleiro não podem ter subempreitada associada.';
  end if;

  update public.faturas
  set obra_id = p_obra_id,
      tipo_origem = p_tipo_origem,
      fornecedor_id = p_fornecedor_id,
      subempreitada_id = p_subempreitada_id,
      numero_doc = btrim(p_numero_doc),
      data_fatura = p_data_fatura,
      valor = p_valor,
      condicao_pagamento = p_condicao_pagamento,
      data_vencimento = case when p_condicao_pagamento = 'outra_data' then p_data_vencimento else null end,
      estado_fluxo = case when v_foi_devolvida then 'recebida' else estado_fluxo end,
      observacao_devolucao = case when v_foi_devolvida then null else observacao_devolucao end,
      devolvido_por = case when v_foi_devolvida then null else devolvido_por end,
      devolvido_em = case when v_foi_devolvida then null else devolvido_em end
  where id = p_fatura_id
  returning * into v_fatura;

  delete from public.faturas_itens where fatura_id = p_fatura_id;
  if p_tipo_origem = 'material' then
    if jsonb_typeof(coalesce(p_itens, '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(p_itens, '[]'::jsonb)) = 0 then
      raise exception 'Uma fatura de material exige pelo menos um artigo.';
    end if;
    for v_item in select value from jsonb_array_elements(p_itens)
    loop
      v_quantidade := nullif(v_item ->> 'quantidade', '')::numeric;
      v_valor_unitario := nullif(v_item ->> 'valor_unitario', '')::numeric;
      v_valor_total := nullif(v_item ->> 'valor_total', '')::numeric;
      v_desconto_percentual := nullif(v_item ->> 'desconto_percentual', '')::numeric;
      v_valor_desconto := nullif(v_item ->> 'valor_desconto', '')::numeric;
      if nullif(btrim(v_item ->> 'designacao'), '') is null
         or nullif(btrim(v_item ->> 'unidade'), '') is null
         or v_quantidade is null or v_quantidade <= 0
         or v_valor_unitario is null or v_valor_unitario < 0
         or v_valor_total is null or v_valor_total < 0
         or (v_desconto_percentual is not null and (v_desconto_percentual < 0 or v_desconto_percentual > 100))
         or (v_valor_desconto is not null and v_valor_desconto < 0) then
        raise exception 'Existe um artigo de material incompleto ou inválido.';
      end if;
      insert into public.faturas_itens (
        fatura_id, designacao, unidade, quantidade, valor_unitario, valor_total,
        desconto_percentual, valor_desconto
      ) values (
        p_fatura_id, btrim(v_item ->> 'designacao'), btrim(v_item ->> 'unidade'),
        v_quantidade, v_valor_unitario, v_valor_total,
        v_desconto_percentual, v_valor_desconto
      );
    end loop;
  end if;
  return v_fatura;
end;
$function$;

revoke all on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) from public, anon;
grant execute on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) to authenticated;

-- Só a equipa técnica com acesso à obra pode confirmar ou alterar o vínculo.
create or replace function public.fn_vincular_fatura_subempreitada(
  p_fatura_id uuid,
  p_subempreitada_id uuid
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_fatura public.faturas;
begin
  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found then
    raise exception 'A fatura selecionada não existe.';
  end if;
  if v_fatura.tipo_origem <> 'subempreitada' then
    raise exception 'Só as faturas de subempreitada podem ser vinculadas a um trabalho.';
  end if;
  if v_fatura.estado_fluxo not in ('recebida', 'em_validacao') then
    raise exception 'O vínculo só pode ser alterado antes da aprovação técnica.';
  end if;
  if not (public.fn_pode_editar_obra(v_fatura.obra_id) or public.fn_e_admin()) then
    raise exception 'Só a equipa técnica responsável pela obra pode confirmar este vínculo.' using errcode = '42501';
  end if;
  if p_subempreitada_id is not null and not exists (
    select 1
    from public.subempreitadas s
    where s.id = p_subempreitada_id
      and s.obra_id = v_fatura.obra_id
      and s.fornecedor_id = v_fatura.fornecedor_id
  ) then
    raise exception 'O trabalho selecionado não pertence simultaneamente a esta obra e a este fornecedor.';
  end if;

  update public.faturas
  set subempreitada_id = p_subempreitada_id
  where id = p_fatura_id
  returning * into v_fatura;

  return v_fatura;
end;
$function$;

revoke all on function public.fn_vincular_fatura_subempreitada(uuid, uuid)
from public, anon;
grant execute on function public.fn_vincular_fatura_subempreitada(uuid, uuid)
to authenticated;

-- Proteção transversal: nem chamadas diretas nem outras RPCs podem aprovar uma
-- fatura de subempreitada sem contrato, ou associá-la a outra obra/fornecedor.
create or replace function public.fn_validar_vinculo_fatura_subempreitada()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.tipo_origem = 'subempreitada' then
    if new.subempreitada_id is not null and not exists (
      select 1 from public.subempreitadas s
      where s.id = new.subempreitada_id
        and s.obra_id = new.obra_id
        and s.fornecedor_id = new.fornecedor_id
    ) then
      raise exception 'A subempreitada não corresponde à obra e ao fornecedor da fatura.';
    end if;
    if new.estado_fluxo in ('aprovada_tecnicamente', 'enviada_financeiro', 'paga')
       and new.subempreitada_id is null then
      raise exception 'Selecione o trabalho/orçamento antes de aprovar tecnicamente a fatura.';
    end if;
  elsif new.subempreitada_id is not null then
    raise exception 'Faturas que não são de subempreitada não podem ter um trabalho associado.';
  end if;
  return new;
end;
$function$;

revoke all on function public.fn_validar_vinculo_fatura_subempreitada()
from public, anon, authenticated;

drop trigger if exists trg_validar_vinculo_fatura_subempreitada on public.faturas;
create trigger trg_validar_vinculo_fatura_subempreitada
before insert or update of tipo_origem, subempreitada_id, obra_id, fornecedor_id, estado_fluxo
on public.faturas
for each row execute function public.fn_validar_vinculo_fatura_subempreitada();

-- Garante que a confirmação do Diretor fica no histórico mesmo em instalações
-- onde o conjunto inicial de triggers de auditoria ainda não incluiu faturas.
do $block$
begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_faturas on public.faturas;
    create trigger trg_auditoria_faturas
    after insert or update or delete on public.faturas
    for each row execute function public.fn_registar_log_auditoria('id');
  end if;
end;
$block$;

commit;

select
  to_regprocedure('public.fn_vincular_fatura_subempreitada(uuid,uuid)') is not null as vinculo_diretor_ativo,
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.faturas'::regclass
      and tgname = 'trg_validar_vinculo_fatura_subempreitada'
      and not tgisinternal and tgenabled <> 'D'
  ) as aprovacao_sem_vinculo_bloqueada,
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.faturas'::regclass
      and tgname = 'trg_auditoria_faturas'
      and not tgisinternal and tgenabled <> 'D'
  ) as auditoria_vinculo_ativa;
