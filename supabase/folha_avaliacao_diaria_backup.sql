-- Backup privado lógico. Preparado apenas; não executado na produção.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF; END $$;
CREATE SCHEMA primeline_diaria_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_diaria_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_diaria_backup.funcoes AS SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proowner owner_oid,p.proacl acl FROM pg_proc p WHERE p.oid=ANY(ARRAY['folha_privado.operar_periodos(jsonb,boolean,text)','folha_privado.reconciliar_he(public.folha_registos)','folha_privado.reconciliar_dia(uuid,date,uuid,text)','folha_privado.linha(uuid,uuid,date,text)','folha_privado.normal(uuid,uuid,date)','folha_privado.payroll_facts(uuid,date)','public.fn_folha_gestao_v2(text,jsonb,boolean,text)','public.fn_folha_gestao_contexto_v2(uuid,uuid,date)','folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)','folha_privado.save(jsonb,uuid,date,uuid,boolean)']::regprocedure[]);
CREATE TABLE primeline_diaria_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY['folha_config_empresa','folha_horarios','folha_registos','folha_historico','folha_he','folha_vencimentos','folha_gestao_historico','quadro_equipa_permanencias','ausencias','quadro_pessoal_alocacao','ponto_pessoal_obra'] LOOP
 EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',t);
 EXECUTE format('INSERT INTO primeline_diaria_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP;END $$;
CREATE TABLE primeline_diaria_backup.operacoes AS TABLE folha_privado.operacoes;
CREATE TABLE primeline_diaria_backup.periodos_revisoes AS TABLE folha_privado.periodos_revisoes;
CREATE TABLE primeline_diaria_backup.catalogo AS SELECT c.oid tabela_oid,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
 (SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.policyname),'[]') FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname) policies,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'acl',a.attacl,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum),'[]') FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) colunas,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('name',k.conname,'definition',pg_get_constraintdef(k.oid)) ORDER BY k.conname),'[]') FROM pg_constraint k WHERE k.conrelid=c.oid) constraints,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgname),'[]') FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal) triggers,
 (SELECT coalesce(jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid),'[]') FROM pg_index i WHERE i.indrelid=c.oid) indices
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN('folha_config_empresa','folha_horarios','folha_registos','folha_historico','folha_he','folha_vencimentos','folha_gestao_historico','quadro_equipa_permanencias','ausencias','quadro_pessoal_alocacao','ponto_pessoal_obra');
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_diaria_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'DAILY_BACKUP_PASS' resultado;
COMMIT;
