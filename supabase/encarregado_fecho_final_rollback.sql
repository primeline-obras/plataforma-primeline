-- Reversão explícita; recusa perda de dados posteriores. Nunca executar automaticamente.
BEGIN;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
DO $$ DECLARE r record; a record; actual jsonb; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_externos_permanencias) OR EXISTS(SELECT 1 FROM folha_privado.periodos_revisoes) THEN RAISE EXCEPTION 'ROLLBACK_DATA_PRESENT'; END IF;
 FOR r IN SELECT * FROM primeline_encarregado_final_backup.privado LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM folha_privado.%I x',r.tabela) INTO actual;
 IF actual IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'PRIVATE_DATA_CHANGED: %',r.tabela; END IF;
 END LOOP;
 FOR r IN SELECT * FROM primeline_encarregado_final_backup.dados LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO actual;
 IF actual IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'OPERATIONAL_DATA_CHANGED: %',r.tabela; END IF;
 END LOOP;

 FOR r IN SELECT * FROM primeline_encarregado_final_backup.funcoes LOOP
 EXECUTE r.definicao;
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',r.assinatura);
 FOR a IN SELECT * FROM aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) LOOP
 EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',a.privilege_type,r.assinatura,CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE quote_ident(a.grantee::regrole::text) END,CASE WHEN a.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
 EXECUTE format('ALTER FUNCTION %s OWNER TO %I',r.assinatura,r.proowner::regrole::text);
 END LOOP;
END $$;
DROP FUNCTION folha_privado.operar_periodos(jsonb,boolean,text),folha_privado.operar_externo(text,jsonb,boolean,text),folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb),folha_privado.normal_externo(uuid,date),folha_privado.operar_final_base(text,jsonb,boolean,text);
DROP TABLE public.folha_externos_permanencias;
DROP FUNCTION folha_privado.integridade_externo();
DROP TABLE folha_privado.externos_revisoes,folha_privado.periodos_revisoes;
SELECT 'ENCARREGADO_FINAL_ROLLBACK_OK' AS resultado;
COMMIT;
