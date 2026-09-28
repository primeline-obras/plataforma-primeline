-- PRIMELINE GO | Encarregado: Equipa Obra XXX, notificações e Folha de Ponto mensal.
-- Incremental. Não altera alocações, pontos ou responsabilidades existentes.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

DO $pre$
BEGIN
  IF coalesce(
    obj_description(
      to_regprocedure('public.fn_quadro_operar(text,jsonb,boolean,text)'),
      'pg_proc'
    ) = 'quadro_v3_20260925',
    false
  ) IS NOT TRUE THEN
    RAISE EXCEPTION 'A migração Quadro de Pessoal v3 não está instalada.';
  END IF;

  IF to_regclass('public.quadro_pessoal_rpc_permit') IS NULL
    OR to_regclass('public.quadro_pessoal_alocacao') IS NULL
    OR to_regclass('public.ponto_pessoal_obra') IS NULL
    OR to_regclass('public.alertas') IS NULL
  THEN
    RAISE EXCEPTION 'Faltam pré-requisitos do Quadro de Pessoal/Folha de Ponto/Alertas.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='alertas'
      AND column_name='destinatario_utilizador_id'
  ) THEN
    RAISE EXCEPTION 'A tabela alertas ainda não possui destinatario_utilizador_id.';
  END IF;
END;
$pre$;

CREATE OR REPLACE FUNCTION public.fn_equipa_obra_encarregado(
  p_data date DEFAULT current_date,
  p_obra_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_atual public.utilizadores;
  v_obra_id uuid;
BEGIN
  SELECT *
  INTO v_atual
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF v_atual.id IS NULL THEN
    RAISE EXCEPTION 'Utilizador sem perfil ativo.';
  END IF;

  IF v_atual.funcao <> 'encarregado' THEN
    RAISE EXCEPTION 'Esta vista está reservada ao Encarregado.'
      USING ERRCODE='42501';
  END IF;

  IF p_data IS NULL THEN
    RAISE EXCEPTION 'Indique a data.';
  END IF;

  IF p_obra_id IS NULL THEN
    SELECT d.id
    INTO v_obra_id
    FROM public.fn_quadro_obras_destino() d
    ORDER BY d.numero, d.nome
    LIMIT 1;
  ELSE
    v_obra_id := p_obra_id;
  END IF;

  IF v_obra_id IS NOT NULL
    AND NOT public.fn_quadro_minha_obra(v_obra_id)
  THEN
    RAISE EXCEPTION 'Sem permissão para consultar esta obra.'
      USING ERRCODE='42501';
  END IF;

  RETURN jsonb_build_object(
    'data', p_data,
    'obra_id', v_obra_id,

    'obras', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'numero', d.numero,
          'nome', d.nome
        )
        ORDER BY d.numero, d.nome
      )
      FROM public.fn_quadro_obras_destino() d
    ), '[]'::jsonb),

    'equipa',
    CASE
      WHEN v_obra_id IS NULL THEN '[]'::jsonb
      ELSE COALESCE((
        WITH equipa AS (
          SELECT
            c.id AS colaborador_id,
            c.nome,
            c.funcao,
            bool_or(q.periodo='dia_inteiro') AS dia_inteiro,
            bool_or(q.periodo='manha') AS manha,
            bool_or(q.periodo='tarde') AS tarde
          FROM public.quadro_pessoal_alocacao q
          JOIN public.colaboradores c
            ON c.id=q.colaborador_id
           AND c.empresa_id=v_atual.empresa_id
          WHERE q.obra_id=v_obra_id
            AND q.data=p_data
            AND q.tipo_alocacao='obra'
            AND q.descricao_livre IS NULL
          GROUP BY c.id,c.nome,c.funcao
        )
        SELECT jsonb_agg(
          jsonb_build_object(
            'colaborador_id', e.colaborador_id,
            'nome', e.nome,
            'funcao', e.funcao,
            'periodo',
              CASE
                WHEN e.dia_inteiro OR (e.manha AND e.tarde) THEN 'dia_inteiro'
                WHEN e.manha THEN 'manha'
                WHEN e.tarde THEN 'tarde'
                ELSE 'dia_inteiro'
              END
          )
          ORDER BY
            CASE
              WHEN lower(coalesce(e.funcao,'')) LIKE '%encarreg%' THEN 1
              WHEN lower(coalesce(e.funcao,'')) LIKE '%pedreiro%' THEN 2
              WHEN lower(coalesce(e.funcao,'')) LIKE '%servente%' THEN 3
              ELSE 4
            END,
            lower(e.nome)
        )
        FROM equipa e
      ), '[]'::jsonb)
    END,

    'candidatos', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'colaborador_id', c.id,
          'nome', c.nome,
          'funcao', c.funcao,
          'ausente', EXISTS(
            SELECT 1
            FROM public.ausencias a
            WHERE a.colaborador_id=c.id
              AND a.data=p_data
          ),
          'alocacoes', COALESCE((
            SELECT jsonb_agg(
              jsonb_build_object(
                'obra_id', q.obra_id,
                'obra_numero', o.numero::text,
                'obra_nome', o.nome,
                'periodo', q.periodo
              )
              ORDER BY o.numero::text, q.periodo
            )
            FROM public.quadro_pessoal_alocacao q
            LEFT JOIN public.obras o ON o.id=q.obra_id
            WHERE q.colaborador_id=c.id
              AND q.data=p_data
              AND q.tipo_alocacao='obra'
              AND q.descricao_livre IS NULL
          ), '[]'::jsonb)
        )
        ORDER BY lower(c.nome)
      )
      FROM public.colaboradores c
      WHERE c.empresa_id=v_atual.empresa_id
        AND c.data_admissao<=p_data
        AND (c.data_saida IS NULL OR c.data_saida>p_data)
    ), '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL
ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid)
FROM PUBLIC,anon;

GRANT EXECUTE
ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid)
TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_quadro_notificar_movimentacao_encarregado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_atual public.utilizadores;
  v_permit public.quadro_pessoal_rpc_permit;
  v_colaborador public.colaboradores;
  v_origem_id uuid;
  v_destino_id uuid;
  v_origem_numero text;
  v_origem_nome text;
  v_destino_numero text;
  v_destino_nome text;
  v_titulo text;
  v_descricao text;
BEGIN
  IF TG_OP NOT IN ('INSERT','UPDATE') THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_atual
  FROM public.utilizadores
  WHERE id=public.fn_utilizador_atual_id()
    AND ativo IS TRUE
    AND funcao='encarregado';

  IF v_atual.id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.*
  INTO v_permit
  FROM public.quadro_pessoal_rpc_permit p
  WHERE p.transacao=txid_current()
    AND p.utilizador_id=v_atual.id
    AND p.colaborador_id=NEW.colaborador_id
    AND p.destino_id=NEW.obra_id
    AND p.data=NEW.data
    AND p.periodo=NEW.periodo
    AND (
      (TG_OP='INSERT' AND p.origem_id IS NULL)
      OR
      (TG_OP='UPDATE' AND p.origem_id=OLD.id)
    )
  LIMIT 1;

  IF v_permit.utilizador_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_origem_id := CASE WHEN TG_OP='UPDATE' THEN OLD.obra_id ELSE NULL END;
  v_destino_id := NEW.obra_id;

  IF TG_OP='UPDATE'
    AND v_origem_id IS NOT DISTINCT FROM v_destino_id
  THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_colaborador
  FROM public.colaboradores
  WHERE id=NEW.colaborador_id
    AND empresa_id=v_atual.empresa_id;

  IF v_colaborador.id IS NULL THEN
    RAISE EXCEPTION 'Colaborador da movimentação não encontrado.';
  END IF;

  IF v_origem_id IS NOT NULL THEN
    SELECT o.numero::text,o.nome
    INTO v_origem_numero,v_origem_nome
    FROM public.obras o
    WHERE o.id=v_origem_id
      AND o.empresa_id=v_atual.empresa_id;
  END IF;

  SELECT o.numero::text,o.nome
  INTO v_destino_numero,v_destino_nome
  FROM public.obras o
  WHERE o.id=v_destino_id
    AND o.empresa_id=v_atual.empresa_id;

  IF v_destino_numero IS NULL THEN
    RAISE EXCEPTION 'Obra de destino da movimentação não encontrada.';
  END IF;

  v_titulo := 'Movimentação de equipa · ' || v_colaborador.nome;

  IF v_origem_id IS NULL THEN
    v_descricao := format(
      '%s foi adicionado à Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      v_destino_numero,
      v_destino_nome,
      to_char(NEW.data,'DD/MM/YYYY'),
      v_atual.nome
    );
  ELSE
    v_descricao := format(
      '%s foi movimentado da Obra %s · %s para a Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      coalesce(v_origem_numero,'—'),
      coalesce(v_origem_nome,'Obra de origem'),
      v_destino_numero,
      v_destino_nome,
      to_char(NEW.data,'DD/MM/YYYY'),
      v_atual.nome
    );
  END IF;

  WITH destinatarios AS (
    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      1 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='encarregado'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      2 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_destino_id AS obra_ref,
      3 AS prioridade
    FROM public.obra_responsaveis r
    WHERE r.obra_id=v_destino_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      u.id AS utilizador_id,
      v_destino_id AS obra_ref,
      4 AS prioridade
    FROM public.utilizadores u
    WHERE u.empresa_id=v_atual.empresa_id
      AND u.funcao='administrativo'
      AND u.ativo IS TRUE
      AND u.auth_user_id IS NOT NULL
  ),
  unicos AS (
    SELECT DISTINCT ON (d.utilizador_id)
      d.utilizador_id,
      d.obra_ref
    FROM destinatarios d
    WHERE d.utilizador_id IS NOT NULL
      AND d.utilizador_id IS DISTINCT FROM v_atual.id
    ORDER BY d.utilizador_id,d.prioridade
  )
  INSERT INTO public.alertas(
    empresa_id,
    obra_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado,
    enviar_email,
    destinatario_utilizador_id
  )
  SELECT
    v_atual.empresa_id,
    u.obra_ref,
    'movimentacao_equipa',
    'quadro_pessoal_alocacao',
    NEW.id,
    v_titulo,
    v_descricao,
    NEW.data,
    0,
    current_date,
    destinatario.funcao,
    'pendente',
    false,
    destinatario.id
  FROM unicos u
  JOIN public.utilizadores destinatario
    ON destinatario.id=u.utilizador_id
   AND destinatario.empresa_id=v_atual.empresa_id
   AND destinatario.ativo IS TRUE
   AND destinatario.auth_user_id IS NOT NULL;

  RETURN NEW;
END;
$function$;

REVOKE ALL
ON FUNCTION public.fn_quadro_notificar_movimentacao_encarregado()
FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS trg_quadro_notificar_movimentacao_encarregado
ON public.quadro_pessoal_alocacao;

CREATE TRIGGER trg_quadro_notificar_movimentacao_encarregado
AFTER INSERT OR UPDATE OF obra_id
ON public.quadro_pessoal_alocacao
FOR EACH ROW
EXECUTE FUNCTION public.fn_quadro_notificar_movimentacao_encarregado();

DROP POLICY IF EXISTS quadro_movimentacao_pessoal_select
ON public.alertas;

CREATE POLICY quadro_movimentacao_pessoal_select
ON public.alertas
FOR SELECT
TO authenticated
USING (
  tipo='movimentacao_equipa'
  AND destinatario_utilizador_id=public.fn_utilizador_atual_id()
);

CREATE OR REPLACE FUNCTION public.fn_folha_ponto_mensal(
  p_mes date,
  p_obra_id uuid DEFAULT NULL
)
RETURNS TABLE(
  data date,
  obra_id uuid,
  obra_numero text,
  obra_nome text,
  colaborador_id uuid,
  colaborador text,
  funcao text,
  estado text,
  periodos_alocados text[],
  entrada_manha time,
  saida_manha time,
  entrada_tarde time,
  saida_tarde time,
  horas numeric,
  observacao text,
  justificacao_estado text,
  registado_por text,
  atualizado_por text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_atual public.utilizadores;
  v_inicio date;
  v_fim date;
BEGIN
  SELECT *
  INTO v_atual
  FROM public.utilizadores
  WHERE id=public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF v_atual.id IS NULL THEN
    RAISE EXCEPTION 'Utilizador sem perfil ativo.';
  END IF;

  IF NOT public.fn_pode_gerir_quadro(NULL) THEN
    RAISE EXCEPTION 'A exportação da Folha de Ponto está reservada ao Administrativo e à Gestão.'
      USING ERRCODE='42501';
  END IF;

  IF p_mes IS NULL THEN
    RAISE EXCEPTION 'Indique o mês de referência.';
  END IF;

  IF p_obra_id IS NOT NULL
    AND NOT EXISTS(
      SELECT 1
      FROM public.obras o
      WHERE o.id=p_obra_id
        AND o.empresa_id=v_atual.empresa_id
    )
  THEN
    RAISE EXCEPTION 'Obra inexistente ou de outra empresa.';
  END IF;

  v_inicio := date_trunc('month',p_mes)::date;
  v_fim := (v_inicio + interval '1 month')::date;

  RETURN QUERY
  SELECT
    p.data,
    o.id,
    o.numero::text,
    o.nome,
    c.id,
    c.nome,
    c.funcao,
    p.estado,
    p.periodos_alocados,
    p.entrada_manha,
    p.saida_manha,
    p.entrada_tarde,
    p.saida_tarde,
    p.horas,
    p.observacao,
    p.justificacao_estado,
    ur.nome,
    ua.nome
  FROM public.ponto_pessoal_obra p
  JOIN public.colaboradores c
    ON c.id=p.colaborador_id
  JOIN public.obras o
    ON o.id=p.obra_id
  LEFT JOIN public.utilizadores ur
    ON ur.id=p.registado_por
  LEFT JOIN public.utilizadores ua
    ON ua.id=p.atualizado_por
  WHERE p.empresa_id=v_atual.empresa_id
    AND p.data>=v_inicio
    AND p.data<v_fim
    AND (p_obra_id IS NULL OR p.obra_id=p_obra_id)
  ORDER BY o.numero::text,lower(c.nome),p.data;
END;
$function$;

REVOKE ALL
ON FUNCTION public.fn_folha_ponto_mensal(date,uuid)
FROM PUBLIC,anon;

GRANT EXECUTE
ON FUNCTION public.fn_folha_ponto_mensal(date,uuid)
TO authenticated;

COMMENT ON FUNCTION public.fn_equipa_obra_encarregado(date,uuid)
IS 'encarregado_equipa_v1_20260928';

COMMENT ON FUNCTION public.fn_quadro_notificar_movimentacao_encarregado()
IS 'encarregado_notificacoes_v1_20260928';

COMMENT ON FUNCTION public.fn_folha_ponto_mensal(date,uuid)
IS 'folha_ponto_mensal_v1_20260928';

COMMIT;

SELECT
  to_regprocedure('public.fn_equipa_obra_encarregado(date,uuid)') IS NOT NULL
    AS equipa_obra_ativa,
  to_regprocedure('public.fn_folha_ponto_mensal(date,uuid)') IS NOT NULL
    AS folha_ponto_mensal_ativa,
  EXISTS(
    SELECT 1
    FROM pg_trigger
    WHERE tgname='trg_quadro_notificar_movimentacao_encarregado'
      AND NOT tgisinternal
  ) AS notificacao_movimentacao_ativa,
  EXISTS(
    SELECT 1
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename='alertas'
      AND policyname='quadro_movimentacao_pessoal_select'
  ) AS politica_notificacao_ativa,
  CASE
    WHEN
      to_regprocedure('public.fn_equipa_obra_encarregado(date,uuid)') IS NOT NULL
      AND to_regprocedure('public.fn_folha_ponto_mensal(date,uuid)') IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM pg_trigger
        WHERE tgname='trg_quadro_notificar_movimentacao_encarregado'
          AND NOT tgisinternal
      )
      AND EXISTS(
        SELECT 1 FROM pg_policies
        WHERE schemaname='public'
          AND tablename='alertas'
          AND policyname='quadro_movimentacao_pessoal_select'
      )
    THEN 'PRONTO_BACKEND_ENCARREGADO_FOLHA_PONTO'
    ELSE 'REVER'
  END AS resultado;