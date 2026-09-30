-- BACKUP PROPOSTO: não executado nesta etapa. Exige autorização separada.
-- Owner SQL Editor, após precheck aprovado. Schema privado, fora da API.
BEGIN;
SET LOCAL lock_timeout = '10s';
LOCK TABLE public.colaboradores,public.medicina_trabalho,public.alertas IN SHARE MODE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.medicina_trabalho)<>35 THEN RAISE EXCEPTION 'BACKUP: fotografia divergente.'; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS primeline_backup;
REVOKE ALL ON SCHEMA primeline_backup FROM PUBLIC,anon,authenticated;
CREATE TABLE primeline_backup.medicina_20260930 AS TABLE public.medicina_trabalho;
CREATE TABLE primeline_backup.medicina_alertas_20260930 AS SELECT * FROM public.alertas
 WHERE tipo IN('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento');
CREATE TABLE primeline_backup.medicina_funcoes_20260930 AS
 SELECT p.oid::regprocedure::text AS assinatura,pg_get_functiondef(p.oid) AS definicao,p.proacl::text AS acl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND p.proname IN('fn_verificar_primeiras_consultas_medicina','fn_verificar_alertas_vencimento',
 'fn_atualizar_colaborador_ciclo_vida','fn_executar_rotinas_diarias','fn_rh_guardar_interno');
CREATE TABLE primeline_backup.medicina_policies_20260930 AS
 SELECT * FROM pg_policies WHERE schemaname='public' AND tablename='medicina_trabalho';
CREATE TABLE primeline_backup.medicina_estrutura_20260930 AS
 SELECT 'table_acl' AS tipo,relacl::text AS definicao FROM pg_class WHERE oid='public.medicina_trabalho'::regclass
 UNION ALL SELECT 'column_acl:'||attname,attacl::text FROM pg_attribute
 WHERE attrelid='public.medicina_trabalho'::regclass AND attnum>0 AND NOT attisdropped
 UNION ALL SELECT 'constraint:'||conname,pg_get_constraintdef(oid) FROM pg_constraint
 WHERE conrelid='public.medicina_trabalho'::regclass
 UNION ALL SELECT 'trigger:'||tgname,pg_get_triggerdef(oid) FROM pg_trigger
 WHERE tgrelid='public.medicina_trabalho'::regclass AND NOT tgisinternal
 UNION ALL SELECT 'index:'||indexname,indexdef FROM pg_indexes
 WHERE schemaname='public' AND tablename='medicina_trabalho';
REVOKE ALL ON SCHEMA primeline_backup FROM service_role;
REVOKE ALL ON primeline_backup.medicina_20260930,primeline_backup.medicina_alertas_20260930,
 primeline_backup.medicina_funcoes_20260930,primeline_backup.medicina_policies_20260930,
 primeline_backup.medicina_estrutura_20260930 FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN
 IF (SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.medicina_trabalho m) IS DISTINCT FROM
 (SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM primeline_backup.medicina_20260930 m) THEN
 RAISE EXCEPTION 'BACKUP: cópia não corresponde à origem.'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM public.alertas a
 WHERE tipo IN('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento')) IS DISTINCT FROM
 (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM primeline_backup.medicina_alertas_20260930 a) THEN
 RAISE EXCEPTION 'BACKUP: alertas divergentes.'; END IF;
END $$;
SELECT count(*) AS linhas,md5(jsonb_agg(to_jsonb(m) ORDER BY id)::text) AS hash
 FROM primeline_backup.medicina_20260930 m;
COMMIT;
-- Exportar também estas duas tabelas de dados e as definições para arquivo privado externo.
-- Não versionar/exportar dados pessoais para o Git.
