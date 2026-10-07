-- Local rollout material. Read-only; no Pacote 2 dependency.
BEGIN READ ONLY;
DO $storage_capability$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'NORMAL_EXECUTOR_REQUIRED' USING ERRCODE='42501'; END IF;
 IF (SELECT count(*) FROM pg_class c WHERE c.oid IN(to_regclass('storage.objects'),to_regclass('storage.buckets')) AND pg_get_userbyid(c.relowner)='supabase_storage_admin' AND c.relrowsecurity)<>2
 THEN RAISE EXCEPTION 'STORAGE_OWNER_OR_RLS_DRIFT' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_roles r ON r.rolname=current_user WHERE c.oid=to_regclass('storage.objects') AND (r.rolsuper OR r.rolbypassrls OR (NOT c.relforcerowsecurity AND pg_has_role(current_user,c.relowner,'USAGE'))))
 THEN RAISE EXCEPTION 'STORAGE_FULL_READ_VISIBILITY_REQUIRED' USING ERRCODE='42501'; END IF;
END $storage_capability$;
DO $document_rpc_baseline$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('public.fn_apagar_documento_entidade(uuid)') AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=public']
 AND encode(sha256(convert_to(replace(pg_get_functiondef(p.oid),chr(13),''),'UTF8')),'hex')='53626d177adc3b6a335f6b3f5d84d0db61c5c70861eafd4d32ddc414e6e161d0'
 AND (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x)='{authenticated=X/postgres,postgres=X/postgres}')
 THEN RAISE EXCEPTION 'DOCUMENT_DELETE_RPC_BASELINE_DRIFT'; END IF;
END $document_rpc_baseline$;
DO $work_document_rpc_baseline$ BEGIN IF EXISTS(SELECT 1 FROM (VALUES ('fn_apagar_anexo_rnc(uuid)','8997b4a81a175a6de37212dc2eeff195fa646215f4dda3ef61cef9fd33968a70'),('fn_apagar_documento_obra(uuid)','9d2464019cf0e668ec82c73d4ca95dfcc346137171d03cdaddefe7fd266b2e74'),('fn_registar_documento_obra(uuid,text,text,text)','61523acf692e7a323b73c453cd8f79052d96d7aee01407ec11446ee8bf6558a1')) e(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure('public.'||e.signature) WHERE p.oid IS NULL OR encode(sha256(convert_to(replace(pg_get_functiondef(p.oid),chr(13),''),'UTF8')),'hex')<>e.hash OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x) IS DISTINCT FROM '{authenticated=X/postgres,postgres=X/postgres}') THEN RAISE EXCEPTION 'WORK_DOCUMENT_RPC_BASELINE_DRIFT'; END IF; END $work_document_rpc_baseline$;

DO $vehicle_rpc_baseline$ BEGIN IF EXISTS(SELECT 1 FROM (VALUES ('fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)','826dd30d3b3b34bea7ce4174aec1d605f3999f2d74ed1c5d1837db9849c48e96'),('fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)','88e0f86de72ff7dd18e6f6f5191a82d8ea5c83c58b581ff442d34a383a5471ec')) e(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure('public.'||e.signature) WHERE p.oid IS NULL OR encode(sha256(convert_to(replace(pg_get_functiondef(p.oid),chr(13),''),'UTF8')),'hex')<>e.hash OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x) IS DISTINCT FROM '{authenticated=X/postgres,postgres=X/postgres}') THEN RAISE EXCEPTION 'VEHICLE_RPC_BASELINE_DRIFT'; END IF; END $vehicle_rpc_baseline$;

DO $document_correlatos_baseline$ BEGIN
 IF EXISTS(SELECT 1 FROM (VALUES ('fn_apagar_anexo_imovel(uuid)','553c355715f6b5ba232a26909169e48adc5bd68dfa84bdd140cc67d8fa8721a9'),
('fn_apagar_anexo_pedido_orcamento(uuid)','8a5a3bab48c0593eff819e3011b4b4b1fd6c6abe2ac0d58199c753e1eebde199'),
('fn_apagar_imovel_empresa(uuid)','f0368bd73ba0d2624583e982b58a244c22a442293b477d211b4352679e84f971'),
('fn_apagar_reuniao_condominio(uuid)','dee15591637f336bbb9b6f02f5069dc64ece29d4a9f9a087ff130269d8b20e62'),
('fn_apagar_versao_pedido_orcamento(uuid)','16c452b738287fca8ba5893a539f2fb26c0dd2add61c540f63e0ab78b312b806'),
('fn_cancelar_pedido_orcamento(uuid)','8517f7fb58aaf15f1bb75119f1a1933279330f68e9952e388d029cca0164d202'),
('fn_gerir_registo_frota(text,uuid,text,jsonb)','3aaba188702682ee0d9047874ef107b738f0f3d72ab28434baf1fc745dbf3121')) e(signature,hash) LEFT JOIN pg_proc p ON p.oid=to_regprocedure('public.'||e.signature) WHERE p.oid IS NULL OR p.proowner<>'postgres'::regrole OR NOT p.prosecdef OR encode(sha256(convert_to(replace(pg_get_functiondef(p.oid),chr(13),''),'UTF8')),'hex')<>e.hash OR (SELECT array_agg(x::text ORDER BY x::text COLLATE "C")::text FROM unnest(coalesce(p.proacl,acldefault('f',p.proowner))) x) IS DISTINCT FROM '{authenticated=X/postgres,postgres=X/postgres}') THEN RAISE EXCEPTION 'DOCUMENT_CORRELATOS_BASELINE_DRIFT'; END IF;
END $document_correlatos_baseline$;

DO $$ DECLARE t text; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='documentos' AND public IS FALSE) THEN RAISE EXCEPTION 'PRIVATE_DOCUMENT_BUCKET_REQUIRED'; END IF;
 FOREACH t IN ARRAY ARRAY['public.documentos','public.colaboradores','public.viaturas','public.ausencias','public.ausencias_anexos','public.utilizadores','storage.objects'] LOOP
  IF to_regclass(t) IS NULL THEN RAISE EXCEPTION 'DOCUMENT_SOURCE_REQUIRED: %',t; END IF;
 END LOOP;
 IF to_regprocedure('public.fn_utilizador_atual_id()') IS NULL OR to_regprocedure('public.fn_e_administrativo()') IS NULL THEN RAISE EXCEPTION 'CANONICAL_ACTOR_REQUIRED'; END IF;
 IF to_regnamespace('primeline_documentos_rh_privado') IS NOT NULL OR to_regnamespace('primeline_documentos_rh_backup') IS NOT NULL THEN RAISE EXCEPTION 'DOCUMENT_ROLLOUT_ALREADY_PRESENT'; END IF;
 IF EXISTS(SELECT 1 FROM public.documentos d WHERE d.entidade_tipo IN('colaborador','viatura') AND NOT (
  EXISTS(SELECT 1 FROM public.colaboradores c WHERE d.entidade_tipo='colaborador' AND c.id=d.entidade_id AND c.empresa_id=d.empresa_id)
  OR EXISTS(SELECT 1 FROM public.viaturas v WHERE d.entidade_tipo='viatura' AND v.id=d.entidade_id AND v.empresa_id=d.empresa_id)))
 THEN RAISE EXCEPTION 'RH_DOCUMENT_ENTITY_COMPANY_MISMATCH: reconcile explicitly before rollout'; END IF;
 IF EXISTS(SELECT 1 FROM public.documentos WHERE entidade_tipo='empresa' AND entidade_id IS DISTINCT FROM empresa_id) THEN RAISE EXCEPTION 'COMPANY_DOCUMENT_ENTITY_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM public.ausencias_anexos an LEFT JOIN public.ausencias a ON a.id=an.ausencia_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE c.id IS NULL)
 THEN RAISE EXCEPTION 'RH_ATTACHMENT_ORPHAN'; END IF;
END $$;
-- Complete policy inventory, including permissive OR and restrictive AND.
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies
WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects') ORDER BY schemaname,tablename,policyname;
SELECT n.nspname,c.relname,c.relrowsecurity,c.relacl FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname='public' AND c.relname IN('documentos','ausencias_anexos')) OR (n.nspname='storage' AND c.relname='objects');
ROLLBACK;
