BEGIN;
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN SHARE MODE;
LOCK TABLE primeline_quadro_rollout.controlo,primeline_quadro_rollout.validacoes IN SHARE MODE;
SELECT primeline_quadro_rollout.exigir_validacao();
CREATE TABLE primeline_backup.quadro_fase_b_controlo_20261001 AS TABLE primeline_quadro_rollout.controlo;
CREATE TABLE primeline_backup.quadro_fase_b_validacoes_20261001 AS TABLE primeline_quadro_rollout.validacoes;
CREATE TABLE primeline_backup.quadro_fase_b_alocacoes_20261001 AS TABLE public.quadro_pessoal_alocacao;
CREATE TABLE primeline_backup.quadro_fase_b_movimentos_20261001 AS TABLE public.quadro_pessoal_movimentos;
CREATE TABLE primeline_backup.quadro_fase_b_revisoes_20261001 AS TABLE public.quadro_dias_revisoes;
CREATE TABLE primeline_backup.quadro_fase_b_operacoes_20261001 AS TABLE public.quadro_operacoes;
CREATE TABLE primeline_backup.quadro_fase_b_funcoes_20261001 AS SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proacl::text acl,pg_get_userbyid(p.proowner) owner FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f' AND (p.proname LIKE 'fn_quadro_%' OR p.proname='fn_registar_movimento_quadro');
CREATE TABLE primeline_backup.quadro_fase_b_policies_20261001 AS SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos');
CREATE TABLE primeline_backup.quadro_fase_b_acl_tabelas_20261001 AS SELECT * FROM primeline_backup.quadro_acl_tabelas_20261001 WITH NO DATA;
INSERT INTO primeline_backup.quadro_fase_b_acl_tabelas_20261001 SELECT c.oid::regclass::text,e.* FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) e WHERE c.oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass);
CREATE TABLE primeline_backup.quadro_fase_b_acl_funcoes_20261001 AS SELECT * FROM primeline_backup.quadro_acl_funcoes_20261001 WITH NO DATA;
INSERT INTO primeline_backup.quadro_fase_b_acl_funcoes_20261001 SELECT p.oid::regprocedure::text,e.* FROM pg_proc p JOIN primeline_backup.quadro_fase_b_funcoes_20261001 b ON p.oid::regprocedure::text=b.assinatura CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) e;
CREATE TABLE primeline_backup.quadro_fase_b_colunas_20261001 AS SELECT a.attrelid::regclass::text tabela,a.attname,a.attnotnull,a.attacl,a.atttypid,pg_get_expr(d.adbin,d.adrelid) valor_default FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND a.attnum>0 AND NOT a.attisdropped;
CREATE TABLE primeline_backup.quadro_fase_b_acl_colunas_20261001 AS SELECT a.attrelid::regclass::text tabela,a.attname,e.* FROM pg_attribute a CROSS JOIN LATERAL aclexplode(a.attacl) e WHERE a.attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND a.attnum>0 AND NOT a.attisdropped;
CREATE TABLE primeline_backup.quadro_fase_b_tabelas_20261001 AS SELECT oid::regclass::text tabela,pg_get_userbyid(relowner) owner,relacl,relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass);
CREATE TABLE primeline_backup.quadro_fase_b_triggers_20261001 AS SELECT tgrelid::regclass::text tabela,tgname,tgenabled,pg_get_triggerdef(oid) definicao FROM pg_trigger WHERE tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT tgisinternal;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_backup FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
