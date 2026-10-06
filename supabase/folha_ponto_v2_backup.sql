-- Executar futuramente só após precheck REAL aprovado e autorização separada.
BEGIN;
SET LOCAL lock_timeout='10s';
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF to_regclass('public.folha_registos') IS NOT NULL THEN RAISE EXCEPTION 'FOLHA_V2_ALREADY_INSTALLED'; END IF;
END $$;
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos,public.ponto_pessoal_obra,public.ausencias,public.colaboradores,public.horas_extraordinarias,public.planeamento_itens,public.alertas IN SHARE MODE;
CREATE SCHEMA primeline_folha_v2_backup;
REVOKE ALL ON SCHEMA primeline_folha_v2_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_folha_v2_backup.alocacoes AS TABLE public.quadro_pessoal_alocacao;
CREATE TABLE primeline_folha_v2_backup.movimentos AS TABLE public.quadro_pessoal_movimentos;
CREATE TABLE primeline_folha_v2_backup.ponto AS TABLE public.ponto_pessoal_obra;
CREATE TABLE primeline_folha_v2_backup.ausencias AS TABLE public.ausencias;
CREATE TABLE primeline_folha_v2_backup.colaboradores AS TABLE public.colaboradores;
CREATE TABLE primeline_folha_v2_backup.he AS TABLE public.horas_extraordinarias;
CREATE TABLE primeline_folha_v2_backup.planeamento AS TABLE public.planeamento_itens;
CREATE TABLE primeline_folha_v2_backup.alertas AS TABLE public.alertas;
CREATE TABLE primeline_folha_v2_backup.ausencias_constraints AS SELECT conname,pg_get_constraintdef(oid) definicao FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND contype='c';
CREATE TABLE primeline_folha_v2_backup.anexos AS TABLE public.ausencias_anexos;
CREATE TABLE primeline_folha_v2_backup.funcoes AS SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proacl::text acl,pg_get_userbyid(p.proowner) owner FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f';
CREATE TABLE primeline_folha_v2_backup.policies AS SELECT * FROM pg_policies WHERE schemaname='public';
CREATE TABLE primeline_folha_v2_backup.triggers AS SELECT t.tgrelid::regclass::text tabela,t.tgname nome,t.tgenabled ativo,pg_get_triggerdef(t.oid) definicao FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal;
CREATE TABLE primeline_folha_v2_backup.estrutura AS SELECT c.oid::regclass::text tabela,c.relacl,c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) owner,
 (SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl::text,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) colunas
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN('r','p');
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_folha_v2_backup FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
