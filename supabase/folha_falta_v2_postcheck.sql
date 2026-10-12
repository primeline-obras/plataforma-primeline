BEGIN READ ONLY;
DO $$ BEGIN
 IF to_regprocedure('public.fn_folha_falta_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'POSTCHECK_FAILED: RPC ausente'; END IF;
 IF EXISTS(SELECT 1 FROM public.ausencias WHERE tipo='falta_justificada_pendente') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: dados operacionais inesperados antes do frontend'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM public.ausencias a) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM primeline_backup.falta_ausencias_20261012 a) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: dados alterados'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY policyname),'[]') FROM pg_policies p WHERE schemaname='public' AND tablename='ausencias') IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY policyname),'[]') FROM primeline_backup.falta_policies_20261012 p) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: policies alteradas'; END IF;
 IF (SELECT relacl FROM pg_class WHERE oid='public.ausencias'::regclass) IS DISTINCT FROM (SELECT relacl FROM primeline_backup.falta_acl_20261012) THEN RAISE EXCEPTION 'POSTCHECK_FAILED: grants alterados'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O') THEN RAISE EXCEPTION 'POSTCHECK_FAILED: writer legado aberto'; END IF;
END $$;
ROLLBACK;
