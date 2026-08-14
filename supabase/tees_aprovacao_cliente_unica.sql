-- PRIMELINE | TEEs — aprovação do cliente como único estado relevante
-- Mantém intactas as colunas históricas de aprovação interna.

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
    if not exists (
      select 1 from public.fases f
      where f.id = v_fase_id and f.obra_id = v_obra_id
    ) then
      raise exception using errcode = '23514', message = 'A fase do TEE não pertence à obra.';
    end if;

    insert into public.alteracoes_tee (
      obra_id, fase_id, numero, descricao, especialidade, valor, preco_custo,
      dias_prorrogacao, data_envio, data_resposta, estado_aprovacao_cliente,
      revisao, data_inicio_execucao, data_fim_execucao
    ) values (
      v_obra_id, v_fase_id, btrim(v_linha ->> 'numero'), nullif(v_linha ->> 'descricao', ''),
      nullif(v_linha ->> 'especialidade', ''), nullif(v_linha ->> 'valor', '')::numeric,
      nullif(v_linha ->> 'preco_custo', '')::numeric,
      coalesce(nullif(v_linha ->> 'dias_prorrogacao', '')::numeric, 0),
      nullif(v_linha ->> 'data_envio', '')::date,
      nullif(v_linha ->> 'data_resposta', '')::date,
      coalesce(nullif(v_linha ->> 'estado_aprovacao_cliente', ''), 'pendente'),
      coalesce(nullif(v_linha ->> 'revisao', ''), 'REV00'),
      nullif(v_linha ->> 'data_inicio_execucao', '')::date,
      nullif(v_linha ->> 'data_fim_execucao', '')::date
    ) returning * into v_tee;

    if jsonb_typeof(v_linha -> 'itens') = 'array' then
      for v_item in select value from jsonb_array_elements(v_linha -> 'itens')
      loop
        insert into public.alteracoes_tee_itens (
          tee_id, numero_artigo, descricao, unidade,
          quantidade, preco_unitario, valor_total
        ) values (
          v_tee.id,
          btrim(v_item ->> 'numero_artigo'),
          btrim(v_item ->> 'descricao'),
          nullif(v_item ->> 'unidade', ''),
          nullif(v_item ->> 'quantidade', '')::numeric,
          nullif(v_item ->> 'preco_unitario', '')::numeric,
          coalesce(
            nullif(v_item ->> 'valor_total', '')::numeric,
            nullif(v_item ->> 'quantidade', '')::numeric
              * nullif(v_item ->> 'preco_unitario', '')::numeric
          )
        );
        v_itens := v_itens + 1;
      end loop;
    end if;
    v_importadas := v_importadas + 1;
  end loop;

  perform public.fn_log_importacao_xlsx(
    'tees', p_nome_ficheiro, v_importadas,
    jsonb_build_object('itens_importados', v_itens)
  );
  return jsonb_build_object(
    'importadas', v_importadas,
    'itens_importados', v_itens
  );
end;
$$;

revoke all on function public.fn_importar_tees_xlsx(jsonb, text) from public, anon;
grant execute on function public.fn_importar_tees_xlsx(jsonb, text) to authenticated;

select
  position('estado_aprovacao_gerencia' in pg_get_functiondef(
    'public.fn_importar_tees_xlsx(jsonb,text)'::regprocedure
  )) = 0 as importacao_ignora_aprovacao_gerencia;
