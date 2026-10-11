BEGIN;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
CREATE SCHEMA primeline_encarregado_final_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_encarregado_final_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_encarregado_final_backup.funcoes AS SELECT p.oid::regprocedure::text assinatura,pg_get_functiondef(p.oid) definicao,p.proacl,p.proowner,md5(p.prosrc) hash FROM pg_proc p WHERE p.oid=ANY(ARRAY['folha_privado.facts(jsonb,date)','folha_privado.local(uuid,uuid,boolean)','folha_privado.linha(uuid,uuid,date,text)','folha_privado.save(jsonb,uuid,date,uuid,boolean)','folha_privado.normal(uuid,uuid,date)','public.fn_equipa_operar_v2(text,jsonb,boolean,text)','public.fn_folha_pessoas_v2(date,uuid)','public.fn_folha_contexto_v2(date,uuid)','public.fn_folha_operar_v2(text,jsonb,boolean,text)','public.fn_listar_colegas_agenda()']::regprocedure[]);
CREATE TABLE primeline_encarregado_final_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $$ DECLARE t text; BEGIN FOR t IN SELECT unnest(ARRAY['folha_registos','folha_externos','folha_externos_dias','folha_historico','quadro_equipa_permanencias','quadro_pessoal_alocacao','quadro_pessoal_movimentos','ausencias','folha_he','folha_vencimentos']) LOOP
 EXECUTE format('INSERT INTO primeline_encarregado_final_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP; END $$;
CREATE TABLE primeline_encarregado_final_backup.privado AS SELECT 'operacoes'::text tabela,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x UNION ALL SELECT 'equipa_revisoes',coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.equipa_revisoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_encarregado_final_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'ENCARREGADO_FINAL_BACKUP_OK' AS resultado;
COMMIT;
