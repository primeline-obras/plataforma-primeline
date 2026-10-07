-- Somente leitura. Aprovação independente do catálogo pós-hotfix/v2 é um gate FUTURO.
-- Este pacote não cria nem atualiza a aprovação para transformar drift em PASS.
BEGIN READ ONLY;
DO $document_catalog$
DECLARE actual jsonb; expected jsonb;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF (SELECT count(*) FROM primeline_documentos_rh_backup.instalacao)<>1 THEN RAISE EXCEPTION 'DOCUMENT_INSTALLATION_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_documentos_rh_backup' AND (n.nspowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole))
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.relnamespace='primeline_documentos_rh_backup'::regnamespace AND (c.relowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole)) THEN RAISE EXCEPTION 'DOCUMENT_BACKUP_NOT_PRIVATE'; END IF;
 SELECT catalogo INTO expected FROM primeline_documentos_rh_backup.instalacao;
 actual:=(SELECT jsonb_build_object(
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename IN('objects','buckets'))),
 'tables',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',(SELECT nspname FROM pg_namespace WHERE oid=c.relnamespace),'name',c.relname,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a),'columns',(SELECT jsonb_agg(jsonb_build_object('name',attname,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(attacl) a)) ORDER BY attnum) FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped)) ORDER BY c.oid) FROM pg_class c WHERE c.oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass)),
 'helpers',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'security_definer',p.prosecdef,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'config',p.proconfig) ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.pronamespace='primeline_documentos_rh_privado'::regnamespace OR p.oid IN(to_regprocedure('public.fn_apagar_anexo_rnc(uuid)'),to_regprocedure('public.fn_apagar_documento_obra(uuid)'),to_regprocedure('public.fn_registar_documento_obra(uuid,text,text,text)'),to_regprocedure('public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)'),to_regprocedure('public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)'),to_regprocedure('public.fn_apagar_documento_entidade(uuid)'),to_regprocedure('public.fn_apagar_anexo_imovel(uuid)'),to_regprocedure('public.fn_apagar_anexo_pedido_orcamento(uuid)'),to_regprocedure('public.fn_apagar_imovel_empresa(uuid)'),to_regprocedure('public.fn_apagar_reuniao_condominio(uuid)'),to_regprocedure('public.fn_apagar_versao_pedido_orcamento(uuid)'),to_regprocedure('public.fn_cancelar_pedido_orcamento(uuid)'),to_regprocedure('public.fn_gerir_registo_frota(text,uuid,text,jsonb)')) OR p.oid IN('public.fn_utilizador_atual_id()'::regprocedure,'public.fn_e_administrativo()'::regprocedure) OR p.oid IN(SELECT d.refobjid FROM pg_depend d JOIN pg_policy pol ON pol.oid=d.objid WHERE d.classid='pg_policy'::regclass AND d.refclassid='pg_proc'::regclass AND pol.polrelid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass))),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',nspowner,'acl',nspacl) ORDER BY nspname) FROM pg_namespace WHERE nspname IN('primeline_documentos_rh_privado','storage')),
 'bucket',(SELECT jsonb_agg(to_jsonb(b)) FROM storage.buckets b WHERE id='documentos')
));
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'DOCUMENT_CATALOG_DRIFT'; END IF;
END $document_catalog$;
DO $$ BEGIN
 IF to_regclass('folha_privado.legacy_cutover') IS NULL OR to_regprocedure('folha_privado.legacy_closed()') IS NULL THEN RAISE EXCEPTION 'CUTOVER_REQUIRED: legacy writer must be closed before B'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O' AND tgtype=62 AND tgfoid='folha_privado.legacy_closed()'::regprocedure) THEN RAISE EXCEPTION 'LEGACY_WRITER_NOT_CLOSED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('folha_privado.legacy_cutover') AND relowner='postgres'::regrole AND relrowsecurity)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute c CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE c.attrelid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'CUTOVER_SNAPSHOT_NOT_PRIVATE'; END IF;
 IF (SELECT btrim(prosrc,E' \t\n\r') FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure) IS DISTINCT FROM $body$BEGIN RAISE EXCEPTION 'LEGACY_WRITER_CLOSED: use Folha de Ponto V2' USING ERRCODE='42501'; END$body$ THEN RAISE EXCEPTION 'CUTOVER_HELPER_BODY_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM (TABLE public.ponto_pessoal_obra EXCEPT ALL TABLE folha_privado.legacy_cutover) x) OR EXISTS(SELECT 1 FROM (TABLE folha_privado.legacy_cutover EXCEPT ALL TABLE public.ponto_pessoal_obra) x) THEN RAISE EXCEPTION 'LEGACY_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure AND (NOT prosecdef OR proowner<>'postgres'::regrole OR proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('authenticated',oid,'EXECUTE') OR has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('service_role',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'CUTOVER_HELPER_INVALID'; END IF;
END $$;

DO $gate$
DECLARE approved jsonb; actual jsonb;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF to_regclass('primeline_pacote2_gate.aprovacao') IS NULL THEN RAISE EXCEPTION 'REAL CATALOG VALIDATION REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_pacote2_gate' AND nspowner='postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_pacote2_gate' AND x.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.oid='primeline_pacote2_gate.aprovacao'::regclass AND (c.relowner<>'postgres'::regrole OR x.grantee<>'postgres'::regrole))
 OR EXISTS(SELECT 1 FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) x WHERE a.attrelid='primeline_pacote2_gate.aprovacao'::regclass AND x.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'GATE_NOT_PRIVATE'; END IF;
 EXECUTE 'SELECT CASE WHEN count(*)=1 THEN jsonb_agg(to_jsonb(x))->0 END FROM primeline_pacote2_gate.aprovacao x' INTO approved;
 IF approved IS NULL OR approved->>'release_id' IS DISTINCT FROM 'pacote2_folha_v2_20261005'
 OR approved->>'reviewed_by' IS DISTINCT FROM 'postgres' OR approved->>'consumed_at' IS NOT NULL
 OR approved->>'frontend_assets_sha256' IS NULL OR approved->>'frontend_assets_sha256' !~ '^[0-9a-f]{64}$'
 OR (approved->>'frontend_validated')::boolean IS DISTINCT FROM true
 OR (approved->>'backend_v2_validated')::boolean IS DISTINCT FROM true
 OR (approved->>'reviewed_at')::timestamptz IS NULL OR (approved->>'reviewed_at')::timestamptz>now()
 THEN RAISE EXCEPTION 'POST_HOTFIX_VALIDATION_REQUIRED'; END IF;
 IF (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'a'
 OR (SELECT instalacao_id::text FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM approved->>'installation_id'
 THEN RAISE EXCEPTION 'INSTALLATION_MISMATCH'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.quadro_pessoal_alocacao'::regclass AND polname='encarregado_sem_dml_direto' AND NOT polpermissive AND polcmd='*'
 AND pg_get_expr(polqual,polrelid)='(NOT fn_encarregado_acesso_direto_bloqueado())' AND pg_get_expr(polwithcheck,polrelid)='(NOT fn_encarregado_acesso_direto_bloqueado())') THEN RAISE EXCEPTION 'HOTFIX_POLICY_REQUIRED'; END IF;
 actual:=(SELECT jsonb_build_object(
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','folha_privado','primeline_documentos_rh_privado','storage') AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.policyname) FROM pg_policies x WHERE x.schemaname=n.nspname AND x.tablename=c.relname),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',x.tgname,'enabled',x.tgenabled,'definition',pg_get_triggerdef(x.oid)) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid AND NOT x.tgisinternal),
 'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY x.indexrelid::regclass::text) FROM pg_index x WHERE x.indrelid=c.oid)) ORDER BY c.oid::regclass::text COLLATE "C") FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname IN('public','folha_privado') OR n.nspname='storage' AND c.relname IN('objects','buckets')) AND c.relkind IN('r','p'))));
 IF actual IS DISTINCT FROM approved->'expected_catalog' THEN RAISE EXCEPTION 'POST_HOTFIX_CATALOG_DRIFT'; END IF;
 IF to_regprocedure('public.fn_folha_operar_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'FOLHA_V2_REQUIRED'; END IF;
END $gate$;
SELECT 'PRECHECK_B_POS_HOTFIX_OK' status;
COMMIT;
