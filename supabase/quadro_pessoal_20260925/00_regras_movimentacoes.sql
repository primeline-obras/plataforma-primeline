-- Preparado para revisão/aplicação manual. NÃO executado em produção.
-- Requer PostgreSQL 15+ e quadro_pessoal_operacional_relatorio.sql instalado.
BEGIN;
SET LOCAL lock_timeout='5s';
LOCK TABLE public.quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE;

CREATE OR REPLACE FUNCTION public.fn_pode_gerir_quadro(p_obra_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
 AND u.ativo IS TRUE AND u.funcao IN ('gestao_plataforma','administrativo')
 AND (p_obra_id IS NULL OR EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=u.empresa_id)));
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_minha_obra(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.obra_responsaveis r
 ON r.utilizador_id=u.id AND r.papel='encarregado' JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=u.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.funcao='encarregado' AND o.id=p_obra_id);
$$;

-- Permissão interna transitória. Não há função pública para a criar, nem GUC
-- manipulável pelo cliente. Protege também escritores SECURITY DEFINER antigos.
CREATE TABLE IF NOT EXISTS public.quadro_pessoal_rpc_permit(
 transacao bigint NOT NULL,utilizador_id uuid NOT NULL,colaborador_id uuid NOT NULL,
 origem_id uuid,destino_id uuid NOT NULL,data date NOT NULL,periodo text NOT NULL,
 PRIMARY KEY(transacao,utilizador_id));
ALTER TABLE public.quadro_pessoal_rpc_permit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quadro_pessoal_rpc_permit FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; q public.quadro_pessoal_alocacao;
BEGIN
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 SELECT * INTO c FROM public.colaboradores WHERE id=q.colaborador_id;
 PERFORM pg_advisory_xact_lock(hashtextextended(q.colaborador_id::text,0));
 IF TG_OP='UPDATE' AND (NEW.id IS DISTINCT FROM OLD.id OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id) THEN
 RAISE EXCEPTION 'Não é permitido alterar a identidade da alocação.'; END IF;
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL THEN
   IF session_user NOT IN ('postgres','supabase_admin') OR auth.uid() IS NOT NULL THEN
   RAISE EXCEPTION 'Sem utilizador autorizado.' USING ERRCODE='42501'; END IF;
 ELSE
   IF c.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'Colaborador de outra empresa.' USING ERRCODE='42501'; END IF;
   IF NOT public.fn_pode_gerir_quadro(NULL) THEN
     IF TG_OP='DELETE' OR NOT EXISTS(SELECT 1 FROM public.quadro_pessoal_rpc_permit p
     WHERE p.transacao=txid_current() AND p.utilizador_id=u.id AND p.colaborador_id=NEW.colaborador_id
     AND p.destino_id=NEW.obra_id AND p.data=NEW.data AND p.periodo=NEW.periodo
     AND NEW.tipo_alocacao='obra' AND NEW.descricao_livre IS NULL
     AND ((TG_OP='INSERT' AND p.origem_id IS NULL) OR
       (TG_OP='UPDATE' AND p.origem_id=OLD.id AND NEW.data=OLD.data AND NEW.periodo=OLD.periodo))
     AND public.fn_quadro_minha_obra(p.destino_id)) THEN
       RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.' USING ERRCODE='42501';
     END IF;
   END IF;
 END IF;
 IF q.obra_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=q.obra_id AND o.empresa_id=c.empresa_id) THEN
 RAISE EXCEPTION 'Obra de outra empresa.' USING ERRCODE='42501'; END IF;
 IF TG_OP<>'DELETE' THEN
   IF c.id IS NULL OR (c.data_saida IS NOT NULL AND c.data_saida<=NEW.data) OR c.data_admissao>NEW.data THEN
   RAISE EXCEPTION 'Colaborador indisponível nesta data.'; END IF;
   IF EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=NEW.colaborador_id AND a.data=NEW.data) THEN
   RAISE EXCEPTION 'Este colaborador está de férias/ausente nesta data.'; END IF;
   IF u.id IS NOT NULL AND TG_OP='INSERT' THEN NEW.criado_por:=u.id; END IF;
   IF TG_OP='UPDATE' THEN NEW.criado_por:=OLD.criado_por; END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_00_quadro_proteger_escrita ON public.quadro_pessoal_alocacao;
CREATE TRIGGER trg_00_quadro_proteger_escrita BEFORE INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao
 FOR EACH ROW EXECUTE FUNCTION public.fn_quadro_proteger_escrita();

CREATE OR REPLACE FUNCTION public.fn_validar_conflito_quadro_pessoal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.id IS DISTINCT FROM NEW.id
 AND q.colaborador_id=NEW.colaborador_id AND q.data=NEW.data AND q.periodo=NEW.periodo
 AND q.obra_id IS NOT DISTINCT FROM NEW.obra_id AND q.tipo_alocacao IS NOT DISTINCT FROM NEW.tipo_alocacao
 AND q.descricao_livre IS NOT DISTINCT FROM NEW.descricao_livre) THEN
 RAISE EXCEPTION 'Alocação idêntica já existente.' USING ERRCODE='23505'; END IF;
 RETURN NEW;
END $$;
ALTER TABLE public.quadro_pessoal_alocacao DROP CONSTRAINT IF EXISTS quadro_pessoal_alocacao_colaborador_data_periodo_key;
DROP INDEX IF EXISTS public.quadro_pessoal_alocacao_colaborador_data_periodo_key;
-- Se houver duplicados, aborta. Não eliminar nem mesclar para criar o índice.
CREATE UNIQUE INDEX IF NOT EXISTS quadro_pessoal_identica_v3_uidx ON public.quadro_pessoal_alocacao
 (colaborador_id,data,periodo,obra_id,tipo_alocacao,descricao_livre) NULLS NOT DISTINCT;

DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT policyname,cmd FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_alocacao' AND cmd<>'SELECT' LOOP
 IF p.cmd='ALL' THEN RAISE EXCEPTION 'Política ALL inesperada (%): rever antes de aplicar.',p.policyname; END IF;
 EXECUTE format('DROP POLICY %I ON public.quadro_pessoal_alocacao',p.policyname);
 END LOOP;
END $$;
ALTER TABLE public.quadro_pessoal_alocacao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quadro_pessoal_alocacao FROM PUBLIC,anon;
REVOKE TRUNCATE,REFERENCES,TRIGGER ON public.quadro_pessoal_alocacao FROM authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.quadro_pessoal_alocacao TO authenticated;
CREATE POLICY quadro_v3_insert ON public.quadro_pessoal_alocacao FOR INSERT TO authenticated
 WITH CHECK(public.fn_pode_gerir_quadro(obra_id) AND criado_por=public.fn_utilizador_atual_id());
CREATE POLICY quadro_v3_update ON public.quadro_pessoal_alocacao FOR UPDATE TO authenticated
 USING(public.fn_pode_gerir_quadro(obra_id)) WITH CHECK(public.fn_pode_gerir_quadro(obra_id));
CREATE POLICY quadro_v3_delete ON public.quadro_pessoal_alocacao FOR DELETE TO authenticated USING(public.fn_pode_gerir_quadro(obra_id));

-- Reutiliza a tabela e o trigger existentes; não cria um segundo histórico.
ALTER TABLE public.quadro_pessoal_movimentos
 ADD COLUMN IF NOT EXISTS perfil_autor text, ADD COLUMN IF NOT EXISTS nome_autor text,
 ADD COLUMN IF NOT EXISTS nome_colaborador text, ADD COLUMN IF NOT EXISTS tipo_acao text,
 ADD COLUMN IF NOT EXISTS alocacao_origem_id uuid, ADD COLUMN IF NOT EXISTS alocacao_destino_id uuid,
 ADD COLUMN IF NOT EXISTS antes jsonb, ADD COLUMN IF NOT EXISTS depois jsonb;
CREATE OR REPLACE FUNCTION public.fn_registar_movimento_quadro()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE c public.colaboradores; u public.utilizadores; q public.quadro_pessoal_alocacao; b jsonb; a jsonb; action text;
BEGIN
 IF TG_OP='UPDATE' AND OLD IS NOT DISTINCT FROM NEW THEN RETURN NEW; END IF;
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 SELECT * INTO c FROM public.colaboradores WHERE id=q.colaborador_id;
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id();
 IF TG_OP<>'INSERT' THEN b:=to_jsonb(OLD); END IF;
 IF TG_OP<>'DELETE' THEN a:=to_jsonb(NEW); END IF;
 action:=CASE WHEN TG_OP='INSERT' THEN 'adicionar' WHEN TG_OP='DELETE' THEN 'remover'
 WHEN OLD.obra_id IS DISTINCT FROM NEW.obra_id OR OLD.data IS DISTINCT FROM NEW.data OR OLD.periodo IS DISTINCT FROM NEW.periodo
 OR OLD.tipo_alocacao IS DISTINCT FROM NEW.tipo_alocacao THEN 'mover' ELSE 'corrigir' END;
 INSERT INTO public.quadro_pessoal_movimentos(empresa_id,alocacao_id,colaborador_id,data,periodo,acao,
 obra_origem_id,obra_destino_id,tipo_origem,tipo_destino,descricao_origem,descricao_destino,
 alterado_por,perfil_autor,nome_autor,nome_colaborador,tipo_acao,alocacao_origem_id,alocacao_destino_id,antes,depois)
 VALUES(c.empresa_id,q.id,c.id,q.data,q.periodo,CASE TG_OP WHEN 'INSERT' THEN 'adicionada' WHEN 'DELETE' THEN 'retirada' ELSE 'alterada' END,
 (b->>'obra_id')::uuid,(a->>'obra_id')::uuid,b->>'tipo_alocacao',a->>'tipo_alocacao',b->>'descricao_livre',a->>'descricao_livre',
 u.id,coalesce(u.funcao,'sql_administrativo'),coalesce(u.nome,session_user),c.nome,action,(b->>'id')::uuid,(a->>'id')::uuid,b,a);
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_quadro_pessoal_movimentos ON public.quadro_pessoal_alocacao;
CREATE TRIGGER trg_quadro_pessoal_movimentos AFTER INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao
 FOR EACH ROW EXECUTE FUNCTION public.fn_registar_movimento_quadro();
REVOKE ALL ON public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.quadro_pessoal_movimentos TO authenticated;
ALTER TABLE public.quadro_pessoal_movimentos ENABLE ROW LEVEL SECURITY;
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='quadro_pessoal_movimentos' LOOP
 EXECUTE format('DROP POLICY %I ON public.quadro_pessoal_movimentos',p.policyname); END LOOP;
END $$;
CREATE POLICY quadro_v3_historico ON public.quadro_pessoal_movimentos FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND u.empresa_id=quadro_pessoal_movimentos.empresa_id) AND
 (public.fn_pode_gerir_quadro(NULL) OR public.fn_quadro_minha_obra(obra_origem_id) OR public.fn_quadro_minha_obra(obra_destino_id)));

CREATE OR REPLACE FUNCTION public.fn_quadro_obras_destino()
RETURNS TABLE(id uuid,numero text,nome text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT o.id,o.numero::text,o.nome FROM public.obras o WHERE public.fn_quadro_minha_obra(o.id) ORDER BY o.numero::text;
$$;

CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; src public.quadro_pessoal_alocacao;
 dest uuid; person uuid; day date; period text; kind text; description text; sid uuid;
 rows_before jsonb; v_version text; n integer; result_id uuid; manage boolean; result jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL THEN RAISE EXCEPTION 'Sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 manage:=public.fn_pode_gerir_quadro(NULL);
 IF p_acao IS NULL OR p_acao NOT IN ('adicionar','mover','remover','corrigir','minha_obra') THEN RAISE EXCEPTION 'Ação inválida.'; END IF;
 IF NOT manage AND (u.funcao<>'encarregado' OR p_acao<>'minha_obra') THEN
 RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.' USING ERRCODE='42501'; END IF;
 -- IDs de origem só são aceites nas ações administrativas explícitas.
 IF p_acao IN ('mover','remover','corrigir') THEN
   sid:=nullif(p_dados->>'id','')::uuid;
   SELECT * INTO src FROM public.quadro_pessoal_alocacao WHERE id=sid;
   IF NOT FOUND THEN RAISE EXCEPTION 'Alocação não encontrada; recarregue.'; END IF;
   person:=src.colaborador_id;
 ELSE person:=(p_dados->>'colaborador_id')::uuid; END IF;
 SELECT * INTO c FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Colaborador não autorizado.' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(person::text,0));
 IF sid IS NOT NULL THEN
   SELECT * INTO src FROM public.quadro_pessoal_alocacao WHERE id=sid FOR UPDATE;
   IF NOT FOUND OR src.colaborador_id<>person THEN RAISE EXCEPTION 'Origem alterada; recarregue.'; END IF;
 END IF;
 day:=coalesce((p_dados->>'data')::date,src.data);
 period:=coalesce(p_dados->>'periodo',src.periodo);
 dest:=nullif(p_dados->>'obra_id','')::uuid; kind:=coalesce(p_dados->>'tipo_alocacao','obra');
 description:=nullif(btrim(p_dados->>'descricao_livre'),'');
 IF p_acao='remover' THEN dest:=src.obra_id; kind:=src.tipo_alocacao; description:=src.descricao_livre; END IF;
 IF day IS NULL OR period IS NULL OR period NOT IN ('manha','tarde','dia_inteiro') THEN RAISE EXCEPTION 'Indique data e período válidos.'; END IF;
 IF p_acao<>'remover' AND ((c.data_saida IS NOT NULL AND c.data_saida<=day) OR c.data_admissao>day) THEN
 RAISE EXCEPTION 'Colaborador indisponível nesta data.'; END IF;
 IF kind NOT IN ('obra','garantia','pontual','escritorio') OR (kind='obra' AND dest IS NULL)
 OR (kind<>'obra' AND (dest IS NOT NULL OR description IS NULL)) THEN RAISE EXCEPTION 'Destino inválido.'; END IF;
 IF kind='obra' THEN description:=NULL; END IF;
 IF dest IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=dest AND o.empresa_id=u.empresa_id) THEN
 RAISE EXCEPTION 'Destino de outra empresa.' USING ERRCODE='42501'; END IF;
 IF p_acao='minha_obra' AND (kind<>'obra' OR NOT public.fn_quadro_minha_obra(dest)) THEN
 RAISE EXCEPTION 'Só pode adicionar à obra em que é Encarregado.' USING ERRCODE='42501'; END IF;
 IF p_acao<>'remover' AND EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=person AND a.data=day) THEN
 RAISE EXCEPTION 'Este colaborador está de férias/ausente nesta data.'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]'::jsonb) INTO rows_before
 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=person AND q.data=day
 AND (q.periodo=period OR q.periodo='dia_inteiro' OR period='dia_inteiro');
 IF p_acao='minha_obra' THEN
   IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=person AND q.data=day
   AND q.periodo=period AND q.obra_id=dest AND q.tipo_alocacao='obra' AND q.descricao_livre IS NULL) THEN
   RAISE EXCEPTION 'Destino já existente: nenhuma origem foi removida.'; END IF;
   n:=jsonb_array_length(rows_before);
   IF n>1 THEN RAISE EXCEPTION 'Várias origens: peça a resolução ao ADM/Gestão. Nada foi alterado.'; END IF;
   IF n=1 THEN
     SELECT * INTO src FROM jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,rows_before->0);
     IF src.periodo<>period THEN RAISE EXCEPTION 'Sobreposição parcial: peça a resolução ao ADM/Gestão.'; END IF;
     sid:=src.id;
   END IF;
 END IF;
 IF p_acao<>'remover' AND EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=person
 AND q.data=day AND q.periodo=period AND q.obra_id IS NOT DISTINCT FROM dest AND q.tipo_alocacao=kind
 AND q.descricao_livre IS NOT DISTINCT FROM description AND q.id IS DISTINCT FROM sid) THEN
 RAISE EXCEPTION 'Alocação idêntica já existente.' USING ERRCODE='23505'; END IF;
 v_version:=md5(jsonb_build_object('linhas',rows_before,'origem',to_jsonb(src),'dados',p_dados,'acao',p_acao)::text);
 result:=jsonb_build_object('versao',v_version,'colaborador',c.nome,'origem_id',sid,'obra_origem_id',src.obra_id,
 'obra_destino_id',dest,'data',day,'periodo',period,'acao',CASE WHEN p_acao='minha_obra' THEN CASE WHEN sid IS NULL THEN 'adicionar' ELSE 'mover' END ELSE p_acao END);
 IF NOT p_confirmar THEN RETURN result||jsonb_build_object('estado','PREVISUALIZACAO'); END IF;
 IF p_versao IS DISTINCT FROM v_version THEN RAISE EXCEPTION 'Pré-visualização desatualizada. Consulte novamente.'; END IF;
 IF NOT manage THEN INSERT INTO public.quadro_pessoal_rpc_permit VALUES(txid_current(),u.id,person,sid,dest,day,period); END IF;
 IF p_acao='remover' THEN
   DELETE FROM public.quadro_pessoal_alocacao WHERE id=sid; result_id:=sid;
 ELSIF sid IS NOT NULL THEN
   UPDATE public.quadro_pessoal_alocacao SET obra_id=dest,data=day,periodo=period,
   semana_inicio=date_trunc('week',day::timestamp)::date,tipo_alocacao=kind,descricao_livre=description WHERE id=sid RETURNING id INTO result_id;
 ELSE
   INSERT INTO public.quadro_pessoal_alocacao(colaborador_id,obra_id,data,periodo,semana_inicio,tipo_alocacao,descricao_livre,criado_por)
   VALUES(person,dest,day,period,date_trunc('week',day::timestamp)::date,kind,description,u.id) RETURNING id INTO result_id;
 END IF;
 DELETE FROM public.quadro_pessoal_rpc_permit WHERE transacao=txid_current() AND utilizador_id=u.id;
 RETURN result||jsonb_build_object('estado','GUARDADO','alocacao_id',result_id);
END $$;
REVOKE ALL ON FUNCTION public.fn_quadro_proteger_escrita(),public.fn_registar_movimento_quadro(),public.fn_validar_conflito_quadro_pessoal() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.fn_pode_gerir_quadro(uuid),public.fn_quadro_minha_obra(uuid),public.fn_quadro_obras_destino(),public.fn_quadro_operar(text,jsonb,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_pode_gerir_quadro(uuid),public.fn_quadro_minha_obra(uuid),public.fn_quadro_obras_destino(),public.fn_quadro_operar(text,jsonb,boolean,text) TO authenticated;
COMMENT ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text) IS 'quadro_v3_20260925';
COMMIT;
