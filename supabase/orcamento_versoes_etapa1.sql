-- Etapa 1: estrutura documental isolada; sem backfill nem alterações ao legado.
-- Não aplicar antes de revisão. Storage imutável é uma tarefa separada.
BEGIN;

CREATE TABLE public.orcamento_versoes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  obra_id uuid NOT NULL REFERENCES public.obras(id) ON DELETE RESTRICT,
  versao_anterior_id uuid REFERENCES public.orcamento_versoes(id) ON DELETE RESTRICT,
  numero_versao integer NOT NULL CHECK (numero_versao > 0),
  rotulo text NOT NULL CHECK (btrim(rotulo) <> ''),
  natureza text NOT NULL CHECK (natureza IN ('original_documental', 'revisao', 'referencia_legada')),
  estado_validacao text NOT NULL CHECK (estado_validacao IN ('rascunho', 'em_validacao', 'validada', 'rejeitada')),
  estado_reconciliacao text NOT NULL CHECK (estado_reconciliacao IN ('nao_avaliada', 'pendente', 'reconciliada')),
  pendencias jsonb,
  manifesto jsonb,
  manifesto_hash text CHECK (manifesto_hash ~ '^[0-9a-f]{64}$'),
  criado_por uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
  criado_em timestamptz NOT NULL DEFAULT now(),
  validado_por uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
  validado_em timestamptz,
  motivo_revisao text,
  UNIQUE (obra_id, numero_versao),
  CHECK (versao_anterior_id IS DISTINCT FROM id),
  CONSTRAINT orcamento_versoes_validacao_completa CHECK (
    estado_validacao <> 'validada' OR (
      validado_por IS NOT NULL AND validado_em IS NOT NULL
      AND manifesto IS NOT NULL AND jsonb_typeof(manifesto) = 'object'
      AND manifesto_hash IS NOT NULL
    )
  )
);

CREATE TABLE public.orcamento_versoes_fontes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  versao_id uuid NOT NULL REFERENCES public.orcamento_versoes(id) ON DELETE RESTRICT,
  documento_obra_id uuid REFERENCES public.documentos_obra(id) ON DELETE RESTRICT,
  papel_fonte text NOT NULL CHECK (btrim(papel_fonte) <> ''),
  nome_original text NOT NULL CHECK (btrim(nome_original) <> ''),
  mime_type text,
  tamanho_bytes bigint CHECK (tamanho_bytes >= 0),
  bucket text NOT NULL CHECK (btrim(bucket) <> ''),
  object_key text NOT NULL CHECK (btrim(object_key) <> ''),
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  folha text,
  intervalo_origem text,
  metadados_extracao jsonb,
  versao_leitor text,
  associado_por uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
  associado_em timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX orcamento_versoes_anterior_idx ON public.orcamento_versoes(versao_anterior_id);
CREATE INDEX orcamento_versoes_fontes_documento_idx ON public.orcamento_versoes_fontes(documento_obra_id);
-- NULL e vazio representam a mesma localização não especificada.
CREATE UNIQUE INDEX orcamento_versoes_fontes_local_unico
  ON public.orcamento_versoes_fontes
  (versao_id, bucket, object_key, papel_fonte, coalesce(folha, ''), coalesce(intervalo_origem, ''));

CREATE FUNCTION public.fn_guardar_integridade_orcamento_versao()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_anterior public.orcamento_versoes%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    IF OLD.estado_validacao = 'validada' THEN
      RAISE EXCEPTION 'Versão validada é imutável; crie uma revisão.' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF ROW(NEW.id, NEW.obra_id, NEW.numero_versao, NEW.versao_anterior_id)
      IS DISTINCT FROM ROW(OLD.id, OLD.obra_id, OLD.numero_versao, OLD.versao_anterior_id) THEN
      RAISE EXCEPTION 'Identidade e linhagem da versão são imutáveis.' USING ERRCODE = '23514';
    END IF;
  END IF;
  IF NEW.versao_anterior_id IS NOT NULL THEN
    SELECT * INTO v_anterior FROM public.orcamento_versoes
      WHERE id = NEW.versao_anterior_id FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Versão anterior inexistente.' USING ERRCODE = '23503';
    END IF;
    IF v_anterior.obra_id <> NEW.obra_id OR v_anterior.numero_versao >= NEW.numero_versao THEN
      RAISE EXCEPTION 'Versão anterior deve ser da mesma obra e ter número menor.' USING ERRCODE = '23514';
    END IF;
  END IF;
  IF NEW.estado_validacao = 'validada' THEN
    IF NOT EXISTS (SELECT 1 FROM public.orcamento_versoes_fontes WHERE versao_id = NEW.id) THEN
      RAISE EXCEPTION 'Validação exige pelo menos uma fonte documental.' USING ERRCODE = '23514';
    END IF;
    -- Revalidar a estrutura, mesmo se constraints tiverem sido removidas antes.
    IF EXISTS (
      SELECT 1 FROM public.orcamento_versoes_fontes f WHERE f.versao_id = NEW.id
        AND (f.id IS NOT NULL AND btrim(f.papel_fonte) <> ''
          AND btrim(f.nome_original) <> '' AND btrim(f.bucket) <> ''
          AND btrim(f.object_key) <> '' AND f.sha256 ~ '^[0-9a-f]{64}$'
          AND (f.tamanho_bytes IS NULL OR f.tamanho_bytes >= 0)
          AND f.associado_em IS NOT NULL) IS NOT TRUE
    ) THEN
      RAISE EXCEPTION 'Fonte documental estruturalmente inválida.' USING ERRCODE = '23514';
    END IF;
    -- Contrato: SHA-256 dos bytes UTF-8 de manifesto::text emitido pelo PostgreSQL.
    -- Não é canonicalização JSON interoperável; não normaliza escalas numéricas.
    IF NEW.manifesto_hash IS DISTINCT FROM
      pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(NEW.manifesto::text, 'UTF8')), 'hex') THEN
      RAISE EXCEPTION 'Hash não corresponde ao manifesto serializado pelo PostgreSQL.' USING ERRCODE = '23514';
    END IF;
    -- Revalidar referências documentais antes de congelar a versão.
    PERFORM d.id FROM public.documentos_obra d
      JOIN public.orcamento_versoes_fontes f ON f.documento_obra_id = d.id
      WHERE f.versao_id = NEW.id FOR SHARE OF d;
    IF EXISTS (
      SELECT 1 FROM public.orcamento_versoes_fontes f
      JOIN public.documentos_obra d ON d.id = f.documento_obra_id
      WHERE f.versao_id = NEW.id AND d.obra_id IS DISTINCT FROM NEW.obra_id
    ) THEN
      RAISE EXCEPTION 'Documento de outra obra na versão.' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.fn_guardar_integridade_orcamento_fonte()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_versao public.orcamento_versoes%ROWTYPE;
  v_obra_documento uuid;
  v_versao_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' AND ROW(NEW.id, NEW.versao_id) IS DISTINCT FROM ROW(OLD.id, OLD.versao_id) THEN
    RAISE EXCEPTION 'Identidade e versão da fonte são imutáveis.' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN v_versao_id := OLD.versao_id;
  ELSE v_versao_id := NEW.versao_id; END IF;
  -- Serializa mutações de fontes com a validação da respetiva versão.
  SELECT * INTO v_versao FROM public.orcamento_versoes WHERE id = v_versao_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Versão da fonte inexistente.' USING ERRCODE = '23503';
  END IF;
  IF v_versao.estado_validacao = 'validada' THEN
    RAISE EXCEPTION 'Fontes de versão validada são imutáveis.' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NEW.documento_obra_id IS NOT NULL THEN
    SELECT obra_id INTO v_obra_documento FROM public.documentos_obra
      WHERE id = NEW.documento_obra_id FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Documento inexistente.' USING ERRCODE = '23503';
    END IF;
    IF v_obra_documento IS DISTINCT FROM v_versao.obra_id THEN
      RAISE EXCEPTION 'Documento pertence a outra obra.' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_guardar_integridade_orcamento_versao() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_guardar_integridade_orcamento_fonte() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_integridade_orcamento_versao
  BEFORE INSERT OR UPDATE OR DELETE ON public.orcamento_versoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_guardar_integridade_orcamento_versao();
CREATE TRIGGER trg_integridade_orcamento_fonte
  BEFORE INSERT OR UPDATE OR DELETE ON public.orcamento_versoes_fontes
  FOR EACH ROW EXECUTE FUNCTION public.fn_guardar_integridade_orcamento_fonte();
CREATE TRIGGER trg_auditoria
  AFTER INSERT OR UPDATE OR DELETE ON public.orcamento_versoes
  FOR EACH ROW EXECUTE FUNCTION public.fn_registar_log_auditoria('id');
CREATE TRIGGER trg_auditoria
  AFTER INSERT OR UPDATE OR DELETE ON public.orcamento_versoes_fontes
  FOR EACH ROW EXECUTE FUNCTION public.fn_registar_log_auditoria('id');

ALTER TABLE public.orcamento_versoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orcamento_versoes_fontes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.orcamento_versoes, public.orcamento_versoes_fontes FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.orcamento_versoes, public.orcamento_versoes_fontes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.orcamento_versoes, public.orcamento_versoes_fontes TO service_role;

CREATE POLICY orcamento_versoes_select ON public.orcamento_versoes
  FOR SELECT TO authenticated
  USING (public.fn_pode_ver_obra(obra_id) OR public.fn_e_admin());
CREATE POLICY orcamento_versoes_fontes_select ON public.orcamento_versoes_fontes
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.orcamento_versoes v WHERE v.id = versao_id
      AND (public.fn_pode_ver_obra(v.obra_id) OR public.fn_e_admin())
  ));

COMMIT;
