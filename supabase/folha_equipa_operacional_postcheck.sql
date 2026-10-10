BEGIN READ ONLY;
DO $$ DECLARE b record; atual jsonb; minus text; sig text; BEGIN
 IF (SELECT count(*) FROM public.quadro_equipa_permanencias)<>0 OR (SELECT count(*) FROM folha_privado.equipa_revisoes)<>0 THEN RAISE EXCEPTION 'EXPECTED_EMPTY_TEAM'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.quadro_equipa_permanencias'::regclass) THEN RAISE EXCEPTION 'TEAM_RLS_DISABLED'; END IF;
 IF has_table_privilege('authenticated','public.quadro_equipa_permanencias','INSERT,UPDATE,DELETE') OR has_table_privilege('anon','public.quadro_equipa_permanencias','SELECT')
 THEN RAISE EXCEPTION 'TEAM_DIRECT_ACCESS'; END IF;
 FOR b IN SELECT * FROM primeline_equipa_backup.legado LOOP
  minus:=CASE WHEN b.tabela IN('colaboradores','obras','utilizadores') THEN 'delegacao' WHEN b.tabela='folha_externos_dias' THEN 'funcao' ELSE '_no_added_field_' END;
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)-%L ORDER BY (to_jsonb(x)-%L)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',minus,minus,b.tabela) INTO atual;
  IF atual IS DISTINCT FROM b.linhas THEN RAISE EXCEPTION 'LEGACY_CHANGED: %',b.tabela; END IF;
 END LOOP;
 FOR b IN SELECT * FROM primeline_equipa_backup.funcoes LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(b.assinatura) AND proowner=b.owner_oid AND proacl IS NOT DISTINCT FROM b.acl) THEN RAISE EXCEPTION 'LEGACY_FUNCTION_ACL_CHANGED: %',b.assinatura; END IF;
 END LOOP;
 FOR b IN SELECT * FROM primeline_equipa_backup.catalogo LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=b.tabela_oid AND relowner=b.relowner AND relacl IS NOT DISTINCT FROM b.relacl AND relrowsecurity=b.relrowsecurity AND relforcerowsecurity=b.relforcerowsecurity) THEN RAISE EXCEPTION 'LEGACY_TABLE_SECURITY_CHANGED: %',b.relname; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.policyname),'[]') INTO atual FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=b.relname;
  IF atual IS DISTINCT FROM b.policies THEN RAISE EXCEPTION 'LEGACY_POLICY_CHANGED: %',b.relname; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('oid',t.oid,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.oid),'[]') INTO atual FROM pg_trigger t WHERE t.tgrelid=b.tabela_oid AND NOT t.tgisinternal AND t.tgname<>'trg_01_equipa_alocacao';
  IF atual IS DISTINCT FROM b.triggers THEN RAISE EXCEPTION 'LEGACY_TRIGGER_CHANGED: %',b.relname; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('oid',k.oid,'definition',pg_get_constraintdef(k.oid)) ORDER BY k.oid),'[]') INTO atual FROM pg_constraint k WHERE k.conrelid=b.tabela_oid AND k.conname NOT IN('colaboradores_delegacao_check','obras_delegacao_check','utilizadores_delegacao_check','folha_externos_dias_funcao_check');
  IF atual IS DISTINCT FROM b.constraints THEN RAISE EXCEPTION 'LEGACY_CONSTRAINT_CHANGED: %',b.relname; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum),'[]') INTO atual FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=b.tabela_oid AND a.attnum>0 AND NOT a.attisdropped AND NOT (b.relname IN('colaboradores','obras','utilizadores') AND a.attname='delegacao') AND NOT (b.relname='folha_externos_dias' AND a.attname='funcao');
  IF atual IS DISTINCT FROM b.colunas THEN RAISE EXCEPTION 'LEGACY_COLUMN_CHANGED: %',b.relname; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.quadro_equipa_permanencias'::regclass,'folha_privado.equipa_revisoes'::regclass) AND relowner<>'postgres'::regrole) THEN RAISE EXCEPTION 'TEAM_OWNER'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_equipa_permanencias'::regclass AND tgname='equipa_integridade' AND tgenabled='O') OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND tgname='trg_01_equipa_alocacao' AND tgenabled='O') THEN RAISE EXCEPTION 'TEAM_TRIGGER_MISSING'; END IF;
 FOREACH sig IN ARRAY ARRAY['public.fn_equipa_operar_v2(text,jsonb,boolean,text)','public.fn_folha_ferias_mapa_v2(date,date)'] LOOP
  IF NOT has_function_privilege('authenticated',sig,'EXECUTE') OR has_function_privilege('anon',sig,'EXECUTE') THEN RAISE EXCEPTION 'RPC_ACL: %',sig; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.ponto_pessoal_obra'::regclass AND t.tgname='trg_01_folha_legacy_closed' AND t.tgfoid=to_regprocedure('folha_privado.legacy_closed()') AND t.tgtype=62 AND t.tgenabled IN('O','A')) THEN RAISE EXCEPTION 'LEGACY_CUTOVER_UNCONFIRMED'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='folha_privado.equipa_revisoes'::regclass) THEN RAISE EXCEPTION 'REVISION_RLS_DISABLED'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname IN('elegivel_equipa','guardar_permanencia','proteger_alocacao_persistente','quadro_diario_preservado','quadro_contexto_preservado','gestao_contexto_preservado') AND (has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'))) THEN RAISE EXCEPTION 'PRIVATE_HELPER_EXPOSED'; END IF;
 RAISE NOTICE 'FOLHA_EQUIPA_POSTCHECK_OK';
END $$;
COMMIT;
