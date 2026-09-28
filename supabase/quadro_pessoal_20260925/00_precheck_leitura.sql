-- SOMENTE LEITURA. Antes de autorizar/aplicar 00_regras_movimentacoes.sql.
-- Não classifica, corrige, elimina ou cria dados.
WITH duplicados AS (
 SELECT colaborador_id,data,periodo,obra_id,tipo_alocacao,descricao_livre,count(*) AS quantidade
 FROM public.quadro_pessoal_alocacao
 GROUP BY colaborador_id,data,periodo,obra_id,tipo_alocacao,descricao_livre HAVING count(*)>1
), politicas_all AS (
 SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_alocacao' AND cmd='ALL'
)
SELECT current_setting('server_version') AS versao_postgresql,
 current_setting('server_version_num')::int>=150000 AS suporta_indice_nulls_not_distinct,
 to_regclass('public.quadro_pessoal_movimentos') IS NOT NULL AS historico_existente,
 to_regprocedure('public.fn_utilizador_atual_id()') IS NOT NULL AS identidade_existente,
 (SELECT count(*) FROM duplicados) AS grupos_duplicados,
 (SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]'::jsonb) FROM duplicados d) AS duplicados_a_rever,
 (SELECT coalesce(jsonb_agg(policyname),'[]'::jsonb) FROM politicas_all) AS politicas_all_a_rever,
 (SELECT jsonb_agg(jsonb_build_object('nome',policyname,'comando',cmd,'using',qual,'check',with_check))
 FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_alocacao') AS politicas_atuais,
 CASE WHEN current_setting('server_version_num')::int>=150000
 AND to_regclass('public.quadro_pessoal_movimentos') IS NOT NULL
 AND to_regprocedure('public.fn_utilizador_atual_id()') IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM duplicados) AND NOT EXISTS(SELECT 1 FROM politicas_all)
 THEN 'PRE_REQUISITOS_OK_REVER_MIGRACAO' ELSE 'BLOQUEADO_NAO_APLICAR' END AS resultado;
