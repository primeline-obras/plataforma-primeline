-- SOMENTE LEITURA. Executar e rever ANTES de autorizar backup/migration.
BEGIN READ ONLY;
SET LOCAL lock_timeout = '10s';
DO $$
BEGIN
 IF (SELECT array_agg(policyname::text ORDER BY policyname) FROM pg_policies
   WHERE schemaname='public' AND tablename='medicina_trabalho') IS DISTINCT FROM
   ARRAY['pl_admin_total','pl_medicina_encarregado_atual_select','pl_medicina_rh']::text[] THEN
  RAISE EXCEPTION 'PRECHECK: policies divergentes.';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.medicina_trabalho'::regclass
   AND attnum>0 AND NOT attisdropped AND attacl IS NOT NULL) THEN
  RAISE EXCEPTION 'PRECHECK: grants por coluna exigem revisão.';
 END IF;
 IF (SELECT count(*) FROM public.medicina_trabalho)<>35 THEN RAISE EXCEPTION 'PRECHECK: contagem diferente de 35.'; END IF;
 IF EXISTS(SELECT 1 FROM public.medicina_trabalho WHERE data_ultima_consulta IS NULL
 OR data_proxima_consulta<data_ultima_consulta) THEN RAISE EXCEPTION 'PRECHECK: datas antigas precisam revisão.'; END IF;
 IF to_regclass('public.medicina_operacoes') IS NOT NULL OR EXISTS(
 SELECT 1 FROM pg_attribute WHERE attrelid='public.medicina_trabalho'::regclass
 AND attname IN('registado_por','request_id','revisao','anulado_em','anulado_por') AND NOT attisdropped) THEN
 RAISE EXCEPTION 'PRECHECK: objetos novos já existem.'; END IF;
END $$;
SELECT count(*) AS total,
 md5(jsonb_agg(to_jsonb(m) ORDER BY id)::text) AS hash_linhas,
 count(*) FILTER(WHERE data_ultima_consulta>current_date) AS consultas_futuras,
 count(*) FILTER(WHERE data_proxima_consulta<current_date) AS vencidas,
 count(*) FILTER(WHERE data_proxima_consulta BETWEEN current_date AND current_date+30) AS a_vencer
FROM public.medicina_trabalho m;
SELECT c.data_saida IS NULL AS ativo,count(*) FILTER(WHERE m.id IS NULL) AS sem_consulta
FROM public.colaboradores c LEFT JOIN public.medicina_trabalho m ON m.colaborador_id=c.id GROUP BY 1;
SELECT tipo,estado,count(*) FROM public.alertas
WHERE tipo IN('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento') GROUP BY tipo,estado;
SELECT jsonb_agg(to_jsonb(a) ORDER BY id) AS snapshot_alertas,
 md5(coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]')::text) AS hash_alertas
FROM public.alertas a WHERE tipo IN('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento');
SELECT p.oid::regprocedure AS assinatura,pg_get_functiondef(p.oid) AS definicao,
 md5(replace(pg_get_functiondef(p.oid),chr(13),'')) AS hash
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
AND p.proname IN('fn_verificar_primeiras_consultas_medicina','fn_verificar_alertas_vencimento',
'fn_atualizar_colaborador_ciclo_vida','fn_executar_rotinas_diarias','fn_rh_guardar_interno');
SELECT * FROM pg_policies WHERE schemaname='public' AND tablename='medicina_trabalho';
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.medicina_trabalho'::regclass;
SELECT pg_get_triggerdef(oid),tgenabled FROM pg_trigger WHERE tgrelid='public.medicina_trabalho'::regclass AND NOT tgisinternal;
SELECT relacl,relrowsecurity FROM pg_class WHERE oid='public.medicina_trabalho'::regclass;
SELECT indexname,indexdef FROM pg_indexes WHERE schemaname='public' AND tablename IN('medicina_trabalho','alertas');
SELECT has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
 has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,p.oid::regprocedure AS assinatura
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
 AND p.proname IN('fn_verificar_primeiras_consultas_medicina','fn_verificar_alertas_vencimento','fn_executar_rotinas_diarias');
COMMIT;
