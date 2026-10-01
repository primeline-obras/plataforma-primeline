-- Rollback B: preserva dados e histórico produzidos após instalação.
BEGIN;
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
SELECT primeline_quadro_rollout.exigir_privacidade();
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM primeline_quadro_rollout.controlo WHERE singleton AND estado='b') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: rollback exige estado b'; END IF; END $$;
DO $$ DECLARE f record; g record; p record; role_name text; BEGIN
 FOR f IN SELECT * FROM primeline_backup.quadro_fase_b_funcoes_20261001 b WHERE (SELECT proc_row.proname FROM pg_proc proc_row WHERE proc_row.oid=b.assinatura::regprocedure) IN('fn_quadro_operar','fn_quadro_proteger_escrita','fn_quadro_ler_obra') LOOP
  EXECUTE f.definicao;
  EXECUTE format('ALTER FUNCTION %s OWNER TO %I',f.assinatura,f.owner);
  FOR g IN SELECT DISTINCT x.grantee FROM pg_proc pr CROSS JOIN LATERAL aclexplode(coalesce(pr.proacl,acldefault('f',pr.proowner))) x WHERE pr.oid=f.assinatura::regprocedure LOOP
   role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',f.assinatura,role_name);
  END LOOP;
  FOR g IN SELECT * FROM primeline_backup.quadro_fase_b_acl_funcoes_20261001 WHERE assinatura=f.assinatura LOOP
   role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',g.privilege_type,f.assinatura,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
 FOR p IN SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP EXECUTE format('DROP POLICY %I ON public.%I',p.policyname,p.tablename); END LOOP;
 FOR p IN SELECT * FROM primeline_backup.quadro_fase_b_policies_20261001 LOOP
  EXECUTE format('CREATE POLICY %I ON public.%I AS %s FOR %s TO %s%s%s',p.policyname,p.tablename,p.permissive,p.cmd,(SELECT string_agg(quote_ident(r),',') FROM unnest(p.roles) r),CASE WHEN p.qual IS NULL THEN '' ELSE ' USING ('||p.qual||')' END,CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK ('||p.with_check||')' END);
 END LOOP;
 REVOKE ALL ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
 FOR g IN SELECT * FROM primeline_backup.quadro_fase_b_acl_tabelas_20261001 WHERE tabela IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos','public.quadro_pessoal_alocacao','public.quadro_pessoal_movimentos') LOOP
  role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
  EXECUTE format('GRANT %s ON TABLE %s TO %s%s',g.privilege_type,g.tabela,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
 FOR g IN SELECT * FROM primeline_backup.quadro_fase_b_acl_colunas_20261001 LOOP
  role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
  EXECUTE format('GRANT %s (%I) ON TABLE %s TO %s%s',g.privilege_type,g.attname,g.tabela,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
END $$;
-- Não restaurar/reativar validações pelo backup: preservar evidência e exigir nova tentativa.
SELECT primeline_quadro_rollout.exigir_privacidade();
UPDATE primeline_quadro_rollout.validacoes SET invalidada_em=clock_timestamp()
WHERE instalacao_id=(SELECT instalacao_id FROM primeline_quadro_rollout.controlo WHERE singleton) AND invalidada_em IS NULL;
UPDATE primeline_quadro_rollout.controlo SET estado='a',tentativa=tentativa+1,tentativa_iniciada_em=clock_timestamp(),fase_b_aplicada_em=NULL WHERE singleton AND estado='b';
SELECT primeline_quadro_rollout.exigir_fase_a();
COMMIT;
