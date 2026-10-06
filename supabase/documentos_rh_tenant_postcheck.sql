BEGIN READ ONLY;
DO $$ DECLARE p text; t regclass; BEGIN
 FOREACH p IN ARRAY ARRAY['rh_empresa_guard','rh_anexo_empresa_guard','rh_storage_empresa_guard'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polname=p AND NOT polpermissive AND polcmd='*' AND polroles=ARRAY['authenticated'::regrole::oid]) THEN RAISE EXCEPTION 'RH_RESTRICTIVE_GUARD_MISSING: %',p; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass) AND NOT relrowsecurity) THEN RAISE EXCEPTION 'RH_RLS_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='primeline_documentos_rh_privado'::regnamespace AND (proowner<>'postgres'::regrole OR NOT prosecdef OR proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('service_role',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'RH_HELPER_PRIVILEGE_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM (TABLE public.documentos EXCEPT ALL TABLE primeline_documentos_rh_backup.documentos) x) OR EXISTS(SELECT 1 FROM (TABLE primeline_documentos_rh_backup.documentos EXCEPT ALL TABLE public.documentos) x)
 OR EXISTS(SELECT 1 FROM (TABLE public.ausencias_anexos EXCEPT ALL TABLE primeline_documentos_rh_backup.anexos) x) OR EXISTS(SELECT 1 FROM (TABLE primeline_documentos_rh_backup.anexos EXCEPT ALL TABLE public.ausencias_anexos) x)
 OR EXISTS(SELECT 1 FROM (TABLE storage.objects EXCEPT ALL TABLE primeline_documentos_rh_backup.objects) x) OR EXISTS(SELECT 1 FROM (TABLE primeline_documentos_rh_backup.objects EXCEPT ALL TABLE storage.objects) x) THEN RAISE EXCEPTION 'RH_DOCUMENT_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM primeline_documentos_rh_backup.tables b JOIN pg_class c ON c.oid=b.oid WHERE c.relacl IS DISTINCT FROM b.relacl) THEN RAISE EXCEPTION 'RH_TABLE_GRANTS_CHANGED'; END IF;
END $$;
SELECT 'DOCUMENTOS_RH_TENANT_POSTCHECK_OK' AS resultado;
ROLLBACK;
