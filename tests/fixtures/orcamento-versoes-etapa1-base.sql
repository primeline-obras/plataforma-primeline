-- Base sintética local. Contratos das dependências confirmados no preflight.
-- Não é um backup da produção; IDs e autenticação são exclusivos dos testes.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
-- Reproduzir grants automáticos permissivos: a migration deve revogá-los.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
CREATE TABLE public.obras(id uuid PRIMARY KEY);
CREATE TABLE public.utilizadores(id uuid PRIMARY KEY);
CREATE TABLE public.fases(id uuid PRIMARY KEY, obra_id uuid REFERENCES public.obras);
CREATE TABLE public.documentos_obra(
  id uuid PRIMARY KEY, obra_id uuid REFERENCES public.obras,
  nome_arquivo text, arquivo_url text
);
CREATE TABLE public.itens_orcamento(
  id uuid PRIMARY KEY, fase_id uuid NOT NULL REFERENCES public.fases,
  numero_artigo text NOT NULL, descricao text NOT NULL,
  venda_prevista numeric(14,2) NOT NULL DEFAULT 0,
  custo_total_estimado numeric(14,2), estado_item text NOT NULL DEFAULT 'ativo',
  considerar_previsao_futura boolean NOT NULL DEFAULT true,
  criado_em timestamptz NOT NULL DEFAULT now(), UNIQUE(fase_id, numero_artigo)
);
CREATE TABLE public.orcamento_fases(
  id uuid PRIMARY KEY, obra_id uuid NOT NULL REFERENCES public.obras ON DELETE CASCADE,
  fase_id uuid NOT NULL UNIQUE REFERENCES public.fases ON DELETE CASCADE,
  venda_prevista numeric NOT NULL DEFAULT 0, custo_total_estimado numeric NOT NULL DEFAULT 0,
  nome_ficheiro_origem text, importado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.contratos(
  id uuid PRIMARY KEY, obra_id uuid NOT NULL UNIQUE REFERENCES public.obras,
  venda_contratual_inicial numeric(14,2), custo_direto_inicial numeric(14,2),
  venda_contratual_efetiva numeric(14,2), custo_direto_efetivo numeric(14,2)
);
CREATE TABLE public.planeamento_itens(
  id uuid PRIMARY KEY, item_orcamento_id uuid REFERENCES public.itens_orcamento ON DELETE SET NULL
);
CREATE TABLE public.log_auditoria(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tabela_afetada text NOT NULL,
  registo_id uuid NOT NULL, campo text, valor_anterior text, valor_novo text,
  utilizador_id uuid REFERENCES public.utilizadores, criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION public.fn_utilizador_atual_id() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('test.utilizador', true), '')::uuid $$;
CREATE FUNCTION public.fn_e_admin() RETURNS boolean LANGUAGE sql STABLE AS
  $$ SELECT coalesce(current_setting('test.admin', true) = 'true', false) $$;
CREATE FUNCTION public.fn_pode_ver_obra(p_obra_id uuid) RETURNS boolean LANGUAGE sql STABLE AS
  $$ SELECT p_obra_id = nullif(current_setting('test.obra', true), '')::uuid $$;
ALTER TABLE public.itens_orcamento ENABLE ROW LEVEL SECURITY;
CREATE POLICY legado_select ON public.itens_orcamento FOR SELECT TO authenticated USING (true);
CREATE VIEW public.vw_previsao_mensal AS
  SELECT f.obra_id, date_trunc('month', i.criado_em) AS mes, sum(i.venda_prevista) AS venda
  FROM public.itens_orcamento i JOIN public.fases f ON f.id = i.fase_id
  WHERE i.considerar_previsao_futura GROUP BY 1, 2;
INSERT INTO public.obras VALUES
  ('00000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-000000000002');
INSERT INTO public.utilizadores VALUES ('00000000-0000-4000-8000-000000000003');
INSERT INTO public.documentos_obra(id, obra_id) VALUES
  ('00000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000005', '00000000-0000-4000-8000-000000000002');
INSERT INTO public.fases SELECT md5('fase' || n)::uuid, '00000000-0000-4000-8000-000000000001'::uuid
  FROM generate_series(1,9) n;
INSERT INTO public.itens_orcamento(id, fase_id, numero_artigo, descricao, venda_prevista)
  SELECT md5('item' || n)::uuid, md5('fase' || ((n+1)/2))::uuid, n::text, 'Legado sintético', n*100
  FROM generate_series(1,18) n;
INSERT INTO public.orcamento_fases(id, obra_id, fase_id, nome_ficheiro_origem)
  SELECT md5('orcamento_fase' || n)::uuid, '00000000-0000-4000-8000-000000000001'::uuid,
    md5('fase' || n)::uuid, 'Recuperação de itens_orcamento históricos' FROM generate_series(1,9) n;
INSERT INTO public.contratos VALUES
  (md5('contrato')::uuid, '00000000-0000-4000-8000-000000000001',553619.19,426540.43,472179.26,355023.64);
INSERT INTO public.planeamento_itens VALUES (md5('tarefa')::uuid, md5('item1')::uuid);
