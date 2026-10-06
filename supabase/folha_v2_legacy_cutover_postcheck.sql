BEGIN READ ONLY;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O' AND tgtype=62 AND tgfoid='folha_privado.legacy_closed()'::regprocedure) THEN RAISE EXCEPTION 'LEGACY_WRITER_NOT_CLOSED'; END IF;
 IF (SELECT btrim(prosrc,E' \t\n\r') FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure) IS DISTINCT FROM $body$BEGIN RAISE EXCEPTION 'LEGACY_WRITER_CLOSED: use Folha de Ponto V2' USING ERRCODE='42501'; END$body$ THEN RAISE EXCEPTION 'CUTOVER_HELPER_BODY_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM (TABLE public.ponto_pessoal_obra EXCEPT ALL TABLE folha_privado.legacy_cutover) x) OR EXISTS(SELECT 1 FROM (TABLE folha_privado.legacy_cutover EXCEPT ALL TABLE public.ponto_pessoal_obra) x) THEN RAISE EXCEPTION 'LEGACY_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure AND (NOT prosecdef OR proowner<>'postgres'::regrole OR proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('authenticated',oid,'EXECUTE') OR has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('service_role',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'CUTOVER_HELPER_INVALID'; END IF;
END $$;
SELECT 'LEGACY_CUTOVER_POSTCHECK_OK' AS status;
ROLLBACK;
