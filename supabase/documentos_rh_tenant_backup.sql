BEGIN;
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

DO $$ BEGIN IF current_user<>'postgres' OR to_regnamespace('primeline_documentos_rh_backup') IS NOT NULL THEN RAISE EXCEPTION 'OWNER_OR_BACKUP_PRECONDITION'; END IF; END $$;
CREATE SCHEMA primeline_documentos_rh_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_documentos_rh_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_documentos_rh_backup.policies AS SELECT * FROM pg_policies WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects');
CREATE TABLE primeline_documentos_rh_backup.tables AS SELECT c.oid,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass);
CREATE TABLE primeline_documentos_rh_backup.rpc AS SELECT p.oid::regprocedure::text AS signature,pg_get_functiondef(p.oid) AS definition,p.proowner,p.proacl,p.proconfig FROM pg_proc p WHERE p.oid IN(to_regprocedure('public.fn_apagar_anexo_rnc(uuid)'),to_regprocedure('public.fn_apagar_documento_obra(uuid)'),to_regprocedure('public.fn_registar_documento_obra(uuid,text,text,text)'),to_regprocedure('public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)'),to_regprocedure('public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)'),'public.fn_apagar_documento_entidade(uuid)'::regprocedure,to_regprocedure('public.fn_apagar_anexo_imovel(uuid)'),to_regprocedure('public.fn_apagar_anexo_pedido_orcamento(uuid)'),to_regprocedure('public.fn_apagar_imovel_empresa(uuid)'),to_regprocedure('public.fn_apagar_reuniao_condominio(uuid)'),to_regprocedure('public.fn_apagar_versao_pedido_orcamento(uuid)'),to_regprocedure('public.fn_cancelar_pedido_orcamento(uuid)'),to_regprocedure('public.fn_gerir_registo_frota(text,uuid,text,jsonb)'));
CREATE TABLE primeline_documentos_rh_backup.documentos AS TABLE public.documentos;
CREATE TABLE primeline_documentos_rh_backup.anexos AS TABLE public.ausencias_anexos;
CREATE TABLE primeline_documentos_rh_backup.objects AS TABLE storage.objects;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_documentos_rh_backup FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
