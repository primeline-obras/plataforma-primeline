-- POSTCHECK somente leitura, imediatamente após instalação e ANTES de utilização.
DO $$ BEGIN
 IF (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.quadro_pessoal_alocacao q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_20261001 q)
 OR (SELECT coalesce(jsonb_agg(to_jsonb(q)-'origem_operacao'-'request_id' ORDER BY id),'[]') FROM public.quadro_pessoal_movimentos q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_movimentos_20261001 q)
 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: alocações/histórico alterados.'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM public.colaboradores c)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM primeline_backup.quadro_colaboradores_20261001 c)
 OR (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM public.ausencias c)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY id),'[]') FROM primeline_backup.quadro_ausencias_20261001 c)
 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: colaboradores/ausências alterados.'; END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM public.obras x) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM primeline_backup.quadro_obras_20261001 x)
 OR (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM public.obra_responsaveis x) IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM primeline_backup.quadro_responsaveis_20261001 x)
 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: obras/responsáveis alterados.'; END IF;
 IF EXISTS(SELECT 1 FROM public.quadro_operacoes) OR EXISTS(SELECT 1 FROM public.quadro_dias_revisoes)
 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: operações inesperadas.'; END IF;
 IF has_table_privilege('authenticated','public.quadro_pessoal_alocacao','INSERT')
 OR has_table_privilege('authenticated','public.quadro_pessoal_alocacao','UPDATE')
 OR has_table_privilege('authenticated','public.quadro_pessoal_alocacao','DELETE')
 OR has_function_privilege('authenticated','public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'POSTCHECK_FAILED: escrita pública indevida.'; END IF;
END $$;
SELECT (SELECT count(*) FROM public.quadro_pessoal_alocacao) alocacoes,
 (SELECT count(*) FROM public.quadro_pessoal_movimentos) movimentos,
 (SELECT count(*) FROM public.quadro_operacoes) operacoes;
SELECT a.id,b.id FROM public.quadro_pessoal_alocacao a JOIN public.quadro_pessoal_alocacao b
 ON a.id<b.id AND a.colaborador_id=b.colaborador_id AND a.data=b.data
WHERE a.periodo='dia_inteiro' OR b.periodo='dia_inteiro' OR a.periodo=b.periodo;
SELECT q.id,a.id FROM public.quadro_pessoal_alocacao q JOIN public.ausencias a
 ON a.colaborador_id=q.colaborador_id AND a.data=q.data;
