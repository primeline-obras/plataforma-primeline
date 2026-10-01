-- Pacote 1: instalação proposta; NÃO executada em produção.
BEGIN;
SET LOCAL lock_timeout = '10s';
LOCK TABLE public.quadro_pessoal_alocacao, public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF to_regclass('primeline_backup.quadro_20261001') IS NULL THEN
  RAISE EXCEPTION 'PRECONDITION_FAILED: executar e rever o backup privado primeiro.';
 END IF;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.quadro_pessoal_alocacao q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_20261001 q)
 OR (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM public.quadro_pessoal_movimentos q)
 IS DISTINCT FROM (SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY id),'[]') FROM primeline_backup.quadro_movimentos_20261001 q)
 THEN RAISE EXCEPTION 'PRECONDITION_FAILED: dados mudaram desde o backup.'; END IF;
 IF to_regclass('public.quadro_operacoes') IS NOT NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: pacote já instalado.'; END IF;
END $$;
DO $$ BEGIN
 IF md5(replace(pg_get_functiondef('fn_quadro_proteger_escrita()'::regprocedure),chr(13),'')) <> '4508b451e7c38db4a2643daa4f977777' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_quadro_proteger_escrita()'; END IF;
 IF md5(replace(pg_get_functiondef('fn_quadro_operar(text,jsonb,boolean,text)'::regprocedure),chr(13),'')) <> 'd48a0abe117d620e1c238085cb230658' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_quadro_operar(text,jsonb,boolean,text)'; END IF;
 IF md5(replace(pg_get_functiondef('fn_registar_movimento_quadro()'::regprocedure),chr(13),'')) <> 'bcd1daceb4c64b00edfaf8bb288b0bed' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_registar_movimento_quadro()'; END IF;
 IF md5(replace(pg_get_functiondef('fn_rh_guardar_interno(jsonb,boolean,boolean)'::regprocedure),chr(13),'')) <> 'df4de93611fed73a230070a8d6550b38' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_rh_guardar_interno(jsonb,boolean,boolean)'; END IF;
 IF md5(replace(pg_get_functiondef('fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid)'::regprocedure),chr(13),'')) <> '64b0316b13cff529454f84cc5119a3c2' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid)'; END IF;
 IF md5(replace(pg_get_functiondef('fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text)'::regprocedure),chr(13),'')) <> '2b2dbf0afc78a12a2c6461e30db70167' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: definição divergente: fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text)'; END IF;
END $$;

DO $$ BEGIN IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.prokind IN('f','p') AND p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?quadro_pessoal_alocacao\M'
 AND p.proname NOT IN('fn_quadro_operar','fn_criar_colaborador_com_alocacao'))
 THEN RAISE EXCEPTION 'PRECONDITION_FAILED: escritor de alocação não tratado.'; END IF; END $$;
DO $$ BEGIN
IF md5(replace(pg_get_functiondef('fn_listar_ponto_obra(date,uuid)'::regprocedure),chr(13),''))<>'2a8a00ccb7f9a288561a426442b5a869' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: seletor temporal divergente: fn_listar_ponto_obra(date,uuid)'; END IF;
IF md5(replace(pg_get_functiondef('fn_guardar_ponto_obra(uuid,uuid,date,text,time without time zone,time without time zone,time without time zone,time without time zone,text)'::regprocedure),chr(13),''))<>'94fc731ac0a5377c2b2bf955c3faf07e' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: seletor temporal divergente: fn_guardar_ponto_obra(uuid,uuid,date,text,time without time zone,time without time zone,time without time zone,time without time zone,text)'; END IF;
END $$;
DO $$ BEGIN
 IF md5(replace(pg_get_functiondef('fn_pode_gerir_quadro(uuid)'::regprocedure),chr(13),'')) <> '42de4f071c3ec70c4c45eb4ae233feed' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: permissões divergentes: fn_pode_gerir_quadro(uuid)'; END IF;
 IF md5(replace(pg_get_functiondef('fn_quadro_minha_obra(uuid)'::regprocedure),chr(13),'')) <> 'ea53c2578c0e7648e7bcbacfb1f0467a' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: permissões divergentes: fn_quadro_minha_obra(uuid)'; END IF;
 IF md5(replace(pg_get_functiondef('fn_pode_consultar_quadro()'::regprocedure),chr(13),'')) <> '338d8a070420471c63ad1acb9cb64c0c' THEN RAISE EXCEPTION 'PRECONDITION_FAILED: permissões divergentes: fn_pode_consultar_quadro()'; END IF;
END $$;
CREATE TABLE public.quadro_dias_revisoes (
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id), data date NOT NULL,
 revisao integer NOT NULL DEFAULT 0 CHECK(revisao>=0), PRIMARY KEY(colaborador_id,data)
);
CREATE TABLE public.quadro_operacoes (
 request_id uuid PRIMARY KEY, empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 utilizador_id uuid NOT NULL REFERENCES public.utilizadores(id), pedido jsonb NOT NULL,
 resultado jsonb NOT NULL, criado_em timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.quadro_escrita_interna (
 transacao bigint NOT NULL, colaborador_id uuid NOT NULL, data date NOT NULL,
 utilizador_id uuid NOT NULL, origem text NOT NULL, request_id uuid,
 PRIMARY KEY(transacao,colaborador_id,data)
);
ALTER TABLE public.quadro_dias_revisoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quadro_operacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quadro_escrita_interna ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.quadro_dias_revisoes,public.quadro_operacoes,public.quadro_escrita_interna FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.quadro_pessoal_movimentos ADD COLUMN origem_operacao text;
ALTER TABLE public.quadro_pessoal_movimentos ADD COLUMN request_id uuid;

CREATE OR REPLACE FUNCTION public.fn_pode_gerir_quadro(p_obra_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
 AND u.ativo IS TRUE AND u.empresa_id IS NOT NULL AND u.funcao IN ('gestao_plataforma','gerencia','administrativo')
 AND (p_obra_id IS NULL OR EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=u.empresa_id)));
$$;
CREATE FUNCTION public.fn_quadro_ler_obra(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fn_pode_gerir_quadro(p_obra_id) OR EXISTS(
 SELECT 1 FROM public.utilizadores u JOIN public.obra_responsaveis r ON r.utilizador_id=u.id
 JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=u.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND o.id=p_obra_id
 AND u.funcao IN('encarregado','diretor_obra','adjunto') AND r.papel=u.funcao);
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_minha_obra(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.obra_responsaveis r ON r.utilizador_id=u.id
 JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=u.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.funcao='encarregado'
 AND r.papel='encarregado' AND o.id=p_obra_id);
$$;
CREATE OR REPLACE FUNCTION public.fn_pode_consultar_quadro()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fn_pode_gerir_quadro(NULL) OR EXISTS(SELECT 1 FROM public.obras o WHERE public.fn_quadro_ler_obra(o.id));
$$;

-- Fonte temporal comum. Privada: cada consumidor conserva a sua autorização.
CREATE FUNCTION public.fn_quadro_resolver_data(p_data date)
RETURNS SETOF public.quadro_pessoal_alocacao LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT q.* FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id
 JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND q.data=p_data;
$$;

CREATE FUNCTION public.fn_quadro_dia_explicito(p_colaborador_id uuid,p_data date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]') FROM public.fn_quadro_resolver_data(p_data) q
 WHERE q.colaborador_id=p_colaborador_id;
$$;

-- Único núcleo de DML. Não é RPC pública. Todos os escritores usam este núcleo.
CREATE FUNCTION public.fn_quadro_aplicar_interno(p_colaborador_id uuid,p_data date,
 p_antes jsonb,p_depois jsonb,p_origem text,p_request_id uuid DEFAULT NULL,p_simular boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; q public.quadro_pessoal_alocacao;
 v_antes jsonb; v_revisao integer; v_row jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM public.colaboradores WHERE id=p_colaborador_id AND empresa_id=u.empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador de outra empresa ou inexistente.' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR p_origem NOT IN('quadro','cadastro_rh','importacao_rh') THEN RAISE EXCEPTION 'VALIDATION_ERROR: data/origem inválida.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_colaborador_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(p_colaborador_id::text||':'||p_data::text,0));
 v_antes:=public.fn_quadro_dia_explicito(p_colaborador_id,p_data);
 IF v_antes IS DISTINCT FROM p_antes THEN RAISE EXCEPTION 'STALE_REVISION: alocação alterada; recarregue.'; END IF;
 IF jsonb_typeof(p_depois) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'VALIDATION_ERROR: alocações inválidas.'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) a GROUP BY a->>'id' HAVING count(*)>1)
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: IDs repetidos.'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) a JOIN jsonb_array_elements(p_depois) b
 ON a->>'id'<b->>'id' WHERE a->>'periodo'='dia_inteiro' OR b->>'periodo'='dia_inteiro' OR a->>'periodo'=b->>'periodo')
 THEN RAISE EXCEPTION 'OVERLAP_CONFLICT: destinos simultâneos; legado requer revisão humana.'; END IF;
 -- Permissão em TODAS as origens e destinos; responsabilidade não é presença.
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_antes||p_depois) LOOP
  IF NOT public.fn_pode_gerir_quadro(NULL) AND
    (v_row->>'tipo_alocacao'<>'obra' OR NOT public.fn_quadro_minha_obra((v_row->>'obra_id')::uuid))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: origem/destino fora da equipa autorizada.' USING ERRCODE='42501'; END IF;
 END LOOP;
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_depois) LOOP
  q:=jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,v_row);
  IF q.id IS NULL OR q.colaborador_id IS DISTINCT FROM p_colaborador_id OR q.data IS DISTINCT FROM p_data
   OR q.periodo IS NULL OR q.periodo NOT IN('manha','tarde','dia_inteiro')
   OR q.tipo_alocacao IS NULL OR q.tipo_alocacao NOT IN('obra','escritorio','garantia','pontual')
   OR (q.tipo_alocacao='obra' AND (q.obra_id IS NULL OR q.descricao_livre IS NOT NULL))
   OR (q.tipo_alocacao<>'obra' AND (q.obra_id IS NOT NULL OR nullif(btrim(q.descricao_livre),'') IS NULL))
  THEN RAISE EXCEPTION 'VALIDATION_ERROR: destino/período inválido.'; END IF;
  IF q.obra_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras o WHERE o.id=q.obra_id AND o.empresa_id=u.empresa_id)
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: obra de outra empresa.' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao x WHERE x.id=q.id AND (x.colaborador_id<>p_colaborador_id OR x.data<>p_data))
  THEN RAISE EXCEPTION 'VALIDATION_ERROR: identidade de outra alocação.'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_antes) b WHERE b=v_row) THEN
   IF c.data_admissao>p_data OR (c.data_saida IS NOT NULL AND c.data_saida<=p_data)
   THEN RAISE EXCEPTION 'VALIDATION_ERROR: colaborador indisponível nesta data.'; END IF;
   -- Mantém a proteção instalada: qualquer ausência registada bloqueia a nova alocação.
   IF EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p_colaborador_id AND a.data=p_data)
   THEN RAISE EXCEPTION 'ABSENCE_CONFLICT: colaborador de férias/ausente nesta data.'; END IF;
  END IF;
 END LOOP;
 IF p_simular THEN RETURN jsonb_build_object('allocations',p_depois,'changed',p_antes IS DISTINCT FROM p_depois); END IF;
 IF p_antes=p_depois THEN RETURN jsonb_build_object('allocations',p_antes,'changed',false); END IF;
 INSERT INTO public.quadro_escrita_interna VALUES(txid_current(),p_colaborador_id,p_data,u.id,p_origem,p_request_id);
 DELETE FROM public.quadro_pessoal_alocacao x WHERE x.colaborador_id=p_colaborador_id AND x.data=p_data
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_depois) d WHERE (d->>'id')::uuid=x.id);
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_depois) LOOP
  q:=jsonb_populate_record(NULL::public.quadro_pessoal_alocacao,v_row);
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao x WHERE x.id=q.id) THEN
   UPDATE public.quadro_pessoal_alocacao x SET obra_id=q.obra_id,periodo=q.periodo,
     tipo_alocacao=q.tipo_alocacao,descricao_livre=q.descricao_livre
   WHERE x.id=q.id AND (x.obra_id,x.periodo,x.tipo_alocacao,x.descricao_livre)
     IS DISTINCT FROM (q.obra_id,q.periodo,q.tipo_alocacao,q.descricao_livre);
  ELSE
   INSERT INTO public.quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,periodo,semana_inicio,tipo_alocacao,descricao_livre,criado_por)
   VALUES(q.id,p_colaborador_id,q.obra_id,p_data,q.periodo,date_trunc('week',p_data::timestamp)::date,q.tipo_alocacao,q.descricao_livre,u.id);
  END IF;
 END LOOP;
 DELETE FROM public.quadro_escrita_interna WHERE transacao=txid_current() AND colaborador_id=p_colaborador_id AND data=p_data;
 INSERT INTO public.quadro_dias_revisoes VALUES(p_colaborador_id,p_data,1)
 ON CONFLICT(colaborador_id,data) DO UPDATE SET revisao=quadro_dias_revisoes.revisao+1 RETURNING revisao INTO v_revisao;
 RETURN jsonb_build_object('allocations',public.fn_quadro_dia_explicito(p_colaborador_id,p_data),'revision',v_revisao,'changed',true);
END $$;

CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.quadro_pessoal_alocacao;
BEGIN
 IF TG_OP='DELETE' THEN q:=OLD; ELSE q:=NEW; END IF;
 IF TG_OP='UPDATE' AND (NEW.id,NEW.colaborador_id,NEW.data) IS DISTINCT FROM (OLD.id,OLD.colaborador_id,OLD.data)
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: identidade imutável.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current()
 AND p.colaborador_id=q.colaborador_id AND p.data=q.data AND p.utilizador_id=public.fn_utilizador_atual_id())
 THEN RAISE EXCEPTION 'CONTROLLED_WRITE_REQUIRED: use a operação controlada de alocação.' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;

CREATE FUNCTION public.fn_quadro_renomear_interno(p_dados jsonb,p_confirmar boolean,p_versao text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; v_request uuid; v_kind text; v_old text; v_new text;
 v_operation public.quadro_operacoes; v_days jsonb; v_day jsonb; v_after jsonb; v_version text; v_result jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR NOT public.fn_pode_gerir_quadro(NULL) THEN RAISE EXCEPTION 'PERMISSION_DENIED: só Administrativo/Gestão pode renomear linhas.' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p_dados->>'request_id','')::uuid; v_kind:=p_dados->>'tipo_alocacao';
 v_old:=nullif(btrim(p_dados->>'descricao_anterior'),''); v_new:=nullif(btrim(p_dados->>'descricao_nova'),'');
 IF v_request IS NULL OR v_old IS NULL OR v_new IS NULL OR v_kind IS NULL OR v_kind NOT IN('garantia','pontual')
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: designação inválida.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('quadro-request:'||v_request::text,0));
 SELECT * INTO v_operation FROM public.quadro_operacoes WHERE request_id=v_request;
 IF FOUND THEN
  IF v_operation.utilizador_id<>u.id OR v_operation.empresa_id<>u.empresa_id OR v_operation.pedido
    IS DISTINCT FROM jsonb_build_object('acao','renomear_linha','dados',p_dados,'versao',p_versao)
  THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: request_id usado com outro pedido.'; END IF;
  RETURN v_operation.resultado||jsonb_build_object('idempotent',true);
 END IF;
 -- Renomeação explícita abrange uma linha da empresa; serializar o conjunto para não perder novos registos.
 LOCK TABLE public.quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE;
 PERFORM c.id FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND EXISTS(
 SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=c.id AND q.tipo_alocacao=v_kind AND q.descricao_livre=v_old) ORDER BY c.id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_object('person',d.colaborador_id,'data',d.data,
  'before',public.fn_quadro_dia_explicito(d.colaborador_id,d.data),
  'revision',coalesce((SELECT r.revisao FROM public.quadro_dias_revisoes r WHERE r.colaborador_id=d.colaborador_id AND r.data=d.data),0))
 ORDER BY d.colaborador_id,d.data),'[]') INTO v_days FROM (
 SELECT DISTINCT q.colaborador_id,q.data FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND q.tipo_alocacao=v_kind AND q.descricao_livre=v_old) d;
 v_version:=md5(jsonb_build_object('days',v_days,'dados',p_dados)::text);
 FOR v_day IN SELECT value FROM jsonb_array_elements(v_days) LOOP
  SELECT jsonb_agg(CASE WHEN a->>'tipo_alocacao'=v_kind AND a->>'descricao_livre'=v_old
    THEN a||jsonb_build_object('descricao_livre',v_new) ELSE a END ORDER BY a->>'id') INTO v_after
    FROM jsonb_array_elements(v_day->'before') a;
  PERFORM public.fn_quadro_aplicar_interno((v_day->>'person')::uuid,(v_day->>'data')::date,v_day->'before',v_after,'quadro',v_request,true);
 END LOOP;
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',1,'committed',false,'versao',v_version,'days',jsonb_array_length(v_days)); END IF;
 IF p_versao IS DISTINCT FROM v_version THEN RAISE EXCEPTION 'STALE_REVISION: designação alterada; recarregue.'; END IF;
 FOR v_day IN SELECT value FROM jsonb_array_elements(v_days) LOOP
  SELECT jsonb_agg(CASE WHEN a->>'tipo_alocacao'=v_kind AND a->>'descricao_livre'=v_old
    THEN a||jsonb_build_object('descricao_livre',v_new) ELSE a END ORDER BY a->>'id') INTO v_after
    FROM jsonb_array_elements(v_day->'before') a;
  PERFORM public.fn_quadro_aplicar_interno((v_day->>'person')::uuid,(v_day->>'data')::date,v_day->'before',v_after,'quadro',v_request);
 END LOOP;
 v_result:=jsonb_build_object('version',1,'committed',true,'idempotent',false,'days',jsonb_array_length(v_days));
 INSERT INTO public.quadro_operacoes(request_id,empresa_id,utilizador_id,pedido,resultado)
 VALUES(v_request,u.empresa_id,u.id,jsonb_build_object('acao','renomear_linha','dados',p_dados,'versao',p_versao),v_result);
 RETURN v_result;
END $$;

-- RPC mantém assinatura; p_dados transporta version, expected_revision e request_id.
CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; v_person uuid; v_day date;
 v_before jsonb; v_after jsonb; v_row jsonb; v_source jsonb; v_period text; v_dest uuid; v_kind text; v_desc text;
 v_request uuid; v_revision integer; v_version text; v_result jsonb; v_operation public.quadro_operacoes;
 v_overlap jsonb; v_id uuid; v_ids jsonb; v_data jsonb;
BEGIN
 IF coalesce(p_dados->>'version','')<>'1' OR jsonb_typeof(p_dados)<>'object' THEN RAISE EXCEPTION 'CONTRACT_VERSION: contrato esperado 1.'; END IF;
 IF p_acao='renomear_linha' AND p_confirmar IS NOT NULL THEN RETURN public.fn_quadro_renomear_interno(p_dados,p_confirmar,p_versao); END IF;
 IF p_acao IS NULL OR p_acao NOT IN('alocar','adicionar','mover','corrigir','remover') OR p_confirmar IS NULL
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: operação inválida.'; END IF;
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 v_request:=nullif(p_dados->>'request_id','')::uuid;
 IF v_request IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: request_id obrigatório.'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('quadro-request:'||v_request::text,0));
 SELECT * INTO v_operation FROM public.quadro_operacoes WHERE request_id=v_request;
 IF FOUND THEN
  IF v_operation.utilizador_id<>u.id OR v_operation.empresa_id<>u.empresa_id
   OR v_operation.pedido IS DISTINCT FROM jsonb_build_object('acao',p_acao,'dados',p_dados,'versao',p_versao)
  THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT: request_id usado com outro pedido.'; END IF;
  RETURN v_operation.resultado||jsonb_build_object('idempotent',true);
 END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 v_person:=(p_dados->>'colaborador_id')::uuid; v_day:=(p_dados->>'data')::date;
 SELECT * INTO c FROM public.colaboradores WHERE id=v_person AND empresa_id=u.empresa_id FOR UPDATE;
 IF NOT FOUND OR v_day IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador/data inválidos nesta empresa.' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_person::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(v_person::text||':'||v_day::text,0));
 SELECT coalesce((SELECT revisao FROM public.quadro_dias_revisoes WHERE colaborador_id=v_person AND data=v_day),0) INTO v_revision;
 IF nullif(p_dados->>'expected_revision','')::integer IS DISTINCT FROM v_revision
 THEN RAISE EXCEPTION 'STALE_REVISION: alocação alterada; recarregue.'; END IF;
 v_before:=public.fn_quadro_dia_explicito(v_person,v_day); v_after:=v_before;
 IF p_acao='remover' THEN
  v_ids:=p_dados->'ids';
  IF jsonb_typeof(v_ids) IS DISTINCT FROM 'array' OR jsonb_array_length(v_ids)=0
   OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_ids) i WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_before) b WHERE b->>'id'=i))
  THEN RAISE EXCEPTION 'STALE_REVISION: origem inexistente; recarregue.'; END IF;
  SELECT coalesce(jsonb_agg(b ORDER BY b->>'id'),'[]') INTO v_after FROM jsonb_array_elements(v_before) b
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_ids) i WHERE b->>'id'=i);
 ELSE
  v_period:=p_dados->>'periodo'; v_kind:=p_dados->>'tipo_alocacao'; v_dest:=nullif(p_dados->>'obra_id','')::uuid;
  v_desc:=CASE WHEN v_kind='obra' THEN NULL ELSE nullif(btrim(p_dados->>'descricao_livre'),'') END;
  IF v_period IS NULL OR v_period NOT IN('manha','tarde','dia_inteiro') THEN RAISE EXCEPTION 'VALIDATION_ERROR: período inválido.'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_before) a JOIN jsonb_array_elements(v_before) b ON a->>'id'<b->>'id'
    WHERE a->>'periodo'='dia_inteiro' OR b->>'periodo'='dia_inteiro' OR a->>'periodo'=b->>'periodo')
  THEN RAISE EXCEPTION 'LEGACY_CONFLICT: sobreposição histórica; solicite revisão humana.'; END IF;
  SELECT coalesce(jsonb_agg(b ORDER BY b->>'id'),'[]') INTO v_overlap FROM jsonb_array_elements(v_before) b
   WHERE v_period='dia_inteiro' OR b->>'periodo'='dia_inteiro' OR b->>'periodo'=v_period;
  v_after:='[]';
  FOR v_row IN SELECT value FROM jsonb_array_elements(v_before) LOOP
   IF v_period<>'dia_inteiro' AND v_row->>'periodo'='dia_inteiro' THEN
    v_after:=v_after||jsonb_build_array(v_row||jsonb_build_object('periodo',CASE v_period WHEN 'manha' THEN 'tarde' ELSE 'manha' END));
   ELSIF NOT(v_period='dia_inteiro' OR v_row->>'periodo'=v_period) THEN v_after:=v_after||jsonb_build_array(v_row);
   END IF;
  END LOOP;
  v_source:=v_overlap->0;
  v_id:=CASE WHEN v_source IS NOT NULL AND NOT(v_period<>'dia_inteiro' AND v_source->>'periodo'='dia_inteiro')
   THEN (v_source->>'id')::uuid ELSE gen_random_uuid() END;
  v_after:=v_after||jsonb_build_array(coalesce(v_source,'{}')||jsonb_build_object('id',v_id,'colaborador_id',v_person,'data',v_day,
    'periodo',v_period,'tipo_alocacao',v_kind,'obra_id',v_dest,'descricao_livre',v_desc));
 END IF;
 SELECT coalesce(jsonb_agg(b ORDER BY b->>'id'),'[]') INTO v_after FROM jsonb_array_elements(v_after) b;
 -- IDs novos só pertencem ao plano transitório: não entram na assinatura do preview.
 SELECT coalesce(jsonb_agg((b-'id'-'criado_em'-'criado_por'-'semana_inicio') ORDER BY b->>'periodo'),'[]') INTO v_data FROM jsonb_array_elements(v_after) b;
 v_version:=md5(jsonb_build_object('before',v_before,'revision',v_revision,'after',v_data,'acao',p_acao,'dados',p_dados)::text);
 IF NOT public.fn_pode_gerir_quadro(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: consulta sem edição.' USING ERRCODE='42501'; END IF;
 FOR v_row IN SELECT value FROM jsonb_array_elements(v_before||v_after) LOOP
  IF NOT public.fn_pode_gerir_quadro(NULL) AND (v_row->>'tipo_alocacao'<>'obra' OR NOT public.fn_quadro_minha_obra((v_row->>'obra_id')::uuid))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: origem/destino fora da equipa autorizada.' USING ERRCODE='42501'; END IF;
 END LOOP;
 PERFORM public.fn_quadro_aplicar_interno(v_person,v_day,v_before,v_after,'quadro',v_request,true);
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',1,'committed',false,'revision',v_revision,'versao',v_version,'before',v_before,'after',v_after); END IF;
 IF p_versao IS DISTINCT FROM v_version THEN RAISE EXCEPTION 'STALE_REVISION: preview desatualizado; recarregue.'; END IF;
 v_result:=public.fn_quadro_aplicar_interno(v_person,v_day,v_before,v_after,'quadro',v_request);
 v_result:=v_result||jsonb_build_object('version',1,'committed',true,'idempotent',false,'colaborador_id',v_person,'data',v_day,'revision',coalesce((v_result->>'revision')::integer,v_revision));
 INSERT INTO public.quadro_operacoes(request_id,empresa_id,utilizador_id,pedido,resultado)
 VALUES(v_request,u.empresa_id,u.id,jsonb_build_object('acao',p_acao,'dados',p_dados,'versao',p_versao),v_result);
 RETURN v_result;
END $$;
CREATE OR REPLACE FUNCTION public.fn_quadro_criar_colaborador_interno(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_alocacao_tipo text, p_obra_id uuid, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text, p_origem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_empresa_id uuid;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_colaborador public.colaboradores%rowtype;
  v_alocacao public.quadro_pessoal_alocacao%rowtype;
  v_semana_inicio date;
begin
  if p_origem not in ('cadastro_rh','importacao_rh') then raise exception 'VALIDATION_ERROR: origem RH inválida.'; end if;
  if not public.fn_pode_gerir_quadro(NULL) then raise exception 'PERMISSION_DENIED: cadastro não autorizado.' using errcode='42501'; end if;
  if nullif(btrim(p_nome), '') is null
     or nullif(btrim(p_funcao), '') is null
     or p_data_admissao is null then
    raise exception
      'Nome, função e data de admissão são obrigatórios.';
  end if;

  if p_valor_hora is not null and p_valor_hora < 0 then
    raise exception 'O valor/hora não pode ser negativo.';
  end if;

  if p_alocacao_tipo is not null and p_alocacao_tipo not in ('obra', 'escritorio') then
    raise exception
      'A alocação inicial deve ser uma obra ativa ou o Escritório.';
  end if;

  select u.empresa_id
  into v_empresa_id
  from public.utilizadores u
  where u.id = v_utilizador_id;

  if v_empresa_id is null then
    raise exception
      'Não foi possível identificar a empresa do utilizador atual.';
  end if;

  if p_alocacao_tipo = 'obra' then
    if p_obra_id is null or not exists (
      select 1
      from public.obras o
      where o.id = p_obra_id
        and o.empresa_id = v_empresa_id
        and coalesce(lower(o.situacao), '') not in (
          'concluida',
          'concluído',
          'concluido',
          'cancelada'
        )
    ) then
      raise exception
        'Selecione uma obra ativa válida para a alocação inicial.';
    end if;
  elsif p_obra_id is not null then
    raise exception
      'A alocação de Escritório não pode ficar ligada a uma obra.';
  end if;

  insert into public.colaboradores (
    empresa_id,
    nome,
    funcao,
    nivel,
    valor_hora,
    nif,
    email,
    contacto,
    morada,
    data_admissao,
    data_nascimento,
    data_saida
  )
  values (
    v_empresa_id,
    btrim(p_nome),
    btrim(p_funcao),
    nullif(btrim(p_nivel), ''),
    p_valor_hora,
    nullif(btrim(p_nif), ''),
    nullif(btrim(p_email), ''),
    nullif(btrim(p_contacto), ''),
    nullif(btrim(p_morada), ''),
    p_data_admissao,
    p_data_nascimento,
    null
  )
  returning *
  into v_colaborador;

  v_semana_inicio :=
    p_data_admissao
    - (extract(isodow from p_data_admissao)::integer - 1);

  if p_alocacao_tipo is not null then
    perform public.fn_quadro_aplicar_interno(v_colaborador.id,p_data_admissao,'[]',
      jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'colaborador_id',v_colaborador.id,
       'data',p_data_admissao,'periodo','dia_inteiro','obra_id',p_obra_id,'tipo_alocacao',p_alocacao_tipo,
       'descricao_livre',case when p_alocacao_tipo='escritorio' then 'Escritório' else null end)),p_origem);
    select * into v_alocacao from public.quadro_pessoal_alocacao
      where colaborador_id=v_colaborador.id and data=p_data_admissao;
  end if;
  return jsonb_build_object(
    'colaborador', to_jsonb(v_colaborador),
    'alocacao', to_jsonb(v_alocacao)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_criar_colaborador_com_alocacao(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date DEFAULT NULL::date, p_alocacao_tipo text DEFAULT 'obra'::text, p_obra_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT public.fn_quadro_criar_colaborador_interno(p_nome,p_funcao,p_data_admissao,p_data_nascimento,p_alocacao_tipo,p_obra_id,NULL,NULL,NULL,NULL,NULL,NULL,'cadastro_rh');
$function$;

CREATE OR REPLACE FUNCTION public.fn_criar_colaborador_com_alocacao(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_alocacao_tipo text, p_obra_id uuid, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 SELECT public.fn_quadro_criar_colaborador_interno(p_nome,p_funcao,p_data_admissao,p_data_nascimento,p_alocacao_tipo,p_obra_id,p_nivel,p_valor_hora,p_nif,p_email,p_contacto,p_morada,'cadastro_rh');
$function$;

CREATE OR REPLACE FUNCTION public.fn_rh_guardar_interno(p_dados jsonb, p_simular boolean, p_importacao boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_empresa uuid:=public.fn_rh_empresa(p_importacao); v_id uuid:=nullif(p_dados->>'id','')::uuid;
  v_antes jsonb; v_patch jsonb:=coalesce(p_dados->'campos','{}'); v_result jsonb;
  v_c public.colaboradores%rowtype; v_ct public.colaboradores_contratos%rowtype;
  v_cp jsonb:=p_dados->'contrato'; v_niss text; v_count integer; v_alterado boolean;
  v_novo boolean:=v_id is null; v_original_ct jsonb;
  v_avisos jsonb:='[]'; v_pendencia text;
begin
  perform pg_advisory_xact_lock(hashtextextended('rh:'||v_empresa::text,0));
  if p_importacao and v_novo then raise exception 'A importação exige ID existente.'; end if;
  if jsonb_typeof(v_patch) is distinct from 'object' then raise exception 'Campos inválidos.'; end if;
  if exists(select 1 from jsonb_object_keys(v_patch) k where k not in
    ('nome','funcao','nivel','valor_hora','nif','email','contacto','morada','data_admissao',
     'data_nascimento','data_saida','codigo_rh','observacoes','seguranca_social_ok','seguro_ok','registo_trabalhador_ok')) then
    raise exception 'Campos de RH desconhecidos.';
  end if;
  if not v_novo then
    perform 1 from public.colaboradores where id=v_id and empresa_id=v_empresa for update;
    if not found then raise exception 'Colaborador não encontrado nesta empresa.'; end if;
    perform 1 from public.colaboradores_contratos where colaborador_id=v_id for update;
    v_antes:=public.fn_rh_consultar(v_id)->0;
  end if;
  v_c:=jsonb_populate_record(null::public.colaboradores,coalesce(v_antes->'colaborador','{}')||v_patch);
  if nullif(btrim(v_c.nome),'') is null or nullif(btrim(v_c.funcao),'') is null or v_c.data_admissao is null then
    raise exception 'Nome, função e admissão são obrigatórios.';
  end if;
  if v_c.valor_hora<0 then raise exception 'Valor/hora não pode ser negativo.'; end if;
  if v_c.data_saida<v_c.data_admissao or v_c.data_nascimento>v_c.data_admissao then raise exception 'Datas incompatíveis.'; end if;
  if nullif(v_c.nif,'') is not null and v_c.nif !~ '^[0-9]{9}$' then raise exception 'NIF deve ter 9 algarismos.'; end if;
  if nullif(v_c.email,'') is not null and v_c.email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Email inválido.'; end if;
  if exists(select 1 from public.colaboradores c where c.empresa_id=v_empresa and c.id is distinct from v_id
    and ((nullif(v_c.nif,'') is not null and c.nif=v_c.nif) or
      (nullif(v_c.codigo_rh,'') is not null and c.codigo_rh=v_c.codigo_rh))) then
    raise exception 'NIF ou código RH já pertence a outro colaborador.';
  end if;
  v_niss:=case when p_dados ? 'niss' then nullif(p_dados->>'niss','') else v_antes->>'niss' end;
  if v_niss is not null and v_niss !~ '^[0-9]{11}$' then raise exception 'NISS deve ter 11 algarismos.'; end if;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if jsonb_typeof(v_cp)<>'object' then raise exception 'Contrato inválido.'; end if;
    if exists(select 1 from jsonb_object_keys(v_cp) k where k not in ('tipo_contrato','data_inicio','data_fim_prevista')) then
      raise exception 'Campos de contrato desconhecidos.';
    end if;
    select count(*) into v_count from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    if v_count>1 then raise exception 'Existem vários contratos ativos; rever antes de editar.'; end if;
    select * into v_ct from public.colaboradores_contratos where colaborador_id=v_id and estado='ativo';
    v_original_ct:=to_jsonb(v_ct);
    v_ct:=jsonb_populate_record(v_ct,v_cp);
    if not p_importacao and (v_ct.tipo_contrato is null or v_ct.tipo_contrato not in ('a_prazo','tempo_indeterminado') or v_ct.data_inicio is null) then
      raise exception 'Tipo e início do contrato são obrigatórios.';
    end if;
    if v_ct.tipo_contrato is not null and v_ct.tipo_contrato not in ('a_prazo','tempo_indeterminado') then
      raise exception 'Tipo de contrato inválido.';
    end if;
    if v_ct.data_inicio is null then v_pendencia:='Início do contrato em falta.';
    elsif v_ct.tipo_contrato='a_prazo' and v_ct.data_fim_prevista is null then v_pendencia:='Indique o fim previsto.';
    elsif v_ct.data_fim_prevista<v_ct.data_inicio then v_pendencia:='Fim contratual anterior ao início.';
    end if;
    if v_pendencia is not null then
      if not p_importacao then raise exception '%',v_pendencia; end if;
      v_avisos:=v_avisos||jsonb_build_array('Contrato não alterado: '||v_pendencia||' Os restantes campos podem ser atualizados.');
      v_cp:=null;
    elsif v_ct.tipo_contrato='tempo_indeterminado' and v_ct.data_fim_prevista is not null then
      if not p_importacao then raise exception 'Tempo indeterminado não tem fim previsto.'; end if;
      -- Na importação parcial, vazio não autoriza apagar uma data anterior.
      if v_cp ? 'data_fim_prevista' then
        v_avisos:=v_avisos||jsonb_build_array('Contrato não alterado: tempo indeterminado com fim fornecido. Rever no cadastro individual.');
        v_cp:=null;
      else
        v_avisos:=v_avisos||jsonb_build_array('Fim previsto existente preservado. Rever no cadastro individual o contrato sem termo.');
      end if;
    elsif v_ct.tipo_contrato is null then
      v_avisos:=v_avisos||jsonb_build_array('Data contratual aceite; tipo de contrato por confirmar pelo RH.');
    end if;
  end if;
  v_alterado:=v_novo or to_jsonb(v_c) is distinct from v_antes->'colaborador'
    or v_niss is distinct from v_antes->>'niss'
    or (v_cp is not null and v_cp<>'null'::jsonb and to_jsonb(v_ct) is distinct from v_original_ct);
  -- Reimportar o mesmo conteúdo é um no-op, mesmo com a versão antiga do Excel.
  if not v_novo and v_alterado and p_dados->>'versao' is distinct from v_antes->>'versao' then
    raise exception 'Cadastro alterado entretanto. Reabra ou exporte novamente o modelo.';
  end if;
  if v_novo then
    if p_dados->>'alocacao_tipo' is not null and p_dados->>'alocacao_tipo' not in ('obra','escritorio') then raise exception 'Indique a alocação inicial.'; end if;
    if p_dados->>'alocacao_tipo'='obra' and not exists(select 1 from public.obras
      where id=nullif(p_dados->>'obra_id','')::uuid and empresa_id=v_empresa and situacao in ('preparacao','em_curso')) then
      raise exception 'Selecione uma obra ativa da empresa.';
    end if;
    if p_dados->>'alocacao_tipo'='escritorio' and nullif(p_dados->>'obra_id','') is not null then raise exception 'Escritório não tem obra.'; end if;
    perform nullif(p_dados->>'epi_data','')::date;
    perform nullif(p_dados->>'medicina_data','')::date;
  end if;
  if p_simular or not v_alterado then return jsonb_build_object('alterado',v_alterado,'id',v_id,'avisos',v_avisos); end if;
  if v_novo then
    v_id:=(public.fn_quadro_criar_colaborador_interno(v_c.nome,v_c.funcao,v_c.data_admissao,v_c.data_nascimento,
      p_dados->>'alocacao_tipo',nullif(p_dados->>'obra_id','')::uuid,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada,case when p_importacao then 'importacao_rh' else 'cadastro_rh' end)
      ->'colaborador'->>'id')::uuid;
  end if;
  update public.colaboradores set nome=v_c.nome,funcao=v_c.funcao,nivel=v_c.nivel,valor_hora=v_c.valor_hora,
    nif=v_c.nif,email=v_c.email,contacto=v_c.contacto,morada=v_c.morada,data_admissao=v_c.data_admissao,
    data_nascimento=v_c.data_nascimento,data_saida=v_c.data_saida,codigo_rh=v_c.codigo_rh,observacoes=v_c.observacoes,
    seguranca_social_ok=v_c.seguranca_social_ok,seguro_ok=v_c.seguro_ok,registo_trabalhador_ok=v_c.registo_trabalhador_ok
    where id=v_id and empresa_id=v_empresa;
  if v_novo then
    if nullif(p_dados->>'epi_data','') is not null then
      insert into public.epis(colaborador_id,tipo_epi,data_entrega,data_validade)
      values(v_id,'Entrega inicial',(p_dados->>'epi_data')::date,null);
    end if;
    if nullif(p_dados->>'medicina_data','') is not null then
      insert into public.medicina_trabalho(colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta)
      values(v_id,(p_dados->>'medicina_data')::date,'Consulta inicial registada na admissão',null);
    end if;
  elsif (v_antes->'colaborador'->>'data_saida') is distinct from v_c.data_saida::text then
    perform public.fn_atualizar_colaborador_ciclo_vida(v_id,v_c.nome,v_c.funcao,v_c.data_admissao,
      v_c.data_nascimento,v_c.data_saida,v_c.nivel,v_c.valor_hora,v_c.nif,v_c.email,v_c.contacto,v_c.morada);
  end if;
  insert into public.colaboradores_rh_privado(colaborador_id,niss) values(v_id,v_niss)
    on conflict(colaborador_id) do update set niss=excluded.niss;
  if v_cp is not null and v_cp<>'null'::jsonb then
    if v_ct.id is null then
      insert into public.colaboradores_contratos(colaborador_id,tipo_contrato,data_inicio,data_fim_prevista,estado)
      values(v_id,v_ct.tipo_contrato,v_ct.data_inicio,v_ct.data_fim_prevista,'ativo');
    else
      update public.colaboradores_contratos set tipo_contrato=v_ct.tipo_contrato,data_inicio=v_ct.data_inicio,
        data_fim_prevista=v_ct.data_fim_prevista where id=v_ct.id;
    end if;
  end if;
  v_result:=public.fn_rh_consultar(v_id)->0;
  insert into public.rh_cadastro_auditoria(empresa_id,colaborador_id,utilizador_id,origem,antes,depois)
    values(v_empresa,v_id,public.fn_utilizador_atual_id(),case when p_importacao then 'importacao_excel' else 'cadastro' end,v_antes,v_result);
  return jsonb_build_object('alterado',true,'id',v_id,'avisos',v_avisos);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_registar_movimento_quadro()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c public.colaboradores;
  u public.utilizadores;
  q public.quadro_pessoal_alocacao;
  b jsonb;
  a jsonb;
  action text;
BEGIN

  IF TG_OP = 'UPDATE'
     AND OLD IS NOT DISTINCT FROM NEW
  THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    q := OLD;
  ELSE
    q := NEW;
  END IF;

  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = q.colaborador_id;

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id();

  IF TG_OP <> 'INSERT' THEN
    b := to_jsonb(OLD);
  END IF;

  IF TG_OP <> 'DELETE' THEN
    a := to_jsonb(NEW);
  END IF;

  action :=
    CASE
      WHEN TG_OP = 'INSERT'
        THEN 'adicionar'
      WHEN TG_OP = 'DELETE'
        THEN 'remover'
      WHEN OLD.obra_id IS DISTINCT FROM NEW.obra_id
        OR OLD.data IS DISTINCT FROM NEW.data
        OR OLD.periodo IS DISTINCT FROM NEW.periodo
        OR OLD.tipo_alocacao IS DISTINCT FROM NEW.tipo_alocacao
        THEN 'mover'
      ELSE 'corrigir'
    END;

  INSERT INTO public.quadro_pessoal_movimentos (
    empresa_id,
    alocacao_id,
    colaborador_id,
    data,
    periodo,
    acao,
    obra_origem_id,
    obra_destino_id,
    tipo_origem,
    tipo_destino,
    descricao_origem,
    descricao_destino,
    alterado_por,
    perfil_autor,
    nome_autor,
    nome_colaborador,
    tipo_acao,
    alocacao_origem_id,
    alocacao_destino_id,
    origem_operacao,
    request_id,
    antes,
    depois
  )
  VALUES (
    c.empresa_id,
    q.id,
    c.id,
    q.data,
    q.periodo,
    CASE TG_OP
      WHEN 'INSERT' THEN 'adicionada'
      WHEN 'DELETE' THEN 'retirada'
      ELSE 'alterada'
    END,
    (b->>'obra_id')::uuid,
    (a->>'obra_id')::uuid,
    b->>'tipo_alocacao',
    a->>'tipo_alocacao',
    b->>'descricao_livre',
    a->>'descricao_livre',
    u.id,
    coalesce(u.funcao, 'sql_administrativo'),
    coalesce(u.nome, session_user),
    c.nome,
    action,
    (b->>'id')::uuid,
    (a->>'id')::uuid,
    (select p.origem from public.quadro_escrita_interna p where p.transacao=txid_current() and p.colaborador_id=q.colaborador_id and p.data=q.data),
    (select p.request_id from public.quadro_escrita_interna p where p.transacao=txid_current() and p.colaborador_id=q.colaborador_id and p.data=q.data),
    b,
    a
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END
$function$;

CREATE FUNCTION public.fn_quadro_contexto(p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; v_allocations jsonb; v_revisions jsonb; v_read jsonb; v_edit jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 IF NOT public.fn_pode_consultar_quadro() THEN RAISE EXCEPTION 'PERMISSION_DENIED: sem responsabilidade autorizada para consultar o Quadro.' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>93 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo inválido.'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.data,q.id),'[]') INTO v_allocations
 FROM generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') d(data)
 CROSS JOIN LATERAL public.fn_quadro_resolver_data(d.data::date) q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND q.data BETWEEN p_inicio AND p_fim
 AND (public.fn_pode_gerir_quadro(NULL) OR (q.tipo_alocacao='obra' AND public.fn_quadro_ler_obra(q.obra_id)));
 SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') INTO v_revisions FROM public.quadro_dias_revisoes d
 JOIN public.colaboradores c ON c.id=d.colaborador_id WHERE c.empresa_id=u.empresa_id AND d.data BETWEEN p_inicio AND p_fim
 AND (public.fn_pode_gerir_quadro(NULL) OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a
 WHERE (a->>'colaborador_id')::uuid=d.colaborador_id AND (a->>'data')::date=d.data));
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_read FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id);
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_edit FROM public.obras o WHERE o.empresa_id=u.empresa_id AND (public.fn_pode_gerir_quadro(o.id) OR public.fn_quadro_minha_obra(o.id));
 RETURN jsonb_build_object('version',1,'allocations',v_allocations,'revisions',v_revisions,
 'can_manage_global',public.fn_pode_gerir_quadro(NULL),'read_work_ids',v_read,'edit_work_ids',v_edit,
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'funcao',c.funcao,'data_admissao',c.data_admissao,'data_saida',c.data_saida) ORDER BY c.nome),'[]') FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND c.data_saida IS NULL AND (
 public.fn_pode_gerir_quadro(NULL) OR u.funcao='encarregado' OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a WHERE (a->>'colaborador_id')::uuid=c.id))),
 'works',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'numero',o.numero,'nome',o.nome,'situacao',o.situacao) ORDER BY o.numero),'[]') FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id)));
END $$;

-- Ponto existente: APENAS resolver diário explícito; sem redesenhar o Ponto.
CREATE OR REPLACE FUNCTION public.fn_listar_ponto_obra(p_data date DEFAULT CURRENT_DATE, p_obra_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and v_atual.funcao <> 'encarregado' then
    raise exception 'O ponto estÃ¡ disponÃ­vel apenas para o Administrativo, GestÃ£o e Encarregados.' using errcode = '42501';
  end if;
  if p_obra_id is not null and not exists (
    select 1 from public.obras o where o.id = p_obra_id and o.empresa_id = v_empresa_id
      and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
  ) then raise exception 'Sem permissÃ£o para consultar o ponto desta obra.' using errcode = '42501'; end if;

  return jsonb_build_object(
    'data', p_data,
    'pode_validar', v_pode_gerir,
    'obras', coalesce((
      select jsonb_agg(jsonb_build_object('id', o.id, 'numero', o.numero, 'nome', o.nome) order by o.numero, o.nome)
      from public.obras o
      where o.empresa_id = v_empresa_id
        and o.situacao in ('preparacao','em_curso','receb_provisoria')
        and (v_pode_gerir or public.fn_e_encarregado_da_obra(o.id))
    ), '[]'::jsonb),
    'linhas', case when p_obra_id is null then '[]'::jsonb else coalesce((
      with eventos as (
        select q.*, slot.periodo_efetivo
        from public.fn_quadro_resolver_data(p_data) q
        join public.colaboradores c on c.id = q.colaborador_id and c.empresa_id = v_empresa_id
        cross join lateral unnest(case when q.periodo = 'dia_inteiro'
          then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
        where q.data = p_data and c.data_saida is null
      ), efetivos as (
        select distinct on (colaborador_id, periodo_efetivo)
          colaborador_id, obra_id, tipo_alocacao, periodo_efetivo, data, criado_em
        from eventos
        order by colaborador_id, periodo_efetivo, data desc, criado_em desc, id desc
      ), equipa as (
        select e.colaborador_id, e.obra_id,
          array_agg(e.periodo_efetivo order by e.periodo_efetivo) as periodos
        from efetivos e
        where e.obra_id = p_obra_id and e.tipo_alocacao = 'obra'
        group by e.colaborador_id, e.obra_id
      )
      select jsonb_agg(jsonb_build_object(
        'colaborador_id', c.id,
        'nome', c.nome,
        'funcao', c.funcao,
        'periodos', eq.periodos,
        'ponto', case when p.id is null then null else to_jsonb(p) end,
        'ausencia', case when a.id is null then null else to_jsonb(a) end
      ) order by
        case
          when lower(coalesce(c.funcao,'')) like '%encarreg%' then 1
          when lower(coalesce(c.funcao,'')) like '%pedreiro%' then 2
          when lower(coalesce(c.funcao,'')) like '%servente%' then 3
          else 4 end,
        c.nome)
      from equipa eq
      join public.colaboradores c on c.id = eq.colaborador_id
      left join public.ponto_pessoal_obra p
        on p.colaborador_id = c.id and p.obra_id = p_obra_id and p.data = p_data
      left join public.ausencias a
        on a.colaborador_id = c.id and a.data = p_data
    ), '[]'::jsonb) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_guardar_ponto_obra(p_obra_id uuid, p_colaborador_id uuid, p_data date, p_estado text, p_entrada_manha time without time zone DEFAULT NULL::time without time zone, p_saida_manha time without time zone DEFAULT NULL::time without time zone, p_entrada_tarde time without time zone DEFAULT NULL::time without time zone, p_saida_tarde time without time zone DEFAULT NULL::time without time zone, p_observacao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_atual public.utilizadores;
  v_empresa_id uuid;
  v_pode_gerir boolean;
  v_periodos text[];
  v_horas numeric(5,2);
  v_registo public.ponto_pessoal_obra;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  v_empresa_id := v_atual.empresa_id;
  v_pode_gerir := public.fn_e_admin() or public.fn_e_administrativo();
  if not v_pode_gerir and not public.fn_e_encarregado_da_obra(p_obra_id) then
    raise exception 'Sem permissÃ£o para registar o ponto desta obra.' using errcode = '42501';
  end if;
  if p_estado not in ('presente','falta_com_justificacao','falta_sem_justificacao') then
    raise exception 'Estado de presenÃ§a invÃ¡lido.';
  end if;
  if p_estado = 'falta_com_justificacao' and nullif(btrim(p_observacao), '') is null then
    raise exception 'Indique a justificaÃ§Ã£o apresentada pelo colaborador.';
  end if;

  with eventos as (
    select q.*, slot.periodo_efetivo
    from public.fn_quadro_resolver_data(p_data) q
    cross join lateral unnest(case when q.periodo = 'dia_inteiro'
      then array['manha','tarde']::text[] else array[q.periodo]::text[] end) slot(periodo_efetivo)
    where q.colaborador_id = p_colaborador_id and q.data = p_data
  ), efetivos as (
    select distinct on (periodo_efetivo) obra_id, tipo_alocacao, periodo_efetivo
    from eventos order by periodo_efetivo, data desc, criado_em desc, id desc
  )
  select array_agg(periodo_efetivo order by periodo_efetivo) into v_periodos
  from efetivos where obra_id = p_obra_id and tipo_alocacao = 'obra';

  if coalesce(cardinality(v_periodos), 0) = 0 then
    raise exception 'Este colaborador nÃ£o estÃ¡ alocado a esta obra na data indicada.';
  end if;
  if not exists (select 1 from public.colaboradores c where c.id = p_colaborador_id and c.empresa_id = v_empresa_id) then
    raise exception 'Colaborador inexistente ou fora da empresa.';
  end if;
  if p_estado = 'presente' and exists (
    select 1 from public.ausencias a
    where a.colaborador_id = p_colaborador_id and a.data = p_data
      and (a.tipo = 'ferias' or a.estado in ('confirmada','justificada'))
  ) then
    raise exception 'Este colaborador tem uma ausÃªncia ou fÃ©rias jÃ¡ confirmadas nesta data.';
  end if;

  if p_estado = 'presente' then
    if 'manha' = any(v_periodos) and (p_entrada_manha is null or p_saida_manha is null or p_saida_manha <= p_entrada_manha) then
      raise exception 'Preencha um horÃ¡rio vÃ¡lido para a manhÃ£.';
    end if;
    if 'tarde' = any(v_periodos) and (p_entrada_tarde is null or p_saida_tarde is null or p_saida_tarde <= p_entrada_tarde) then
      raise exception 'Preencha um horÃ¡rio vÃ¡lido para a tarde.';
    end if;
    if p_saida_manha is not null and p_entrada_tarde is not null and p_entrada_tarde < p_saida_manha then
      raise exception 'Os perÃ­odos da manhÃ£ e da tarde nÃ£o podem sobrepor-se.';
    end if;
    if not ('manha'=any(v_periodos)) then p_entrada_manha:=null; p_saida_manha:=null; end if;
    if not ('tarde'=any(v_periodos)) then p_entrada_tarde:=null; p_saida_tarde:=null; end if;
    v_horas := public.fn_ponto_horas(
      p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde
    );
    if v_horas <= 0 or v_horas > 16 then raise exception 'O total diÃ¡rio deve estar entre 0 e 16 horas.'; end if;
    if exists (
      select 1 from public.ponto_pessoal_obra outro
      where outro.colaborador_id=p_colaborador_id and outro.data=p_data
        and outro.obra_id<>p_obra_id and outro.estado='presente'
        and (
          (p_entrada_manha is not null and outro.entrada_manha is not null and p_entrada_manha < outro.saida_manha and outro.entrada_manha < p_saida_manha)
          or (p_entrada_manha is not null and outro.entrada_tarde is not null and p_entrada_manha < outro.saida_tarde and outro.entrada_tarde < p_saida_manha)
          or (p_entrada_tarde is not null and outro.entrada_manha is not null and p_entrada_tarde < outro.saida_manha and outro.entrada_manha < p_saida_tarde)
          or (p_entrada_tarde is not null and outro.entrada_tarde is not null and p_entrada_tarde < outro.saida_tarde and outro.entrada_tarde < p_saida_tarde)
        )
    ) then raise exception 'O horÃ¡rio sobrepÃµe-se ao ponto deste colaborador noutra obra.'; end if;
  else
    v_horas := 0;
    p_entrada_manha := null; p_saida_manha := null;
    p_entrada_tarde := null; p_saida_tarde := null;
  end if;

  insert into public.ponto_pessoal_obra(
    empresa_id, obra_id, colaborador_id, data, periodos_alocados, estado,
    entrada_manha, saida_manha, entrada_tarde, saida_tarde, horas,
    observacao, justificacao_estado, registado_por, atualizado_por, atualizado_em
  ) values (
    v_empresa_id, p_obra_id, p_colaborador_id, p_data, v_periodos, p_estado,
    p_entrada_manha, p_saida_manha, p_entrada_tarde, p_saida_tarde, v_horas,
    nullif(btrim(p_observacao), ''),
    case when p_estado='falta_com_justificacao' then 'pendente' else 'nao_aplicavel' end,
    v_atual.id, v_atual.id, now()
  ) on conflict (colaborador_id, obra_id, data) do update set
    periodos_alocados = excluded.periodos_alocados,
    estado = excluded.estado,
    entrada_manha = excluded.entrada_manha,
    saida_manha = excluded.saida_manha,
    entrada_tarde = excluded.entrada_tarde,
    saida_tarde = excluded.saida_tarde,
    horas = excluded.horas,
    observacao = excluded.observacao,
    justificacao_estado = excluded.justificacao_estado,
    atualizado_por = v_atual.id,
    atualizado_em = now()
  returning * into v_registo;

  return to_jsonb(v_registo);
end;
$function$;
-- Escritores adaptados acima; só agora fechar DML direto da aplicação.
DO $$ DECLARE r record; BEGIN FOR r IN SELECT policyname,tablename FROM pg_policies
 WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos') LOOP
 EXECUTE format('DROP POLICY %I ON public.%I',r.policyname,r.tablename);
 END LOOP; END $$;
REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON public.quadro_pessoal_alocacao FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON public.quadro_pessoal_movimentos FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos TO authenticated;
CREATE POLICY quadro_controlado_leitura ON public.quadro_pessoal_alocacao FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE c.id=colaborador_id AND u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND (public.fn_pode_gerir_quadro(NULL) OR (tipo_alocacao='obra' AND public.fn_quadro_ler_obra(obra_id)))));
CREATE POLICY quadro_controlado_historico ON public.quadro_pessoal_movimentos FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE
 AND u.empresa_id=quadro_pessoal_movimentos.empresa_id)
 AND (public.fn_pode_gerir_quadro(NULL) OR public.fn_quadro_ler_obra(obra_origem_id) OR public.fn_quadro_ler_obra(obra_destino_id)));
REVOKE ALL ON FUNCTION public.fn_quadro_resolver_data(date) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_quadro_renomear_interno(jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean),
 public.fn_quadro_criar_colaborador_interno(text,text,date,date,text,uuid,text,numeric,text,text,text,text,text),
 public.fn_quadro_dia_explicito(uuid,date),public.fn_quadro_proteger_escrita(),public.fn_registar_movimento_quadro()
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text),public.fn_quadro_contexto(date,date),
 public.fn_quadro_ler_obra(uuid),public.fn_pode_gerir_quadro(uuid),public.fn_pode_consultar_quadro(),public.fn_quadro_minha_obra(uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.fn_quadro_operar(text,jsonb,boolean,text),public.fn_quadro_contexto(date,date),
 public.fn_quadro_ler_obra(uuid),public.fn_pode_gerir_quadro(uuid),public.fn_pode_consultar_quadro(),public.fn_quadro_minha_obra(uuid) TO authenticated;

COMMIT;
