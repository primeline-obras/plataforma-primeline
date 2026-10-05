BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF; END $$;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ DECLARE f record; g record; role_name text; BEGIN
 IF to_regclass('primeline_quadro_b_20261005.funcoes') IS NULL OR (SELECT estado FROM primeline_quadro_rollout.controlo WHERE singleton) IS DISTINCT FROM 'b' THEN RAISE EXCEPTION 'ROLLBACK_B_PRECONDITION'; END IF;
 FOR f IN SELECT * FROM primeline_quadro_b_20261005.funcoes WHERE assinatura IN('fn_quadro_proteger_escrita()','fn_quadro_operar(text,jsonb,boolean,text)','public.fn_quadro_proteger_escrita()','public.fn_quadro_operar(text,jsonb,boolean,text)') LOOP
  EXECUTE f.definicao;EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.assinatura);
  FOR g IN SELECT * FROM aclexplode(coalesce(f.acl::aclitem[],acldefault('f',f.owner::regrole))) LOOP
   role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',g.privilege_type,f.assinatura,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
 REVOKE ALL ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
 FOR g IN SELECT * FROM primeline_quadro_b_20261005.acl_tabelas LOOP
  role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
  EXECUTE format('GRANT %s ON TABLE %s TO %s%s',g.privilege_type,g.tabela,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
 FOR g IN SELECT * FROM primeline_quadro_b_20261005.acl_colunas LOOP
  role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
  EXECUTE format('GRANT %s (%I) ON TABLE %s TO %s%s',g.privilege_type,g.attname,g.tabela,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
END $$;
-- Não apagar dados/história/revisões nem reativar a aprovação consumida.
UPDATE primeline_quadro_rollout.controlo SET estado='a',tentativa=tentativa+1,tentativa_iniciada_em=clock_timestamp(),fase_b_aplicada_em=NULL WHERE singleton;
COMMIT;
