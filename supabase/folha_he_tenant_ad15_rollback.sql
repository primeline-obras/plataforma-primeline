-- Manual only. Recuses drift/use since backup; never overwrite operational data.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_registos,public.folha_he,public.folha_vencimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $function$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex')<>'e5dc4c1c3aea0720fcf142e4d52121c40e61d0b1308f87a81e23f5eaf66f2fef' THEN RAISE EXCEPTION 'AD15_FIXED_FUNCTION_DRIFT'; END IF;
END $function$;
DO $data$ DECLARE r record; rows_now jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad15_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad15_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD15_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad15_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD15_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad15_backup.operacoes) THEN RAISE EXCEPTION 'AD15_OPERATIONS_DRIFT'; END IF;
END $data$;
DO $restore$ DECLARE r record; BEGIN
 SELECT * INTO STRICT r FROM primeline_ad15_backup.funcao;
 EXECUTE r.definicao;
END $restore$;
DO $gate$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regprocedure('public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'AD15_DAILY_PACKAGE_REQUIRED'; END IF;
 IF encode(sha256(convert_to(btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),E' \n\t'),'UTF8')),'hex')<>'189eb93caeea512629b5823403657032ddabab49358d9b66901caaf244d357fb' THEN RAISE EXCEPTION 'AD15_BASELINE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico h LEFT JOIN public.utilizadores u ON u.id=h.ator_id LEFT JOIN public.obras o ON o.id=h.obra_id LEFT JOIN public.folha_avaliacoes_diarias a ON a.id=h.entidade_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE h.action IN('daily_he_validate','daily_he_disregard','daily_reference_correct') AND (u.empresa_id IS DISTINCT FROM h.empresa_id OR a.empresa_id IS DISTINCT FROM h.empresa_id OR c.empresa_id IS DISTINCT FROM h.empresa_id OR (h.obra_id IS NOT NULL AND (o.empresa_id IS DISTINCT FROM h.empresa_id OR h.action IN('daily_he_validate','daily_he_disregard'))))) THEN RAISE EXCEPTION 'AD15_HISTORICAL_CONTEXT_REQUIRES_RECONCILIATION'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_gestao_historico'::regclass) AND NOT relrowsecurity) OR has_table_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE,DELETE') OR has_any_column_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE') OR has_any_column_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE') THEN RAISE EXCEPTION 'AD15_DIRECT_WRITER_EXPOSED'; END IF;
END $gate$;
SELECT 'AD15_ROLLBACK_OK' resultado;
COMMIT;
