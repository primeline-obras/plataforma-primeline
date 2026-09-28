-- Quadro de Pessoal: apenas 28/09 a 02/10/2026, dia_inteiro; 95 posições.
-- Fonte: pré-visualização (18).csv, retiradas SOMENTE as 5 posições de Wanderson.
-- Manoel excluído. João Afonso -> Pedreiro. Nenhuma atualização de flags.
-- Não executar automaticamente. Sem semanas futuras; sem alterações de responsabilidades.
-- APENAS LEITURA. Executar imediatamente depois do SQL 02, antes de ajustes manuais.
WITH atual AS (SELECT jsonb_build_object(
 'colaboradores',coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM public.colaboradores c WHERE c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb),
 'alocacoes',coalesce((SELECT jsonb_agg(to_jsonb(q) ORDER BY q.id) FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id WHERE c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb),
 'ausencias',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb),
 'obras',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.id) FROM public.obras o WHERE o.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb),
 'responsabilidades',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text) FROM public.obra_responsaveis r JOIN public.obras o ON o.id=r.obra_id WHERE o.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb),
 'movimentos',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.id) FROM public.quadro_pessoal_movimentos h WHERE h.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'),'[]'::jsonb)
 ) AS dados), b AS (SELECT * FROM public.quadro_pessoal_20260928_v3_backup WHERE lote='quadro_20260928_20261002_v3'),
checklist AS (SELECT b.*,a.dados AS atual,
 (SELECT count(*) FROM jsonb_array_elements(b.manifesto) m WHERE
 (SELECT count(*) FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=(m->>'colaborador_id')::uuid
 AND q.obra_id=(m->>'obra_id')::uuid AND q.data=(m->>'data')::date AND q.periodo=m->>'periodo' AND q.tipo_alocacao='obra' AND q.descricao_livre IS NULL)=1) AS posicoes_confirmadas
 FROM b CROSS JOIN atual a)
SELECT lote,posicoes_confirmadas,jsonb_array_length(manifesto) AS posicoes_previstas,
 (SELECT funcao='Pedreiro' FROM public.colaboradores WHERE id='81a195a3-d75f-4504-87a7-4060078b9f9e') AS joao_pedreiro,
 atual->'ausencias'=antes->'ausencias' AS ferias_preservadas,
 atual->'responsabilidades'=antes->'responsabilidades' AS responsabilidades_preservadas,
 NOT EXISTS(SELECT 1 FROM jsonb_array_elements(manifesto) m WHERE m->>'colaborador_id'='ae4df908-5847-4fcd-bf14-f0fbb441cb74') AS wanderson_fora_manifesto,
 NOT EXISTS(SELECT 1 FROM jsonb_array_elements(antes->'alocacoes') x WHERE NOT(atual->'alocacoes' @> jsonb_build_array(x))) AS alocacoes_anteriores_preservadas,
 NOT EXISTS(SELECT 1 FROM jsonb_array_elements(antes->'colaboradores') x JOIN jsonb_array_elements(atual->'colaboradores') y ON x->>'id'=y->>'id'
 WHERE x->'permite_multiplas_obras' IS DISTINCT FROM y->'permite_multiplas_obras') AS flags_preservadas,
 atual=depois AS sem_divergencias,
 CASE WHEN posicoes_confirmadas=95 AND jsonb_array_length(manifesto)=95 AND atual=depois AND concluido_em IS NOT NULL
 THEN 'CONCLUIDO' ELSE 'REVER_NAO_REPETIR_AUTOMATICAMENTE' END AS resultado
FROM checklist;
