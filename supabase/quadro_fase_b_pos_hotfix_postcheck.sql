BEGIN READ ONLY;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.ponto_pessoal_obra'::regclass AND tgname='trg_01_folha_legacy_closed' AND tgenabled='O' AND tgtype=62 AND tgfoid='folha_privado.legacy_closed()'::regprocedure) THEN RAISE EXCEPTION 'LEGACY_WRITER_NOT_CLOSED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('folha_privado.legacy_cutover') AND relowner='postgres'::regrole AND relrowsecurity)
 OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a WHERE c.oid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_attribute c CROSS JOIN LATERAL aclexplode(c.attacl) a WHERE c.attrelid=to_regclass('folha_privado.legacy_cutover') AND a.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'CUTOVER_SNAPSHOT_NOT_PRIVATE'; END IF;
 IF (SELECT btrim(prosrc,E' \t\n\r') FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure) IS DISTINCT FROM $body$BEGIN RAISE EXCEPTION 'LEGACY_WRITER_CLOSED: use Folha de Ponto V2' USING ERRCODE='42501'; END$body$ THEN RAISE EXCEPTION 'CUTOVER_HELPER_BODY_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM (TABLE public.ponto_pessoal_obra EXCEPT ALL TABLE folha_privado.legacy_cutover) x) OR EXISTS(SELECT 1 FROM (TABLE folha_privado.legacy_cutover EXCEPT ALL TABLE public.ponto_pessoal_obra) x) THEN RAISE EXCEPTION 'LEGACY_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.legacy_closed()'::regprocedure AND (NOT prosecdef OR proowner<>'postgres'::regrole OR proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('authenticated',oid,'EXECUTE') OR has_function_privilege('anon',oid,'EXECUTE') OR has_function_privilege('service_role',oid,'EXECUTE'))) THEN RAISE EXCEPTION 'CUTOVER_HELPER_INVALID'; END IF;
END $$;

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
DO $$ DECLARE f record; r text; c record; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'b'
 OR NOT EXISTS(SELECT 1 FROM primeline_pacote2_gate.aprovacao WHERE consumed_at IS NOT NULL) THEN RAISE EXCEPTION 'B_NOT_INSTALLED'; END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOR c IN SELECT oid FROM pg_class WHERE oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) LOOP
   IF has_table_privilege(r,c.oid,'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN RAISE EXCEPTION 'LEGACY_DML_GRANT'; END IF;
   IF EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped AND
    (has_column_privilege(r,c.oid,a.attnum,'INSERT') OR has_column_privilege(r,c.oid,a.attnum,'UPDATE') OR has_column_privilege(r,c.oid,a.attnum,'REFERENCES'))) THEN RAISE EXCEPTION 'LEGACY_COLUMN_GRANT'; END IF;
  END LOOP;
  IF has_function_privilege(r,'public.fn_quadro_operar(text,jsonb,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'LEGACY_RPC_GRANT'; END IF;
 END LOOP;
 IF NOT has_function_privilege('authenticated','public.fn_quadro_operar_v1(text,jsonb,boolean,text)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.fn_folha_operar_v2(text,jsonb,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'CONTROLLED_RPC_LOST'; END IF;
 FOR f IN SELECT * FROM primeline_quadro_b_20261005.funcoes WHERE assinatura NOT IN('fn_quadro_proteger_escrita()','fn_quadro_operar(text,jsonb,boolean,text)','public.fn_quadro_proteger_escrita()','public.fn_quadro_operar(text,jsonb,boolean,text)') LOOP
  IF replace(pg_get_functiondef(f.assinatura::regprocedure),chr(13),'') IS DISTINCT FROM replace(f.definicao,chr(13),'')
  OR (SELECT proacl::text FROM pg_proc WHERE oid=f.assinatura::regprocedure) IS DISTINCT FROM f.acl
  THEN RAISE EXCEPTION 'UNEXPECTED_FUNCTION_CHANGE: %',f.assinatura; END IF;
 END LOOP;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM pg_policies x WHERE schemaname='public')
 IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY tablename,policyname) FROM primeline_quadro_b_20261005.policies x) THEN RAISE EXCEPTION 'HOTFIX_POLICY_DRIFT'; END IF;
 IF (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.quadro_pessoal_alocacao x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.alocacoes x)
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.quadro_pessoal_movimentos x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.movimentos x)
 OR (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.ponto_pessoal_obra x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_quadro_b_20261005.ponto x) THEN RAISE EXCEPTION 'OPERATIONAL_DATA_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT tgisinternal AND tgenabled<>'O') THEN RAISE EXCEPTION 'TRIGGER_DISABLED'; END IF;
END $$;
SELECT 'POSTCHECK_B_POS_HOTFIX_OK' status;
COMMIT;
