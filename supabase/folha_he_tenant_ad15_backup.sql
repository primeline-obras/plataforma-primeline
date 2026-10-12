-- Specific private backup. No business rows modified.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_registos,public.folha_he,public.folha_vencimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $gate$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regprocedure('public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'AD15_DAILY_PACKAGE_REQUIRED'; END IF;
 IF encode(sha256(convert_to(btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),E' \n\t'),'UTF8')),'hex')<>'189eb93caeea512629b5823403657032ddabab49358d9b66901caaf244d357fb' THEN RAISE EXCEPTION 'AD15_BASELINE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico h LEFT JOIN public.utilizadores u ON u.id=h.ator_id LEFT JOIN public.obras o ON o.id=h.obra_id LEFT JOIN public.folha_avaliacoes_diarias a ON a.id=h.entidade_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE h.action IN('daily_he_validate','daily_he_disregard','daily_reference_correct') AND (u.empresa_id IS DISTINCT FROM h.empresa_id OR a.empresa_id IS DISTINCT FROM h.empresa_id OR c.empresa_id IS DISTINCT FROM h.empresa_id OR (h.obra_id IS NOT NULL AND (o.empresa_id IS DISTINCT FROM h.empresa_id OR h.action IN('daily_he_validate','daily_he_disregard'))))) THEN RAISE EXCEPTION 'AD15_HISTORICAL_CONTEXT_REQUIRES_RECONCILIATION'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_gestao_historico'::regclass) AND NOT relrowsecurity) OR has_table_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE,DELETE') OR has_any_column_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE') OR has_any_column_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE') THEN RAISE EXCEPTION 'AD15_DIRECT_WRITER_EXPOSED'; END IF;
END $gate$;
CREATE SCHEMA primeline_ad15_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad15_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad15_backup.funcao AS SELECT pg_get_functiondef(p.oid) definicao,p.prosrc,p.proowner,p.proacl,p.proconfig,p.prosecdef FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure;
CREATE TABLE primeline_ad15_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['folha_avaliacoes_diarias','folha_gestao_historico','folha_horarios','folha_horarios_versoes','folha_config_empresa','folha_registos','folha_he','folha_vencimentos'] LOOP
 EXECUTE format('INSERT INTO primeline_ad15_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP; END $snapshot$;
CREATE TABLE primeline_ad15_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad15_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD15_BACKUP_OK' resultado;
COMMIT;
