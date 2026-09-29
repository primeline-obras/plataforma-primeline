-- Protege apenas a reatribuição de obra de evidência económica validada.
-- Não altera dados, policies, auditoria, DELETE ou Storage.
-- Aplicar como postgres, proprietário de confiança das funções da Etapa 1.
BEGIN;

CREATE FUNCTION public.fn_impedir_reatribuicao_documento_validado()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
SET row_security = off
AS $$
BEGIN
  IF NEW.obra_id IS NOT DISTINCT FROM OLD.obra_id THEN
    RETURN NEW;
  END IF;

  -- O UPDATE já bloqueia esta linha, em conflito com o FOR SHARE usado
  -- pela validação existente. VOLATILE permite uma leitura atualizada
  -- após a espera em READ COMMITTED. Snapshots fixos não são seguros aqui.
  IF current_setting('transaction_isolation') NOT IN
    ('read committed', 'read uncommitted') THEN
    RAISE EXCEPTION 'Reatribuição de documento exige uma nova transação READ COMMITTED.'
      USING ERRCODE = '40001',
        HINT = 'Anule a transação e repita a operação em READ COMMITTED.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.orcamento_versoes_fontes AS f
    JOIN public.orcamento_versoes AS v ON v.id = f.versao_id
    WHERE f.documento_obra_id = OLD.id
      AND v.estado_validacao = 'validada'
  ) THEN
    RAISE EXCEPTION 'Não é permitido alterar a obra de um documento usado por uma versão económica validada.'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

ALTER FUNCTION public.fn_impedir_reatribuicao_documento_validado() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_impedir_reatribuicao_documento_validado()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_impedir_reatribuicao_documento_validado
  BEFORE UPDATE OF obra_id ON public.documentos_obra
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_impedir_reatribuicao_documento_validado();

COMMIT;
