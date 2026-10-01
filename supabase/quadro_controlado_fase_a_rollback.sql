-- Rollback A: preserva dados e histórico produzidos após instalação.
BEGIN;
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
SELECT primeline_quadro_rollout.exigir_privacidade();
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM primeline_quadro_rollout.controlo WHERE singleton AND estado='a') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: rollback exige estado a'; END IF; END $$;
DO $$ DECLARE f record; g record; p record; role_name text; BEGIN
 FOR f IN SELECT * FROM primeline_backup.quadro_funcoes_20261001 b WHERE (SELECT proc_row.proname FROM pg_proc proc_row WHERE proc_row.oid=b.assinatura::regprocedure) IN('fn_quadro_operar','fn_quadro_proteger_escrita','fn_registar_movimento_quadro','fn_criar_colaborador_com_alocacao','fn_rh_guardar_interno','fn_quadro_notificar_movimentacao_encarregado') LOOP
  EXECUTE f.definicao;
  EXECUTE format('ALTER FUNCTION %s OWNER TO %I',f.assinatura,f.owner);
  FOR g IN SELECT DISTINCT x.grantee FROM pg_proc pr CROSS JOIN LATERAL aclexplode(coalesce(pr.proacl,acldefault('f',pr.proowner))) x WHERE pr.oid=f.assinatura::regprocedure LOOP
   role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %s',f.assinatura,role_name);
  END LOOP;
  FOR g IN SELECT * FROM primeline_backup.quadro_acl_funcoes_20261001 WHERE assinatura=f.assinatura LOOP
   role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
   EXECUTE format('GRANT %s ON FUNCTION %s TO %s%s',g.privilege_type,f.assinatura,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
  END LOOP;
 END LOOP;
 FOR p IN SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP EXECUTE format('DROP POLICY %I ON public.%I',p.policyname,p.tablename); END LOOP;
 FOR p IN SELECT * FROM primeline_backup.quadro_policies_20261001 LOOP
  EXECUTE format('CREATE POLICY %I ON public.%I AS %s FOR %s TO %s%s%s',p.policyname,p.tablename,p.permissive,p.cmd,(SELECT string_agg(quote_ident(r),',') FROM unnest(p.roles) r),CASE WHEN p.qual IS NULL THEN '' ELSE ' USING ('||p.qual||')' END,CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK ('||p.with_check||')' END);
 END LOOP;
 REVOKE ALL ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
 FOR g IN SELECT * FROM primeline_backup.quadro_acl_tabelas_20261001 WHERE tabela IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos','public.quadro_pessoal_alocacao','public.quadro_pessoal_movimentos') LOOP
  role_name:=CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee)) END;
  EXECUTE format('GRANT %s ON TABLE %s TO %s%s',g.privilege_type,g.tabela,role_name,CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
 END LOOP;
END $$;
DROP TRIGGER IF EXISTS trg_00_quadro_lock_escrita_v1 ON public.quadro_pessoal_alocacao;
REVOKE ALL ON FUNCTION public.fn_quadro_operar_v1(text,jsonb,boolean,text),public.fn_quadro_contexto_v1(date,date) FROM PUBLIC,anon,authenticated,service_role;
-- Nova UI deve ser retirada/recarregada no cliente compatível. Tabelas privadas e colunas históricas ficam preservadas para reconciliação.
-- Controlo de rollout não é RPC pública; owner/ACL/RLS privados obrigatórios.
SELECT primeline_quadro_rollout.exigir_privacidade();
UPDATE primeline_quadro_rollout.validacoes SET invalidada_em=clock_timestamp()
WHERE invalidada_em IS NULL;
UPDATE primeline_quadro_rollout.controlo SET estado='a_rollback',tentativa=tentativa+1,tentativa_iniciada_em=clock_timestamp(),fase_b_aplicada_em=NULL WHERE singleton;
COMMIT;
