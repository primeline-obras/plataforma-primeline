-- Execução MANUAL no projeto znttyadndpkxuekhjamd. Não é uma migration.
-- BLOCO 1: executar de BEGIN até ROLLBACK e exportar a única linha JSON.
-- Sem registos pessoais, URLs de ficheiros ou valores económicos.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '90s';
WITH rels AS (
 SELECT c.*,n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('public','storage','folha_privado','primeline_quadro_rollout','primeline_pacote2_gate','primeline_documentos_rh_privado')
 AND c.relkind IN ('r','p','v','m')
), funcs AS (
 SELECT p.*,n.nspname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','folha_privado','primeline_documentos_rh_privado','storage') AND p.prokind IN ('f','p')
), expected(name) AS (
 VALUES ('public.folha_config_empresa'),('public.folha_horarios'),('public.folha_externos'),
 ('public.folha_externos_dias'),('public.folha_registos'),('public.folha_historico'),('public.folha_he'),
 ('folha_privado.operacoes'),('public.folha_direitos_ferias'),('public.folha_ferias_revisoes'),
 ('public.folha_vencimentos'),('public.folha_tarefas_reportes'),('public.folha_gestao_historico')
), counts AS (
 SELECT n.nspname,c.relname,
 (xpath('/table/row/n/text()',query_to_xml(format('SELECT count(*) AS n FROM %I.%I',n.nspname,c.relname),false,false,'')))[1]::text::bigint AS total
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relname IN
 ('ponto_pessoal_obra','ausencias','horas_extraordinarias','quadro_pessoal_alocacao','quadro_pessoal_movimentos')
)
SELECT jsonb_build_object(
 'environment',jsonb_build_object('project','znttyadndpkxuekhjamd','at',now(),'database',current_database(),'role',current_user,'server_version',current_setting('server_version'),'read_only',current_setting('transaction_read_only')),
 'document_policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY schemaname,tablename,policyname) FROM pg_policies p WHERE (schemaname='public' AND tablename IN ('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename IN('objects','buckets'))),
 'document_bucket',(SELECT jsonb_agg(to_jsonb(b)) FROM storage.buckets b WHERE id='documentos'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('schema',r.nspname,'name',r.relname,'kind',r.relkind,'owner',pg_get_userbyid(r.relowner),'rls',r.relrowsecurity,'force_rls',r.relforcerowsecurity,'acl',r.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'nullable',NOT a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl::text) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',x.conname,'type',x.contype,'definition',pg_get_constraintdef(x.oid),'validated',x.convalidated) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=r.oid),
 'indexes',(SELECT jsonb_agg(jsonb_build_object('definition',pg_get_indexdef(x.indexrelid),'valid',x.indisvalid) ORDER BY x.indexrelid) FROM pg_index x WHERE x.indrelid=r.oid),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid),'function',t.tgfoid::regprocedure::text) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=r.oid AND NOT t.tgisinternal),
 'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.policyname) FROM pg_policies p WHERE p.schemaname=r.nspname AND p.tablename=r.relname),
 'view_definition',CASE WHEN r.relkind IN ('v','m') THEN pg_get_viewdef(r.oid,true) END) ORDER BY r.nspname,r.relname) FROM rels r),
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'schema',p.nspname,'owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'config',p.proconfig,'acl',coalesce(p.proacl,acldefault('f',p.proowner))::text,'definition_sha256',pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(replace(pg_get_functiondef(p.oid),chr(13),''),'UTF8')),'hex'),'volatility',p.provolatile,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'body',replace(p.prosrc,chr(13),'')) ORDER BY p.nspname,p.oid::regprocedure::text) FROM funcs p),
 'schemas',(SELECT jsonb_agg(jsonb_build_object('name',nspname,'owner',pg_get_userbyid(nspowner),'acl',nspacl::text) ORDER BY nspname) FROM pg_namespace WHERE nspname IN ('folha_privado','primeline_pacote2_gate','primeline_quadro_rollout','primeline_encarregado_20261004','primeline_documentos_rh_privado','primeline_documentos_rh_backup')),
 'expected_new_objects',(SELECT jsonb_agg(jsonb_build_object('name',name,'exists',to_regclass(name) IS NOT NULL) ORDER BY name) FROM expected),
 'counts',(SELECT jsonb_agg(to_jsonb(x) ORDER BY relname) FROM counts x),
 'calendar_candidates',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'column',a.attname,'type',format_type(a.atttypid,a.atttypmod)) ORDER BY n.nspname,c.relname,a.attnum) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped WHERE n.nspname IN ('public','folha_privado') AND (c.relname ~* '(feriad|calendar|calendario|laboral)' OR a.attname ~* '(feriad|holiday|calendar|dia_especial)')),
 'table_grants',(SELECT jsonb_agg(to_jsonb(g) ORDER BY table_schema,table_name,grantee,privilege_type) FROM information_schema.table_privileges g WHERE table_schema IN ('public','storage','folha_privado')),
 'column_grants',(SELECT jsonb_agg(to_jsonb(g) ORDER BY table_schema,table_name,column_name,grantee,privilege_type) FROM information_schema.column_privileges g WHERE table_schema IN ('public','storage','folha_privado'))
) AS readonly_catalog;
-- Additional aggregate readiness in the SAME read-only snapshot. No RPC execution.
DO $readiness$
DECLARE r record; cfg jsonb; years jsonb; sources jsonb:='[]'; installed jsonb; historical jsonb; approval jsonb; live jsonb; approval_state text:='ABSENT'; approval_count integer:=0; cutover boolean; gate_private boolean:=false; installation_matches boolean:=false;
BEGIN
 IF to_regclass('public.folha_config_empresa') IS NOT NULL THEN
  EXECUTE 'SELECT jsonb_agg(jsonb_build_object(''empresa_id'',empresa_id,''revision'',revision,''calendar_complete'',calendar_complete,''calendar_validated_years'',calendar_validated_years,''holiday_count'',cardinality(holiday_dates),''overtime_enabled'',overtime_enabled)) FROM public.folha_config_empresa' INTO cfg;
 END IF;
 FOR r IN SELECT n.nspname,c.relname,a.attname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid WHERE n.nspname='public' AND c.relkind IN('r','p') AND c.relname ~* '(feriad|calendar|calendario)' AND a.atttypid='date'::regtype AND a.attnum>0 AND NOT a.attisdropped LOOP
  EXECUTE format('SELECT jsonb_agg(y ORDER BY y) FROM (SELECT DISTINCT extract(year FROM %I)::integer y FROM %I.%I WHERE %I IS NOT NULL) x',r.attname,r.nspname,r.relname,r.attname) INTO years;
  sources:=sources||jsonb_build_array(jsonb_build_object('schema',r.nspname,'table',r.relname,'column',r.attname,'years',years,'completeness','NOT_INFERRED_FROM_ROWS'));
 END LOOP;
 IF to_regclass('primeline_encarregado_20261004.instalacao') IS NOT NULL THEN EXECUTE 'SELECT jsonb_agg(md5(catalogo::text)) FROM primeline_encarregado_20261004.instalacao' INTO installed; END IF;
 IF to_regclass('primeline_encarregado_20261004.snapshot') IS NOT NULL THEN EXECUTE 'SELECT jsonb_agg(md5(catalogo::text)) FROM primeline_encarregado_20261004.snapshot' INTO historical; END IF;
 cutover:=to_regclass('folha_privado.legacy_cutover') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=to_regclass('public.ponto_pessoal_obra') AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O' AND tgtype=62 AND tgfoid=to_regprocedure('folha_privado.legacy_closed()'));
 IF cutover THEN
  cutover:=EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('folha_privado.legacy_closed()') AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND NOT has_function_privilege('authenticated',oid,'EXECUTE') AND NOT has_function_privilege('anon',oid,'EXECUTE') AND NOT has_function_privilege('service_role',oid,'EXECUTE') AND btrim(prosrc,E' \t\n\r')=$body$BEGIN RAISE EXCEPTION 'LEGACY_WRITER_CLOSED: use Folha de Ponto V2' USING ERRCODE='42501'; END$body$)
   AND EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('folha_privado.legacy_cutover') AND relowner='postgres'::regrole AND relrowsecurity)
   AND NOT EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole)
   AND NOT EXISTS(SELECT 1 FROM pg_attribute c CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE c.attrelid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole);
  IF cutover THEN
   EXECUTE 'SELECT NOT EXISTS(SELECT 1 FROM (TABLE public.ponto_pessoal_obra EXCEPT ALL TABLE folha_privado.legacy_cutover) x) AND NOT EXISTS(SELECT 1 FROM (TABLE folha_privado.legacy_cutover EXCEPT ALL TABLE public.ponto_pessoal_obra) x)' INTO cutover;
  END IF;
 END IF;
 IF to_regclass('primeline_pacote2_gate.aprovacao') IS NOT NULL THEN
  EXECUTE 'SELECT count(*)::integer, CASE WHEN count(*)=1 THEN jsonb_agg(to_jsonb(x))->0 END FROM primeline_pacote2_gate.aprovacao x' INTO approval_count,approval;
  gate_private:=EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_pacote2_gate' AND nspowner='postgres'::regrole)
   AND NOT EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='primeline_pacote2_gate' AND a.grantee<>'postgres'::regrole)
   AND NOT EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid=to_regclass('primeline_pacote2_gate.aprovacao') AND (c.relowner<>'postgres'::regrole OR a.grantee<>'postgres'::regrole))
   AND NOT EXISTS(SELECT 1 FROM pg_attribute c CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE c.attrelid=to_regclass('primeline_pacote2_gate.aprovacao') AND a.grantee<>'postgres'::regrole);
  IF to_regclass('primeline_quadro_rollout.controlo') IS NOT NULL THEN
   EXECUTE 'SELECT estado=''a'' AND instalacao_id::text=$1 FROM primeline_quadro_rollout.controlo WHERE singleton' INTO installation_matches USING approval->>'installation_id';
  END IF;
 END IF;
  live:=(SELECT jsonb_build_object(
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','folha_privado','primeline_documentos_rh_privado','storage') AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.policyname) FROM pg_policies x WHERE x.schemaname=n.nspname AND x.tablename=c.relname),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',x.tgname,'enabled',x.tgenabled,'definition',pg_get_triggerdef(x.oid)) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid AND NOT x.tgisinternal),
 'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY x.indexrelid::regclass::text) FROM pg_index x WHERE x.indrelid=c.oid)) ORDER BY c.oid::regclass::text COLLATE "C") FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname IN('public','folha_privado') OR n.nspname='storage' AND c.relname IN('objects','buckets')) AND c.relkind IN('r','p'))));
 IF to_regclass('primeline_pacote2_gate.aprovacao') IS NOT NULL THEN
  approval_state:=CASE WHEN approval_count=0 THEN 'ABSENT' WHEN approval IS NULL OR jsonb_typeof(approval->'expected_catalog') IS DISTINCT FROM 'object' THEN 'INCOMPATIBLE'
   WHEN approval->'expected_catalog' IS DISTINCT FROM live THEN 'STALE'
   WHEN NOT cutover OR NOT gate_private OR installation_matches IS DISTINCT FROM true OR approval->>'release_id' IS DISTINCT FROM 'pacote2_folha_v2_20261005' OR approval->>'consumed_at' IS NOT NULL OR approval->>'reviewed_by' IS DISTINCT FROM 'postgres' OR approval->>'reviewed_at' IS NULL OR (approval->>'reviewed_at')::timestamptz>now() OR approval->>'frontend_validated' IS DISTINCT FROM 'true' OR approval->>'backend_v2_validated' IS DISTINCT FROM 'true' OR approval->>'frontend_assets_sha256' IS NULL OR approval->>'frontend_assets_sha256' !~ '^[0-9a-f]{64}$' THEN 'INCOMPATIBLE'
   ELSE 'MATCH' END;
 END IF;
 RAISE NOTICE 'READINESS_AGGREGATE: %',jsonb_build_object(
  'historical_fingerprints',historical,'installation_fingerprints',installed,
  'documentary_installation_evidence',to_regclass('primeline_documentos_rh_backup.instalacao') IS NOT NULL,
  'folha_installed',to_regprocedure('public.fn_folha_operar_v2(text,jsonb,boolean,text)') IS NOT NULL,
  'legacy_cutover_installed',to_regprocedure('folha_privado.legacy_closed()') IS NOT NULL,
  'phase_b_approval_present',to_regclass('primeline_pacote2_gate.aprovacao') IS NOT NULL,
  'phase_b_approval',jsonb_build_object('state',approval_state,'cutover_present',cutover,'gate_private',gate_private,'installation_match',installation_matches,'expected_sha256',encode(sha256(convert_to((approval->'expected_catalog')::text,'UTF8')),'hex'),'live_sha256',encode(sha256(convert_to(live::text,'UTF8')),'hex'),'catalog_match',approval->'expected_catalog'=live),
  'compatibility_verdict','REAL_VALIDATION_REQUIRED: compare complete catalog with reviewed rollout; presence is not approval',
  'calendar_config',cfg,'calendar_sources',sources,'calendar_verdict',CASE WHEN cfg IS NULL THEN 'CONFIG_REQUIRED' ELSE 'VERIFY_VALIDATED_YEARS_AND_COMPLETENESS' END);
END $readiness$;
ROLLBACK;
