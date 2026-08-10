-- PRIMELINE | Importação XLSX com confirmação no frontend e gravação transacional.
-- Executar uma vez no SQL Editor antes de usar os três botões "Importar Excel".

begin;

alter table public.consultas_subempreitada
  add column if not exists data_proposta date,
  add column if not exists custo_direto numeric,
  add column if not exists preco_venda numeric,
  add column if not exists margem_prevista numeric;

create table if not exists public.alteracoes_tee_itens (
  id uuid primary key default gen_random_uuid(),
  tee_id uuid not null references public.alteracoes_tee(id) on delete cascade,
  numero_artigo text not null,
  descricao text not null,
  unidade text,
  quantidade numeric,
  preco_unitario numeric,
  valor_total numeric,
  criado_em timestamptz not null default now()
);

alter table public.alteracoes_tee_itens enable row level security;
revoke all on public.alteracoes_tee_itens from anon;
grant select on public.alteracoes_tee_itens to authenticated;

drop policy if exists alteracoes_tee_itens_select on public.alteracoes_tee_itens;
create policy alteracoes_tee_itens_select
on public.alteracoes_tee_itens for select to authenticated
using (
  exists (
    select 1 from public.alteracoes_tee t
    where t.id = tee_id
      and (public.fn_pode_ver_obra(t.obra_id) or public.fn_e_financeiro())
  )
);

create or replace function public.fn_log_importacao_xlsx(
  p_modulo text,
  p_nome_ficheiro text,
  p_total integer,
  p_detalhes jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.log_auditoria (
    tabela_afetada, registo_id, campo, valor_anterior, valor_novo,
    utilizador_id, criado_em
  ) values (
    'public.importacoes_excel',
    gen_random_uuid(),
    '__IMPORT__',
    null,
    jsonb_build_object(
      'modulo', p_modulo,
      'ficheiro', p_nome_ficheiro,
      'linhas_importadas', p_total,
      'detalhes', coalesce(p_detalhes, '{}'::jsonb)
    )::text,
    public.fn_utilizador_atual_id(),
    now()
  );
end;
$$;

revoke all on function public.fn_log_importacao_xlsx(text, text, integer, jsonb) from public, anon, authenticated;

create or replace function public.fn_importar_subempreitadas_xlsx(
  p_linhas jsonb,
  p_nome_ficheiro text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linha jsonb;
  v_consulta public.consultas_subempreitada%rowtype;
  v_candidato public.consultas_subempreitada_candidatos%rowtype;
  v_subempreitada public.subempreitadas%rowtype;
  v_importadas integer := 0;
  v_estado text;
  v_obra_id uuid;
  v_fase_id uuid;
  v_fornecedor_id uuid;
begin
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023', message = 'As linhas da importação são inválidas.';
  end if;

  for v_linha in select value from jsonb_array_elements(p_linhas)
  loop
    v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
    v_fase_id := nullif(v_linha ->> 'fase_id', '')::uuid;
    v_fornecedor_id := nullif(v_linha ->> 'fornecedor_id', '')::uuid;
    v_estado := v_linha ->> 'estado';

    if not public.fn_pode_editar_obra(v_obra_id) then
      raise exception using errcode = '42501', message = 'Sem permissão para importar subempreitadas nesta obra.';
    end if;
    if nullif(btrim(v_linha ->> 'trabalho'), '') is null
       or v_estado not in ('em_consulta', 'recusado', 'adjudicado', 'em_execucao', 'concluido') then
      raise exception using errcode = '23514', message = 'Linha de subempreitada inválida.';
    end if;
    if v_fase_id is not null and not exists (
      select 1 from public.fases f where f.id = v_fase_id and f.obra_id = v_obra_id
    ) then
      raise exception using errcode = '23514', message = 'A fase não pertence à obra indicada.';
    end if;
    if v_fornecedor_id is not null and not exists (select 1 from public.fornecedores f where f.id = v_fornecedor_id) then
      raise exception using errcode = '23503', message = 'Fornecedor inexistente. Nenhum fornecedor foi criado automaticamente.';
    end if;
    if v_estado in ('adjudicado', 'em_execucao', 'concluido')
       and (v_fase_id is null or v_fornecedor_id is null or nullif(v_linha ->> 'valor_adjudicado', '') is null) then
      raise exception using errcode = '23514', message = 'Uma subempreitada adjudicada exige fase, fornecedor e valor.';
    end if;

    insert into public.consultas_subempreitada (
      obra_id, fase_id, trabalho, data_pedido, data_proposta, custo_direto,
      preco_venda, margem_prevista, fornecedor_id, data_contrato, estado
    ) values (
      v_obra_id, v_fase_id, btrim(v_linha ->> 'trabalho'),
      coalesce(nullif(v_linha ->> 'data_pedido', '')::date, current_date),
      nullif(v_linha ->> 'data_proposta', '')::date,
      nullif(v_linha ->> 'custo_direto', '')::numeric,
      nullif(v_linha ->> 'preco_venda', '')::numeric,
      nullif(v_linha ->> 'margem_prevista', '')::numeric,
      v_fornecedor_id,
      nullif(v_linha ->> 'data_contrato', '')::date,
      case when v_estado in ('adjudicado', 'em_execucao', 'concluido') then 'adjudicado' else v_estado end
    ) returning * into v_consulta;

    if v_fornecedor_id is not null then
      insert into public.consultas_subempreitada_candidatos (
        consulta_subempreitada_id, fornecedor_id, valor_total, escolhido
      ) values (
        v_consulta.id, v_fornecedor_id,
        nullif(v_linha ->> 'valor_adjudicado', '')::numeric,
        v_estado in ('adjudicado', 'em_execucao', 'concluido')
      ) returning * into v_candidato;
    end if;

    if v_estado in ('adjudicado', 'em_execucao', 'concluido') then
      if v_fornecedor_id is null then
        raise exception using errcode = '23514', message = 'Uma linha adjudicada exige fornecedor existente.';
      end if;
      insert into public.subempreitadas (
        obra_id, fase_id, consulta_id, fornecedor_id, especialidade,
        valor_adjudicado, estado, tipo_pagamento, condicao_pagamento,
        data_inicio_prevista, data_fim_prevista
      ) values (
        v_obra_id, v_fase_id, v_consulta.id, v_fornecedor_id,
        btrim(v_linha ->> 'trabalho'),
        nullif(v_linha ->> 'valor_adjudicado', '')::numeric,
        v_estado,
        nullif(v_linha ->> 'tipo_pagamento', ''),
        nullif(v_linha ->> 'condicao_pagamento', ''),
        nullif(v_linha ->> 'data_inicio_prevista', '')::date,
        nullif(v_linha ->> 'data_fim_prevista', '')::date
      ) returning * into v_subempreitada;
    end if;
    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx('subempreitadas', p_nome_ficheiro, v_importadas, jsonb_build_object('linhas_recebidas', jsonb_array_length(p_linhas)));
  return jsonb_build_object('importadas', v_importadas);
end;
$$;

create or replace function public.fn_importar_tees_xlsx(
  p_linhas jsonb,
  p_nome_ficheiro text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linha jsonb;
  v_item jsonb;
  v_tee public.alteracoes_tee%rowtype;
  v_importadas integer := 0;
  v_itens integer := 0;
  v_obra_id uuid;
  v_fase_id uuid;
begin
  if jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023', message = 'As linhas da importação são inválidas.';
  end if;

  for v_linha in select value from jsonb_array_elements(p_linhas)
  loop
    v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
    v_fase_id := nullif(v_linha ->> 'fase_id', '')::uuid;
    if not public.fn_pode_editar_obra(v_obra_id) then
      raise exception using errcode = '42501', message = 'Sem permissão para importar TEEs nesta obra.';
    end if;
    if nullif(btrim(v_linha ->> 'numero'), '') is null then
      raise exception using errcode = '23514', message = 'O Nº TEE é obrigatório.';
    end if;
    if nullif(btrim(v_linha ->> 'descricao'), '') is null then
      raise exception using errcode = '23514', message = 'A descrição do TEE é obrigatória.';
    end if;
    if not exists (select 1 from public.fases f where f.id = v_fase_id and f.obra_id = v_obra_id) then
      raise exception using errcode = '23514', message = 'A fase do TEE não pertence à obra.';
    end if;

    insert into public.alteracoes_tee (
      obra_id, fase_id, numero, descricao, especialidade, valor, preco_custo,
      dias_prorrogacao, data_envio, data_resposta, estado_aprovacao_gerencia,
      estado_aprovacao_cliente, revisao, data_inicio_execucao, data_fim_execucao
    ) values (
      v_obra_id, v_fase_id, btrim(v_linha ->> 'numero'), nullif(v_linha ->> 'descricao', ''),
      nullif(v_linha ->> 'especialidade', ''), nullif(v_linha ->> 'valor', '')::numeric,
      nullif(v_linha ->> 'preco_custo', '')::numeric, coalesce(nullif(v_linha ->> 'dias_prorrogacao', '')::numeric, 0),
      nullif(v_linha ->> 'data_envio', '')::date, nullif(v_linha ->> 'data_resposta', '')::date,
      case when public.fn_e_admin()
        then coalesce(nullif(v_linha ->> 'estado_aprovacao_gerencia', ''), 'pendente')
        else 'pendente'
      end,
      coalesce(nullif(v_linha ->> 'estado_aprovacao_cliente', ''), 'pendente'),
      coalesce(nullif(v_linha ->> 'revisao', ''), 'REV00'),
      nullif(v_linha ->> 'data_inicio_execucao', '')::date,
      nullif(v_linha ->> 'data_fim_execucao', '')::date
    ) returning * into v_tee;

    if jsonb_typeof(v_linha -> 'itens') = 'array' then
      for v_item in select value from jsonb_array_elements(v_linha -> 'itens')
      loop
        insert into public.alteracoes_tee_itens (
          tee_id, numero_artigo, descricao, unidade, quantidade, preco_unitario, valor_total
        ) values (
          v_tee.id, btrim(v_item ->> 'numero_artigo'), btrim(v_item ->> 'descricao'),
          nullif(v_item ->> 'unidade', ''), nullif(v_item ->> 'quantidade', '')::numeric,
          nullif(v_item ->> 'preco_unitario', '')::numeric,
          coalesce(nullif(v_item ->> 'valor_total', '')::numeric,
                   nullif(v_item ->> 'quantidade', '')::numeric * nullif(v_item ->> 'preco_unitario', '')::numeric)
        );
        v_itens := v_itens + 1;
      end loop;
    end if;
    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx('tees', p_nome_ficheiro, v_importadas, jsonb_build_object('itens_importados', v_itens));
  return jsonb_build_object('importadas', v_importadas, 'itens_importados', v_itens);
end;
$$;

create or replace function public.fn_importar_mapa_financeiro_xlsx(
  p_ano integer,
  p_linhas jsonb,
  p_nome_ficheiro text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linha jsonb;
  v_valor jsonb;
  v_mes integer;
  v_importadas integer := 0;
  v_obra_id uuid;
  v_debito_id uuid;
  v_categoria text;
  v_descricao text;
begin
  if not (public.fn_e_admin() or public.fn_e_financeiro()) then
    raise exception using errcode = '42501', message = 'Sem permissão para importar o Mapa Financeiro.';
  end if;
  if p_ano not between 2000 and 2200 or jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023', message = 'Ano ou linhas de importação inválidos.';
  end if;

  for v_linha in select value from jsonb_array_elements(p_linhas)
  loop
    if v_linha ->> 'tipo' = 'obra' then
      v_obra_id := nullif(v_linha ->> 'obra_id', '')::uuid;
      if not exists (select 1 from public.obras o where o.id = v_obra_id) then
        raise exception using errcode = '23503', message = 'Obra inexistente no Mapa Financeiro.';
      end if;
      v_mes := 0;
      for v_valor in select value from jsonb_array_elements(v_linha -> 'meses')
      loop
        v_mes := v_mes + 1;
        if jsonb_typeof(v_valor) = 'number' then
          insert into public.mapa_financeiro_ajustes (
            obra_id, ano, mes, valor_calculado_referencia, valor_ajustado,
            motivo, atualizado_por, atualizado_em
          ) values (
            v_obra_id, p_ano, v_mes, null, (v_valor #>> '{}')::numeric,
            'Importação Excel: ' || p_nome_ficheiro, public.fn_utilizador_atual_id(), now()
          ) on conflict (obra_id, ano, mes) do update set
            valor_ajustado = excluded.valor_ajustado,
            motivo = excluded.motivo,
            atualizado_por = excluded.atualizado_por,
            atualizado_em = excluded.atualizado_em;
        end if;
      end loop;
    elsif v_linha ->> 'tipo' = 'despesa_fixa' then
      v_categoria := v_linha ->> 'categoria';
      if v_categoria not in ('remuneracoes_sede', 'despesas_sede', 'despesas_armazem') then
        raise exception using errcode = '23514', message = 'Grupo de despesas fixas inválido.';
      end if;
      v_descricao := 'Importação Mapa Financeiro · ' || v_categoria;
      select id into v_debito_id from public.debitos_diretos
      where obra_id is null and categoria = v_categoria and descricao = v_descricao
      order by criado_em limit 1;
      if v_debito_id is null then
        insert into public.debitos_diretos (
          obra_id, descricao, categoria, valor_previsto, recorrencia,
          dia_mes, data_inicio, ativo, criado_por
        ) values (
          null, v_descricao, v_categoria, 0, 'mensal', 1,
          make_date(p_ano, 1, 1), true, public.fn_utilizador_atual_id()
        ) returning id into v_debito_id;
      end if;
      v_mes := 0;
      for v_valor in select value from jsonb_array_elements(v_linha -> 'meses')
      loop
        v_mes := v_mes + 1;
        if jsonb_typeof(v_valor) = 'number' then
          insert into public.debitos_diretos_lancamentos (debito_direto_id, data, valor)
          values (v_debito_id, make_date(p_ano, v_mes, 1), (v_valor #>> '{}')::numeric)
          on conflict (debito_direto_id, data) do update set valor = excluded.valor;
        end if;
      end loop;
    end if;
    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx('mapa_financeiro', p_nome_ficheiro, v_importadas, jsonb_build_object('ano', p_ano));
  return jsonb_build_object('importadas', v_importadas);
end;
$$;

revoke all on function public.fn_importar_subempreitadas_xlsx(jsonb, text) from public, anon;
revoke all on function public.fn_importar_tees_xlsx(jsonb, text) from public, anon;
revoke all on function public.fn_importar_mapa_financeiro_xlsx(integer, jsonb, text) from public, anon;
grant execute on function public.fn_importar_subempreitadas_xlsx(jsonb, text) to authenticated;
grant execute on function public.fn_importar_tees_xlsx(jsonb, text) to authenticated;
grant execute on function public.fn_importar_mapa_financeiro_xlsx(integer, jsonb, text) to authenticated;

commit;

select
  to_regclass('public.alteracoes_tee_itens') is not null as tee_itens,
  to_regprocedure('public.fn_importar_subempreitadas_xlsx(jsonb,text)') is not null as importar_subempreitadas,
  to_regprocedure('public.fn_importar_tees_xlsx(jsonb,text)') is not null as importar_tees,
  to_regprocedure('public.fn_importar_mapa_financeiro_xlsx(integer,jsonb,text)') is not null as importar_mapa_financeiro;
