-- Synthetic structures only; no real rows.
CREATE TABLE IF NOT EXISTS public.imoveis_empresa(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid,nome text,morada text,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.imoveis_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),imovel_id uuid,arquivo_url text,nome_arquivo text,criado_por uuid,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.imoveis_reunioes_condominio(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),imovel_id uuid,data date,hora time without time zone,local text,notas text,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.pedidos_orcamento(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid,cliente_nome text,cliente_contacto text,intermediario text,descricao_trabalho text,data_limite_entrega date,estado text,situacao_atual text,criado_por uuid,criado_em timestamp with time zone,prioritario boolean);
CREATE TABLE IF NOT EXISTS public.pedidos_orcamento_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid,versao_id uuid,arquivo_url text,nome_arquivo text,criado_por uuid,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.pedidos_orcamento_versoes(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid,data_envio date,valor numeric,notas text,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.viaturas_eventos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),viatura_id uuid,tipo text,data date,descricao text,custo numeric,fornecedor_id uuid,criado_em timestamp with time zone,validade_operacao text,validade_anterior date,validade_nova date,validade_base date,validade_opcao text,motivo text,registado_por uuid,request_id text);
CREATE TABLE IF NOT EXISTS public.viaturas_sinistros(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),viatura_id uuid,colaborador_id uuid,data date,descricao text,estado text,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.multas(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),colaborador_id uuid,viatura_id uuid,data date,descricao text,valor numeric,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.viaturas_sinistros_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),sinistro_id uuid,arquivo_url text,nome_arquivo text,criado_em timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.multas_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),multa_id uuid,arquivo_url text,nome_arquivo text,criado_em timestamp with time zone);
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS marca_modelo text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS matricula text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS numero_interno integer;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS colaborador_atribuido_id uuid;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS cartao_frota_venc date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS iuc_liquidacao date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS seguro_data date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS seguro_seguradora text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS data_revisao date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS kms_revisao text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS data_inspecao_proxima date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS kms_inspecao text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS chaves_estado text;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS criado_em timestamp with time zone;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS data_proxima_revisao date;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS seguro_ciclo_id uuid;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS inspecao_ciclo_id uuid;
ALTER TABLE public.viaturas ADD COLUMN IF NOT EXISTS atribuicao_revisao integer DEFAULT 0;
CREATE TABLE IF NOT EXISTS public.viaturas_atribuicoes_historico(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),viatura_id uuid,colaborador_anterior_id uuid,colaborador_novo_id uuid,revisao_anterior integer,revisao_nova integer,alterado_por uuid,alterado_em timestamp with time zone,request_id uuid,motivo text);
CREATE TABLE IF NOT EXISTS public.documentos_obra(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),obra_id uuid,tipo text,nome_arquivo text,arquivo_url text,enviado_por uuid,criado_em timestamp with time zone,numero_documento text,revisao text,destinatarios text,enviado_em timestamp with time zone,descricao text,data_emissao date,data_resposta_indice date,estado_indice text,notas text);
CREATE TABLE IF NOT EXISTS public.rnc(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),obra_id uuid,numero integer,fase_id uuid,subempreitada_id uuid,data_deteccao date,local_ocorrencia text,descricao text,origem text,gravidade text,acao_corretiva text,responsavel_correcao text,prazo_correcao date,estado text,reportado_por uuid,verificado_por uuid,data_fecho date,criado_em timestamp with time zone,observacao_verificacao text);
CREATE TABLE IF NOT EXISTS public.rnc_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),rnc_id uuid,arquivo_url text,nome_arquivo text,criado_em timestamp with time zone);
CREATE SCHEMA IF NOT EXISTS auth;
DO $fixture$ BEGIN IF to_regprocedure('auth.uid()') IS NULL THEN EXECUTE 'CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS ''SELECT nullif(current_setting(''''test.actor'''',true),'''''''')::uuid'''; END IF; END $fixture$;

DO $fixture$ BEGIN IF to_regprocedure('public.fn_pode_editar_obra(uuid)') IS NULL THEN EXECUTE 'CREATE OR REPLACE FUNCTION public.fn_pode_editar_obra(p_obra_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''public''
AS $function$
  select public.fn_e_admin()
    or exists (
      select 1
      from public.obra_responsaveis r
      join public.utilizadores u
        on u.id = r.utilizador_id
      where r.obra_id = p_obra_id
        and r.utilizador_id = public.fn_utilizador_atual_id()
        and u.funcao in (
          ''diretor_obra'',
          ''adjunto'',
          ''preparador''
        )
        and r.papel in (
          ''diretor_obra'',
          ''adjunto'',
          ''preparador''
        )
        and coalesce(u.ativo, true)
    );
$function$
'; END IF; END $fixture$;
DO $fixture$ BEGIN IF to_regprocedure('public.fn_pode_editar_documentos_obra(uuid)') IS NULL THEN EXECUTE 'CREATE FUNCTION public.fn_pode_editar_documentos_obra(w uuid) RETURNS boolean LANGUAGE sql AS ''SELECT public.fn_pode_editar_obra(w) OR public.fn_e_administrativo()'''; END IF; END $fixture$;
