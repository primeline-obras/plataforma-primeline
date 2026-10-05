BEGIN READ ONLY;
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
