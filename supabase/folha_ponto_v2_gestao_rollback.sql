BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF; END $$;
DO $$ BEGIN IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF; END $$;
-- Coordinate Quadro/Folha writers before any emptiness check. Fail closed on contention.
SET LOCAL lock_timeout='5s';
LOCK TABLE public.quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_gestao_historico,public.folha_vencimentos,public.folha_tarefas_reportes,public.folha_direitos_ferias,public.folha_ferias_revisoes,folha_privado.operacoes IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico) OR EXISTS(SELECT 1 FROM public.folha_vencimentos)
 OR EXISTS(SELECT 1 FROM public.folha_tarefas_reportes) OR EXISTS(SELECT 1 FROM public.folha_direitos_ferias)
 OR EXISTS(SELECT 1 FROM public.folha_ferias_revisoes)
 OR EXISTS(SELECT 1 FROM folha_privado.operacoes WHERE payload->>'contract'='gestao_v2')
 THEN RAISE EXCEPTION 'ROLLBACK_DATA_PRESENT: preservar factos; requer plano específico'; END IF;
END $$;
DROP TRIGGER trg_zz_folha_confirmacao_ausencia ON public.ausencias;
DROP TRIGGER trg_folha_anexo_doenca ON public.ausencias_anexos;
DROP TRIGGER trg_00_folha_anexo_lock ON public.ausencias_anexos;
DROP FUNCTION folha_privado.guardar_confirmacao_ausencia();
DROP FUNCTION folha_privado.guardar_anexo_doenca();
DROP FUNCTION folha_privado.prazo_he(uuid,date);
DROP FUNCTION folha_privado.adm();
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT * FROM primeline_folha_v2_backup.ausencias_constraints LOOP
  EXECUTE format('ALTER TABLE public.ausencias DROP CONSTRAINT %I',c.conname);
  EXECUTE format('ALTER TABLE public.ausencias ADD CONSTRAINT %I %s',c.conname,c.definicao);
 END LOOP;
END $$;
ALTER TABLE public.folha_he DROP COLUMN processado_em,DROP COLUMN processado_por,DROP COLUMN prazo_processamento;
-- calendar_validated_years is shared with core; keep until core rollback.
DROP TRIGGER folha_tarefa_concluida ON public.planeamento_itens;
DROP FUNCTION folha_privado.tarefa_concluida();
DROP TRIGGER trg_folha_vencimentos_ausencia ON public.ausencias;
DROP TRIGGER trg_folha_vencimentos_facto ON public.folha_registos;
DROP TRIGGER trg_folha_vencimentos_alocacao ON public.quadro_pessoal_alocacao;
DROP TRIGGER trg_folha_vencimentos_legado ON public.ponto_pessoal_obra;
DROP FUNCTION folha_privado.reconciliar_vencimentos();
DROP FUNCTION public.fn_folha_gestao_v2(text,jsonb,boolean,text);
DROP FUNCTION public.fn_folha_gestao_contexto_v2(uuid,uuid,date);
DROP FUNCTION folha_privado.he_operacional(jsonb);
DROP FUNCTION folha_privado.payroll_facts(uuid,date);
DROP TABLE public.folha_gestao_historico;
DROP TABLE public.folha_tarefas_reportes;
DROP TABLE public.folha_vencimentos;
DROP TABLE public.folha_ferias_revisoes;
DROP TABLE public.folha_direitos_ferias;
ALTER TABLE public.folha_config_empresa DROP COLUMN payroll_rules_ready;
ALTER TABLE public.folha_config_empresa DROP COLUMN official_template_hash;
COMMIT;
