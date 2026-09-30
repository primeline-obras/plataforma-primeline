-- Medicina do Trabalho: backend controlado. NÃO aplicado em produção.
BEGIN;
DO $$ BEGIN
 IF md5(replace(pg_get_functiondef('public.fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date)'::regprocedure),chr(13),'')) <> 'f85d19fc2f70a8655f7169755b0f8841' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date)'; END IF;
 IF md5(replace(pg_get_functiondef('public.fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date,text,numeric,text,text,text,text)'::regprocedure),chr(13),'')) <> '97a86f43524447d2efd071aff452b705' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_atualizar_colaborador_ciclo_vida(uuid,text,text,date,date,date,text,numeric,text,text,text,text)'; END IF;
 IF md5(replace(pg_get_functiondef('public.fn_executar_rotinas_diarias()'::regprocedure),chr(13),'')) <> 'eafafef50828812e496dd1f28c835e71' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_executar_rotinas_diarias()'; END IF;
 IF md5(replace(pg_get_functiondef('public.fn_rh_guardar_interno(jsonb,boolean,boolean)'::regprocedure),chr(13),'')) <> 'df4de93611fed73a230070a8d6550b38' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_rh_guardar_interno(jsonb,boolean,boolean)'; END IF;
 IF md5(replace(pg_get_functiondef('public.fn_verificar_alertas_vencimento()'::regprocedure),chr(13),'')) <> 'da2acec36d98be12bd5b7b185d76de1c' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_verificar_alertas_vencimento()'; END IF;
 IF md5(replace(pg_get_functiondef('public.fn_verificar_primeiras_consultas_medicina()'::regprocedure),chr(13),'')) <> 'f3ad636c530e435ab2f2175ca823b9cb' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_verificar_primeiras_consultas_medicina()'; END IF;
END $$;

DO $$
BEGIN
 IF to_regclass('public.medicina_operacoes') IS NOT NULL THEN
  RAISE EXCEPTION 'PRECONDITION_FAILED: backend já instalado.';
 END IF;
 IF (SELECT count(*) FROM public.medicina_trabalho) <> 34 THEN
  RAISE EXCEPTION 'PRECONDITION_FAILED: esperados 34 registos; repetir preflight.';
 END IF;
 IF EXISTS(SELECT 1 FROM public.medicina_trabalho WHERE data_ultima_consulta IS NULL
    OR data_proxima_consulta < data_ultima_consulta) THEN
  RAISE EXCEPTION 'PRECONDITION_FAILED: datas antigas exigem revisão, sem preenchimento automático.';
 END IF;
END $$;

-- Fotografia interna de instalação, sem credenciais; acesso reservado ao owner.
CREATE TABLE public.medicina_instalacao_snapshot (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 criado_em timestamptz NOT NULL DEFAULT now(),
 linhas jsonb NOT NULL, alertas jsonb NOT NULL
);
REVOKE ALL ON public.medicina_instalacao_snapshot FROM PUBLIC, anon, authenticated;
INSERT INTO public.medicina_instalacao_snapshot(id,linhas,alertas)
SELECT true,
 coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY id) FROM public.medicina_trabalho m),'[]'),
 coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM public.alertas a
 WHERE tipo IN ('primeira_consulta_medicina','consulta_medicina','medicina_trabalho_vencimento')),'[]');

ALTER TABLE public.medicina_trabalho
 ADD COLUMN registado_por uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
 ADD COLUMN request_id uuid UNIQUE,
 ADD COLUMN revisao integer NOT NULL DEFAULT 0 CHECK(revisao>=0),
 ADD COLUMN anulado_em timestamptz,
 ADD COLUMN anulado_por uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
 ADD CONSTRAINT medicina_datas_coerentes CHECK(data_proxima_consulta IS NULL
   OR (data_ultima_consulta IS NOT NULL AND data_proxima_consulta>=data_ultima_consulta)),
 ADD CONSTRAINT medicina_anulacao_coerente CHECK((anulado_em IS NULL)=(anulado_por IS NULL));
-- Autoria e request antigos permanecem NULL. Nunca atribuir autoria retroativamente.
CREATE TABLE public.medicina_operacoes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 consulta_id uuid NOT NULL REFERENCES public.medicina_trabalho(id) ON DELETE RESTRICT,
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id) ON DELETE RESTRICT,
 empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE RESTRICT,
 operacao text NOT NULL CHECK(operacao IN ('registar','corrigir','anular')),
 autor_id uuid NOT NULL REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
 criado_em timestamptz NOT NULL DEFAULT now(),
 request_id uuid NOT NULL UNIQUE,
 pedido jsonb NOT NULL,
 motivo text,
 antes jsonb, depois jsonb NOT NULL,
 resposta jsonb NOT NULL,
 CHECK(operacao='registar' OR nullif(btrim(motivo),'') IS NOT NULL)
);
CREATE TABLE public.medicina_alertas_historico (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 alerta_id uuid NOT NULL REFERENCES public.alertas(id) ON DELETE RESTRICT,
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id) ON DELETE RESTRICT,
 consulta_atual_id uuid REFERENCES public.medicina_trabalho(id) ON DELETE RESTRICT,
 autor_id uuid REFERENCES public.utilizadores(id) ON DELETE RESTRICT,
 criado_em timestamptz NOT NULL DEFAULT now(),
 motivo text NOT NULL, antes jsonb NOT NULL, depois jsonb NOT NULL
);
ALTER TABLE public.medicina_operacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicina_alertas_historico ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.medicina_operacoes,public.medicina_alertas_historico FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.medicina_operacoes,public.medicina_alertas_historico TO authenticated;
CREATE POLICY medicina_operacoes_select ON public.medicina_operacoes FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
 AND u.ativo AND u.empresa_id=medicina_operacoes.empresa_id
 AND u.funcao IN ('gestao_plataforma','gerencia','administrativo')));
CREATE POLICY medicina_alertas_select ON public.medicina_alertas_historico FOR SELECT TO authenticated
 USING(EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE c.id=medicina_alertas_historico.colaborador_id AND u.id=public.fn_utilizador_atual_id()
 AND u.ativo AND u.funcao IN ('gestao_plataforma','gerencia','administrativo')));

CREATE FUNCTION public.fn_medicina_pode_gerir(p_colaborador_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE c.id=p_colaborador_id AND u.id=public.fn_utilizador_atual_id() AND u.ativo
 AND u.funcao IN ('gestao_plataforma','gerencia','administrativo'));
$$;
CREATE FUNCTION public.fn_medicina_atual(p_colaborador_id uuid)
RETURNS public.medicina_trabalho LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT m FROM public.medicina_trabalho m WHERE m.colaborador_id=p_colaborador_id
 AND m.anulado_em IS NULL AND m.data_ultima_consulta IS NOT NULL
 AND m.data_ultima_consulta<=current_date
 AND (m.data_proxima_consulta IS NULL OR m.data_proxima_consulta>=m.data_ultima_consulta)
 ORDER BY m.data_ultima_consulta DESC,m.criado_em DESC,m.id DESC LIMIT 1;
$$;

DROP POLICY pl_admin_total ON public.medicina_trabalho;
DROP POLICY pl_medicina_rh ON public.medicina_trabalho;
DROP POLICY pl_medicina_encarregado_atual_select ON public.medicina_trabalho;
CREATE POLICY medicina_leitura ON public.medicina_trabalho FOR SELECT TO authenticated
 USING(public.fn_medicina_pode_gerir(colaborador_id)
 OR (public.fn_colaborador_na_obra_atual_encarregado(colaborador_id) AND EXISTS(
 SELECT 1 FROM public.utilizadores u JOIN public.colaboradores c ON c.empresa_id=u.empresa_id
 WHERE c.id=medicina_trabalho.colaborador_id AND u.id=public.fn_utilizador_atual_id() AND u.ativo)));
REVOKE ALL ON public.medicina_trabalho FROM PUBLIC,anon,authenticated;
-- Mantém as colunas da aba atual; metadados de auditoria só pela RPC autorizada.
GRANT SELECT(id,colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta,criado_em)
 ON public.medicina_trabalho TO authenticated;

CREATE FUNCTION public.fn_medicina_reconciliar_alertas(p_colaborador_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_atual public.medicina_trabalho; v_pessoa public.colaboradores;
 v_a public.alertas; v_depois jsonb; v_n integer:=0; v_dias integer; v_chave uuid;
BEGIN
 SELECT * INTO v_pessoa FROM public.colaboradores WHERE id=p_colaborador_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'VALIDATION_FAILED: colaborador inexistente.'; END IF;
 SELECT * INTO v_atual FROM public.fn_medicina_atual(p_colaborador_id);
 IF v_atual.id IS NOT NULL THEN
  SELECT id INTO v_chave FROM public.medicina_operacoes WHERE consulta_id=v_atual.id
   AND (depois->>'revisao')::integer=v_atual.revisao ORDER BY criado_em DESC,id DESC LIMIT 1;
 ELSE
  SELECT id INTO v_chave FROM public.medicina_operacoes WHERE colaborador_id=p_colaborador_id
   ORDER BY criado_em DESC,id DESC LIMIT 1;
 END IF;
 v_dias:=public.fn_parametro_operacional_numero('antecedencia_alerta_medicina',30)::integer;
 FOR v_a IN SELECT a.* FROM public.alertas a WHERE a.estado='pendente' AND
 ((a.tipo='primeira_consulta_medicina' AND a.entidade_tipo='colaboradores' AND a.entidade_id=p_colaborador_id)
 OR (a.tipo IN ('consulta_medicina','medicina_trabalho_vencimento') AND a.entidade_tipo='medicina_trabalho'
 AND a.entidade_id IN(SELECT id FROM public.medicina_trabalho WHERE colaborador_id=p_colaborador_id)))
 AND (v_pessoa.data_saida IS NOT NULL
 OR (a.tipo='primeira_consulta_medicina' AND
   (v_atual.id IS NOT NULL OR v_pessoa.data_admissao IS NULL
    OR a.data_evento_referencia IS DISTINCT FROM v_pessoa.data_admissao+30
    OR a.ocorrencia_chave IS DISTINCT FROM v_chave))
 OR (a.tipo<>'primeira_consulta_medicina' AND
   (a.entidade_id IS DISTINCT FROM v_atual.id
    OR a.data_evento_referencia IS DISTINCT FROM v_atual.data_proxima_consulta
    OR a.antecedencia_dias IS DISTINCT FROM v_dias
    OR a.ocorrencia_chave IS DISTINCT FROM v_chave
    OR v_atual.data_proxima_consulta IS NULL)))
 ORDER BY a.id FOR UPDATE
 LOOP
  UPDATE public.alertas SET estado='resolvido',resolvido_em=now(),
   resolvido_por=public.fn_utilizador_atual_id() WHERE id=v_a.id RETURNING to_jsonb(alertas.*) INTO v_depois;
  INSERT INTO public.medicina_alertas_historico(alerta_id,colaborador_id,consulta_atual_id,autor_id,motivo,antes,depois)
   VALUES(v_a.id,p_colaborador_id,v_atual.id,public.fn_utilizador_atual_id(),
    CASE WHEN v_pessoa.data_saida IS NOT NULL THEN 'Colaborador inativo'
    ELSE 'Ocorrência substituída pela situação atual de Medicina' END,to_jsonb(v_a),v_depois);
  v_n:=v_n+1;
 END LOOP;
 -- Gerar apenas a ocorrência corrente; resolved antigos nunca são apagados/reabertos.
 IF v_pessoa.data_saida IS NULL THEN
  IF v_atual.id IS NULL AND v_pessoa.data_admissao IS NOT NULL
     AND v_pessoa.data_admissao+30<=current_date THEN
   INSERT INTO public.alertas(empresa_id,tipo,entidade_tipo,entidade_id,titulo,descricao,
    data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado,ocorrencia_chave)
   VALUES(v_pessoa.empresa_id,'primeira_consulta_medicina','colaboradores',p_colaborador_id,
    'Marcar primeira consulta: '||v_pessoa.nome,'Sem consulta realizada válida registada.',
    v_pessoa.data_admissao+30,0,v_pessoa.data_admissao+30,'administrativo','pendente',v_chave)
   ON CONFLICT DO NOTHING;
  ELSIF v_atual.data_proxima_consulta IS NOT NULL AND v_atual.data_proxima_consulta-v_dias<=current_date THEN
   INSERT INTO public.alertas(empresa_id,tipo,entidade_tipo,entidade_id,titulo,descricao,
    data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado,ocorrencia_chave)
   VALUES(v_pessoa.empresa_id,'consulta_medicina','medicina_trabalho',v_atual.id,
    'Consulta de medicina a vencer: '||v_pessoa.nome,
    'Próxima consulta em '||to_char(v_atual.data_proxima_consulta,'DD/MM/YYYY'),
    v_atual.data_proxima_consulta,v_dias,v_atual.data_proxima_consulta-v_dias,'administrativo','pendente',v_chave)
   ON CONFLICT DO NOTHING;
  END IF;
 END IF;
 RETURN v_n;
END $$;

CREATE FUNCTION public.fn_medicina_proteger()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,public AS $$
DECLARE v_owner name; v_inicial boolean;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'PROTECTED_HISTORY: anule pela RPC, não apague.' USING ERRCODE='42501'; END IF;
 SELECT pg_get_userbyid(proowner) INTO v_owner FROM pg_proc
 WHERE oid='public.fn_medicina_guardar_interno(integer,text,uuid,uuid,date,text,date,integer,uuid,text)'::regprocedure;
 IF current_user<>v_owner THEN
  RAISE EXCEPTION 'PROTECTED_MEDICINE: use as RPCs de Medicina.' USING ERRCODE='42501';
 END IF;
 -- Compatibilidade restrita com a admissão existente SECURITY DEFINER.
 -- Nenhuma linha antiga recebe autor/request. Só um INSERT novo de admissão.
 v_inicial:=TG_OP='INSERT' AND coalesce(current_setting('primeline.medicina_rpc',true),'')<>'on';
 IF v_inicial THEN
  IF NEW.resultado IS DISTINCT FROM 'Consulta inicial registada na admissão'
   OR NEW.data_proxima_consulta IS NOT NULL
   OR NOT public.fn_medicina_pode_gerir(NEW.colaborador_id)
   OR EXISTS(SELECT 1 FROM public.medicina_trabalho WHERE colaborador_id=NEW.colaborador_id) THEN
   RAISE EXCEPTION 'PROTECTED_MEDICINE: inserção fora do fluxo controlado.' USING ERRCODE='42501';
  END IF;
  NEW.registado_por:=public.fn_utilizador_atual_id(); NEW.request_id:=gen_random_uuid();
 ELSIF coalesce(current_setting('primeline.medicina_rpc',true),'')<>'on' THEN
  RAISE EXCEPTION 'PROTECTED_MEDICINE: sinalizador e proprietário obrigatórios.' USING ERRCODE='42501';
 END IF;
 IF NEW.anulado_em IS NULL AND (NEW.data_ultima_consulta IS NULL OR NEW.data_ultima_consulta>current_date) THEN
  RAISE EXCEPTION 'VALIDATION_FAILED: indique uma consulta efetivamente realizada, não futura.' USING ERRCODE='22023';
 END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.revisao<>0 OR NEW.anulado_em IS NOT NULL OR NEW.registado_por IS NULL OR NEW.request_id IS NULL THEN
   RAISE EXCEPTION 'VALIDATION_FAILED: metadados de criação inválidos.';
  END IF;
 ELSE
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id
   OR NEW.criado_em IS DISTINCT FROM OLD.criado_em OR NEW.registado_por IS DISTINCT FROM OLD.registado_por
   OR NEW.request_id IS DISTINCT FROM OLD.request_id OR NEW.revisao<>OLD.revisao+1
   OR OLD.anulado_em IS NOT NULL THEN
   RAISE EXCEPTION 'VALIDATION_FAILED: identidade/histórico imutável ou consulta anulada.';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_medicina_proteger BEFORE INSERT OR UPDATE OR DELETE ON public.medicina_trabalho
 FOR EACH ROW EXECUTE FUNCTION public.fn_medicina_proteger();

CREATE FUNCTION public.fn_medicina_proteger_historico()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,public AS $$
BEGIN
 IF TG_OP<>'INSERT' OR current_user<>(
 SELECT pg_get_userbyid(proowner) FROM pg_proc
 WHERE oid='public.fn_medicina_guardar_interno(integer,text,uuid,uuid,date,text,date,integer,uuid,text)'::regprocedure) THEN
  RAISE EXCEPTION 'PROTECTED_HISTORY: histórico de Medicina imutável.' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_medicina_operacoes_proteger BEFORE INSERT OR UPDATE OR DELETE ON public.medicina_operacoes
 FOR EACH ROW EXECUTE FUNCTION public.fn_medicina_proteger_historico();
CREATE TRIGGER trg_medicina_alertas_proteger BEFORE INSERT OR UPDATE OR DELETE ON public.medicina_alertas_historico
 FOR EACH ROW EXECUTE FUNCTION public.fn_medicina_proteger_historico();

CREATE FUNCTION public.fn_medicina_guardar_interno(
 p_version integer,p_operacao text,p_colaborador_id uuid,p_consulta_id uuid,
 p_data_consulta date,p_resultado text,p_proxima_consulta date,
 p_revisao_esperada integer,p_request_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_actor uuid:=public.fn_utilizador_atual_id(); v_c uuid; v_empresa uuid;
 v_old public.medicina_trabalho; v_new public.medicina_trabalho; v_replay public.medicina_operacoes;
 v_pedido jsonb; v_result jsonb; v_h uuid:=gen_random_uuid(); v_flag text;
BEGIN
 IF p_version IS DISTINCT FROM 1 OR p_request_id IS NULL
 OR p_operacao NOT IN ('registar','corrigir','anular') THEN
  RAISE EXCEPTION 'VALIDATION_FAILED: versão, operação ou request_id inválido.' USING ERRCODE='22023';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'STALE_REVISION: repetir em READ COMMITTED.' USING ERRCODE='40001';
 END IF;
 v_c:=p_colaborador_id;
 IF p_operacao<>'registar' THEN
  SELECT colaborador_id INTO v_c FROM public.medicina_trabalho WHERE id=p_consulta_id;
 END IF;
 IF NOT public.fn_medicina_pode_gerir(v_c) THEN
  RAISE EXCEPTION 'PERMISSION_DENIED: Medicina reservada ao RH autorizado da empresa.' USING ERRCODE='42501';
 END IF;
 v_pedido:=jsonb_build_object('version',p_version,'operacao',p_operacao,'colaborador_id',v_c,
  'consulta_id',p_consulta_id,'data_consulta',p_data_consulta,'resultado',p_resultado,
  'proxima_consulta',p_proxima_consulta,'revisao_esperada',p_revisao_esperada,'motivo',p_motivo,'autor',v_actor);
 PERFORM pg_advisory_xact_lock(hashtextextended('medicina:'||p_request_id::text,0));
 SELECT * INTO v_replay FROM public.medicina_operacoes WHERE request_id=p_request_id;
 IF FOUND THEN
  IF v_replay.pedido IS DISTINCT FROM v_pedido THEN
   RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: request_id usado com pedido diferente.' USING ERRCODE='22023';
  END IF;
  RETURN v_replay.resposta||jsonb_build_object('idempotent',true);
 END IF;
 SELECT empresa_id INTO v_empresa FROM public.colaboradores WHERE id=v_c FOR UPDATE;
 IF p_operacao<>'registar' THEN
  SELECT * INTO v_old FROM public.medicina_trabalho WHERE id=p_consulta_id FOR UPDATE;
  IF v_old.revisao IS DISTINCT FROM p_revisao_esperada THEN
   RAISE EXCEPTION 'STALE_REVISION: consulta alterada entretanto.' USING ERRCODE='40001';
  END IF;
  IF nullif(btrim(p_motivo),'') IS NULL THEN
   RAISE EXCEPTION 'VALIDATION_FAILED: motivo obrigatório para correção/anulação.' USING ERRCODE='22023';
  END IF;
 END IF;
 v_flag:=current_setting('primeline.medicina_rpc',true);
 PERFORM set_config('primeline.medicina_rpc','on',true);
 IF p_operacao='registar' THEN
  INSERT INTO public.medicina_trabalho(colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta,registado_por,request_id)
  VALUES(v_c,p_data_consulta,p_resultado,p_proxima_consulta,v_actor,p_request_id) RETURNING * INTO v_new;
 ELSIF p_operacao='corrigir' THEN
  UPDATE public.medicina_trabalho SET data_ultima_consulta=p_data_consulta,resultado=p_resultado,
   data_proxima_consulta=p_proxima_consulta,revisao=revisao+1 WHERE id=p_consulta_id RETURNING * INTO v_new;
 ELSE
  UPDATE public.medicina_trabalho SET anulado_em=now(),anulado_por=v_actor,revisao=revisao+1
  WHERE id=p_consulta_id RETURNING * INTO v_new;
 END IF;
 PERFORM set_config('primeline.medicina_rpc',coalesce(v_flag,''),true);
 v_result:=jsonb_build_object('version',1,'committed',true,'idempotent',false,
  'consulta',to_jsonb(v_new),'historico_id',v_h);
 INSERT INTO public.medicina_operacoes(id,consulta_id,colaborador_id,empresa_id,operacao,autor_id,
  request_id,pedido,motivo,antes,depois,resposta)
 VALUES(v_h,v_new.id,v_c,v_empresa,p_operacao,v_actor,p_request_id,v_pedido,p_motivo,
  CASE WHEN p_operacao='registar' THEN NULL ELSE to_jsonb(v_old) END,to_jsonb(v_new),v_result);
 PERFORM public.fn_medicina_reconciliar_alertas(v_c);
 RETURN v_result;
END $$;

CREATE FUNCTION public.fn_medicina_registar_consulta(p_version integer,p_colaborador_id uuid,
 p_data_consulta date,p_resultado text,p_proxima_consulta date,p_request_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.fn_medicina_guardar_interno(p_version,'registar',p_colaborador_id,NULL,
 p_data_consulta,p_resultado,p_proxima_consulta,NULL,p_request_id,NULL);
$$;
CREATE FUNCTION public.fn_medicina_corrigir_consulta(p_version integer,p_consulta_id uuid,
 p_data_consulta date,p_resultado text,p_proxima_consulta date,p_revisao_esperada integer,p_request_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.fn_medicina_guardar_interno(p_version,'corrigir',NULL,p_consulta_id,
 p_data_consulta,p_resultado,p_proxima_consulta,p_revisao_esperada,p_request_id,p_motivo);
$$;
CREATE FUNCTION public.fn_medicina_anular_consulta(p_version integer,p_consulta_id uuid,
 p_revisao_esperada integer,p_request_id uuid,p_motivo text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
 SELECT public.fn_medicina_guardar_interno(p_version,'anular',NULL,p_consulta_id,
 NULL,NULL,NULL,p_revisao_esperada,p_request_id,p_motivo);
$$;
CREATE FUNCTION public.fn_medicina_consultar_colaborador(p_version integer,p_colaborador_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_manage boolean; v_atual public.medicina_trabalho; v_linhas jsonb; v_audit jsonb;
BEGIN
 IF p_version IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'VALIDATION_FAILED: versão inválida.'; END IF;
 v_manage:=public.fn_medicina_pode_gerir(p_colaborador_id);
 IF NOT v_manage AND NOT (public.fn_colaborador_na_obra_atual_encarregado(p_colaborador_id)
 AND EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE c.id=p_colaborador_id AND u.id=public.fn_utilizador_atual_id() AND u.ativo)) THEN
  RAISE EXCEPTION 'PERMISSION_DENIED: sem acesso à Medicina deste colaborador.' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_atual FROM public.fn_medicina_atual(p_colaborador_id);
 IF NOT v_manage THEN
  RETURN jsonb_build_object('version',1,'can_write',false,'atual',
   CASE WHEN v_atual.id IS NULL THEN NULL ELSE jsonb_build_object('id',v_atual.id,
   'colaborador_id',v_atual.colaborador_id,'data_ultima_consulta',v_atual.data_ultima_consulta,
   'resultado',v_atual.resultado,'data_proxima_consulta',v_atual.data_proxima_consulta,'criado_em',v_atual.criado_em) END);
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY data_ultima_consulta DESC NULLS LAST,criado_em DESC,id DESC),'[]')
 INTO v_linhas FROM public.medicina_trabalho m WHERE colaborador_id=p_colaborador_id;
 SELECT coalesce(jsonb_agg(to_jsonb(o) ORDER BY criado_em,id),'[]') INTO v_audit
 FROM public.medicina_operacoes o WHERE colaborador_id=p_colaborador_id;
 RETURN jsonb_build_object('version',1,'can_write',true,'atual',
 CASE WHEN v_atual.id IS NULL THEN NULL ELSE to_jsonb(v_atual) END,'consultas',v_linhas,'historico',v_audit);
END $$;

-- Auditar e reconciliar o INSERT inicial que permanece no cadastro existente.
CREATE FUNCTION public.fn_medicina_admissao_historico()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE v_empresa uuid;
BEGIN
 IF coalesce(current_setting('primeline.medicina_rpc',true),'')='on' THEN RETURN NEW; END IF;
 SELECT empresa_id INTO v_empresa FROM public.colaboradores WHERE id=NEW.colaborador_id;
 INSERT INTO public.medicina_operacoes(consulta_id,colaborador_id,empresa_id,operacao,autor_id,request_id,pedido,depois,resposta)
 VALUES(NEW.id,NEW.colaborador_id,v_empresa,'registar',NEW.registado_por,NEW.request_id,
  jsonb_build_object('origem','admissao'),to_jsonb(NEW),
  jsonb_build_object('version',1,'committed',true,'consulta',to_jsonb(NEW)));
 PERFORM public.fn_medicina_reconciliar_alertas(NEW.colaborador_id);
 RETURN NEW;
END $$;
CREATE TRIGGER trg_medicina_admissao_historico AFTER INSERT ON public.medicina_trabalho
 FOR EACH ROW EXECUTE FUNCTION public.fn_medicina_admissao_historico();

-- Funções internas sem EXECUTE público. RPCs públicas explicitamente concedidas.
REVOKE ALL ON FUNCTION public.fn_medicina_pode_gerir(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_medicina_pode_gerir(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_medicina_atual(uuid),public.fn_medicina_reconciliar_alertas(uuid),
 public.fn_medicina_proteger(),public.fn_medicina_proteger_historico(),public.fn_medicina_admissao_historico(),
 public.fn_medicina_guardar_interno(integer,text,uuid,uuid,date,text,date,integer,uuid,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.fn_medicina_registar_consulta(integer,uuid,date,text,date,uuid),
 public.fn_medicina_corrigir_consulta(integer,uuid,date,text,date,integer,uuid,text),
 public.fn_medicina_anular_consulta(integer,uuid,integer,uuid,text),
 public.fn_medicina_consultar_colaborador(integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_medicina_registar_consulta(integer,uuid,date,text,date,uuid),
 public.fn_medicina_corrigir_consulta(integer,uuid,date,text,date,integer,uuid,text),
 public.fn_medicina_anular_consulta(integer,uuid,integer,uuid,text),
 public.fn_medicina_consultar_colaborador(integer,uuid) TO authenticated;

-- Definições COMPLETAS; ramos não médicos preservados da BD instalada.
CREATE OR REPLACE FUNCTION public.fn_verificar_primeiras_consultas_medicina()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_before bigint; v_after bigint;
BEGIN
 SELECT count(*) INTO v_before FROM public.alertas WHERE tipo='primeira_consulta_medicina';
 PERFORM public.fn_medicina_reconciliar_alertas(c.id) FROM public.colaboradores c ORDER BY c.id;
 SELECT count(*) INTO v_after FROM public.alertas WHERE tipo='primeira_consulta_medicina';
 RETURN greatest(0,v_after-v_before)::integer;
END $$;


CREATE OR REPLACE FUNCTION public.fn_verificar_alertas_vencimento()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inseridos integer := 0;
  v_parcial integer := 0;

  v_doc_colaborador integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_documento_colaborador',
      30
    )::integer;

  v_epi integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_epi',
      30
    )::integer;

  v_medicina integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_medicina',
      30
    )::integer;

  v_inspecao integer :=
    public.fn_parametro_operacional_numero(
      'antecedencia_alerta_viatura_inspecao',
      15
    )::integer;

  v_documentos_empresa integer[] :=
    public.fn_parametro_operacional_dias(
      'antecedencias_alerta_documento_empresa',
      array[15,7,3]
    );
begin
  -- Documentos dos colaboradores.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento a vencer: '
      || coalesce(c.nome, d.nome_arquivo, 'colaborador'),
    coalesce(d.tipo_documento, 'Documento')
      || ' · validade em '
      || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    v_doc_colaborador,
    d.data_validade - v_doc_colaborador,
    'administrativo',
    'pendente'
  from public.documentos d
  left join public.colaboradores c
    on c.id = d.entidade_id
  where d.entidade_tipo = 'colaborador'
    and d.data_validade is not null
    and d.data_validade - v_doc_colaborador <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Documentos da empresa.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    d.empresa_id,
    'validade_documento',
    'documentos',
    d.id,
    'Documento da empresa a vencer',
    coalesce(d.tipo_documento, d.nome_arquivo, 'Documento')
      || ' · validade em '
      || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade,
    limiar.dias,
    d.data_validade - limiar.dias,
    'administrativo',
    'pendente'
  from public.documentos d
  cross join lateral (
    select min(dias) as dias
    from unnest(v_documentos_empresa) as valores(dias)
    where d.data_validade - current_date <= dias
  ) limiar
  where d.entidade_tipo = 'empresa'
    and d.data_validade is not null
    and limiar.dias is not null
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- EPI.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    c.empresa_id,
    'validade_epi',
    'epis',
    e.id,
    'EPI a vencer: ' || c.nome,
    coalesce(
      to_jsonb(e)->>'tipo_epi',
      to_jsonb(e)->>'tipo_equipamento',
      to_jsonb(e)->>'tipo',
      'EPI'
    )
      || ' · validade em '
      || to_char(e.data_validade, 'DD/MM/YYYY'),
    e.data_validade,
    v_epi,
    e.data_validade - v_epi,
    'administrativo',
    'pendente'
  from public.epis e
  join public.colaboradores c
    on c.id = e.colaborador_id
  where c.data_saida is null
    and e.data_validade is not null
    and e.data_validade - v_epi <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  -- Medicina: apenas consulta realizada corrente; resolver substituídas.
  select count(*) into v_parcial from public.alertas
  where tipo in ('consulta_medicina','primeira_consulta_medicina');
  perform public.fn_medicina_reconciliar_alertas(c.id)
  from public.colaboradores c order by c.id;
  select greatest(0,count(*)-v_parcial)::integer into v_parcial
  from public.alertas where tipo in ('consulta_medicina','primeira_consulta_medicina');
  v_inseridos := v_inseridos + v_parcial;

  -- Inspeções das viaturas.
  insert into public.alertas (
    empresa_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado
  )
  select
    v.empresa_id,
    'inspecao_viatura',
    'viaturas',
    v.id,
    'Inspeção da viatura a vencer',
    concat_ws(
      ' · ',
      nullif(v.marca_modelo, ''),
      nullif(v.matricula, ''),
      'inspeção em '
        || to_char(v.data_inspecao_proxima, 'DD/MM/YYYY')
    ),
    v.data_inspecao_proxima,
    v_inspecao,
    v.data_inspecao_proxima - v_inspecao,
    'administrativo',
    'pendente'
  from public.viaturas v
  where v.data_inspecao_proxima is not null
    and v.data_inspecao_proxima - v_inspecao <= current_date
  on conflict do nothing;

  get diagnostics v_parcial = row_count;
  v_inseridos := v_inseridos + v_parcial;

  return v_inseridos;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_atualizar_colaborador_ciclo_vida(p_colaborador_id uuid, p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date DEFAULT NULL::date, p_data_saida date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_colaborador public.colaboradores%rowtype;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A gestão de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_data_saida is not null
     and p_data_saida < p_data_admissao then
    raise exception
      'A data de saída não pode ser anterior à data de admissão.';
  end if;

  update public.colaboradores
  set
    nome = btrim(p_nome),
    funcao = btrim(p_funcao),
    data_admissao = p_data_admissao,
    data_nascimento = p_data_nascimento,
    data_saida = p_data_saida
  where id = p_colaborador_id
  returning * into v_colaborador;

  if v_colaborador.id is null then
    raise exception 'Colaborador não encontrado.';
  end if;

  if p_data_saida is not null then
    delete from public.alertas a
    where a.estado = 'pendente'
      and (
        (
          a.entidade_tipo = 'epis'
          and a.entidade_id in (
            select e.id
            from public.epis e
            where e.colaborador_id = p_colaborador_id
          )
        )

      );
  elsif to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    perform public.fn_verificar_alertas_vencimento();
  end if;

  perform public.fn_medicina_reconciliar_alertas(p_colaborador_id);
  return to_jsonb(v_colaborador);
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_atualizar_colaborador_ciclo_vida(p_colaborador_id uuid, p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_data_saida date, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_colaborador public.colaboradores%rowtype;
begin
  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
  ) then
    raise exception
      'A gestão de colaboradores está reservada ao Administrativo e à Gerência.';
  end if;

  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_data_saida is not null
     and p_data_saida < p_data_admissao then
    raise exception
      'A data de saída não pode ser anterior à data de admissão.';
  end if;

  if p_valor_hora is not null and p_valor_hora < 0 then
    raise exception 'O valor/hora não pode ser negativo.';
  end if;

  update public.colaboradores
  set
    nome = btrim(p_nome),
    funcao = btrim(p_funcao),
    nivel = nullif(btrim(p_nivel), ''),
    valor_hora = p_valor_hora,
    nif = nullif(btrim(p_nif), ''),
    email = nullif(btrim(p_email), ''),
    contacto = nullif(btrim(p_contacto), ''),
    morada = nullif(btrim(p_morada), ''),
    data_admissao = p_data_admissao,
    data_nascimento = p_data_nascimento,
    data_saida = p_data_saida
  where id = p_colaborador_id
  returning *
  into v_colaborador;

  if v_colaborador.id is null then
    raise exception 'Colaborador não encontrado.';
  end if;

  if p_data_saida is not null then
    delete from public.alertas a
    where a.estado = 'pendente'
      and (
        (
          a.entidade_tipo = 'epis'
          and a.entidade_id in (
            select e.id
            from public.epis e
            where e.colaborador_id = p_colaborador_id
          )
        )

      );
  elsif to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    perform public.fn_verificar_alertas_vencimento();
  end if;

  perform public.fn_medicina_reconciliar_alertas(p_colaborador_id);
  return to_jsonb(v_colaborador);
end;
$function$;

COMMIT;
