CREATE OR REPLACE FUNCTION public.fn_planeamento_lote_preview_v1(p_lote jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_obra_id uuid;
  v_expected_items jsonb;
  v_expected_deps jsonb;
  v_changes jsonb;
  v_dependencies jsonb;

  v_change jsonb;
  v_dep jsonb;
  v_id text;

  v_conflicts jsonb := '[]'::jsonb;
  v_more jsonb := '[]'::jsonb;
  v_cascade jsonb := '[]'::jsonb;

  v_db_count integer;
  v_expected_count integer;
  v_rows integer := 0;
  v_iter integer;
  v_limit integer;
  v_cycle boolean := false;

  v_seen_changes text[] := ARRAY[]::text[];
BEGIN
  IF p_lote IS NULL
     OR jsonb_typeof(p_lote) <> 'object'
     OR p_lote->>'version' IS DISTINCT FROM '1'
     OR NULLIF(p_lote->>'obra_id', '') IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: lote inválido.';
  END IF;

  v_obra_id := (p_lote->>'obra_id')::uuid;

  IF NOT COALESCE(public.fn_pode_editar_obra(v_obra_id), false) THEN
    RAISE EXCEPTION 'FORBIDDEN: sem permissão para editar esta obra.'
      USING ERRCODE = '42501';
  END IF;

  v_expected_items := COALESCE(p_lote->'expected_items', '[]'::jsonb);
  v_expected_deps := COALESCE(p_lote->'expected_dependencies', '[]'::jsonb);
  v_changes := COALESCE(p_lote->'changes', '[]'::jsonb);
  v_dependencies := COALESCE(p_lote->'dependencies', '[]'::jsonb);

  IF jsonb_typeof(v_expected_items) <> 'array'
     OR jsonb_typeof(v_expected_deps) <> 'array'
     OR jsonb_typeof(v_changes) <> 'array'
     OR jsonb_typeof(v_dependencies) <> 'array'
     OR jsonb_typeof(COALESCE(p_lote->'approved_cascade', '[]'::jsonb)) <> 'array'
  THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: arrays do lote inválidos.';
  END IF;


  -- ----------------------------------------------------------
  -- Snapshot otimista das tarefas
  -- ----------------------------------------------------------

  SELECT count(*)
  INTO v_db_count
  FROM public.planeamento_itens pi
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id;

  v_expected_count := jsonb_array_length(v_expected_items);

  IF v_db_count <> v_expected_count THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object(
        'type', 'stale_revision',
        'area', 'items',
        'expected', v_expected_count,
        'current', v_db_count
      )
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_expected_items) e(value)
    WHERE NULLIF(e.value->>'id', '') IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.planeamento_itens pi
         JOIN public.fases f ON f.id = pi.fase_id
         WHERE f.obra_id = v_obra_id
           AND pi.id::text = e.value->>'id'
           AND to_jsonb(pi) @> (e.value - '_new' - '_archive')
       )
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object(
        'type', 'stale_revision',
        'area', 'items'
      )
    );
  END IF;

  IF (
    SELECT count(*)
    FROM jsonb_array_elements(v_expected_items)
  ) <> (
    SELECT count(DISTINCT e.value->>'id')
    FROM jsonb_array_elements(v_expected_items) e(value)
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object('type', 'duplicate_id', 'area', 'expected_items')
    );
  END IF;


  -- ----------------------------------------------------------
  -- Snapshot otimista das dependências
  -- ----------------------------------------------------------

  SELECT count(*)
  INTO v_db_count
  FROM public.planeamento_itens_dependencias d
  JOIN public.planeamento_itens pi ON pi.id = d.item_id
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id;

  v_expected_count := jsonb_array_length(v_expected_deps);

  IF v_db_count <> v_expected_count THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object(
        'type', 'stale_revision',
        'area', 'dependencies',
        'expected', v_expected_count,
        'current', v_db_count
      )
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_expected_deps) e(value)
    WHERE NULLIF(e.value->>'id', '') IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.planeamento_itens_dependencias d
         JOIN public.planeamento_itens pi ON pi.id = d.item_id
         JOIN public.fases f ON f.id = pi.fase_id
         WHERE f.obra_id = v_obra_id
           AND d.id::text = e.value->>'id'
           AND to_jsonb(d) @> e.value
       )
  ) THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object(
        'type', 'stale_revision',
        'area', 'dependencies'
      )
    );
  END IF;

  IF jsonb_array_length(v_conflicts) > 0 THEN
    RETURN jsonb_build_object(
      'conflicts', v_conflicts,
      'approved_cascade', '[]'::jsonb
    );
  END IF;


  -- ----------------------------------------------------------
  -- Estado temporário da obra
  -- ----------------------------------------------------------

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.pl_lote_items (
    id text PRIMARY KEY,
    persist_id uuid,
    fase_id uuid,
    codigo text,
    descricao text,
    responsavel text,
    duracao_dias numeric,
    data_inicio_prevista date,
    data_fim_prevista date,
    data_fim_real date,
    peso_percentual numeric,
    percentual_executado numeric,
    estado text,
    causa_atraso text,
    impacto text,
    impedido boolean,
    observacao_impedimento text,
    data_inicio_baseline date,
    data_fim_baseline date,
    data_inicio_real date,
    especialidade_id uuid,
    executado_por text,
    item_orcamento_id uuid,
    custo_estado text,
    valor_estimado numeric,
    valor_orca_pl numeric,
    arquivado_em timestamptz,
    archive_requested boolean NOT NULL DEFAULT false,
    manual_dates boolean NOT NULL DEFAULT false,
    is_new boolean NOT NULL DEFAULT false,
    direct_start date,
    direct_end date,
    calc_start date,
    calc_end date,
    shift_duration integer
  ) ON COMMIT DROP;

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.pl_lote_deps (
    id text PRIMARY KEY,
    item_id text NOT NULL,
    depende_de_item_id text NOT NULL,
    tipo text NOT NULL,
    atraso_dias integer NOT NULL
  ) ON COMMIT DROP;

  TRUNCATE pg_temp.pl_lote_items;
  TRUNCATE pg_temp.pl_lote_deps;

  INSERT INTO pg_temp.pl_lote_items (
    id,
    persist_id,
    fase_id,
    codigo,
    descricao,
    responsavel,
    duracao_dias,
    data_inicio_prevista,
    data_fim_prevista,
    data_fim_real,
    peso_percentual,
    percentual_executado,
    estado,
    causa_atraso,
    impacto,
    impedido,
    observacao_impedimento,
    data_inicio_baseline,
    data_fim_baseline,
    data_inicio_real,
    especialidade_id,
    executado_por,
    item_orcamento_id,
    custo_estado,
    valor_estimado,
    valor_orca_pl,
    arquivado_em
  )
  SELECT
    pi.id::text,
    pi.id,
    pi.fase_id,
    pi.codigo,
    pi.descricao,
    pi.responsavel,
    pi.duracao_dias,
    pi.data_inicio_prevista,
    pi.data_fim_prevista,
    pi.data_fim_real,
    pi.peso_percentual,
    pi.percentual_executado,
    pi.estado,
    pi.causa_atraso,
    pi.impacto,
    pi.impedido,
    pi.observacao_impedimento,
    pi.data_inicio_baseline,
    pi.data_fim_baseline,
    pi.data_inicio_real,
    pi.especialidade_id,
    pi.executado_por,
    pi.item_orcamento_id,
    pi.custo_estado,
    pi.valor_estimado,
    pi.valor_orca_pl,
    pi.arquivado_em
  FROM public.planeamento_itens pi
  JOIN public.fases f ON f.id = pi.fase_id
  WHERE f.obra_id = v_obra_id;


  -- ----------------------------------------------------------
  -- Aplicar alterações apenas na cópia temporária
  -- ----------------------------------------------------------

  FOR v_change IN
    SELECT value
    FROM jsonb_array_elements(v_changes)
  LOOP
    v_id := NULLIF(v_change->>'id', '');

    IF v_id IS NULL OR v_id = ANY(v_seen_changes) THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object('type', 'duplicate_id', 'id', v_id)
      );
      CONTINUE;
    END IF;

    v_seen_changes := array_append(v_seen_changes, v_id);

    IF EXISTS (
      SELECT 1
      FROM jsonb_object_keys(v_change) AS k(key)
      WHERE k.key NOT IN (
        'id', '_new', '_archive',
        'fase_id', 'codigo', 'descricao', 'responsavel',
        'duracao_dias',
        'data_inicio_prevista', 'data_fim_prevista',
        'data_inicio_real', 'data_fim_real',
        'peso_percentual', 'percentual_executado',
        'percentual_ponderado', 'estado',
        'causa_atraso', 'impacto',
        'impedido', 'observacao_impedimento',
        'especialidade_id', 'executado_por',
        'item_orcamento_id', 'custo_estado',
        'valor_estimado', 'valor_orca_pl'
      )
    ) THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'type', 'validation',
          'id', v_id,
          'message', 'Campo não autorizado no lote.'
        )
      );
      CONTINUE;
    END IF;

    IF COALESCE((v_change->>'_new')::boolean, false) THEN

      IF EXISTS (
        SELECT 1
        FROM pg_temp.pl_lote_items
        WHERE id = v_id
      ) THEN
        v_conflicts := v_conflicts || jsonb_build_array(
          jsonb_build_object('type', 'duplicate_id', 'id', v_id)
        );
        CONTINUE;
      END IF;

      IF COALESCE((v_change->>'_archive')::boolean, false) THEN
        v_conflicts := v_conflicts || jsonb_build_array(
          jsonb_build_object(
            'type', 'validation',
            'id', v_id,
            'message', 'Uma tarefa nova não pode ser arquivada no mesmo lote.'
          )
        );
        CONTINUE;
      END IF;

      INSERT INTO pg_temp.pl_lote_items (
        id,
        persist_id,
        fase_id,
        codigo,
        descricao,
        responsavel,
        duracao_dias,
        data_inicio_prevista,
        data_fim_prevista,
        data_fim_real,
        peso_percentual,
        percentual_executado,
        estado,
        causa_atraso,
        impacto,
        impedido,
        observacao_impedimento,
        data_inicio_real,
        especialidade_id,
        executado_por,
        item_orcamento_id,
        custo_estado,
        valor_estimado,
        valor_orca_pl,
        archive_requested,
        manual_dates,
        is_new
      )
      VALUES (
        v_id,
        NULL,
        NULLIF(v_change->>'fase_id', '')::uuid,
        NULLIF(btrim(v_change->>'codigo'), ''),
        NULLIF(btrim(v_change->>'descricao'), ''),
        NULLIF(btrim(v_change->>'responsavel'), ''),
        CASE
          WHEN v_change ? 'duracao_dias'
            THEN NULLIF(v_change->>'duracao_dias', '')::numeric
          WHEN NULLIF(v_change->>'data_inicio_prevista', '') IS NOT NULL
           AND NULLIF(v_change->>'data_fim_prevista', '') IS NOT NULL
            THEN NULLIF(v_change->>'data_fim_prevista', '')::date
               - NULLIF(v_change->>'data_inicio_prevista', '')::date
          ELSE NULL
        END,
        NULLIF(v_change->>'data_inicio_prevista', '')::date,
        NULLIF(v_change->>'data_fim_prevista', '')::date,
        NULLIF(v_change->>'data_fim_real', '')::date,
        NULLIF(v_change->>'peso_percentual', '')::numeric,
        COALESCE(NULLIF(v_change->>'percentual_executado', '')::numeric, 0),
        NULL,
        NULLIF(btrim(v_change->>'causa_atraso'), ''),
        NULLIF(btrim(v_change->>'impacto'), ''),
        COALESCE((v_change->>'impedido')::boolean, false),
        NULLIF(btrim(v_change->>'observacao_impedimento'), ''),
        NULLIF(v_change->>'data_inicio_real', '')::date,
        NULLIF(v_change->>'especialidade_id', '')::uuid,
        NULLIF(v_change->>'executado_por', ''),
        NULLIF(v_change->>'item_orcamento_id', '')::uuid,
        COALESCE(NULLIF(v_change->>'custo_estado', ''), 'orcamentado'),
        NULLIF(v_change->>'valor_estimado', '')::numeric,
        NULLIF(v_change->>'valor_orca_pl', '')::numeric,
        false,
        v_change ?| ARRAY[
          'data_inicio_prevista',
          'data_fim_prevista',
          'data_inicio_real',
          'data_fim_real'
        ],
        true
      );

    ELSE

      IF NOT EXISTS (
        SELECT 1
        FROM pg_temp.pl_lote_items
        WHERE id = v_id
      ) THEN
        v_conflicts := v_conflicts || jsonb_build_array(
          jsonb_build_object('type', 'missing_task', 'id', v_id)
        );
        CONTINUE;
      END IF;

      UPDATE pg_temp.pl_lote_items
      SET
        fase_id =
          CASE WHEN v_change ? 'fase_id'
            THEN NULLIF(v_change->>'fase_id', '')::uuid
            ELSE fase_id END,

        codigo =
          CASE WHEN v_change ? 'codigo'
            THEN NULLIF(btrim(v_change->>'codigo'), '')
            ELSE codigo END,

        descricao =
          CASE WHEN v_change ? 'descricao'
            THEN NULLIF(btrim(v_change->>'descricao'), '')
            ELSE descricao END,

        responsavel =
          CASE WHEN v_change ? 'responsavel'
            THEN NULLIF(btrim(v_change->>'responsavel'), '')
            ELSE responsavel END,

        duracao_dias =
          CASE WHEN v_change ? 'duracao_dias'
            THEN NULLIF(v_change->>'duracao_dias', '')::numeric
            ELSE duracao_dias END,

        data_inicio_prevista =
          CASE WHEN v_change ? 'data_inicio_prevista'
            THEN NULLIF(v_change->>'data_inicio_prevista', '')::date
            ELSE data_inicio_prevista END,

        data_fim_prevista =
          CASE WHEN v_change ? 'data_fim_prevista'
            THEN NULLIF(v_change->>'data_fim_prevista', '')::date
            ELSE data_fim_prevista END,

        data_inicio_real =
          CASE WHEN v_change ? 'data_inicio_real'
            THEN NULLIF(v_change->>'data_inicio_real', '')::date
            ELSE data_inicio_real END,

        data_fim_real =
          CASE WHEN v_change ? 'data_fim_real'
            THEN NULLIF(v_change->>'data_fim_real', '')::date
            ELSE data_fim_real END,

        peso_percentual =
          CASE WHEN v_change ? 'peso_percentual'
            THEN NULLIF(v_change->>'peso_percentual', '')::numeric
            ELSE peso_percentual END,

        percentual_executado =
          CASE WHEN v_change ? 'percentual_executado'
            THEN NULLIF(v_change->>'percentual_executado', '')::numeric
            ELSE percentual_executado END,

        causa_atraso =
          CASE WHEN v_change ? 'causa_atraso'
            THEN NULLIF(btrim(v_change->>'causa_atraso'), '')
            ELSE causa_atraso END,

        impacto =
          CASE WHEN v_change ? 'impacto'
            THEN NULLIF(btrim(v_change->>'impacto'), '')
            ELSE impacto END,

        impedido =
          CASE WHEN v_change ? 'impedido'
            THEN COALESCE((v_change->>'impedido')::boolean, false)
            ELSE impedido END,

        observacao_impedimento =
          CASE WHEN v_change ? 'observacao_impedimento'
            THEN NULLIF(btrim(v_change->>'observacao_impedimento'), '')
            ELSE observacao_impedimento END,

        especialidade_id =
          CASE WHEN v_change ? 'especialidade_id'
            THEN NULLIF(v_change->>'especialidade_id', '')::uuid
            ELSE especialidade_id END,

        executado_por =
          CASE WHEN v_change ? 'executado_por'
            THEN NULLIF(v_change->>'executado_por', '')
            ELSE executado_por END,

        item_orcamento_id =
          CASE WHEN v_change ? 'item_orcamento_id'
            THEN NULLIF(v_change->>'item_orcamento_id', '')::uuid
            ELSE item_orcamento_id END,

        custo_estado =
          CASE WHEN v_change ? 'custo_estado'
            THEN COALESCE(NULLIF(v_change->>'custo_estado', ''), 'orcamentado')
            ELSE custo_estado END,

        valor_estimado =
          CASE WHEN v_change ? 'valor_estimado'
            THEN NULLIF(v_change->>'valor_estimado', '')::numeric
            ELSE valor_estimado END,

        valor_orca_pl =
          CASE WHEN v_change ? 'valor_orca_pl'
            THEN NULLIF(v_change->>'valor_orca_pl', '')::numeric
            ELSE valor_orca_pl END,

        archive_requested =
          CASE WHEN v_change ? '_archive'
            THEN COALESCE((v_change->>'_archive')::boolean, false)
            ELSE archive_requested END,

        manual_dates =
          manual_dates OR v_change ?| ARRAY[
            'data_inicio_prevista',
            'data_fim_prevista',
            'data_inicio_real',
            'data_fim_real'
          ]
      WHERE id = v_id;

    END IF;
  END LOOP;


  -- ----------------------------------------------------------
  -- Campos derivados na cópia temporária
  -- ----------------------------------------------------------

  UPDATE pg_temp.pl_lote_items
  SET
    estado =
      CASE
        WHEN percentual_executado >= 100 THEN 'concluido'
        WHEN percentual_executado > 0 THEN 'em_execucao'
        ELSE 'por_iniciar'
      END,

    direct_start = data_inicio_prevista,
    direct_end = data_fim_prevista,
    calc_start = data_inicio_prevista,
    calc_end = data_fim_prevista,

    shift_duration =
      CASE
        WHEN data_inicio_prevista IS NOT NULL
         AND data_fim_prevista IS NOT NULL
          THEN GREATEST(0, data_fim_prevista - data_inicio_prevista)
        ELSE GREATEST(0, CEIL(COALESCE(duracao_dias, 0))::integer)
      END
  WHERE id IS NOT NULL;


  -- ----------------------------------------------------------
  -- Validação básica das tarefas
  -- ----------------------------------------------------------

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'description',
      'id', id
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE NULLIF(btrim(descricao), '') IS NULL
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'progress',
      'id', id
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE percentual_executado IS NULL
       OR percentual_executado < 0
       OR percentual_executado > 100
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'date_order',
      'id', id
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE data_inicio_prevista IS NOT NULL
      AND data_fim_prevista IS NOT NULL
      AND data_fim_prevista < data_inicio_prevista
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'phase',
      'id', i.id
    ) AS x
    FROM pg_temp.pl_lote_items i
    LEFT JOIN public.fases f
      ON f.id = i.fase_id
     AND f.obra_id = v_obra_id
    WHERE f.id IS NULL
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'validation',
      'id', id,
      'message', 'Executado por inválido.'
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE executado_por IS NOT NULL
      AND executado_por NOT IN ('PL', 'subempreitada', 'misto')
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'validation',
      'id', id,
      'message', 'Estado de custo inválido.'
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE custo_estado IS NOT NULL
      AND custo_estado NOT IN (
        'orcamentado',
        'em_consulta',
        'adjudicado',
        'em_execucao',
        'concluido',
        'cancelado'
      )
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'validation',
      'id', id,
      'message', 'Tarefa impedida sem observação.'
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE COALESCE(impedido, false)
      AND NULLIF(btrim(observacao_impedimento), '') IS NULL
  ) q;

  v_conflicts := v_conflicts || v_more;


  IF EXISTS (
    SELECT 1
    FROM pg_temp.pl_lote_items
    WHERE archive_requested
  )
  AND NULLIF(btrim(p_lote->>'archive_reason'), '') IS NULL
  THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object(
        'type', 'validation',
        'message', 'Motivo de retirada obrigatório.'
      )
    );
  END IF;


  -- ----------------------------------------------------------
  -- Pesos: cada fase com tarefas ativas deve totalizar 100%
  -- ----------------------------------------------------------

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'phase_weights',
      'id', fase_id::text,
      'assigned', COALESCE(sum(peso_percentual), 0),
      'count', count(*)
    ) AS x
    FROM pg_temp.pl_lote_items
    WHERE arquivado_em IS NULL
      AND NOT archive_requested
    GROUP BY fase_id
    HAVING
      count(*) FILTER (
        WHERE peso_percentual IS NULL
           OR peso_percentual < 0
           OR peso_percentual > 100
      ) > 0
      OR abs(COALESCE(sum(peso_percentual), 0) - 100) > 0.010000001
  ) q;

  v_conflicts := v_conflicts || v_more;


  -- ----------------------------------------------------------
  -- Dependências propostas
  -- ----------------------------------------------------------

  FOR v_dep IN
    SELECT value
    FROM jsonb_array_elements(v_dependencies)
  LOOP
    IF NULLIF(v_dep->>'id', '') IS NULL
       OR NULLIF(v_dep->>'item_id', '') IS NULL
       OR NULLIF(v_dep->>'depende_de_item_id', '') IS NULL
    THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object('type', 'missing_dependency')
      );
      CONTINUE;
    END IF;

    IF (v_dep->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'type', 'unsupported_dependency',
          'id', v_dep->>'id'
        )
      );
      CONTINUE;
    END IF;

    IF COALESCE(v_dep->>'tipo', '') <> 'fim_inicio'
       OR COALESCE(v_dep->>'atraso_dias', '') !~ '^-?[0-9]+$'
    THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'type', 'unsupported_dependency',
          'id', v_dep->>'id'
        )
      );
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM pg_temp.pl_lote_deps
      WHERE id = v_dep->>'id'
         OR (
           item_id = v_dep->>'item_id'
           AND depende_de_item_id = v_dep->>'depende_de_item_id'
         )
    ) THEN
      v_conflicts := v_conflicts || jsonb_build_array(
        jsonb_build_object(
          'type', 'duplicate_id',
          'id', v_dep->>'id'
        )
      );
      CONTINUE;
    END IF;

    INSERT INTO pg_temp.pl_lote_deps (
      id,
      item_id,
      depende_de_item_id,
      tipo,
      atraso_dias
    )
    VALUES (
      v_dep->>'id',
      v_dep->>'item_id',
      v_dep->>'depende_de_item_id',
      v_dep->>'tipo',
      (v_dep->>'atraso_dias')::integer
    );
  END LOOP;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'missing_dependency',
      'dependency', d.id
    ) AS x
    FROM pg_temp.pl_lote_deps d
    LEFT JOIN pg_temp.pl_lote_items alvo
      ON alvo.id = d.item_id
    LEFT JOIN pg_temp.pl_lote_items origem
      ON origem.id = d.depende_de_item_id
    WHERE alvo.id IS NULL
       OR origem.id IS NULL
  ) q;

  v_conflicts := v_conflicts || v_more;


  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb)
  INTO v_more
  FROM (
    SELECT jsonb_build_object(
      'type', 'archived_dependency',
      'id', alvo.id,
      'predecessor', origem.id
    ) AS x
    FROM pg_temp.pl_lote_deps d
    JOIN pg_temp.pl_lote_items alvo
      ON alvo.id = d.item_id
    JOIN pg_temp.pl_lote_items origem
      ON origem.id = d.depende_de_item_id
    WHERE alvo.arquivado_em IS NULL
      AND NOT alvo.archive_requested
      AND (
        origem.arquivado_em IS NOT NULL
        OR origem.archive_requested
      )
  ) q;

  v_conflicts := v_conflicts || v_more;


  -- ----------------------------------------------------------
  -- Ciclos
  -- ----------------------------------------------------------

  WITH RECURSIVE walk AS (
    SELECT
      d.item_id AS start_id,
      d.depende_de_item_id AS current_id,
      ARRAY[d.item_id, d.depende_de_item_id]::text[] AS path,
      (d.depende_de_item_id = d.item_id) AS cycle
    FROM pg_temp.pl_lote_deps d
    JOIN pg_temp.pl_lote_items alvo ON alvo.id = d.item_id
    JOIN pg_temp.pl_lote_items origem ON origem.id = d.depende_de_item_id
    WHERE alvo.arquivado_em IS NULL
      AND NOT alvo.archive_requested
      AND origem.arquivado_em IS NULL
      AND NOT origem.archive_requested

    UNION ALL

    SELECT
      w.start_id,
      d.depende_de_item_id,
      w.path || d.depende_de_item_id,
      d.depende_de_item_id = ANY(w.path)
    FROM walk w
    JOIN pg_temp.pl_lote_deps d
      ON d.item_id = w.current_id
    JOIN pg_temp.pl_lote_items alvo
      ON alvo.id = d.item_id
    JOIN pg_temp.pl_lote_items origem
      ON origem.id = d.depende_de_item_id
    WHERE NOT w.cycle
      AND cardinality(w.path) <= (
        SELECT count(*) + 1
        FROM pg_temp.pl_lote_items
      )
      AND alvo.arquivado_em IS NULL
      AND NOT alvo.archive_requested
      AND origem.arquivado_em IS NULL
      AND NOT origem.archive_requested
  )
  SELECT EXISTS (
    SELECT 1
    FROM walk
    WHERE cycle
  )
  INTO v_cycle;

  IF v_cycle THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object('type', 'dependency_cycle')
    );
  END IF;


  IF jsonb_array_length(v_conflicts) > 0 THEN
    RETURN jsonb_build_object(
      'conflicts', v_conflicts,
      'approved_cascade', '[]'::jsonb
    );
  END IF;


  -- ----------------------------------------------------------
  -- Cascata server-side
  -- ----------------------------------------------------------

  v_limit := GREATEST(
    1,
    (SELECT count(*) + 1 FROM pg_temp.pl_lote_items)
  );

  FOR v_iter IN 1..v_limit LOOP

    WITH req AS (
      SELECT
        d.item_id,
        max(
          COALESCE(origem.data_fim_real, origem.calc_end)
          + d.atraso_dias
        )::date AS required_start
      FROM pg_temp.pl_lote_deps d
      JOIN pg_temp.pl_lote_items alvo
        ON alvo.id = d.item_id
      JOIN pg_temp.pl_lote_items origem
        ON origem.id = d.depende_de_item_id
      WHERE alvo.arquivado_em IS NULL
        AND NOT alvo.archive_requested
        AND origem.arquivado_em IS NULL
        AND NOT origem.archive_requested
        AND alvo.data_fim_real IS NULL
        AND alvo.calc_start IS NOT NULL
        AND COALESCE(origem.data_fim_real, origem.calc_end) IS NOT NULL
      GROUP BY d.item_id
    )
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'type', 'manual_date_collision',
        'id', alvo.id,
        'requiredStart', req.required_start::text
      )
    ), '[]'::jsonb)
    INTO v_more
    FROM req
    JOIN pg_temp.pl_lote_items alvo
      ON alvo.id = req.item_id
    WHERE req.required_start > alvo.calc_start
      AND alvo.manual_dates;

    IF jsonb_array_length(v_more) > 0 THEN
      v_conflicts := v_conflicts || v_more;
      EXIT;
    END IF;


    WITH req AS (
      SELECT
        d.item_id,
        max(
          COALESCE(origem.data_fim_real, origem.calc_end)
          + d.atraso_dias
        )::date AS required_start
      FROM pg_temp.pl_lote_deps d
      JOIN pg_temp.pl_lote_items alvo
        ON alvo.id = d.item_id
      JOIN pg_temp.pl_lote_items origem
        ON origem.id = d.depende_de_item_id
      WHERE alvo.arquivado_em IS NULL
        AND NOT alvo.archive_requested
        AND origem.arquivado_em IS NULL
        AND NOT origem.archive_requested
        AND alvo.data_fim_real IS NULL
        AND alvo.calc_start IS NOT NULL
        AND COALESCE(origem.data_fim_real, origem.calc_end) IS NOT NULL
      GROUP BY d.item_id
    )
    UPDATE pg_temp.pl_lote_items alvo
    SET
      calc_start = req.required_start,
      calc_end = req.required_start + alvo.shift_duration
    FROM req
    WHERE alvo.id = req.item_id
      AND NOT alvo.manual_dates
      AND req.required_start > alvo.calc_start;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    EXIT WHEN v_rows = 0;
  END LOOP;


  IF jsonb_array_length(v_conflicts) > 0 THEN
    RETURN jsonb_build_object(
      'conflicts', v_conflicts,
      'approved_cascade', '[]'::jsonb
    );
  END IF;


  IF v_rows > 0 THEN
    v_conflicts := v_conflicts || jsonb_build_array(
      jsonb_build_object('type', 'dependency_cycle')
    );

    RETURN jsonb_build_object(
      'conflicts', v_conflicts,
      'approved_cascade', '[]'::jsonb
    );
  END IF;


  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'data_inicio_prevista', calc_start::text,
        'data_fim_prevista', calc_end::text
      )
      ORDER BY id
    ),
    '[]'::jsonb
  )
  INTO v_cascade
  FROM pg_temp.pl_lote_items
  WHERE arquivado_em IS NULL
    AND NOT archive_requested
    AND (
      calc_start IS DISTINCT FROM direct_start
      OR calc_end IS DISTINCT FROM direct_end
    );

  RETURN jsonb_build_object(
    'conflicts', v_conflicts,
    'approved_cascade', v_cascade
  );
END;
$function$;
