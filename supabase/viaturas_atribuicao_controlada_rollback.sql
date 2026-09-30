-- Rollback estrutural seguro: recusa eliminar histórico ou revisões já utilizadas.
-- Não reverte responsáveis nem alertas; não usar CASCADE.
BEGIN;
LOCK TABLE public.viaturas IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.colaboradores IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.viaturas_atribuicoes_historico IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.viaturas_atribuicoes_historico)
     OR EXISTS (SELECT 1 FROM public.viaturas WHERE atribuicao_revisao <> 0) THEN
    RAISE EXCEPTION 'ROLLBACK_BLOCKED: existem atribuições registadas; preservar histórico e preparar reversão específica.';
  END IF;
END;
$$;
DROP TRIGGER trg_impedir_saida_colaborador_com_viaturas ON public.colaboradores;
DROP FUNCTION public.fn_impedir_saida_colaborador_com_viaturas();
DROP TRIGGER trg_proteger_atribuicao_viatura ON public.viaturas;
DROP FUNCTION public.fn_alterar_responsavel_viatura(integer,uuid,uuid,integer,uuid,text);
DROP TABLE public.viaturas_atribuicoes_historico;
DROP FUNCTION public.fn_proteger_historico_atribuicao_viatura();
DROP FUNCTION public.fn_proteger_atribuicao_viatura();
ALTER TABLE public.viaturas DROP COLUMN atribuicao_revisao;
COMMIT;
