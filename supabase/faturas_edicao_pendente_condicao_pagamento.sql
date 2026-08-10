-- PRIMELINE | Edição de faturas pendentes e quarta condição de pagamento
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.faturas
  add column if not exists data_vencimento date;

-- Consolida eventuais datas manuais antigas na nova opção única.
update public.faturas
set condicao_pagamento = 'outra_data'
where data_vencimento is not null
  and condicao_pagamento is distinct from 'outra_data';

-- Remove apenas checks que já incidiam sobre condicao_pagamento, mesmo que o
-- nome concreto da constraint varie entre ambientes.
do $$
declare
  v_constraint record;
begin
  for v_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.faturas'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%condicao_pagamento%'
  loop
    execute format('alter table public.faturas drop constraint %I', v_constraint.conname);
  end loop;
end;
$$;

alter table public.faturas
  add constraint faturas_condicao_pagamento_check
  check (
    condicao_pagamento is null
    or condicao_pagamento = any (array[
      'imediato'::text,
      '15_dias'::text,
      '30_dias'::text,
      'outra_data'::text
    ])
  ),
  add constraint faturas_outra_data_check
  check (
    (condicao_pagamento = 'outra_data' and data_vencimento is not null)
    or (condicao_pagamento is distinct from 'outra_data' and data_vencimento is null)
  );

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
as $$
declare
  v_fatura public.faturas;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_item jsonb;
  v_quantidade numeric;
  v_valor_unitario numeric;
  v_valor_total numeric;
  v_desconto_percentual numeric;
  v_valor_desconto numeric;
begin
  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente e não pode ser editada.';
  end if;

  if not public.fn_e_admin()
     and not (
       public.fn_e_administrativo()
       and v_fatura.criado_por is not null
       and v_fatura.criado_por = v_utilizador_id
     ) then
    raise exception 'Só quem lançou a fatura ou a Gerência pode editá-la enquanto pendente.';
  end if;

  if p_obra_id is null
     or p_fornecedor_id is null
     or nullif(btrim(p_numero_doc), '') is null
     or p_data_fatura is null
     or p_valor is null
     or p_valor <= 0 then
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

  if p_tipo_origem = 'subempreitada' then
    if p_subempreitada_id is null or not exists (
      select 1
      from public.subempreitadas s
      where s.id = p_subempreitada_id
        and s.obra_id = p_obra_id
        and s.fornecedor_id = p_fornecedor_id
    ) then
      raise exception 'A subempreitada não corresponde à obra e ao fornecedor selecionados.';
    end if;
  elsif p_subempreitada_id is not null then
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
      data_vencimento = case when p_condicao_pagamento = 'outra_data' then p_data_vencimento else null end
  where id = p_fatura_id
  returning * into v_fatura;

  -- Os artigos fazem parte da mesma correção e são substituídos de forma
  -- transacional; uma falha deixa a fatura e os artigos anteriores intactos.
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
        p_fatura_id,
        btrim(v_item ->> 'designacao'),
        btrim(v_item ->> 'unidade'),
        v_quantidade,
        v_valor_unitario,
        v_valor_total,
        v_desconto_percentual,
        v_valor_desconto
      );
    end loop;
  end if;

  return v_fatura;
end;
$$;

revoke all on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) from public, anon;
grant execute on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) to authenticated;

comment on function public.fn_editar_fatura_pendente(
  uuid, uuid, text, uuid, uuid, text, date, numeric, text, date, jsonb
) is 'Edita uma fatura ainda pendente; apenas o Administrativo autor do lançamento ou a Gerência.';

commit;
