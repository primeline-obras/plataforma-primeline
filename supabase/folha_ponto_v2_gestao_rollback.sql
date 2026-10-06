BEGIN;
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico) OR EXISTS(SELECT 1 FROM public.folha_vencimentos)
 OR EXISTS(SELECT 1 FROM public.folha_tarefas_reportes) OR EXISTS(SELECT 1 FROM public.folha_direitos_ferias)
 THEN RAISE EXCEPTION 'ROLLBACK_DATA_PRESENT: preservar factos; requer plano específico'; END IF;
END $$;
DROP TRIGGER folha_tarefa_concluida ON public.planeamento_itens;
DROP FUNCTION folha_privado.tarefa_concluida();
DROP TRIGGER trg_folha_vencimentos_ausencia ON public.ausencias;
DROP TRIGGER trg_folha_vencimentos_facto ON public.folha_registos;
DROP TRIGGER trg_folha_vencimentos_alocacao ON public.quadro_pessoal_alocacao;
DROP TRIGGER trg_folha_vencimentos_legado ON public.ponto_pessoal_obra;
DROP FUNCTION folha_privado.reconciliar_vencimentos();
DROP FUNCTION public.fn_folha_gestao_v2(text,jsonb,boolean,text);
DROP FUNCTION public.fn_folha_gestao_contexto_v2(uuid,uuid,date);
DROP FUNCTION folha_privado.payroll_facts(uuid,date);
DROP TABLE public.folha_gestao_historico;
DROP TABLE public.folha_tarefas_reportes;
DROP TABLE public.folha_vencimentos;
DROP TABLE public.folha_ferias_revisoes;
DROP TABLE public.folha_direitos_ferias;
ALTER TABLE public.folha_config_empresa DROP COLUMN payroll_rules_ready;
ALTER TABLE public.folha_config_empresa DROP COLUMN official_template_hash;
COMMIT;
