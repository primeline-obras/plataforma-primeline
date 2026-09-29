-- Remove apenas esta proteção. Não remove fontes, versões ou auditoria.
-- Não aplicar com versões validadas: voltaria a expor evidência existente.
BEGIN;

LOCK TABLE public.documentos_obra, public.orcamento_versoes,
  public.orcamento_versoes_fontes IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.orcamento_versoes_fontes AS f
    JOIN public.orcamento_versoes AS v ON v.id = f.versao_id
    WHERE f.documento_obra_id IS NOT NULL
      AND v.estado_validacao = 'validada'
  ) THEN
    RAISE EXCEPTION 'Rollback recusado: existem documentos usados por versões validadas.';
  END IF;
END;
$$;

DROP TRIGGER trg_impedir_reatribuicao_documento_validado ON public.documentos_obra;
DROP FUNCTION public.fn_impedir_reatribuicao_documento_validado();

COMMIT;
