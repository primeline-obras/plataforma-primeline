-- Rollback apenas antes de existirem versões/fontes; nunca apaga evidência.
BEGIN;
LOCK TABLE public.orcamento_versoes, public.orcamento_versoes_fontes IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.orcamento_versoes)
    OR EXISTS (SELECT 1 FROM public.orcamento_versoes_fontes) THEN
    RAISE EXCEPTION 'Rollback recusado: existem versões/fontes. Preservar dados e rever a recuperação.';
  END IF;
END;
$$;
DROP TABLE public.orcamento_versoes_fontes;
DROP TABLE public.orcamento_versoes;
DROP FUNCTION public.fn_guardar_integridade_orcamento_fonte();
DROP FUNCTION public.fn_guardar_integridade_orcamento_versao();
-- O log de auditoria e todos os objetos legados permanecem intactos.
COMMIT;
