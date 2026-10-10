-- Frontend published: 11aac61a165369007d9d18276d8cab79329d4121; 59 verified assets.
-- Fingerprint: SHA-256(UTF-8(path TAB lowercase-sha256 LF)), paths sorted ordinal.
-- Existing identical gate is reused without mutation; divergent state is refused. Does not consume the gate or run Phase B.
BEGIN;
DO $exact_functions$
DECLARE expected jsonb; actual jsonb;
BEGIN
 IF (SELECT count(*) FROM primeline_folha_v2_backup.instalacao_funcoes)<>1 THEN RAISE EXCEPTION 'FOLHA_INSTALLATION_EVIDENCE_REQUIRED'; END IF;
 SELECT jsonb_agg INTO expected FROM primeline_folha_v2_backup.instalacao_funcoes;
 actual:=(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',p.proowner,'acl',p.proacl,'config',p.proconfig) ORDER BY p.oid::regprocedure::text COLLATE "C")
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' OR (n.nspname='public' AND p.proname IN('fn_folha_contexto_v2','fn_folha_pessoas_v2','fn_folha_operar_v2','fn_folha_historico_v2','fn_folha_gestao_v2','fn_folha_gestao_contexto_v2')));
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FOLHA_FUNCTION_CATALOG_DRIFT'; END IF;
END $exact_functions$;
DO $$ DECLARE t text; r text; f record; current_columns jsonb; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 FOREACH t IN ARRAY ARRAY['folha_registos','folha_historico','folha_he','folha_externos','folha_externos_dias','folha_config_empresa','folha_horarios','folha_direitos_ferias','folha_ferias_revisoes','folha_vencimentos','folha_tarefas_reportes','folha_gestao_historico'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('public.'||t) AND relowner='postgres'::regrole AND relrowsecurity) THEN RAISE EXCEPTION 'NEW_TABLE_INVALID: %',t; END IF;
  EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I)',t) INTO f;
  IF f.exists THEN RAISE EXCEPTION 'NEW_TABLE_NOT_EMPTY: %',t; END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_table_privilege(r,'public.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') THEN RAISE EXCEPTION 'NEW_TABLE_PUBLIC_GRANT'; END IF;
  END LOOP;
 END LOOP;
 FOREACH t IN ARRAY ARRAY['fn_folha_contexto_v2(date,uuid)','fn_folha_pessoas_v2(date,uuid)','fn_folha_historico_v2(jsonb)','fn_folha_operar_v2(text,jsonb,boolean,text)','fn_folha_gestao_v2(text,jsonb,boolean,text)','fn_folha_gestao_contexto_v2(uuid,uuid,date)'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=t::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'])
   OR NOT has_function_privilege('authenticated',t,'EXECUTE') OR has_function_privilege('anon',t,'EXECUTE')
   OR EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE p.oid=t::regprocedure AND x.grantee=0)
  THEN RAISE EXCEPTION 'NEW_RPC_INVALID: %',t; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_gestao_historico'::regclass AND attname='dominio' AND attgenerated='s')
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_gestao_historico'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%planning_concluded_alerts_resolved%')
 THEN RAISE EXCEPTION 'MANAGEMENT_HISTORY_DOMAIN_INVALID'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_registos'::regclass AND tgname='trg_folha_invalidar_review' AND tgenabled='O')
 OR to_regprocedure('folha_privado.he_operacional(jsonb)') IS NULL
 OR strpos(pg_get_functiondef('folha_privado.linha(uuid,uuid,date,text)'::regprocedure),'''special_reviewed''')=0
 OR strpos(pg_get_expr((SELECT adbin FROM pg_attrdef WHERE adrelid='public.folha_gestao_historico'::regclass AND adnum=(SELECT attnum FROM pg_attribute WHERE attrelid='public.folha_gestao_historico'::regclass AND attname='dominio')),'public.folha_gestao_historico'::regclass),'he_process')>0
 THEN RAISE EXCEPTION 'SECURITY_VISIBILITY_CONTRACT_INVALID'; END IF;
 IF strpos(pg_get_functiondef('public.fn_folha_contexto_v2(date,uuid)'::regprocedure),'public.ponto_pessoal_obra h JOIN public.colaboradores')=0
  OR strpos(pg_get_functiondef('public.fn_folha_contexto_v2(date,uuid)'::regprocedure),'absence_pending')=0
  OR strpos(pg_get_functiondef('folha_privado.linha(uuid,uuid,date,text)'::regprocedure),'''legacy'',legacy')=0
  OR strpos(pg_get_functiondef('folha_privado.linha(uuid,uuid,date,text)'::regprocedure),'NOT legacy AND conf IS NULL')=0
 THEN RAISE EXCEPTION 'VISIBLE_STATE_CONTRACT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND (p.proowner<>'postgres'::regrole OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'PRIVATE_HELPER_EXPOSED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='trg_zz_folha_confirmacao_ausencia' AND tgenabled='O') OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias_anexos'::regclass AND tgname='trg_00_folha_anexo_lock' AND tgenabled='O') THEN RAISE EXCEPTION 'ADM_DOCUMENT_GUARDS_REQUIRED'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.ausencias_anexos x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_folha_v2_backup.anexos x) THEN RAISE EXCEPTION 'ATTACHMENT_DATA_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_registos'::regclass AND attname='expected_minutes' AND NOT attisdropped)
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='trg_folha_ausencia_reconciliar' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND tgname='trg_folha_alocacao_reconciliar' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ausencias'::regclass AND tgname='trg_folha_vencimentos_ausencia' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_registos'::regclass AND tgname='trg_folha_vencimentos_facto' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND tgname='trg_folha_vencimentos_alocacao' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_folha_vencimentos_legado' AND tgenabled='O')
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND tgname='trg_00_folha_alocacao_lock' AND tgenabled='O')
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'RECONCILIATION_CONTRACT_INVALID'; END IF;
 FOR f IN SELECT * FROM primeline_folha_v2_backup.triggers LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=f.tabela::regclass AND tgname=f.nome AND tgenabled=f.ativo AND pg_get_triggerdef(oid)=f.definicao)
  THEN RAISE EXCEPTION 'LEGACY_TRIGGER_DRIFT: %.%',f.tabela,f.nome; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND t.tgenabled<>'O') THEN RAISE EXCEPTION 'NEW_TRIGGER_DISABLED'; END IF;
 FOR f IN SELECT * FROM primeline_folha_v2_backup.estrutura LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=f.tabela::regclass AND relacl IS NOT DISTINCT FROM f.relacl AND relrowsecurity=f.relrowsecurity AND relforcerowsecurity=f.relforcerowsecurity AND pg_get_userbyid(relowner)=f.owner)
  THEN RAISE EXCEPTION 'LEGACY_TABLE_ACL_DRIFT: %',f.tabela; END IF;
  SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) INTO current_columns FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=f.tabela::regclass AND a.attnum>0 AND NOT a.attisdropped;
  IF current_columns IS DISTINCT FROM f.colunas THEN RAISE EXCEPTION 'LEGACY_COLUMN_DRIFT: %',f.tabela; END IF;
 END LOOP;
 FOR f IN SELECT * FROM primeline_folha_v2_backup.funcoes WHERE assinatura NOT IN('fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)','public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)') LOOP
  IF replace(pg_get_functiondef(f.assinatura::regprocedure),chr(13),'') IS DISTINCT FROM replace(f.definicao,chr(13),'')
   OR (SELECT proacl::text FROM pg_proc WHERE oid=f.assinatura::regprocedure) IS DISTINCT FROM f.acl THEN RAISE EXCEPTION 'LEGACY_FUNCTION_DRIFT: %',f.assinatura; END IF;
 END LOOP;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM pg_policies x WHERE schemaname='public' AND tablename NOT LIKE 'folha_%') IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM primeline_folha_v2_backup.policies x) THEN RAISE EXCEPTION 'LEGACY_POLICY_DRIFT'; END IF;
 FOR t,r IN VALUES ('quadro_pessoal_alocacao','alocacoes'),('quadro_pessoal_movimentos','movimentos'),('ponto_pessoal_obra','ponto'),('ausencias','ausencias'),('colaboradores','colaboradores'),('horas_extraordinarias','he'),('planeamento_itens','planeamento'),('alertas','alertas') LOOP
  EXECUTE format('SELECT (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.%I x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_folha_v2_backup.%I x)',t,r) INTO f;
  IF f."?column?" THEN RAISE EXCEPTION 'LEGACY_DATA_CHANGED: %',t; END IF;
 END LOOP;
END $$;
SELECT 'FOLHA_V2_POSTCHECK_OK' status;

DO $storage_baseline$ BEGIN
 IF (SELECT count(*) FROM pg_class c WHERE c.oid IN(to_regclass('storage.objects'),to_regclass('storage.buckets')) AND pg_get_userbyid(c.relowner)='supabase_storage_admin' AND c.relrowsecurity)<>2
 THEN RAISE EXCEPTION 'STORAGE_OWNER_OR_RLS_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_roles r ON r.rolname=current_user WHERE c.oid=to_regclass('storage.objects') AND (r.rolsuper OR r.rolbypassrls OR (NOT c.relforcerowsecurity AND pg_has_role(current_user,c.relowner,'USAGE')))) THEN RAISE EXCEPTION 'STORAGE_FULL_READ_VISIBILITY_REQUIRED'; END IF;
END $storage_baseline$;
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
 IF (SELECT backup_fingerprint FROM primeline_documentos_rh_backup.instalacao) IS DISTINCT FROM (SELECT jsonb_object_agg(name,jsonb_build_object('rows',digest,'metadata',(SELECT jsonb_build_object('owner',c.relowner,'kind',c.relkind,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'acl',c.relacl,'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',a.atttypid,'mod',a.atttypmod,'nullable',NOT a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl,'dropped',a.attisdropped,'identity',a.attidentity,'generated',a.attgenerated) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0),'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),'triggers',(SELECT jsonb_agg(pg_get_triggerdef(x.oid) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid),'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY pg_get_indexdef(x.indexrelid)) FROM pg_index x WHERE x.indrelid=c.oid)) FROM pg_class c WHERE c.oid=to_regclass('primeline_documentos_rh_backup.'||name)))) FROM (SELECT name,(xpath('/table/row/value/text()',query_to_xml(format('SELECT md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'''')) value FROM primeline_documentos_rh_backup.%I t',name),false,false,'')))[1]::text digest FROM unnest(ARRAY['documentos','anexos','objects','policies','tables','rpc']) name) d) THEN RAISE EXCEPTION 'DOCUMENT_ORIGINAL_BACKUP_CHANGED'; END IF;
 IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'DOCUMENT_CATALOG_DRIFT'; END IF;
END $document_catalog$;
DO $$ DECLARE p text; t regclass; BEGIN
 FOREACH p IN ARRAY ARRAY['rh_empresa_guard','rh_anexo_empresa_guard'] LOOP
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

DO $state$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regclass('folha_privado.legacy_cutover') IS NOT NULL OR (SELECT count(*) FROM public.ponto_pessoal_obra)<>0 THEN RAISE EXCEPTION 'CUTOVER_STATE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM public.ponto_pessoal_obra p JOIN public.folha_registos f ON f.colaborador_id=p.colaborador_id AND f.data=p.data) THEN RAISE EXCEPTION 'LEGACY_V2_CONFLICT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_quadro_rollout.controlo WHERE singleton AND estado='a' AND fase_b_aplicada_em IS NULL) THEN RAISE EXCEPTION 'ROLLOUT_STATE_CHANGED'; END IF;
END $state$;
DO $approval$
DECLARE v_catalog jsonb; v_live jsonb; v_installation text; v_created boolean:=false;
BEGIN
 IF to_regclass('primeline_pacote2_gate.aprovacao') IS NULL THEN
  IF to_regnamespace('primeline_pacote2_gate') IS NOT NULL THEN RAISE EXCEPTION 'UNEXPECTED_GATE_SCHEMA'; END IF;
  CREATE SCHEMA primeline_pacote2_gate AUTHORIZATION postgres;
  REVOKE ALL ON SCHEMA primeline_pacote2_gate FROM PUBLIC,anon,authenticated,service_role;
  CREATE TABLE primeline_pacote2_gate.aprovacao(release_id text,reviewed_by text,reviewed_at timestamptz,consumed_at timestamptz,frontend_assets_sha256 text,frontend_validated boolean,backend_v2_validated boolean,installation_id text,expected_catalog jsonb);
  ALTER TABLE primeline_pacote2_gate.aprovacao OWNER TO postgres;
  ALTER TABLE primeline_pacote2_gate.aprovacao ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON primeline_pacote2_gate.aprovacao FROM PUBLIC,anon,authenticated,service_role;
  v_created:=true;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_pacote2_gate' AND nspowner='postgres'::regrole)
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='primeline_pacote2_gate.aprovacao'::regclass AND relowner='postgres'::regrole AND relrowsecurity)
 OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_pacote2_gate' AND x.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.oid='primeline_pacote2_gate.aprovacao'::regclass AND x.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) x WHERE a.attrelid='primeline_pacote2_gate.aprovacao'::regclass AND x.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'GATE_NOT_PRIVATE'; END IF;
 SELECT instalacao_id::text INTO STRICT v_installation FROM primeline_quadro_rollout.controlo WHERE singleton;
 SELECT jsonb_build_object(
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','folha_privado','primeline_documentos_rh_privado','storage') AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.policyname) FROM pg_policies x WHERE x.schemaname=n.nspname AND x.tablename=c.relname),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',x.tgname,'enabled',x.tgenabled,'definition',pg_get_triggerdef(x.oid)) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid AND NOT x.tgisinternal),
 'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY x.indexrelid::regclass::text) FROM pg_index x WHERE x.indrelid=c.oid)) ORDER BY c.oid::regclass::text COLLATE "C") FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname IN('public','folha_privado') OR n.nspname='storage' AND c.relname IN('objects','buckets')) AND c.relkind IN('r','p'))) INTO v_catalog;
 IF v_created THEN
  INSERT INTO primeline_pacote2_gate.aprovacao VALUES('pacote2_folha_v2_20261005','postgres',clock_timestamp(),NULL,'99f9904ded011f6aa0a2140a1e9b89490abf39407dc4fdd81fee473491ddc76b',true,true,v_installation,v_catalog);
 END IF;
 SELECT jsonb_build_object(
 'functions',(SELECT jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',replace(pg_get_functiondef(p.oid),chr(13),''),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text COLLATE "C") FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('public','folha_privado','primeline_documentos_rh_privado','storage') AND p.prokind='f'),
 'tables',(SELECT jsonb_agg(jsonb_build_object('name',c.oid::regclass::text,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl::text,
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'policies',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.policyname) FROM pg_policies x WHERE x.schemaname=n.nspname AND x.tablename=c.relname),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('name',x.tgname,'enabled',x.tgenabled,'definition',pg_get_triggerdef(x.oid)) ORDER BY x.tgname) FROM pg_trigger x WHERE x.tgrelid=c.oid AND NOT x.tgisinternal),
 'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(x.indexrelid) ORDER BY x.indexrelid::regclass::text) FROM pg_index x WHERE x.indrelid=c.oid)) ORDER BY c.oid::regclass::text COLLATE "C") FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname IN('public','folha_privado') OR n.nspname='storage' AND c.relname IN('objects','buckets')) AND c.relkind IN('r','p'))) INTO v_live;
 IF (SELECT count(*) FROM primeline_pacote2_gate.aprovacao)<>1 OR NOT EXISTS(SELECT 1 FROM primeline_pacote2_gate.aprovacao WHERE release_id='pacote2_folha_v2_20261005' AND reviewed_by='postgres' AND reviewed_at IS NOT NULL AND reviewed_at<=clock_timestamp() AND expected_catalog=v_live AND installation_id=v_installation AND consumed_at IS NULL AND frontend_validated IS TRUE AND backend_v2_validated IS TRUE AND frontend_assets_sha256='99f9904ded011f6aa0a2140a1e9b89490abf39407dc4fdd81fee473491ddc76b' AND frontend_assets_sha256 ~ '^[0-9a-f]{64}$') THEN RAISE EXCEPTION 'GATE_APPROVAL_MISMATCH'; END IF;
END $approval$;
SELECT 'PACOTE2_GATE_PRE_CUTOVER_OK' AS status;
COMMIT;
