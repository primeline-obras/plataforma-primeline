BEGIN READ ONLY;
DO $document_catalog$
DECLARE actual jsonb; expected jsonb;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF (SELECT count(*) FROM primeline_documentos_rh_backup.instalacao)<>1 THEN RAISE EXCEPTION 'DOCUMENT_INSTALLATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_documentos_rh_backup' AND (n.nspowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole))
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.relnamespace='primeline_documentos_rh_backup'::regnamespace AND (c.relowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole)) THEN RAISE EXCEPTION 'DOCUMENT_BACKUP_NOT_PRIVATE'; END IF;
 SELECT catalogo INTO expected FROM primeline_documentos_rh_backup.instalacao;
 -- Expected rollback = installed catalog with only the permissive RH policy restored.
 expected:=jsonb_set(expected,'{policies}',coalesce((SELECT jsonb_agg(p ORDER BY p->>'schemaname',p->>'tablename',p->>'policyname') FROM (
 SELECT p FROM jsonb_array_elements(expected->'policies') p WHERE NOT(p->>'schemaname'='public' AND p->>'tablename'='documentos' AND p->>'policyname'='pl_documentos_rh')
 UNION ALL SELECT to_jsonb(p) FROM primeline_documentos_rh_backup.policies p WHERE schemaname='public' AND tablename='documentos' AND policyname='pl_documentos_rh') x),'[]'::jsonb));
 actual:=(SELECT jsonb_build_object(
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename IN('objects','buckets'))),
 'tables',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',(SELECT nspname FROM pg_namespace WHERE oid=c.relnamespace),'name',c.relname,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a),'columns',(SELECT jsonb_agg(jsonb_build_object('name',attname,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(attacl) a)) ORDER BY attnum) FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped)) ORDER BY c.oid) FROM pg_class c WHERE c.oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass)),
 'helpers',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'security_definer',p.prosecdef,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'config',p.proconfig) ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.pronamespace='primeline_documentos_rh_privado'::regnamespace OR p.oid IN('public.fn_utilizador_atual_id()'::regprocedure,'public.fn_e_administrativo()'::regprocedure) OR p.oid IN(SELECT d.refobjid FROM pg_depend d JOIN pg_policy pol ON pol.oid=d.objid WHERE d.classid='pg_policy'::regclass AND d.refclassid='pg_proc'::regclass AND pol.polrelid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass))),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',nspowner,'acl',nspacl) ORDER BY nspname) FROM pg_namespace WHERE nspname IN('primeline_documentos_rh_privado','storage')),
 'bucket',(SELECT jsonb_agg(to_jsonb(b)) FROM storage.buckets b WHERE id='documentos')
));
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'DOCUMENT_CATALOG_DRIFT'; END IF;
END $document_catalog$;
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
SELECT 'DOCUMENTOS_RH_SAFE_ROLLBACK_OK' AS resultado;
ROLLBACK;
