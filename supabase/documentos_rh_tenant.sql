-- Independent, main-compatible RH metadata/Storage guard. No data/path migration.
BEGIN;
SET LOCAL lock_timeout='10s';
DO $storage_capability$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'NORMAL_EXECUTOR_REQUIRED' USING ERRCODE='42501'; END IF;
 IF (SELECT count(*) FROM pg_class c WHERE c.oid IN(to_regclass('storage.objects'),to_regclass('storage.buckets')) AND pg_get_userbyid(c.relowner)='supabase_storage_admin' AND c.relrowsecurity)<>2
 THEN RAISE EXCEPTION 'STORAGE_OWNER_OR_RLS_DRIFT' USING ERRCODE='42501'; END IF;
 IF NOT pg_has_role(session_user,'supabase_storage_admin','SET') THEN RAISE EXCEPTION 'STORAGE_OWNER_CAPABILITY_BLOCKED' USING ERRCODE='42501'; END IF;
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

DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' OR to_regnamespace('primeline_documentos_rh_backup') IS NULL THEN RAISE EXCEPTION 'OWNER_AND_PRIVATE_BACKUP_REQUIRED'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='documentos' AND public IS FALSE) THEN RAISE EXCEPTION 'PRIVATE_DOCUMENT_BUCKET_REQUIRED'; END IF; END $$;
-- Locks last until transaction end; no Storage data is changed.
SET LOCAL ROLE supabase_storage_admin;
LOCK TABLE storage.objects,storage.buckets IN SHARE MODE;
RESET ROLE;
LOCK TABLE public.documentos,public.ausencias_anexos IN SHARE MODE;
-- Validate the existing evidence without modifying/replacing it.
DO $existing_backup$ DECLARE s text; BEGIN
 WITH storage_owner AS (
 SELECT e.name,pg_get_userbyid(c.relowner) owner,c.relrowsecurity rls,
 CASE WHEN c.relowner IS NOT NULL THEN pg_has_role(session_user,c.relowner,'SET') ELSE false END can_set
 FROM (VALUES ('storage.objects'),('storage.buckets')) e(name) LEFT JOIN pg_class c ON c.oid=to_regclass(e.name)
), backup_expected(name,source) AS (VALUES ('documentos','public.documentos'),('anexos','public.ausencias_anexos'),('objects','storage.objects'),('policies','pg_catalog.pg_policies'),('tables',NULL),('rpc',NULL)),
backup_shape AS (
 SELECT e.name,c.oid,
 CASE WHEN e.source IS NOT NULL THEN
 (SELECT jsonb_agg(jsonb_build_array(a.attname,a.atttypid,a.atttypmod) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped)
 IS NOT DISTINCT FROM
 (SELECT jsonb_agg(jsonb_build_array(a.attname,a.atttypid,a.atttypmod) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=to_regclass(e.source) AND a.attnum>0 AND NOT a.attisdropped)
 ELSE
 (SELECT jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod)) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped)
 = CASE e.name WHEN 'tables' THEN '[["oid","oid"],["relrowsecurity","boolean"],["relacl","aclitem[]"]]'::jsonb ELSE '[["signature","text"],["definition","text"],["proowner","oid"],["proacl","aclitem[]"],["proconfig","text[]"]]'::jsonb END END
 AND c.relkind='r' AND NOT c.relrowsecurity AND NOT c.relforcerowsecurity
 AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND (a.attnotnull OR a.atthasdef OR a.attisdropped OR a.attgenerated<>'' OR a.attidentity<>''))
 AND NOT EXISTS(SELECT 1 FROM pg_constraint x WHERE x.conrelid=c.oid)
 AND NOT EXISTS(SELECT 1 FROM pg_trigger x WHERE x.tgrelid=c.oid)
 AND NOT EXISTS(SELECT 1 FROM pg_index x WHERE x.indrelid=c.oid) shape_ok
 FROM backup_expected e LEFT JOIN pg_class c ON c.oid=to_regclass('primeline_documentos_rh_backup.'||e.name)
), backup_metadata AS (
 SELECT to_regnamespace('primeline_documentos_rh_backup') IS NOT NULL backup_exists,
 (SELECT bool_and(coalesce(c.relkind='r' AND (NOT c.relrowsecurity OR (SELECT r.rolsuper OR r.rolbypassrls FROM pg_roles r WHERE r.rolname=current_user) OR (NOT c.relforcerowsecurity AND pg_has_role(current_user,c.relowner,'USAGE'))),false)) FROM (VALUES ('public.documentos'),('public.ausencias_anexos'),('storage.objects')) e(name) LEFT JOIN pg_class c ON c.oid=to_regclass(e.name)) backup_full_visibility,
 (SELECT bool_and(coalesce(has_table_privilege(current_user,c.oid,'SELECT'),false)) FROM backup_expected e LEFT JOIN pg_class c ON c.oid=to_regclass('primeline_documentos_rh_backup.'||e.name))
 AND (SELECT bool_and(coalesce(has_table_privilege(current_user,c.oid,'SELECT'),false)) FROM (VALUES ('public.documentos'),('public.ausencias_anexos'),('storage.objects')) e(name) LEFT JOIN pg_class c ON c.oid=to_regclass(e.name)) backup_readable,
 EXISTS(SELECT 1 FROM pg_namespace n WHERE n.nspname='primeline_documentos_rh_backup' AND pg_get_userbyid(n.nspowner)='postgres'
 AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE a.grantee<>n.nspowner))
 AND NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.relnamespace=to_regnamespace('primeline_documentos_rh_backup') AND (pg_get_userbyid(c.relowner)<>'postgres' OR EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE a.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute x CROSS JOIN LATERAL aclexplode(x.attacl) a WHERE x.attrelid=c.oid AND a.grantee<>c.relowner))) backup_private,
 (SELECT count(*) FROM pg_class c WHERE c.relnamespace=to_regnamespace('primeline_documentos_rh_backup'))=6
 AND (SELECT bool_and(coalesce(shape_ok,false)) FROM backup_shape)
 AND NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace=to_regnamespace('primeline_documentos_rh_backup')) backup_shape_ok,
 to_regnamespace('primeline_documentos_rh_privado') IS NOT NULL OR to_regclass('primeline_documentos_rh_backup.instalacao') IS NOT NULL
 OR EXISTS(SELECT 1 FROM pg_policy p WHERE p.polname IN('rh_empresa_guard','rh_anexo_empresa_guard','rh_storage_empresa_guard') AND p.polrelid IN(to_regclass('public.documentos'),to_regclass('public.ausencias_anexos'),to_regclass('storage.objects'))) migration_partial
), backup_comparison AS (
 SELECT CASE WHEN backup_exists AND backup_private AND backup_shape_ok AND backup_readable AND backup_full_visibility AND NOT migration_partial
 THEN (xpath('/table/row/value/text()',query_to_xml('SELECT jsonb_agg(to_jsonb(d) ORDER BY object)::text value FROM (SELECT ''documentos'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT * FROM public.documentos) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.documentos) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.documentos EXCEPT ALL SELECT * FROM (SELECT * FROM public.documentos) live)) difference UNION ALL SELECT ''anexos'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT * FROM public.ausencias_anexos) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.anexos) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.anexos EXCEPT ALL SELECT * FROM (SELECT * FROM public.ausencias_anexos) live)) difference UNION ALL SELECT ''objects'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT * FROM storage.objects) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.objects) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.objects EXCEPT ALL SELECT * FROM (SELECT * FROM storage.objects) live)) difference UNION ALL SELECT ''policies'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT * FROM pg_policies WHERE (schemaname=''public'' AND tablename IN(''documentos'',''ausencias_anexos'')) OR (schemaname=''storage'' AND tablename=''objects'')) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.policies) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.policies EXCEPT ALL SELECT * FROM (SELECT * FROM pg_policies WHERE (schemaname=''public'' AND tablename IN(''documentos'',''ausencias_anexos'')) OR (schemaname=''storage'' AND tablename=''objects'')) live)) difference UNION ALL SELECT ''tables'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT c.oid,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN(''public.documentos''::regclass,''public.ausencias_anexos''::regclass,''storage.objects''::regclass)) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.tables) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.tables EXCEPT ALL SELECT * FROM (SELECT c.oid,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN(''public.documentos''::regclass,''public.ausencias_anexos''::regclass,''storage.objects''::regclass)) live)) difference UNION ALL SELECT ''rpc'' object, count(*)::bigint delta FROM ((SELECT * FROM (SELECT p.oid::regprocedure::text AS signature,pg_get_functiondef(p.oid) AS definition,p.proowner,p.proacl,p.proconfig FROM pg_proc p WHERE p.oid IN(to_regprocedure(''public.fn_apagar_anexo_rnc(uuid)''),to_regprocedure(''public.fn_apagar_documento_obra(uuid)''),to_regprocedure(''public.fn_registar_documento_obra(uuid,text,text,text)''),to_regprocedure(''public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)''),to_regprocedure(''public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)''),to_regprocedure(''public.fn_apagar_documento_entidade(uuid)''),to_regprocedure(''public.fn_apagar_anexo_imovel(uuid)''),to_regprocedure(''public.fn_apagar_anexo_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_apagar_imovel_empresa(uuid)''),to_regprocedure(''public.fn_apagar_reuniao_condominio(uuid)''),to_regprocedure(''public.fn_apagar_versao_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_cancelar_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_gerir_registo_frota(text,uuid,text,jsonb)''))) live EXCEPT ALL SELECT * FROM primeline_documentos_rh_backup.rpc) UNION ALL (SELECT * FROM primeline_documentos_rh_backup.rpc EXCEPT ALL SELECT * FROM (SELECT p.oid::regprocedure::text AS signature,pg_get_functiondef(p.oid) AS definition,p.proowner,p.proacl,p.proconfig FROM pg_proc p WHERE p.oid IN(to_regprocedure(''public.fn_apagar_anexo_rnc(uuid)''),to_regprocedure(''public.fn_apagar_documento_obra(uuid)''),to_regprocedure(''public.fn_registar_documento_obra(uuid,text,text,text)''),to_regprocedure(''public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)''),to_regprocedure(''public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)''),to_regprocedure(''public.fn_apagar_documento_entidade(uuid)''),to_regprocedure(''public.fn_apagar_anexo_imovel(uuid)''),to_regprocedure(''public.fn_apagar_anexo_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_apagar_imovel_empresa(uuid)''),to_regprocedure(''public.fn_apagar_reuniao_condominio(uuid)''),to_regprocedure(''public.fn_apagar_versao_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_cancelar_pedido_orcamento(uuid)''),to_regprocedure(''public.fn_gerir_registo_frota(text,uuid,text,jsonb)''))) live)) difference) d',false,false,'')))[1]::text::jsonb ELSE NULL END differences FROM backup_metadata
), backup_resume AS (
 SELECT m.*,c.differences,coalesce((SELECT bool_and((x->>'delta')::bigint=0) FROM jsonb_array_elements(c.differences) x),false) backup_matches_live,
 CASE WHEN NOT backup_exists AND NOT migration_partial THEN 'CLEAN_START'
 WHEN backup_exists AND backup_private AND backup_shape_ok AND NOT migration_partial AND coalesce((SELECT bool_and((x->>'delta')::bigint=0) FROM jsonb_array_elements(c.differences) x),false) THEN 'VALID_EXISTING_BACKUP_RESUME'
 ELSE 'PARTIAL_OR_UNKNOWN_STATE' END resume_state
 FROM backup_metadata m CROSS JOIN backup_comparison c
) SELECT resume_state INTO s FROM backup_resume;
 IF s IS DISTINCT FROM 'VALID_EXISTING_BACKUP_RESUME' THEN RAISE EXCEPTION 'DOCUMENT_BACKUP_RESUME_BLOCKED: %',s; END IF;
END $existing_backup$;
CREATE SCHEMA primeline_documentos_rh_privado AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_documentos_rh_privado FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA primeline_documentos_rh_privado TO authenticated;
CREATE FUNCTION primeline_documentos_rh_privado.empresa(empresa uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.empresa_id=empresa)
$$;
CREATE FUNCTION primeline_documentos_rh_privado.entidade(tipo text,entidade uuid,empresa uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.empresa_id IS NOT NULL AND public.fn_e_administrativo()
 AND (empresa IS NULL OR empresa=u.empresa_id) AND (
 tipo='colaborador' AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=entidade AND c.empresa_id=u.empresa_id)
 OR tipo='viatura' AND EXISTS(SELECT 1 FROM public.viaturas v WHERE v.id=entidade AND v.empresa_id=u.empresa_id)
 OR tipo='ausencia' AND EXISTS(SELECT 1 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=entidade AND c.empresa_id=u.empresa_id)))
$$;
CREATE FUNCTION primeline_documentos_rh_privado.objeto(nome text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p text[]:=string_to_array(nome,'/'); BEGIN
 IF cardinality(p)<4 OR p[1]<>'rh' OR p[2] NOT IN('colaborador','viatura','ausencia') OR p[3] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 OR EXISTS(SELECT 1 FROM unnest(p) x WHERE x IN('','.', '..')) THEN RETURN false; END IF;
 RETURN primeline_documentos_rh_privado.entidade(p[2],p[3]::uuid,NULL);
END $$;
REVOKE ALL ON FUNCTION primeline_documentos_rh_privado.empresa(uuid),primeline_documentos_rh_privado.entidade(text,uuid,uuid),primeline_documentos_rh_privado.objeto(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION primeline_documentos_rh_privado.empresa(uuid),primeline_documentos_rh_privado.entidade(text,uuid,uuid),primeline_documentos_rh_privado.objeto(text) TO authenticated;
ALTER TABLE public.documentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ausencias_anexos ENABLE ROW LEVEL SECURITY;
-- Restrictive tenant check for the existing document namespaces. Existing role policies still apply.
CREATE FUNCTION primeline_documentos_rh_privado.objeto_empresa(bucket text,nome text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE p text[]:=string_to_array(nome,'/'); entidade uuid; empresa uuid;
BEGIN
 IF bucket NOT IN('documentos','faturas') THEN RETURN true; END IF;
 IF cardinality(p)<2 OR EXISTS(SELECT 1 FROM unnest(p) x WHERE x IN('','.', '..')) THEN RETURN false; END IF;
 IF bucket='documentos' AND p[1]='rh' THEN RETURN primeline_documentos_rh_privado.objeto(nome); END IF;
 IF bucket='documentos' AND p[1]='empresa' THEN
  IF p[2] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
  RETURN primeline_documentos_rh_privado.empresa(p[2]::uuid);
 END IF;
 IF bucket='documentos' AND p[1]='entidades' THEN
  IF cardinality(p)<4 OR p[3] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
  entidade:=p[3]::uuid;
  IF p[2]='imovel' THEN SELECT empresa_id INTO empresa FROM public.imoveis_empresa WHERE id=entidade;
  ELSIF p[2]='pedido_orcamento' THEN SELECT empresa_id INTO empresa FROM public.pedidos_orcamento WHERE id=entidade;
  ELSE RETURN false; END IF;
  RETURN primeline_documentos_rh_privado.empresa(empresa);
 END IF;
 IF p[1] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN false; END IF;
 SELECT empresa_id INTO empresa FROM public.obras WHERE id=p[1]::uuid;
 RETURN primeline_documentos_rh_privado.empresa(empresa);
END $$;
REVOKE ALL ON FUNCTION primeline_documentos_rh_privado.objeto_empresa(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION primeline_documentos_rh_privado.objeto_empresa(text,text) TO authenticated;

-- Restrictive AND closes every existing permissive OR path, preserving non-RH work access.
CREATE POLICY rh_empresa_guard ON public.documentos AS RESTRICTIVE FOR ALL TO authenticated
 USING(primeline_documentos_rh_privado.empresa(empresa_id) AND (entidade_tipo NOT IN('colaborador','viatura') OR primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id)))
 WITH CHECK(primeline_documentos_rh_privado.empresa(empresa_id) AND (entidade_tipo NOT IN('colaborador','viatura') OR primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id)));
CREATE POLICY rh_anexo_empresa_guard ON public.ausencias_anexos AS RESTRICTIVE FOR ALL TO authenticated
 USING(primeline_documentos_rh_privado.entidade('ausencia',ausencia_id,NULL)) WITH CHECK(primeline_documentos_rh_privado.entidade('ausencia',ausencia_id,NULL));
-- Temporary name-resolution privilege only; removed in the same transaction.
GRANT USAGE ON SCHEMA primeline_documentos_rh_privado TO supabase_storage_admin;
SET LOCAL ROLE supabase_storage_admin;
CREATE POLICY rh_storage_empresa_guard ON storage.objects AS RESTRICTIVE FOR ALL TO authenticated
 USING(primeline_documentos_rh_privado.objeto_empresa(bucket_id,name))
 WITH CHECK(primeline_documentos_rh_privado.objeto_empresa(bucket_id,name));
RESET ROLE;
REVOKE USAGE ON SCHEMA primeline_documentos_rh_privado FROM supabase_storage_admin;
-- Tighten the dedicated permissive policy as well; no new Storage operations are granted.
DROP POLICY IF EXISTS pl_documentos_rh ON public.documentos;
CREATE POLICY pl_documentos_rh ON public.documentos FOR ALL TO authenticated
 USING(entidade_tipo IN('colaborador','viatura') AND primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id))
 WITH CHECK(entidade_tipo IN('colaborador','viatura') AND primeline_documentos_rh_privado.entidade(entidade_tipo,entidade_id,empresa_id));
-- Lock target before checking its tenant/entity. UPDATE/DELETE cannot race this check.
-- Administrative capability is inherited unchanged; active actor/tenant is mandatory.
CREATE OR REPLACE FUNCTION public.fn_apagar_documento_entidade(p_documento_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $function$
DECLARE d public.documentos%ROWTYPE; actor_empresa uuid;
BEGIN
 SELECT u.empresa_id INTO actor_empresa FROM public.utilizadores u
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE FOR SHARE;
 IF actor_empresa IS NULL OR public.fn_e_administrativo() IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'DOCUMENT_DELETE_NOT_AUTHORIZED' USING ERRCODE='42501';
 END IF;
 SELECT * INTO d FROM public.documentos WHERE id=p_documento_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'DOCUMENT_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF d.empresa_id IS DISTINCT FROM actor_empresa OR (d.entidade_tipo='empresa' AND d.entidade_id IS DISTINCT FROM actor_empresa) OR
 (d.entidade_tipo IN('colaborador','viatura') AND NOT primeline_documentos_rh_privado.entidade(d.entidade_tipo,d.entidade_id,d.empresa_id)) THEN
  RAISE EXCEPTION 'DOCUMENT_OUTSIDE_COMPANY_OR_ENTITY' USING ERRCODE='42501';
 END IF;
 DELETE FROM public.documentos WHERE id=p_documento_id;
END $function$;
ALTER FUNCTION public.fn_apagar_documento_entidade(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_documento_entidade(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_documento_entidade(uuid) TO authenticated;

CREATE FUNCTION primeline_documentos_rh_privado.autorizar_alvo(tipo text, alvo uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE empresa uuid; target_empresa uuid; v uuid; pessoa uuid; pedido uuid; versao uuid;
BEGIN
 SELECT u.empresa_id INTO empresa FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE FOR SHARE;
 IF empresa IS NULL OR (tipo NOT IN('obras','documentos_obra','rnc_anexos') AND public.fn_e_administrativo() IS DISTINCT FROM true) THEN RAISE EXCEPTION 'DOCUMENT_TARGET_NOT_AUTHORIZED' USING ERRCODE='42501'; END IF;
 CASE tipo
 WHEN 'obras' THEN SELECT empresa_id INTO target_empresa FROM public.obras WHERE id=alvo FOR SHARE;
 WHEN 'documentos_obra' THEN SELECT o.empresa_id INTO target_empresa FROM public.documentos_obra d JOIN public.obras o ON o.id=d.obra_id WHERE d.id=alvo FOR UPDATE OF d FOR SHARE OF o;
 WHEN 'rnc_anexos' THEN SELECT o.empresa_id INTO target_empresa FROM public.rnc_anexos a JOIN public.rnc r ON r.id=a.rnc_id JOIN public.obras o ON o.id=r.obra_id WHERE a.id=alvo FOR UPDATE OF a,r FOR SHARE OF o;
 WHEN 'viaturas' THEN SELECT empresa_id INTO target_empresa FROM public.viaturas WHERE id=alvo FOR UPDATE;
 WHEN 'imoveis_empresa' THEN SELECT empresa_id INTO target_empresa FROM public.imoveis_empresa WHERE id=alvo FOR UPDATE;
 WHEN 'imoveis_anexos' THEN SELECT p.empresa_id INTO target_empresa FROM public.imoveis_anexos a JOIN public.imoveis_empresa p ON p.id=a.imovel_id WHERE a.id=alvo FOR UPDATE OF a,p;
 WHEN 'imoveis_reunioes_condominio' THEN SELECT p.empresa_id INTO target_empresa FROM public.imoveis_reunioes_condominio a JOIN public.imoveis_empresa p ON p.id=a.imovel_id WHERE a.id=alvo FOR UPDATE OF a,p;
 WHEN 'pedidos_orcamento' THEN SELECT empresa_id INTO target_empresa FROM public.pedidos_orcamento WHERE id=alvo FOR UPDATE;
 WHEN 'pedidos_orcamento_versoes' THEN SELECT p.empresa_id INTO target_empresa FROM public.pedidos_orcamento_versoes a JOIN public.pedidos_orcamento p ON p.id=a.pedido_id WHERE a.id=alvo FOR UPDATE OF a,p;
 WHEN 'pedidos_orcamento_anexos' THEN
  SELECT pedido_id,versao_id INTO pedido,versao FROM public.pedidos_orcamento_anexos WHERE id=alvo FOR UPDATE;
  SELECT empresa_id INTO target_empresa FROM public.pedidos_orcamento WHERE id=pedido FOR UPDATE;
  IF versao IS NOT NULL THEN
   SELECT pedido_id INTO v FROM public.pedidos_orcamento_versoes WHERE id=versao FOR UPDATE;
   IF v IS DISTINCT FROM pedido THEN RAISE EXCEPTION 'DOCUMENT_VERSION_PARENT_MISMATCH' USING ERRCODE='42501'; END IF;
  END IF;
 WHEN 'viaturas_eventos' THEN SELECT viatura_id INTO v FROM public.viaturas_eventos WHERE id=alvo FOR UPDATE;
 WHEN 'viaturas_sinistros' THEN SELECT viatura_id,colaborador_id INTO v,pessoa FROM public.viaturas_sinistros WHERE id=alvo FOR UPDATE;
 WHEN 'multas' THEN SELECT viatura_id,colaborador_id INTO v,pessoa FROM public.multas WHERE id=alvo FOR UPDATE;
 WHEN 'viaturas_sinistros_anexos' THEN SELECT s.viatura_id,s.colaborador_id INTO v,pessoa FROM public.viaturas_sinistros_anexos a JOIN public.viaturas_sinistros s ON s.id=a.sinistro_id WHERE a.id=alvo FOR UPDATE OF a,s;
 WHEN 'multas_anexos' THEN SELECT s.viatura_id,s.colaborador_id INTO v,pessoa FROM public.multas_anexos a JOIN public.multas s ON s.id=a.multa_id WHERE a.id=alvo FOR UPDATE OF a,s;
 ELSE RAISE EXCEPTION 'DOCUMENT_TARGET_UNSUPPORTED' USING ERRCODE='42501';
 END CASE;
 IF tipo IN('viaturas_eventos','viaturas_sinistros','multas','viaturas_sinistros_anexos','multas_anexos') THEN
  IF v IS NOT NULL THEN SELECT empresa_id INTO target_empresa FROM public.viaturas WHERE id=v FOR UPDATE;
   IF target_empresa IS DISTINCT FROM empresa THEN RAISE EXCEPTION 'DOCUMENT_TARGET_OUTSIDE_COMPANY' USING ERRCODE='42501'; END IF;
  END IF;
  IF pessoa IS NOT NULL THEN SELECT empresa_id INTO target_empresa FROM public.colaboradores WHERE id=pessoa FOR SHARE; END IF;
 END IF;
 IF target_empresa IS DISTINCT FROM empresa THEN RAISE EXCEPTION 'DOCUMENT_TARGET_OUTSIDE_COMPANY' USING ERRCODE='42501'; END IF;
END $$;
REVOKE ALL ON FUNCTION primeline_documentos_rh_privado.autorizar_alvo(text,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_imovel(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_path text; begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('imoveis_anexos',p_anexo_id); if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.imoveis_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $function$;
ALTER FUNCTION public.fn_apagar_anexo_imovel(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_imovel(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_imovel(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_pedido_orcamento(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_path text; begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('pedidos_orcamento_anexos',p_anexo_id); if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Sem permissão.' using errcode='42501'; end if;
delete from public.pedidos_orcamento_anexos where id=p_anexo_id returning arquivo_url into v_path; if v_path is null then raise exception 'Anexo não encontrado.'; end if; return v_path; end; $function$;
ALTER FUNCTION public.fn_apagar_anexo_pedido_orcamento(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_imovel_empresa(p_imovel_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('imoveis_empresa',p_imovel_id);
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar imóveis.';
  end if;

  if not exists (
    select 1
    from public.imoveis_empresa
    where id = p_imovel_id
  ) then
    raise exception 'Imóvel não encontrado.';
  end if;

  delete from public.imoveis_reunioes_condominio
  where imovel_id = p_imovel_id;

  delete from public.imoveis_empresa
  where id = p_imovel_id;
end;
$function$;
ALTER FUNCTION public.fn_apagar_imovel_empresa(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_imovel_empresa(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_imovel_empresa(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_reuniao_condominio(p_reuniao_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('imoveis_reunioes_condominio',p_reuniao_id);
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar reuniões de condomínio.';
  end if;

  if not exists (
    select 1
    from public.imoveis_reunioes_condominio
    where id = p_reuniao_id
  ) then
    raise exception 'Reunião não encontrada.';
  end if;

  delete from public.imoveis_reunioes_condominio
  where id = p_reuniao_id;
end;
$function$;
ALTER FUNCTION public.fn_apagar_reuniao_condominio(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_reuniao_condominio(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_reuniao_condominio(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_versao_pedido_orcamento(p_versao_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('pedidos_orcamento_versoes',p_versao_id);
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode apagar versões de pedidos de orçamento.';
  end if;

  if not exists (
    select 1
    from public.pedidos_orcamento_versoes
    where id = p_versao_id
  ) then
    raise exception 'Versão não encontrada.';
  end if;

  delete from public.pedidos_orcamento_versoes
  where id = p_versao_id;
end;
$function$;
ALTER FUNCTION public.fn_apagar_versao_pedido_orcamento(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_versao_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_versao_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_cancelar_pedido_orcamento(p_pedido_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('pedidos_orcamento',p_pedido_id);
  if not public.fn_e_administrativo() then
    raise exception 'Só o Administrativo ou a Gerência pode cancelar pedidos de orçamento.';
  end if;

  if not exists (
    select 1
    from public.pedidos_orcamento
    where id = p_pedido_id
  ) then
    raise exception 'Pedido de orçamento não encontrado.';
  end if;

  update public.pedidos_orcamento
  set
    estado = 'cancelado',
    situacao_atual = coalesce(
      nullif(btrim(situacao_atual), ''),
      'Cancelado pelo utilizador'
    )
  where id = p_pedido_id;
end;
$function$;
ALTER FUNCTION public.fn_cancelar_pedido_orcamento(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_cancelar_pedido_orcamento(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_cancelar_pedido_orcamento(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_gerir_registo_frota(p_tabela text, p_registo_id uuid, p_acao text, p_dados jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_row jsonb;
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo(p_tabela,p_registo_id);
  if not (public.fn_e_admin() or public.fn_e_administrativo()) then raise exception 'Operação reservada a Administrativo/Gerência.' using errcode='42501'; end if;
  if p_acao not in ('editar','apagar') then raise exception 'Ação inválida.'; end if;
  if p_tabela='viaturas_eventos' then
    if p_acao='editar' then update public.viaturas_eventos set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row;
    else delete from public.viaturas_eventos where id=p_registo_id returning to_jsonb(viaturas_eventos) into v_row; end if;
  elsif p_tabela='viaturas_sinistros' then
    if p_acao='editar' then update public.viaturas_sinistros set descricao=coalesce(nullif(btrim(p_dados->>'descricao'),''),descricao),estado=case when p_dados ? 'estado' and p_dados->>'estado' in ('aberto','em_seguradora','fechado') then p_dados->>'estado' else estado end where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row;
    else delete from public.viaturas_sinistros where id=p_registo_id returning to_jsonb(viaturas_sinistros) into v_row; end if;
  elsif p_tabela='multas' then
    if p_acao='editar' then update public.multas set descricao=nullif(btrim(p_dados->>'descricao'),'') where id=p_registo_id returning to_jsonb(multas) into v_row;
    else delete from public.multas where id=p_registo_id returning to_jsonb(multas) into v_row; end if;
  elsif p_tabela='viaturas_sinistros_anexos' and p_acao='apagar' then delete from public.viaturas_sinistros_anexos where id=p_registo_id returning to_jsonb(viaturas_sinistros_anexos) into v_row;
  elsif p_tabela='multas_anexos' and p_acao='apagar' then delete from public.multas_anexos where id=p_registo_id returning to_jsonb(multas_anexos) into v_row;
  else raise exception 'Tabela de frota não autorizada.'; end if;
  if v_row is null then raise exception 'Registo não encontrado.'; end if;
  return v_row;
end; $function$;
ALTER FUNCTION public.fn_gerir_registo_frota(text,uuid,text,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_gerir_registo_frota(text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_gerir_registo_frota(text,uuid,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_alterar_responsavel_viatura(p_version integer, p_viatura_id uuid, p_novo_colaborador_id uuid, p_revisao_esperada integer, p_request_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v public.viaturas%ROWTYPE;
  c public.colaboradores%ROWTYPE;
  h public.viaturas_atribuicoes_historico%ROWTYPE;
  v_user uuid;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_contexto text;
  v_idempotent boolean := false;
BEGIN
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('viaturas',p_viatura_id);
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
$function$;
ALTER FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_guardar_validade_viatura(p_version integer, p_viatura_id uuid, p_tipo text, p_operacao text, p_data_atual_esperada date, p_data_base date, p_validade_opcao text, p_nova_data date, p_motivo text, p_request_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v public.viaturas%rowtype;
  e public.viaturas_eventos%rowtype;

  v_user uuid;

  v_data_atual date;
  v_data_nova date;

  v_ciclo_antigo uuid;
  v_ciclo_novo uuid;

  v_tipo_alerta text;
  v_operacao_hist text;
  v_descricao text;

  v_alerta jsonb;
BEGIN
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('viaturas',p_viatura_id);

  -- ----------------------------------------------------------
  -- Validação
  -- ----------------------------------------------------------

  IF p_version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: versão inválida.';
  END IF;

  IF p_viatura_id IS NULL
     OR p_tipo NOT IN ('seguro', 'inspecao')
     OR p_operacao NOT IN ('renovar', 'editar_data')
     OR nullif(btrim(p_request_id), '') IS NULL
  THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: dados incompletos.';
  END IF;

  IF NOT (
    public.fn_e_admin()
    OR public.fn_e_administrativo()
  ) THEN
    RAISE EXCEPTION
      'FORBIDDEN: operação reservada a Administrativo/Gerência.'
      USING ERRCODE = '42501';
  END IF;

  v_user := public.fn_utilizador_atual_id();

  IF v_user IS NULL THEN
    RAISE EXCEPTION
      'FORBIDDEN: utilizador não identificado.'
      USING ERRCODE = '42501';
  END IF;

  v_operacao_hist :=
    CASE
      WHEN p_operacao = 'renovar'
        THEN 'renovacao'
      ELSE 'correcao_data'
    END;


  -- ----------------------------------------------------------
  -- Idempotência
  -- ----------------------------------------------------------

  SELECT *
  INTO e
  FROM public.viaturas_eventos
  WHERE request_id = p_request_id;

  IF FOUND THEN

    IF e.viatura_id IS DISTINCT FROM p_viatura_id
       OR e.tipo IS DISTINCT FROM p_tipo
       OR e.validade_operacao IS DISTINCT FROM v_operacao_hist
       OR e.validade_anterior IS DISTINCT FROM p_data_atual_esperada
    THEN
      RAISE EXCEPTION
        'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
    END IF;

    IF p_operacao = 'editar_data' THEN
      IF e.validade_nova IS DISTINCT FROM p_nova_data
         OR coalesce(e.motivo, '') IS DISTINCT FROM
            coalesce(nullif(btrim(p_motivo), ''), '')
      THEN
        RAISE EXCEPTION
          'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
      END IF;
    ELSE
      IF e.validade_base IS DISTINCT FROM p_data_base
         OR e.validade_opcao IS DISTINCT FROM p_validade_opcao
      THEN
        RAISE EXCEPTION
          'IDEMPOTENCY_CONFLICT: request_id reutilizado com conteúdo diferente.';
      END IF;
    END IF;

    SELECT *
    INTO v
    FROM public.viaturas
    WHERE id = p_viatura_id;

    RETURN jsonb_build_object(
      'version', 1,
      'committed', true,
      'idempotent', true,
      'vehicle', to_jsonb(v),
      'event', to_jsonb(e)
    );
  END IF;


  -- ----------------------------------------------------------
  -- Lock da viatura
  -- ----------------------------------------------------------

  SELECT *
  INTO v
  FROM public.viaturas
  WHERE id = p_viatura_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: viatura não encontrada.';
  END IF;


  IF p_tipo = 'seguro' THEN
    v_data_atual := v.seguro_data;
    v_ciclo_antigo := v.seguro_ciclo_id;
    v_tipo_alerta := 'seguro_viatura';
  ELSE
    v_data_atual := v.data_inspecao_proxima;
    v_ciclo_antigo := v.inspecao_ciclo_id;
    v_tipo_alerta := 'inspecao_viatura';
  END IF;


  -- ----------------------------------------------------------
  -- Concorrência otimista
  -- ----------------------------------------------------------

  IF v_data_atual IS DISTINCT FROM p_data_atual_esperada THEN
    RAISE EXCEPTION
      'STALE_REVISION: a validade foi alterada. Atualize antes de repetir.';
  END IF;


  -- ==========================================================
  -- RENOVAR
  -- ==========================================================

  IF p_operacao = 'renovar' THEN

    IF p_data_base IS NULL
       OR p_validade_opcao NOT IN (
         '1_ano',
         '2_anos',
         'outra'
       )
    THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: data de renovação e validade são obrigatórias.';
    END IF;

    IF p_validade_opcao = '1_ano' THEN
      v_data_nova :=
        (p_data_base + interval '1 year')::date;

    ELSIF p_validade_opcao = '2_anos' THEN
      v_data_nova :=
        (p_data_base + interval '2 years')::date;

    ELSE
      IF p_nova_data IS NULL THEN
        RAISE EXCEPTION
          'VALIDATION_FAILED: informe o novo vencimento.';
      END IF;

      v_data_nova := p_nova_data;
    END IF;

    IF v_data_nova < p_data_base THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: vencimento anterior à data da renovação.';
    END IF;

    v_descricao :=
      CASE
        WHEN p_tipo = 'seguro'
          THEN 'Renovação do seguro'
        ELSE 'Renovação da inspeção'
      END;


  -- ==========================================================
  -- EDITAR DATA
  -- ==========================================================

  ELSE

    IF p_nova_data IS NULL
       OR nullif(btrim(p_motivo), '') IS NULL
    THEN
      RAISE EXCEPTION
        'VALIDATION_FAILED: nova data e motivo são obrigatórios.';
    END IF;

    v_data_nova := p_nova_data;

    v_descricao :=
      CASE
        WHEN p_tipo = 'seguro'
          THEN 'Correção da data do seguro'
        ELSE 'Correção da data da inspeção'
      END;

  END IF;


  IF v_data_nova IS NOT DISTINCT FROM v_data_atual THEN
    RAISE EXCEPTION
      'VALIDATION_FAILED: a nova data é igual à atual.';
  END IF;


  -- ----------------------------------------------------------
  -- Resolver alerta antigo
  -- ----------------------------------------------------------

  UPDATE public.alertas
  SET
    estado = 'resolvido',
    resolvido_por = v_user,
    resolvido_em = now()
  WHERE entidade_tipo = 'viaturas'
    AND entidade_id = p_viatura_id
    AND tipo = v_tipo_alerta
    AND estado = 'pendente'
    AND data_evento_referencia
        IS NOT DISTINCT FROM v_data_atual
    AND (
      ocorrencia_chave IS NOT DISTINCT FROM v_ciclo_antigo
      OR ocorrencia_chave IS NULL
    );


  -- ----------------------------------------------------------
  -- Novo ciclo
  -- ----------------------------------------------------------

  v_ciclo_novo := gen_random_uuid();


  -- ----------------------------------------------------------
  -- Atualizar validade
  -- ----------------------------------------------------------

  IF p_tipo = 'seguro' THEN

    UPDATE public.viaturas
    SET
      seguro_data = v_data_nova,
      seguro_ciclo_id = v_ciclo_novo
    WHERE id = p_viatura_id
    RETURNING *
    INTO v;

  ELSE

    UPDATE public.viaturas
    SET
      data_inspecao_proxima = v_data_nova,
      inspecao_ciclo_id = v_ciclo_novo
    WHERE id = p_viatura_id
    RETURNING *
    INTO v;

  END IF;


  -- ----------------------------------------------------------
  -- Criar histórico protegido
  -- ----------------------------------------------------------

  PERFORM set_config(
    'primeline.validade_viatura_rpc',
    'on',
    true
  );

  INSERT INTO public.viaturas_eventos (
    viatura_id,
    tipo,
    data,
    descricao,
    validade_operacao,
    validade_anterior,
    validade_nova,
    validade_base,
    validade_opcao,
    motivo,
    registado_por,
    request_id
  )
  VALUES (
    p_viatura_id,
    p_tipo,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_data_base
      ELSE current_date
    END,

    v_descricao,
    v_operacao_hist,
    v_data_atual,
    v_data_nova,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_data_base
      ELSE NULL
    END,

    CASE
      WHEN p_operacao = 'renovar'
        THEN p_validade_opcao
      ELSE NULL
    END,

    nullif(btrim(p_motivo), ''),
    v_user,
    p_request_id
  )
  RETURNING *
  INTO e;


  -- ----------------------------------------------------------
  -- Se já estiver dentro de 15 dias cria o alerta agora.
  -- Caso contrário, fica para o job diário.
  -- ----------------------------------------------------------

  v_alerta :=
    public.fn_criar_alerta_validade_viatura(
      p_viatura_id,
      p_tipo
    );


  RETURN jsonb_build_object(
    'version', 1,
    'committed', true,
    'idempotent', false,

    'validity',
      jsonb_build_object(
        'type', p_tipo,
        'operation', p_operacao,
        'previous_date', v_data_atual,
        'new_date', v_data_nova,
        'cycle_id', v_ciclo_novo
      ),

    'vehicle', to_jsonb(v),
    'event', to_jsonb(e),
    'alert', v_alerta
  );

END;
$function$;
ALTER FUNCTION public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_anexo_rnc(p_anexo_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare v_path text; v_obra uuid;
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('rnc_anexos',p_anexo_id);
  select a.arquivo_url,r.obra_id into v_path,v_obra from public.rnc_anexos a join public.rnc r on r.id=a.rnc_id where a.id=p_anexo_id;
  if not found then raise exception 'Anexo não encontrado.'; end if;
  if not public.fn_pode_editar_obra(v_obra) then raise exception 'Sem permissão.' using errcode='42501'; end if;
  delete from public.rnc_anexos where id=p_anexo_id; return v_path;
end; $function$
;
ALTER FUNCTION public.fn_apagar_anexo_rnc(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_anexo_rnc(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_anexo_rnc(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_apagar_documento_obra(p_documento_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_obra_id uuid;
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('documentos_obra',p_documento_id);
  select obra_id
  into v_obra_id
  from public.documentos_obra
  where id = p_documento_id;

  if v_obra_id is null then
    raise exception 'Documento não encontrado.';
  end if;

  if not public.fn_pode_editar_documentos_obra(v_obra_id) then
    raise exception 'Sem permissão para apagar este documento.';
  end if;

  delete from public.documentos_obra
  where id = p_documento_id;
end;
$function$
;
ALTER FUNCTION public.fn_apagar_documento_obra(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_apagar_documento_obra(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_apagar_documento_obra(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_registar_documento_obra(p_obra_id uuid, p_tipo text, p_nome_arquivo text, p_arquivo_url text)
 RETURNS documentos_obra
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_documento public.documentos_obra;
  v_utilizador_id uuid;
begin
 PERFORM primeline_documentos_rh_privado.autorizar_alvo('obras',p_obra_id);
  if auth.uid() is null then
    raise exception 'Sessão autenticada obrigatória.';
  end if;

  if not public.fn_pode_editar_obra(p_obra_id) then
    raise exception 'Sem permissão para enviar documentos para esta obra.';
  end if;

  if p_tipo is null or p_tipo not in (
    'contrato',
    'orcamento',
    'plantas_projeto',
    'licencas',
    'planeamento_detalhado',
    'outro'
  ) then
    raise exception 'Tipo de documento inválido.';
  end if;

  if nullif(btrim(p_nome_arquivo), '') is null then
    raise exception 'O nome do ficheiro é obrigatório.';
  end if;

  if nullif(btrim(p_arquivo_url), '') is null
     or p_arquivo_url not like p_obra_id::text || '/%' then
    raise exception 'O caminho do documento não pertence à obra indicada.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();
  if v_utilizador_id is null then
    raise exception 'O utilizador autenticado não está associado a public.utilizadores.';
  end if;

  insert into public.documentos_obra (
    obra_id,
    tipo,
    nome_arquivo,
    arquivo_url,
    enviado_por
  )
  values (
    p_obra_id,
    p_tipo,
    btrim(p_nome_arquivo),
    p_arquivo_url,
    v_utilizador_id
  )
  returning * into v_documento;

  return v_documento;
end;
$function$
;
ALTER FUNCTION public.fn_registar_documento_obra(uuid,text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_registar_documento_obra(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_registar_documento_obra(uuid,text,text,text) TO authenticated;
-- Immutable installation evidence in the already private backup namespace.
-- Captured only by this reviewed transaction, never refreshed by postcheck.
CREATE TABLE primeline_documentos_rh_backup.instalacao AS
SELECT jsonb_build_object(
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename IN('objects','buckets'))),
 'tables',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'schema',(SELECT nspname FROM pg_namespace WHERE oid=c.relnamespace),'name',c.relname,'owner',c.relowner,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a),'columns',(SELECT jsonb_agg(jsonb_build_object('name',attname,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(attacl) a)) ORDER BY attnum) FROM pg_attribute WHERE attrelid=c.oid AND attnum>0 AND NOT attisdropped)) ORDER BY c.oid) FROM pg_class c WHERE c.oid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass)),
 'helpers',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'owner',p.proowner,'security_definer',p.prosecdef,'acl',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.grantor,a.grantee,a.privilege_type,a.is_grantable) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),'config',p.proconfig) ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.pronamespace='primeline_documentos_rh_privado'::regnamespace OR p.oid IN(to_regprocedure('public.fn_apagar_anexo_rnc(uuid)'),to_regprocedure('public.fn_apagar_documento_obra(uuid)'),to_regprocedure('public.fn_registar_documento_obra(uuid,text,text,text)'),to_regprocedure('public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text)'),to_regprocedure('public.fn_guardar_validade_viatura(integer,uuid,text,text,date,date,text,date,text,text)'),to_regprocedure('public.fn_apagar_documento_entidade(uuid)'),to_regprocedure('public.fn_apagar_anexo_imovel(uuid)'),to_regprocedure('public.fn_apagar_anexo_pedido_orcamento(uuid)'),to_regprocedure('public.fn_apagar_imovel_empresa(uuid)'),to_regprocedure('public.fn_apagar_reuniao_condominio(uuid)'),to_regprocedure('public.fn_apagar_versao_pedido_orcamento(uuid)'),to_regprocedure('public.fn_cancelar_pedido_orcamento(uuid)'),to_regprocedure('public.fn_gerir_registo_frota(text,uuid,text,jsonb)')) OR p.oid IN('public.fn_utilizador_atual_id()'::regprocedure,'public.fn_e_administrativo()'::regprocedure) OR p.oid IN(SELECT d.refobjid FROM pg_depend d JOIN pg_policy pol ON pol.oid=d.objid WHERE d.classid='pg_policy'::regclass AND d.refclassid='pg_proc'::regclass AND pol.polrelid IN('public.documentos'::regclass,'public.ausencias_anexos'::regclass,'storage.objects'::regclass,'storage.buckets'::regclass))),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',nspowner,'acl',nspacl) ORDER BY nspname) FROM pg_namespace WHERE nspname IN('primeline_documentos_rh_privado','storage')),
 'bucket',(SELECT jsonb_agg(to_jsonb(b)) FROM storage.buckets b WHERE id='documentos')
) AS catalogo;
REVOKE ALL ON primeline_documentos_rh_backup.instalacao FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
