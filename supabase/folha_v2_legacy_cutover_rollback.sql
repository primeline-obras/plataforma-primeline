BEGIN;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.ponto_pessoal_obra,public.folha_registos,public.folha_historico IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_registos) OR EXISTS(SELECT 1 FROM public.folha_historico) OR EXISTS(SELECT 1 FROM folha_privado.operacoes) THEN RAISE EXCEPTION 'ROLLBACK_V2_FACTS_PRESENT: preserve facts; roll forward or authorize a specific plan'; END IF;
 IF EXISTS(SELECT 1 FROM (TABLE public.ponto_pessoal_obra EXCEPT ALL TABLE folha_privado.legacy_cutover) x) OR EXISTS(SELECT 1 FROM (TABLE folha_privado.legacy_cutover EXCEPT ALL TABLE public.ponto_pessoal_obra) x) THEN RAISE EXCEPTION 'LEGACY_DATA_CHANGED'; END IF;
END $$;
DROP TRIGGER trg_01_folha_legacy_closed ON public.ponto_pessoal_obra;
DROP FUNCTION folha_privado.legacy_closed();
DROP TABLE folha_privado.legacy_cutover;
COMMIT;
