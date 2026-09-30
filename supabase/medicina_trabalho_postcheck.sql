-- SOMENTE LEITURA, imediatamente após migration, antes de qualquer operação real.
BEGIN READ ONLY;
DO $$
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE oid IN('public.medicina_trabalho'::regclass,
 'public.medicina_operacoes'::regclass,'public.medicina_alertas_historico'::regclass,
 'public.medicina_instalacao_snapshot'::regclass) AND relrowsecurity)<>4 THEN
  RAISE EXCEPTION 'POSTCHECK: RLS incompleto.';
 END IF;
 IF has_table_privilege('anon','public.medicina_instalacao_snapshot','SELECT')
 OR has_table_privilege('authenticated','public.medicina_instalacao_snapshot','SELECT')
 OR has_table_privilege('service_role','public.medicina_instalacao_snapshot','SELECT')
 OR has_table_privilege('service_role','public.medicina_trabalho','UPDATE')
 OR has_table_privilege('service_role','public.medicina_operacoes','TRUNCATE') THEN
  RAISE EXCEPTION 'POSTCHECK: fotografia ou escrita técnica exposta.';
 END IF;
 IF (SELECT count(*) FROM public.medicina_trabalho)<>35
 OR (SELECT jsonb_agg(to_jsonb(m)-ARRAY['registado_por','request_id','revisao','anulado_em','anulado_por'] ORDER BY id)
 FROM public.medicina_trabalho m) IS DISTINCT FROM (SELECT linhas FROM public.medicina_instalacao_snapshot) THEN
 RAISE EXCEPTION 'POSTCHECK: linhas antigas divergentes.'; END IF;
 IF EXISTS(SELECT 1 FROM public.medicina_trabalho WHERE registado_por IS NOT NULL
 OR request_id IS NOT NULL OR revisao<>0 OR anulado_em IS NOT NULL OR anulado_por IS NOT NULL) THEN
 RAISE EXCEPTION 'POSTCHECK: metadados antigos preenchidos indevidamente.'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY id),'[]') FROM public.alertas a
 WHERE tipo IN('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento'))
 IS DISTINCT FROM (SELECT alertas FROM public.medicina_instalacao_snapshot) THEN
 RAISE EXCEPTION 'POSTCHECK: alertas alterados durante instalação.'; END IF;
 IF EXISTS(SELECT 1 FROM public.medicina_operacoes) OR EXISTS(SELECT 1 FROM public.medicina_alertas_historico) THEN
 RAISE EXCEPTION 'POSTCHECK: histórico deveria estar vazio após instalação.'; END IF;
 IF has_table_privilege('authenticated','public.medicina_trabalho','UPDATE')
 OR has_table_privilege('authenticated','public.medicina_trabalho','DELETE')
 OR has_table_privilege('authenticated','public.medicina_trabalho','INSERT')
 OR has_table_privilege('authenticated','public.medicina_operacoes','UPDATE')
 OR has_table_privilege('authenticated','public.medicina_operacoes','DELETE')
 OR has_function_privilege('authenticated','public.fn_medicina_reconciliar_alertas(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'POSTCHECK: privilégio indevido.'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.medicina_trabalho'::regclass
 AND tgname IN('trg_medicina_proteger','trg_medicina_admissao_historico') AND tgenabled IN('O','A'))<>2 THEN
 RAISE EXCEPTION 'POSTCHECK: triggers não ativos.'; END IF;
END $$;
SELECT count(*) AS total,
 md5(jsonb_agg(to_jsonb(m)-ARRAY['registado_por','request_id','revisao','anulado_em','anulado_por'] ORDER BY id)::text) AS hash_campos_antigos
FROM public.medicina_trabalho m;
SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('medicina_trabalho','medicina_operacoes','medicina_alertas_historico');
SELECT p.oid::regprocedure AS assinatura,pg_get_functiondef(p.oid) AS definicao FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'fn_medicina_%';
COMMIT;
-- Os testes sintéticos de produção serão preparados/confirmados apenas após autorização.
-- Não executar RPC de lançamento fora de transação explícita com ROLLBACK.
