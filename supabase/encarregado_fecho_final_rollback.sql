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
 IF (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.definicao OR (SELECT jsonb_build_object('owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'proconfig',p.proconfig,'volatility',p.provolatile,'parallel',p.proparallel,'strict',p.proisstrict,'leakproof',p.proleakproof,'kind',p.prokind,'linguagem',l.lanname,'argumentos',pg_get_function_arguments(p.oid),'argumentos_identidade',pg_get_function_identity_arguments(p.oid),'retorno',pg_get_function_result(p.oid),'tipo_retorno',p.prorettype::regtype::text,'acl_efetiva',(SELECT coalesce(jsonb_agg(jsonb_build_object('grantee',CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,'grantor',pg_get_userbyid(gate_acl.grantor),'privilege',gate_acl.privilege_type,'grantable',gate_acl.is_grantable) ORDER BY CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,pg_get_userbyid(gate_acl.grantor),gate_acl.privilege_type,gate_acl.is_grantable),'[]'::jsonb) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) gate_acl)) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.metadata THEN RAISE EXCEPTION 'ROLLBACK_FUNCTION_DIVERGENCE: %',r.assinatura; END IF;
 END LOOP;
END $$;
DROP FUNCTION folha_privado.operar_periodos(jsonb,boolean,text),folha_privado.operar_externo(text,jsonb,boolean,text),folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb),folha_privado.normal_externo(uuid,date),folha_privado.operar_final_base(text,jsonb,boolean,text);
DROP TABLE public.folha_externos_permanencias;
DROP FUNCTION folha_privado.integridade_externo();
DROP TABLE folha_privado.externos_revisoes,folha_privado.periodos_revisoes;
SELECT 'ENCARREGADO_FINAL_ROLLBACK_OK' AS resultado;
COMMIT;
