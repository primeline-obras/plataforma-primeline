-- Viaturas: atribuição controlada. Preparada localmente; não aplicada em produção.
-- Pré-requisitos confirmados no preflight real de 30/09/2026.
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.viaturas'::regclass
      AND tgname = 'trg_atualizar_destinatario_alerta_viatura'
      AND NOT tgisinternal AND tgenabled IN ('O', 'A')
  ) OR to_regprocedure('public.fn_registar_log_auditoria()') IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION_FAILED: trigger de alertas e auditoria existentes são obrigatórios.';
  END IF;
END;
$$;

ALTER TABLE public.viaturas
  ADD COLUMN atribuicao_revisao integer NOT NULL DEFAULT 0
  CHECK (atribuicao_revisao >= 0);

CREATE TABLE public.viaturas_atribuicoes_historico (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viatura_id uuid NOT NULL REFERENCES public.viaturas(id) ON DELETE RESTRICT,
  colaborador_anterior_id uuid REFERENCES public.colaboradores(id) ON DELETE RESTRICT,
  colaborador_novo_id uuid REFERENCES public.colaboradores(id) ON DELETE RESTRICT,
  revisao_anterior integer NOT NULL CHECK (revisao_anterior >= 0),
  revisao_nova integer NOT NULL,
  alterado_por uuid NOT NULL REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
  alterado_em timestamptz NOT NULL DEFAULT now(),
  request_id uuid NOT NULL UNIQUE,
  motivo text,
  CHECK (revisao_nova = revisao_anterior + 1),
  CHECK (colaborador_anterior_id IS DISTINCT FROM colaborador_novo_id),
  UNIQUE (viatura_id, revisao_nova)
);

ALTER TABLE public.viaturas_atribuicoes_historico ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.viaturas_atribuicoes_historico FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.viaturas_atribuicoes_historico TO authenticated;
CREATE POLICY viaturas_atribuicoes_historico_select
  ON public.viaturas_atribuicoes_historico FOR SELECT TO authenticated
  USING (public.fn_e_admin() OR public.fn_e_administrativo());

-- SECURITY INVOKER é intencional: o sinalizador, sozinho, não autoriza escrita.
-- Dentro da RPC, current_user é o proprietário da função SECURITY DEFINER.
CREATE FUNCTION public.fn_proteger_atribuicao_viatura()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF coalesce(current_setting('primeline.atribuicao_viatura_rpc', true), '') <> 'on'
     OR current_user <> (
       SELECT pg_get_userbyid(proowner) FROM pg_proc
       WHERE oid = 'public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)'::regprocedure
     ) THEN
    RAISE EXCEPTION 'PROTECTED_ASSIGNMENT: use fn_alterar_responsavel_viatura.'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.atribuicao_revisao <> OLD.atribuicao_revisao + 1
     OR NEW.colaborador_atribuido_id IS NOT DISTINCT FROM OLD.colaborador_atribuido_id THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: transição de atribuição inválida.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.fn_proteger_historico_atribuicao_viatura()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'PROTECTED_HISTORY: histórico de atribuições é imutável.' USING ERRCODE = '42501';
  END IF;
  IF coalesce(current_setting('primeline.atribuicao_viatura_rpc', true), '') <> 'on'
     OR current_user <> (
       SELECT pg_get_userbyid(proowner) FROM pg_proc
       WHERE oid = 'public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)'::regprocedure
     ) THEN
    RAISE EXCEPTION 'PROTECTED_HISTORY: histórico deve ser criado pela RPC.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

-- FOR SHARE na RPC e o lock de UPDATE do colaborador serializam atribuição/saída.
-- O SELECT do trigger VOLATILE vê o commit que libertou o lock em READ COMMITTED.
CREATE FUNCTION public.fn_impedir_saida_colaborador_com_viaturas()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_quantidade bigint;
BEGIN
  IF OLD.data_saida IS NOT NULL OR NEW.data_saida IS NULL THEN
    RETURN NEW;
  END IF;
  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'STALE_REVISION: repita a saída em READ COMMITTED para validar atribuições atuais.'
      USING ERRCODE = '40001';
  END IF;
  SELECT count(*) INTO v_quantidade FROM public.viaturas
    WHERE colaborador_atribuido_id = OLD.id;
  IF v_quantidade > 0 THEN
    RAISE EXCEPTION 'VEHICLE_ASSIGNMENT_PENDING: o colaborador possui % viatura(s) atribuída(s); é necessário primeiro reatribuir ou deixar "Sem atribuição" pela RPC de Viaturas.', v_quantidade
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.fn_alterar_responsavel_viatura(
  p_version integer,
  p_viatura_id uuid,
  p_novo_colaborador_id uuid,
  p_revisao_esperada integer,
  p_request_id uuid,
  p_motivo text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v public.viaturas%ROWTYPE;
  c public.colaboradores%ROWTYPE;
  h public.viaturas_atribuicoes_historico%ROWTYPE;
  v_user uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_contexto text;
  v_idempotent boolean := false;
BEGIN
  IF p_version IS DISTINCT FROM 1 OR p_viatura_id IS NULL
     OR p_request_id IS NULL OR p_revisao_esperada IS NULL OR p_revisao_esperada < 0 THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: versão ou parâmetros inválidos.' USING ERRCODE = '22023';
  END IF;
  v_user := public.fn_utilizador_atual_id();
  IF v_user IS NULL OR NOT (public.fn_e_admin() OR public.fn_e_administrativo()) THEN
    RAISE EXCEPTION 'FORBIDDEN: operação reservada a Administrativo/Gerência.' USING ERRCODE = '42501';
  END IF;

  IF current_setting('transaction_isolation') <> 'read committed' THEN
    RAISE EXCEPTION 'STALE_REVISION: repita a atribuição em READ COMMITTED.' USING ERRCODE = '40001';
  END IF;

  -- Serializa o mesmo pedido, incluindo tentativas sobre viaturas diferentes.
  -- Colisões do hash apenas serializam pedidos distintos; UNIQUE é a garantia final.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_request_id::text, 0));
  SELECT * INTO v FROM public.viaturas WHERE id = p_viatura_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATION_FAILED: viatura não encontrada.' USING ERRCODE = '22023';
  END IF;

  -- Replay antes do teste de revisão: devolve o resultado original, mesmo após outras trocas.
  SELECT * INTO h FROM public.viaturas_atribuicoes_historico WHERE request_id = p_request_id;
  IF FOUND THEN
    IF h.viatura_id IS DISTINCT FROM p_viatura_id
       OR h.colaborador_novo_id IS DISTINCT FROM p_novo_colaborador_id
       OR h.revisao_anterior IS DISTINCT FROM p_revisao_esperada
       OR h.motivo IS DISTINCT FROM v_motivo
       OR h.alterado_por IS DISTINCT FROM v_user THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: request_id reutilizado com outro pedido ou autor.' USING ERRCODE = '22023';
    END IF;
    v_idempotent := true;
  ELSE
    IF v.atribuicao_revisao IS DISTINCT FROM p_revisao_esperada THEN
      RAISE EXCEPTION 'STALE_REVISION: atribuição alterada; atualize antes de repetir.' USING ERRCODE = '40001';
    END IF;
    IF p_novo_colaborador_id IS NOT NULL THEN
      -- Impede saída/mudança de empresa concorrente durante a validação e gravação.
      SELECT * INTO c FROM public.colaboradores WHERE id = p_novo_colaborador_id FOR SHARE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'VALIDATION_FAILED: colaborador não encontrado.' USING ERRCODE = '22023';
      END IF;
      IF c.empresa_id IS DISTINCT FROM v.empresa_id OR c.data_saida IS NOT NULL THEN
        RAISE EXCEPTION 'VALIDATION_FAILED: colaborador deve estar ativo e pertencer à empresa da viatura.' USING ERRCODE = '22023';
      END IF;
    END IF;
    IF v.colaborador_atribuido_id IS NOT DISTINCT FROM p_novo_colaborador_id THEN
      RAISE EXCEPTION 'VALIDATION_FAILED: responsável já corresponde ao pedido.' USING ERRCODE = '22023';
    END IF;
    IF v.atribuicao_revisao = 2147483647 THEN
      RAISE EXCEPTION 'VALIDATION_FAILED: limite da revisão atingido.' USING ERRCODE = '22023';
    END IF;

    v_contexto := coalesce(current_setting('primeline.atribuicao_viatura_rpc', true), '');
    PERFORM set_config('primeline.atribuicao_viatura_rpc', 'on', true);
    UPDATE public.viaturas
      SET colaborador_atribuido_id = p_novo_colaborador_id,
          atribuicao_revisao = atribuicao_revisao + 1
      WHERE id = v.id;
    -- O trigger existente trata os alertas pendentes. Não duplicar essa lógica.
    INSERT INTO public.viaturas_atribuicoes_historico (
      viatura_id, colaborador_anterior_id, colaborador_novo_id,
      revisao_anterior, revisao_nova, alterado_por, request_id, motivo
    ) VALUES (
      v.id, v.colaborador_atribuido_id, p_novo_colaborador_id,
      v.atribuicao_revisao, v.atribuicao_revisao + 1, v_user, p_request_id, v_motivo
    ) RETURNING * INTO h;
    PERFORM set_config('primeline.atribuicao_viatura_rpc', v_contexto, true);
  END IF;

  RETURN jsonb_build_object(
    'version', 1, 'committed', true, 'idempotent', v_idempotent,
    'viatura_id', h.viatura_id,
    'colaborador_anterior_id', h.colaborador_anterior_id,
    'colaborador_novo_id', h.colaborador_novo_id,
    'atribuicao_revisao', h.revisao_nova, 'historico_id', h.id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.fn_proteger_atribuicao_viatura() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_proteger_historico_atribuicao_viatura() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_proteger_atribuicao_viatura
  BEFORE UPDATE OF colaborador_atribuido_id, atribuicao_revisao ON public.viaturas
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_atribuicao_viatura();
CREATE TRIGGER trg_proteger_historico_atribuicao_viatura
  BEFORE INSERT OR UPDATE OR DELETE ON public.viaturas_atribuicoes_historico
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_historico_atribuicao_viatura();
CREATE TRIGGER trg_auditoria_viaturas_atribuicoes_historico
  AFTER INSERT ON public.viaturas_atribuicoes_historico
  FOR EACH ROW EXECUTE FUNCTION public.fn_registar_log_auditoria('id');

REVOKE ALL ON FUNCTION public.fn_impedir_saida_colaborador_com_viaturas() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_impedir_saida_colaborador_com_viaturas
  BEFORE UPDATE OF data_saida ON public.colaboradores
  FOR EACH ROW WHEN (OLD.data_saida IS NULL AND NEW.data_saida IS NOT NULL)
  EXECUTE FUNCTION public.fn_impedir_saida_colaborador_com_viaturas();

COMMIT;
