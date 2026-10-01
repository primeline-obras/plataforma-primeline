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
 SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proacl::text acl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN('f','p')
 AND (p.prosrc ILIKE '%quadro%' OR p.proname LIKE 'fn_rh_%');
CREATE TABLE primeline_backup.quadro_policies_20261001 AS SELECT * FROM pg_policies
 WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos');
CREATE TABLE primeline_backup.quadro_estrutura_20261001 AS
 SELECT 'table:'||relname AS tipo,relacl::text AS definicao FROM pg_class WHERE oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass)
 UNION ALL SELECT 'trigger:'||tgname,pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid='public.quadro_pessoal_alocacao'::regclass AND NOT tgisinternal
 UNION ALL SELECT 'constraint:'||conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass);
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_backup FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.quadro_pessoal_alocacao q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_20261001 q)
 THEN RAISE EXCEPTION 'BACKUP_FAILED: cópia divergente.'; END IF;
END $$;
COMMIT;
-- Exportar as cópias para arquivo privado externo; nunca para o Git.
