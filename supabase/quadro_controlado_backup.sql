-- BACKUP privado proposto: aplicar só com autorização separada e após precheck revisto.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos,public.colaboradores,
 public.ausencias,public.obras,public.obra_responsaveis IN SHARE MODE;
CREATE SCHEMA IF NOT EXISTS primeline_backup;
REVOKE ALL ON SCHEMA primeline_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_backup.quadro_20261001 AS TABLE public.quadro_pessoal_alocacao;
CREATE TABLE primeline_backup.quadro_movimentos_20261001 AS TABLE public.quadro_pessoal_movimentos;
CREATE TABLE primeline_backup.quadro_colaboradores_20261001 AS TABLE public.colaboradores;
CREATE TABLE primeline_backup.quadro_ausencias_20261001 AS TABLE public.ausencias;
CREATE TABLE primeline_backup.quadro_obras_20261001 AS TABLE public.obras;
CREATE TABLE primeline_backup.quadro_responsaveis_20261001 AS TABLE public.obra_responsaveis;
CREATE TABLE primeline_backup.quadro_funcoes_20261001 AS
 SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proacl::text acl,pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer,p.proconfig search_path
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p')
 AND (p.prosrc ILIKE '%quadro%' OR p.proname LIKE 'fn_rh_%' OR p.proname IN('fn_pode_gerir_quadro','fn_quadro_minha_obra','fn_pode_consultar_quadro'));
CREATE TABLE primeline_backup.quadro_policies_20261001 AS SELECT * FROM pg_policies
 WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos');
CREATE TABLE primeline_backup.quadro_estrutura_20261001 AS
 SELECT 'table:'||relname AS tipo,relacl::text AS definicao FROM pg_class WHERE oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass)
 UNION ALL SELECT 'trigger:'||tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT tgisinternal
 UNION ALL SELECT 'constraint:'||conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass);
CREATE TABLE primeline_backup.quadro_colunas_20261001 AS
 SELECT a.attrelid::regclass::text tabela,a.attname,a.atttypid::regtype::text tipo,a.attnotnull,a.attacl,pg_get_expr(d.adbin,d.adrelid) valor_default
 FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND a.attnum>0 AND NOT a.attisdropped;
CREATE TABLE primeline_backup.quadro_tabelas_20261001 AS SELECT oid::regclass::text tabela,pg_get_userbyid(relowner) owner,relrowsecurity,relforcerowsecurity,relacl FROM pg_class WHERE oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_pessoal_rpc_permit'::regclass);
CREATE TABLE primeline_backup.quadro_acl_funcoes_20261001 AS
 SELECT p.oid::regprocedure::text assinatura,e.* FROM pg_proc p JOIN primeline_backup.quadro_funcoes_20261001 b ON p.oid::regprocedure::text=b.assinatura CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) e;
CREATE TABLE primeline_backup.quadro_acl_tabelas_20261001 AS
 SELECT c.oid::regclass::text tabela,e.* FROM pg_class c JOIN primeline_backup.quadro_tabelas_20261001 b ON c.oid::regclass::text=b.tabela CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) e;
CREATE TABLE primeline_backup.quadro_triggers_20261001 AS
 SELECT tgrelid::regclass::text tabela,tgname,tgenabled,pg_get_triggerdef(oid) definicao FROM pg_trigger WHERE tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT tgisinternal;
CREATE TABLE primeline_backup.quadro_sequencias_20261001 AS
 SELECT c.oid::regclass::text sequencia,c.relacl,c.relowner FROM pg_class c JOIN pg_depend d ON d.objid=c.oid WHERE c.relkind='S' AND d.refobjid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass);
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_backup FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.quadro_pessoal_alocacao q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_20261001 q)
 THEN RAISE EXCEPTION 'BACKUP_FAILED: cópia divergente.'; END IF;
END $$;
COMMIT;
-- Exportar as cópias para arquivo privado externo; nunca para o Git.
