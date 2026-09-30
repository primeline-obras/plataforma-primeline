-- Fixture sintética local. Sem dados/credenciais reais.
-- Estrutura e trigger de retarget reproduzem o preflight real de 30/09/2026.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE TABLE public.empresas(id uuid PRIMARY KEY);
CREATE TABLE public.utilizadores(id uuid PRIMARY KEY,empresa_id uuid REFERENCES empresas(id),funcao text,ativo boolean NOT NULL DEFAULT true,auth_user_id uuid);
CREATE TABLE public.colaboradores(id uuid PRIMARY KEY,empresa_id uuid REFERENCES empresas(id),nome text,data_saida date,utilizador_id uuid REFERENCES utilizadores(id));
CREATE TABLE public.viaturas(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL REFERENCES empresas(id),
 marca_modelo text NOT NULL,matricula text NOT NULL UNIQUE,numero_interno integer,
 colaborador_atribuido_id uuid REFERENCES colaboradores(id),cartao_frota_venc date,iuc_liquidacao date,
 seguro_data date,seguro_seguradora text,data_revisao date,kms_revisao text,data_inspecao_proxima date,
 kms_inspecao text,chaves_estado text,criado_em timestamptz NOT NULL DEFAULT now(),data_proxima_revisao date,
 seguro_ciclo_id uuid NOT NULL DEFAULT gen_random_uuid(),inspecao_ciclo_id uuid NOT NULL DEFAULT gen_random_uuid()
);
CREATE TABLE public.alertas(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),entidade_tipo text,entidade_id uuid,tipo text,
 estado text,destinatario_role text,destinatario_colaborador_id uuid REFERENCES colaboradores(id),
 destinatario_utilizador_id uuid REFERENCES utilizadores(id),resolvido_em timestamptz,resolvido_por uuid,
 data_evento_referencia date,ocorrencia_chave uuid);
CREATE TABLE public.log_auditoria(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tabela_afetada text NOT NULL,
 registo_id uuid NOT NULL,campo text,valor_anterior text,valor_novo text,utilizador_id uuid REFERENCES utilizadores(id),criado_em timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.viaturas_eventos(id uuid PRIMARY KEY,viatura_id uuid REFERENCES viaturas(id),descricao text);
CREATE TABLE public.viaturas_sinistros(id uuid PRIMARY KEY,viatura_id uuid REFERENCES viaturas(id),descricao text);
CREATE TABLE public.multas(id uuid PRIMARY KEY,viatura_id uuid REFERENCES viaturas(id),descricao text);
-- Apenas a identidade autenticada é substituída por configuração local do teste.
CREATE FUNCTION public.fn_utilizador_atual_id() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('test.utilizador',true),'')::uuid;
$$;
CREATE FUNCTION public.fn_e_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id()
 AND ativo AND funcao IN ('gerencia','gestao_plataforma'));
$$;
CREATE FUNCTION public.fn_e_administrativo() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
 SELECT public.fn_e_admin() OR EXISTS(SELECT 1 FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo AND funcao='administrativo');
$$;
ALTER TABLE public.viaturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY pl_admin_total ON public.viaturas FOR ALL TO authenticated USING(public.fn_e_admin()) WITH CHECK(public.fn_e_admin());
CREATE POLICY pl_viaturas_rh ON public.viaturas FOR ALL TO authenticated USING(public.fn_e_administrativo()) WITH CHECK(public.fn_e_administrativo());
GRANT SELECT,INSERT,UPDATE,DELETE ON public.viaturas TO authenticated;
ALTER TABLE public.log_auditoria ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.log_auditoria TO authenticated;
CREATE POLICY log_auditoria_admin_select ON public.log_auditoria FOR SELECT TO authenticated USING(public.fn_e_admin());
CREATE FUNCTION public.fn_atualizar_destinatario_alerta_viatura() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_utilizador_id uuid;
BEGIN
 IF NEW.colaborador_atribuido_id IS NOT NULL THEN
  SELECT c.utilizador_id INTO v_utilizador_id FROM public.colaboradores c WHERE c.id=NEW.colaborador_atribuido_id;
 ELSE v_utilizador_id:=NULL; END IF;
 UPDATE public.alertas SET destinatario_role='administrativo',destinatario_colaborador_id=NEW.colaborador_atribuido_id,destinatario_utilizador_id=v_utilizador_id
 WHERE entidade_tipo='viaturas' AND entidade_id=NEW.id AND tipo IN ('seguro_viatura','inspecao_viatura') AND estado='pendente';
 RETURN NEW;
END;
$$;
CREATE TRIGGER trg_atualizar_destinatario_alerta_viatura AFTER UPDATE OF colaborador_atribuido_id ON public.viaturas
 FOR EACH ROW WHEN(OLD.colaborador_atribuido_id IS DISTINCT FROM NEW.colaborador_atribuido_id)
 EXECUTE FUNCTION public.fn_atualizar_destinatario_alerta_viatura();

ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;
CREATE POLICY pl_colaboradores_rh ON public.colaboradores FOR ALL TO authenticated
 USING(public.fn_e_administrativo()) WITH CHECK(public.fn_e_administrativo());
GRANT SELECT,UPDATE ON public.colaboradores TO authenticated;
