BEGIN READ ONLY;
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
COMMIT;
