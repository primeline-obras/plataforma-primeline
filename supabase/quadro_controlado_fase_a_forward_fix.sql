-- Reinstalação revista após rollback A; não cria nem corrige alocações.
BEGIN;
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED: executar como operador postgres, sem SET ROLE da aplicação.' USING ERRCODE='42501';
 END IF;
END $$;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao,public.quadro_pessoal_movimentos IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF to_regclass('primeline_backup.quadro_funcoes_20261001') IS NULL OR to_regclass('public.quadro_dias_revisoes') IS NULL THEN RAISE EXCEPTION 'PRECONDITION_FAILED: requer backup e estruturas A retidas.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM primeline_quadro_rollout.controlo WHERE singleton AND estado='a_rollback') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: forward-fix A exige rollback A'; END IF;
 IF NOT has_table_privilege('authenticated','public.quadro_pessoal_alocacao','UPDATE') THEN RAISE EXCEPTION 'PRECONDITION_FAILED: não reabrir cliente legado na Fase B.'; END IF;
END $$;
INSERT INTO public.quadro_dias_revisoes(colaborador_id,data,revisao,obras_visiveis)
SELECT q.colaborador_id,q.data,1,coalesce(array_agg(DISTINCT q.obra_id) FILTER(WHERE q.obra_id IS NOT NULL),ARRAY[]::uuid[]) FROM public.quadro_pessoal_alocacao q GROUP BY q.colaborador_id,q.data
ON CONFLICT(colaborador_id,data) DO UPDATE SET obras_visiveis=ARRAY(SELECT DISTINCT w FROM unnest(quadro_dias_revisoes.obras_visiveis||EXCLUDED.obras_visiveis) w);
UPDATE public.quadro_dias_revisoes SET revisao=revisao+1 WHERE colaborador_id IS NOT NULL;
CREATE OR REPLACE FUNCTION public.fn_quadro_pode_gerir_v1(p_obra_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id()
 AND u.ativo IS TRUE AND u.empresa_id IS NOT NULL AND u.funcao IN ('gestao_plataforma','administrativo')
 AND (p_obra_id IS NULL OR EXISTS(SELECT 1 FROM public.obras o WHERE o.id=p_obra_id AND o.empresa_id=u.empresa_id)));
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_leitura_global_v1() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.empresa_id IS NOT NULL AND u.funcao IN('administrativo','gestao_plataforma','gerencia'));
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_lock_escrita_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN PERFORM pg_advisory_xact_lock(61001,1); RETURN NULL; END $$;
DROP TRIGGER IF EXISTS trg_00_quadro_lock_escrita_v1 ON public.quadro_pessoal_alocacao;
CREATE TRIGGER trg_00_quadro_lock_escrita_v1 BEFORE INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao FOR EACH STATEMENT EXECUTE FUNCTION public.fn_quadro_lock_escrita_v1();
CREATE OR REPLACE FUNCTION public.fn_quadro_ler_obra(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fn_quadro_leitura_global_v1() AND EXISTS(SELECT 1 FROM public.obras o JOIN public.utilizadores u ON u.empresa_id=o.empresa_id WHERE o.id=p_obra_id AND u.id=public.fn_utilizador_atual_id()) OR EXISTS(
 SELECT 1 FROM public.utilizadores u JOIN public.obra_responsaveis r ON r.utilizador_id=u.id
 JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=u.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND o.id=p_obra_id
 AND u.funcao IN('encarregado','diretor_obra','adjunto') AND r.papel=u.funcao);
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_minha_obra_v1(p_obra_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores u JOIN public.obra_responsaveis r ON r.utilizador_id=u.id
 JOIN public.obras o ON o.id=r.obra_id AND o.empresa_id=u.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND u.funcao='encarregado'
 AND r.papel='encarregado' AND o.id=p_obra_id);
$$;
CREATE OR REPLACE FUNCTION public.fn_quadro_pode_consultar_v1()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM public.obras o WHERE public.fn_quadro_ler_obra(o.id));
$$;

-- Fonte temporal comum. Privada: cada consumidor conserva a sua autorização.
CREATE OR REPLACE FUNCTION public.fn_quadro_resolver_data(p_data date)
RETURNS SETOF public.quadro_pessoal_alocacao LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT q.* FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id
 JOIN public.utilizadores u ON u.empresa_id=c.empresa_id
 WHERE u.id=public.fn_utilizador_atual_id() AND u.ativo IS TRUE AND q.data=p_data;
$$;

CREATE OR REPLACE FUNCTION public.fn_quadro_dia_explicito(p_colaborador_id uuid,p_data date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.id),'[]') FROM public.fn_quadro_resolver_data(p_data) q
 WHERE q.colaborador_id=p_colaborador_id;
$$;

-- Núcleo de DML dos novos clientes e RH. O escritor legado é preservado apenas na Fase A.
CREATE OR REPLACE FUNCTION public.fn_quadro_aplicar_interno(p_colaborador_id uuid,p_data date,
 p_antes jsonb,p_depois jsonb,p_origem text,p_request_id uuid DEFAULT NULL,p_simular boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; c public.colaboradores; q public.quadro_pessoal_alocacao;
 v_antes jsonb; v_revisao integer; v_row jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
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
  IF NOT (public.fn_quadro_pode_gerir_v1(NULL) OR (p_origem IN('cadastro_rh','importacao_rh') AND public.fn_rh_empresa(false)=u.empresa_id)) AND
    (v_row->>'tipo_alocacao'<>'obra' OR NOT public.fn_quadro_minha_obra_v1((v_row->>'obra_id')::uuid))
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
 -- Um alerta por par origem/destino e destinatário, incluindo split/merge dos períodos.
 FOR v_row IN SELECT jsonb_build_object('origem',b->>'obra_id','destino',a->>'obra_id','id',min(a->>'id'))
 FROM jsonb_array_elements(p_depois) a LEFT JOIN jsonb_array_elements(p_antes) b
 ON b->>'periodo'='dia_inteiro' OR a->>'periodo'='dia_inteiro' OR b->>'periodo'=a->>'periodo'
 WHERE (b->>'obra_id') IS DISTINCT FROM (a->>'obra_id')
 GROUP BY b->>'obra_id',a->>'obra_id' LOOP
  PERFORM public.fn_quadro_notificar_controlado_v1(p_colaborador_id,p_data,(v_row->>'origem')::uuid,(v_row->>'destino')::uuid,(v_row->>'id')::uuid);
 END LOOP;
 DELETE FROM public.quadro_escrita_interna WHERE transacao=txid_current() AND colaborador_id=p_colaborador_id AND data=p_data;
 INSERT INTO public.quadro_dias_revisoes(colaborador_id,data,revisao,obras_visiveis)
 VALUES(p_colaborador_id,p_data,1,ARRAY(SELECT DISTINCT (r->>'obra_id')::uuid FROM jsonb_array_elements(p_antes||p_depois) r WHERE r->>'obra_id' IS NOT NULL))
 ON CONFLICT(colaborador_id,data) DO UPDATE SET revisao=quadro_dias_revisoes.revisao+1,
 obras_visiveis=ARRAY(SELECT DISTINCT x FROM unnest(quadro_dias_revisoes.obras_visiveis||EXCLUDED.obras_visiveis) x)
 RETURNING revisao INTO v_revisao;
 RETURN jsonb_build_object('allocations',public.fn_quadro_dia_explicito(p_colaborador_id,p_data),'revision',v_revisao,'changed',true);
END $$;

CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  u public.utilizadores;
  c public.colaboradores;
  q public.quadro_pessoal_alocacao;
BEGIN
  IF TG_OP = 'DELETE' THEN
    q := OLD;
  ELSE
    q := NEW;
  END IF;

  IF EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current() AND p.colaborador_id=q.colaborador_id AND p.data=q.data AND p.utilizador_id=public.fn_utilizador_atual_id()) THEN
    IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
  END IF;
  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = q.colaborador_id;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(q.colaborador_id::text, 0)
  );

  IF TG_OP = 'UPDATE'
     AND (
       NEW.id IS DISTINCT FROM OLD.id
       OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id
     )
  THEN
    RAISE EXCEPTION 'Não é permitido alterar a identidade da alocação.';
  END IF;

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF u.id IS NULL THEN

    IF session_user NOT IN ('postgres', 'supabase_admin')
       OR auth.uid() IS NOT NULL
    THEN
      RAISE EXCEPTION 'Sem utilizador autorizado.'
      USING ERRCODE = '42501';
    END IF;

  ELSE

    IF c.empresa_id IS DISTINCT FROM u.empresa_id THEN
      RAISE EXCEPTION 'Colaborador de outra empresa.'
      USING ERRCODE = '42501';
    END IF;

    IF NOT public.fn_pode_gerir_quadro(NULL) THEN

      IF TG_OP = 'DELETE'
         OR NOT EXISTS (
           SELECT 1
           FROM public.quadro_pessoal_rpc_permit p
           WHERE p.transacao = txid_current()
             AND p.utilizador_id = u.id
             AND p.colaborador_id = NEW.colaborador_id
             AND p.destino_id = NEW.obra_id
             AND p.data = NEW.data
             AND p.periodo = NEW.periodo
             AND NEW.tipo_alocacao = 'obra'
             AND NEW.descricao_livre IS NULL
             AND (
               (
                 TG_OP = 'INSERT'
                 AND p.origem_id IS NULL
               )
               OR (
                 TG_OP = 'UPDATE'
                 AND p.origem_id = OLD.id
                 AND NEW.data = OLD.data
                 AND NEW.periodo = OLD.periodo
               )
             )
             AND public.fn_quadro_minha_obra(p.destino_id)
         )
      THEN
        RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.'
        USING ERRCODE = '42501';
      END IF;

    END IF;
  END IF;

  IF q.obra_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.obras o
       WHERE o.id = q.obra_id
         AND o.empresa_id = c.empresa_id
     )
  THEN
    RAISE EXCEPTION 'Obra de outra empresa.'
    USING ERRCODE = '42501';
  END IF;

  IF TG_OP <> 'DELETE' THEN

    IF c.id IS NULL
       OR (
         c.data_saida IS NOT NULL
         AND c.data_saida <= NEW.data
       )
       OR c.data_admissao > NEW.data
    THEN
      RAISE EXCEPTION 'Colaborador indisponível nesta data.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.ausencias a
      WHERE a.colaborador_id = NEW.colaborador_id
        AND a.data = NEW.data
    )
    THEN
      RAISE EXCEPTION
        'Este colaborador está de férias/ausente nesta data.';
    END IF;

    IF u.id IS NOT NULL
       AND TG_OP = 'INSERT'
    THEN
      NEW.criado_por := u.id;
    END IF;

    IF TG_OP = 'UPDATE' THEN
      NEW.criado_por := OLD.criado_por;
    END IF;

  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END
$function$
;

CREATE OR REPLACE FUNCTION public.fn_quadro_renomear_interno(p_dados jsonb,p_confirmar boolean,p_versao text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; v_request uuid; v_kind text; v_old text; v_new text;
 v_operation public.quadro_operacoes; v_days jsonb; v_day jsonb; v_after jsonb; v_version text; v_result jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR NOT public.fn_quadro_pode_gerir_v1(NULL) THEN RAISE EXCEPTION 'PERMISSION_DENIED: só Administrativo/Gestão pode renomear linhas.' USING ERRCODE='42501'; END IF;
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
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
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

-- RPC v1 distinta da API antiga; p_dados transporta version, expected_revision e request_id.
CREATE OR REPLACE FUNCTION public.fn_quadro_operar_v1(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
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
 PERFORM pg_advisory_xact_lock(61001,1);
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
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: consulta sem edição.' USING ERRCODE='42501'; END IF;
 FOR v_row IN SELECT value FROM jsonb_array_elements(v_before||v_after) LOOP
  IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND (v_row->>'tipo_alocacao'<>'obra' OR NOT public.fn_quadro_minha_obra_v1((v_row->>'obra_id')::uuid))
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
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_empresa_id uuid;
  v_utilizador_id uuid := public.fn_utilizador_atual_id();
  v_colaborador public.colaboradores%rowtype;
  v_alocacao public.quadro_pessoal_alocacao%rowtype;
  v_semana_inicio date;
begin
  if p_origem not in ('cadastro_rh','importacao_rh') then raise exception 'VALIDATION_ERROR: origem RH inválida.'; end if;
  if public.fn_rh_empresa(false) is null then raise exception 'PERMISSION_DENIED: cadastro não autorizado.' using errcode='42501'; end if;
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
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT public.fn_quadro_criar_colaborador_interno(p_nome,p_funcao,p_data_admissao,p_data_nascimento,p_alocacao_tipo,p_obra_id,NULL,NULL,NULL,NULL,NULL,NULL,'cadastro_rh');
$function$;

CREATE OR REPLACE FUNCTION public.fn_criar_colaborador_com_alocacao(p_nome text, p_funcao text, p_data_admissao date, p_data_nascimento date, p_alocacao_tipo text, p_obra_id uuid, p_nivel text, p_valor_hora numeric, p_nif text, p_email text, p_contacto text, p_morada text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
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

  IF NOT EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current() AND p.colaborador_id=q.colaborador_id AND p.data=q.data) THEN
    INSERT INTO public.quadro_dias_revisoes(colaborador_id,data,revisao,obras_visiveis)
    VALUES(q.colaborador_id,q.data,1,ARRAY(SELECT DISTINCT x FROM unnest(ARRAY[(b->>'obra_id')::uuid,(a->>'obra_id')::uuid]) x WHERE x IS NOT NULL))
    ON CONFLICT(colaborador_id,data) DO UPDATE SET revisao=quadro_dias_revisoes.revisao+1,
    obras_visiveis=ARRAY(SELECT DISTINCT x FROM unnest(quadro_dias_revisoes.obras_visiveis||EXCLUDED.obras_visiveis) x);
    IF TG_OP='UPDATE' AND OLD.data IS DISTINCT FROM NEW.data THEN
      INSERT INTO public.quadro_dias_revisoes(colaborador_id,data,revisao,obras_visiveis) VALUES(OLD.colaborador_id,OLD.data,1,ARRAY[OLD.obra_id])
      ON CONFLICT(colaborador_id,data) DO UPDATE SET revisao=quadro_dias_revisoes.revisao+1;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION public.fn_quadro_contexto_v1(p_inicio date,p_fim date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE u public.utilizadores; v_allocations jsonb; v_revisions jsonb; v_read jsonb; v_edit jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 IF NOT public.fn_quadro_pode_consultar_v1() THEN RAISE EXCEPTION 'PERMISSION_DENIED: sem responsabilidade autorizada para consultar o Quadro.' USING ERRCODE='42501'; END IF;
 IF p_inicio IS NULL OR p_fim IS NULL OR p_fim<p_inicio OR p_fim-p_inicio>93 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo inválido.'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(q) ORDER BY q.data,q.id),'[]') INTO v_allocations
 FROM generate_series(p_inicio::timestamp,p_fim::timestamp,interval '1 day') d(data)
 CROSS JOIN LATERAL public.fn_quadro_resolver_data(d.data::date) q JOIN public.colaboradores c ON c.id=q.colaborador_id
 WHERE c.empresa_id=u.empresa_id AND q.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR (q.tipo_alocacao='obra' AND public.fn_quadro_ler_obra(q.obra_id)));
 SELECT coalesce(jsonb_agg(to_jsonb(d)),'[]') INTO v_revisions FROM public.quadro_dias_revisoes d
 JOIN public.colaboradores c ON c.id=d.colaborador_id WHERE c.empresa_id=u.empresa_id AND d.data BETWEEN p_inicio AND p_fim
 AND (public.fn_quadro_leitura_global_v1() OR EXISTS(SELECT 1 FROM unnest(d.obras_visiveis) w(id) WHERE public.fn_quadro_ler_obra(w.id)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a
 WHERE (a->>'colaborador_id')::uuid=d.colaborador_id AND (a->>'data')::date=d.data));
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_read FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id);
 SELECT coalesce(jsonb_agg(o.id ORDER BY o.id),'[]') INTO v_edit FROM public.obras o WHERE o.empresa_id=u.empresa_id AND (public.fn_quadro_pode_gerir_v1(o.id) OR public.fn_quadro_minha_obra_v1(o.id));
 RETURN jsonb_build_object('version',1,'allocations',v_allocations,'revisions',v_revisions,
 'can_manage_global',public.fn_quadro_pode_gerir_v1(NULL),'read_work_ids',v_read,'edit_work_ids',v_edit,
 'people',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nome',c.nome,'funcao',c.funcao,'data_admissao',c.data_admissao,'data_saida',c.data_saida) ORDER BY c.nome),'[]') FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND c.data_saida IS NULL AND (
 public.fn_quadro_leitura_global_v1() OR u.funcao='encarregado' OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_allocations) a WHERE (a->>'colaborador_id')::uuid=c.id))),
 'works',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'numero',o.numero,'nome',o.nome,'situacao',o.situacao) ORDER BY o.numero),'[]') FROM public.obras o WHERE o.empresa_id=u.empresa_id AND public.fn_quadro_ler_obra(o.id)));
END $$;


CREATE OR REPLACE FUNCTION public.fn_quadro_notificar_controlado_v1(p_colaborador uuid,p_data date,p_origem uuid,p_destino uuid,p_alocacao uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_atual public.utilizadores;
  v_colaborador public.colaboradores;
  v_origem_id uuid;
  v_destino_id uuid;
  v_origem_numero text;
  v_origem_nome text;
  v_destino_numero text;
  v_destino_nome text;
  v_titulo text;
  v_descricao text;
BEGIN
 SELECT * INTO v_atual FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE AND funcao='encarregado';
 IF v_atual.id IS NULL OR p_destino IS NULL OR p_origem IS NOT DISTINCT FROM p_destino THEN RETURN; END IF;
 v_origem_id:=p_origem; v_destino_id:=p_destino;
  SELECT *
  INTO v_colaborador
  FROM public.colaboradores
  WHERE id=p_colaborador
    AND empresa_id=v_atual.empresa_id;

  IF v_colaborador.id IS NULL THEN
    RAISE EXCEPTION 'Colaborador da movimentação não encontrado.';
  END IF;

  IF v_origem_id IS NOT NULL THEN
    SELECT o.numero::text,o.nome
    INTO v_origem_numero,v_origem_nome
    FROM public.obras o
    WHERE o.id=v_origem_id
      AND o.empresa_id=v_atual.empresa_id;
  END IF;

  SELECT o.numero::text,o.nome
  INTO v_destino_numero,v_destino_nome
  FROM public.obras o
  WHERE o.id=v_destino_id
    AND o.empresa_id=v_atual.empresa_id;

  IF v_destino_numero IS NULL THEN
    RAISE EXCEPTION 'Obra de destino da movimentação não encontrada.';
  END IF;

  v_titulo := 'Movimentação de equipa · ' || v_colaborador.nome;

  IF v_origem_id IS NULL THEN
    v_descricao := format(
      '%s foi adicionado à Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      v_destino_numero,
      v_destino_nome,
      to_char(p_data,'DD/MM/YYYY'),
      v_atual.nome
    );
  ELSE
    v_descricao := format(
      '%s foi movimentado da Obra %s · %s para a Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      coalesce(v_origem_numero,'—'),
      coalesce(v_origem_nome,'Obra de origem'),
      v_destino_numero,
      v_destino_nome,
      to_char(p_data,'DD/MM/YYYY'),
      v_atual.nome
    );
  END IF;

  WITH destinatarios AS (
    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      1 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='encarregado'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      2 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_destino_id AS obra_ref,
      3 AS prioridade
    FROM public.obra_responsaveis r
    WHERE r.obra_id=v_destino_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      u.id AS utilizador_id,
      v_destino_id AS obra_ref,
      4 AS prioridade
    FROM public.utilizadores u
    WHERE u.empresa_id=v_atual.empresa_id
      AND u.funcao='administrativo'
      AND u.ativo IS TRUE
      AND u.auth_user_id IS NOT NULL
  ),
  unicos AS (
    SELECT DISTINCT ON (d.utilizador_id)
      d.utilizador_id,
      d.obra_ref
    FROM destinatarios d
    WHERE d.utilizador_id IS NOT NULL
      AND d.utilizador_id IS DISTINCT FROM v_atual.id
    ORDER BY d.utilizador_id,d.prioridade
  )
  INSERT INTO public.alertas(
    empresa_id,
    obra_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado,
    enviar_email,
    destinatario_utilizador_id
  )
  SELECT
    v_atual.empresa_id,
    u.obra_ref,
    'movimentacao_equipa',
    'quadro_pessoal_alocacao',
    p_alocacao,
    v_titulo,
    v_descricao,
    p_data,
    0,
    current_date,
    destinatario.funcao,
    'pendente',
    false,
    destinatario.id
  FROM unicos u
  JOIN public.utilizadores destinatario
    ON destinatario.id=u.utilizador_id
   AND destinatario.empresa_id=v_atual.empresa_id
   AND destinatario.ativo IS TRUE
   AND destinatario.auth_user_id IS NOT NULL;

END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_quadro_notificar_movimentacao_encarregado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_atual public.utilizadores;
  v_permit public.quadro_pessoal_rpc_permit;
  v_colaborador public.colaboradores;
  v_origem_id uuid;
  v_destino_id uuid;
  v_origem_numero text;
  v_origem_nome text;
  v_destino_numero text;
  v_destino_nome text;
  v_titulo text;
  v_descricao text;
BEGIN
 IF EXISTS(SELECT 1 FROM public.quadro_escrita_interna p WHERE p.transacao=txid_current() AND p.colaborador_id=NEW.colaborador_id AND p.data=NEW.data) THEN RETURN NEW; END IF;
  IF TG_OP NOT IN ('INSERT','UPDATE') THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_atual
  FROM public.utilizadores
  WHERE id=public.fn_utilizador_atual_id()
    AND ativo IS TRUE
    AND funcao='encarregado';

  IF v_atual.id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.*
  INTO v_permit
  FROM public.quadro_pessoal_rpc_permit p
  WHERE p.transacao=txid_current()
    AND p.utilizador_id=v_atual.id
    AND p.colaborador_id=NEW.colaborador_id
    AND p.destino_id=NEW.obra_id
    AND p.data=NEW.data
    AND p.periodo=NEW.periodo
    AND (
      (TG_OP='INSERT' AND p.origem_id IS NULL)
      OR
      (TG_OP='UPDATE' AND p.origem_id=OLD.id)
    )
  LIMIT 1;

  IF v_permit.utilizador_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_origem_id := CASE WHEN TG_OP='UPDATE' THEN OLD.obra_id ELSE NULL END;
  v_destino_id := NEW.obra_id;

  IF TG_OP='UPDATE'
    AND v_origem_id IS NOT DISTINCT FROM v_destino_id
  THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_colaborador
  FROM public.colaboradores
  WHERE id=NEW.colaborador_id
    AND empresa_id=v_atual.empresa_id;

  IF v_colaborador.id IS NULL THEN
    RAISE EXCEPTION 'Colaborador da movimentação não encontrado.';
  END IF;

  IF v_origem_id IS NOT NULL THEN
    SELECT o.numero::text,o.nome
    INTO v_origem_numero,v_origem_nome
    FROM public.obras o
    WHERE o.id=v_origem_id
      AND o.empresa_id=v_atual.empresa_id;
  END IF;

  SELECT o.numero::text,o.nome
  INTO v_destino_numero,v_destino_nome
  FROM public.obras o
  WHERE o.id=v_destino_id
    AND o.empresa_id=v_atual.empresa_id;

  IF v_destino_numero IS NULL THEN
    RAISE EXCEPTION 'Obra de destino da movimentação não encontrada.';
  END IF;

  v_titulo := 'Movimentação de equipa · ' || v_colaborador.nome;

  IF v_origem_id IS NULL THEN
    v_descricao := format(
      '%s foi adicionado à Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      v_destino_numero,
      v_destino_nome,
      to_char(NEW.data,'DD/MM/YYYY'),
      v_atual.nome
    );
  ELSE
    v_descricao := format(
      '%s foi movimentado da Obra %s · %s para a Obra %s · %s em %s por %s.',
      v_colaborador.nome,
      coalesce(v_origem_numero,'—'),
      coalesce(v_origem_nome,'Obra de origem'),
      v_destino_numero,
      v_destino_nome,
      to_char(NEW.data,'DD/MM/YYYY'),
      v_atual.nome
    );
  END IF;

  WITH destinatarios AS (
    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      1 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='encarregado'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_origem_id AS obra_ref,
      2 AS prioridade
    FROM public.obra_responsaveis r
    WHERE v_origem_id IS NOT NULL
      AND r.obra_id=v_origem_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      r.utilizador_id,
      v_destino_id AS obra_ref,
      3 AS prioridade
    FROM public.obra_responsaveis r
    WHERE r.obra_id=v_destino_id
      AND r.papel='diretor_obra'

    UNION ALL

    SELECT
      u.id AS utilizador_id,
      v_destino_id AS obra_ref,
      4 AS prioridade
    FROM public.utilizadores u
    WHERE u.empresa_id=v_atual.empresa_id
      AND u.funcao='administrativo'
      AND u.ativo IS TRUE
      AND u.auth_user_id IS NOT NULL
  ),
  unicos AS (
    SELECT DISTINCT ON (d.utilizador_id)
      d.utilizador_id,
      d.obra_ref
    FROM destinatarios d
    WHERE d.utilizador_id IS NOT NULL
      AND d.utilizador_id IS DISTINCT FROM v_atual.id
    ORDER BY d.utilizador_id,d.prioridade
  )
  INSERT INTO public.alertas(
    empresa_id,
    obra_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado,
    enviar_email,
    destinatario_utilizador_id
  )
  SELECT
    v_atual.empresa_id,
    u.obra_ref,
    'movimentacao_equipa',
    'quadro_pessoal_alocacao',
    NEW.id,
    v_titulo,
    v_descricao,
    NEW.data,
    0,
    current_date,
    destinatario.funcao,
    'pendente',
    false,
    destinatario.id
  FROM unicos u
  JOIN public.utilizadores destinatario
    ON destinatario.id=u.utilizador_id
   AND destinatario.empresa_id=v_atual.empresa_id
   AND destinatario.ativo IS TRUE
   AND destinatario.auth_user_id IS NOT NULL;

  RETURN NEW;
END;
$function$
;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND (p.proname LIKE 'fn_quadro_%v1' OR p.proname IN('fn_quadro_resolver_data','fn_quadro_ler_obra','fn_quadro_dia_explicito','fn_quadro_renomear_interno','fn_quadro_aplicar_interno','fn_quadro_criar_colaborador_interno')) LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.signature);
 END LOOP; END $$;
GRANT EXECUTE ON FUNCTION public.fn_quadro_operar_v1(text,jsonb,boolean,text),public.fn_quadro_contexto_v1(date,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_quadro_operar(p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  u public.utilizadores;
  c public.colaboradores;
  src public.quadro_pessoal_alocacao;
  dest uuid;
  person uuid;
  day date;
  period text;
  kind text;
  description text;
  sid uuid;
  rows_before jsonb;
  v_version text;
  n integer;
  result_id uuid;
  manage boolean;
  result jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);

  SELECT *
  INTO u
  FROM public.utilizadores
  WHERE id = public.fn_utilizador_atual_id()
    AND ativo IS TRUE;

  IF u.id IS NULL THEN
    RAISE EXCEPTION 'Sessão sem utilizador ativo.'
    USING ERRCODE = '42501';
  END IF;

  manage := public.fn_pode_gerir_quadro(NULL);

  IF p_acao IS NULL
     OR p_acao NOT IN (
       'adicionar',
       'mover',
       'remover',
       'corrigir',
       'minha_obra'
     )
  THEN
    RAISE EXCEPTION 'Ação inválida.';
  END IF;

  IF NOT manage
     AND (
       u.funcao <> 'encarregado'
       OR p_acao <> 'minha_obra'
     )
  THEN
    RAISE EXCEPTION 'Sem autorização para editar o Quadro Geral.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao IN ('mover', 'remover', 'corrigir') THEN

    sid := nullif(p_dados->>'id', '')::uuid;

    SELECT *
    INTO src
    FROM public.quadro_pessoal_alocacao
    WHERE id = sid;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Alocação não encontrada; recarregue.';
    END IF;

    person := src.colaborador_id;

  ELSE

    person := (p_dados->>'colaborador_id')::uuid;

  END IF;

  SELECT *
  INTO c
  FROM public.colaboradores
  WHERE id = person
    AND empresa_id = u.empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Colaborador não autorizado.'
    USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(person::text, 0)
  );

  IF sid IS NOT NULL THEN

    SELECT *
    INTO src
    FROM public.quadro_pessoal_alocacao
    WHERE id = sid
    FOR UPDATE;

    IF NOT FOUND
       OR src.colaborador_id <> person
    THEN
      RAISE EXCEPTION 'Origem alterada; recarregue.';
    END IF;

  END IF;

  day := coalesce(
    (p_dados->>'data')::date,
    src.data
  );

  period := coalesce(
    p_dados->>'periodo',
    src.periodo
  );

  dest := nullif(p_dados->>'obra_id', '')::uuid;

  kind := coalesce(
    p_dados->>'tipo_alocacao',
    'obra'
  );

  description := nullif(
    btrim(p_dados->>'descricao_livre'),
    ''
  );

  IF p_acao = 'remover' THEN
    dest := src.obra_id;
    kind := src.tipo_alocacao;
    description := src.descricao_livre;
  END IF;

  IF day IS NULL
     OR period IS NULL
     OR period NOT IN ('manha', 'tarde', 'dia_inteiro')
  THEN
    RAISE EXCEPTION 'Indique data e período válidos.';
  END IF;

  IF p_acao <> 'remover'
     AND (
       (
         c.data_saida IS NOT NULL
         AND c.data_saida <= day
       )
       OR c.data_admissao > day
     )
  THEN
    RAISE EXCEPTION 'Colaborador indisponível nesta data.';
  END IF;

  IF kind NOT IN (
       'obra',
       'garantia',
       'pontual',
       'escritorio'
     )
     OR (
       kind = 'obra'
       AND dest IS NULL
     )
     OR (
       kind <> 'obra'
       AND (
         dest IS NOT NULL
         OR description IS NULL
       )
     )
  THEN
    RAISE EXCEPTION 'Destino inválido.';
  END IF;

  IF kind = 'obra' THEN
    description := NULL;
  END IF;

  IF dest IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.obras o
       WHERE o.id = dest
         AND o.empresa_id = u.empresa_id
     )
  THEN
    RAISE EXCEPTION 'Destino de outra empresa.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao = 'minha_obra'
     AND (
       kind <> 'obra'
       OR NOT public.fn_quadro_minha_obra(dest)
     )
  THEN
    RAISE EXCEPTION
      'Só pode adicionar à obra em que é Encarregado.'
    USING ERRCODE = '42501';
  END IF;

  IF p_acao <> 'remover'
     AND EXISTS (
       SELECT 1
       FROM public.ausencias a
       WHERE a.colaborador_id = person
         AND a.data = day
     )
  THEN
    RAISE EXCEPTION
      'Este colaborador está de férias/ausente nesta data.';
  END IF;

  SELECT coalesce(
           jsonb_agg(
             to_jsonb(q)
             ORDER BY q.id
           ),
           '[]'::jsonb
         )
  INTO rows_before
  FROM public.quadro_pessoal_alocacao q
  WHERE q.colaborador_id = person
    AND q.data = day
    AND (
      q.periodo = period
      OR q.periodo = 'dia_inteiro'
      OR period = 'dia_inteiro'
    );

  IF p_acao = 'minha_obra' THEN

    IF EXISTS (
      SELECT 1
      FROM public.quadro_pessoal_alocacao q
      WHERE q.colaborador_id = person
        AND q.data = day
        AND q.periodo = period
        AND q.obra_id = dest
        AND q.tipo_alocacao = 'obra'
        AND q.descricao_livre IS NULL
    )
    THEN
      RAISE EXCEPTION
        'Destino já existente: nenhuma origem foi removida.';
    END IF;

    n := jsonb_array_length(rows_before);

    IF n > 1 THEN
      RAISE EXCEPTION
        'Várias origens: peça a resolução ao ADM/Gestão. Nada foi alterado.';
    END IF;

    IF n = 1 THEN

      SELECT *
      INTO src
      FROM jsonb_populate_record(
        NULL::public.quadro_pessoal_alocacao,
        rows_before->0
      );

      IF src.periodo <> period THEN
        RAISE EXCEPTION
          'Sobreposição parcial: peça a resolução ao ADM/Gestão.';
      END IF;

      sid := src.id;

    END IF;

  END IF;

  IF p_acao <> 'remover'
     AND EXISTS (
       SELECT 1
       FROM public.quadro_pessoal_alocacao q
       WHERE q.colaborador_id = person
         AND q.data = day
         AND q.periodo = period
         AND q.obra_id IS NOT DISTINCT FROM dest
         AND q.tipo_alocacao = kind
         AND q.descricao_livre IS NOT DISTINCT FROM description
         AND q.id IS DISTINCT FROM sid
     )
  THEN
    RAISE EXCEPTION 'Alocação idêntica já existente.'
    USING ERRCODE = '23505';
  END IF;

  v_version := md5(
    jsonb_build_object(
      'linhas', rows_before,
      'origem', to_jsonb(src),
      'dados', p_dados,
      'acao', p_acao
    )::text
  );

  result := jsonb_build_object(
    'versao', v_version,
    'colaborador', c.nome,
    'origem_id', sid,
    'obra_origem_id', src.obra_id,
    'obra_destino_id', dest,
    'data', day,
    'periodo', period,
    'acao',
      CASE
        WHEN p_acao = 'minha_obra'
          THEN CASE
                 WHEN sid IS NULL THEN 'adicionar'
                 ELSE 'mover'
               END
        ELSE p_acao
      END
  );

  IF NOT p_confirmar THEN
    RETURN result
      || jsonb_build_object(
           'estado',
           'PREVISUALIZACAO'
         );
  END IF;

  IF p_versao IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION
      'Pré-visualização desatualizada. Consulte novamente.';
  END IF;

  IF NOT manage THEN

    INSERT INTO public.quadro_pessoal_rpc_permit
    VALUES (
      txid_current(),
      u.id,
      person,
      sid,
      dest,
      day,
      period
    );

  END IF;

  IF p_acao = 'remover' THEN

    DELETE FROM public.quadro_pessoal_alocacao
    WHERE id = sid;

    result_id := sid;

  ELSIF sid IS NOT NULL THEN

    UPDATE public.quadro_pessoal_alocacao
    SET
      obra_id = dest,
      data = day,
      periodo = period,
      semana_inicio =
        date_trunc(
          'week',
          day::timestamp
        )::date,
      tipo_alocacao = kind,
      descricao_livre = description
    WHERE id = sid
    RETURNING id INTO result_id;

  ELSE

    INSERT INTO public.quadro_pessoal_alocacao (
      colaborador_id,
      obra_id,
      data,
      periodo,
      semana_inicio,
      tipo_alocacao,
      descricao_livre,
      criado_por
    )
    VALUES (
      person,
      dest,
      day,
      period,
      date_trunc(
        'week',
        day::timestamp
      )::date,
      kind,
      description,
      u.id
    )
    RETURNING id INTO result_id;

  END IF;

  DELETE FROM public.quadro_pessoal_rpc_permit
  WHERE transacao = txid_current()
    AND utilizador_id = u.id;

  RETURN result
    || jsonb_build_object(
         'estado',
         'GUARDADO',
         'alocacao_id',
         result_id
       );

END
$function$
;

CREATE OR REPLACE FUNCTION primeline_quadro_rollout.identidade_a()
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
 SELECT md5(jsonb_build_object(
  'funcoes',(SELECT jsonb_agg(jsonb_build_object('assinatura',p.oid::regprocedure::text,'definicao',pg_get_functiondef(p.oid),'acl',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.grantee,x.privilege_type) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x),'owner',p.proowner,'config',p.proconfig,'sd',p.prosecdef) ORDER BY p.oid::regprocedure::text)
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.prokind IN('f','p') AND n.nspname='public' AND (p.proname LIKE 'fn_quadro_%' OR p.proname LIKE 'fn_rh_%' OR p.proname IN('fn_criar_colaborador_com_alocacao','fn_registar_movimento_quadro','fn_pode_gerir_quadro','fn_pode_consultar_quadro','fn_listar_ponto_obra','fn_guardar_ponto_obra') OR p.prosrc ILIKE '%quadro_pessoal_alocacao%' OR p.oid IN(SELECT tgfoid FROM pg_trigger WHERE tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT tgisinternal)) OR (p.prokind IN('f','p') AND n.nspname='primeline_quadro_rollout')),
  'tabelas',(SELECT jsonb_agg(jsonb_build_object('oid',c.oid,'owner',c.relowner,'acl',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.grantee,x.privilege_type) FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity) ORDER BY c.oid) FROM pg_class c WHERE c.oid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass)),
  'colunas',(SELECT jsonb_agg(jsonb_build_object('rel',a.attrelid,'nome',a.attname,'tipo',a.atttypid,'notnull',a.attnotnull,'acl',(SELECT jsonb_agg(to_jsonb(x) ORDER BY x.grantee,x.privilege_type) FROM aclexplode(a.attacl) x),'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attrelid,a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass) AND a.attnum>0 AND NOT a.attisdropped),
  'policies',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.tablename,p.policyname) FROM pg_policies p WHERE (p.schemaname='public' AND p.tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos','quadro_dias_revisoes','quadro_operacoes','quadro_escrita_interna')) OR p.schemaname='primeline_quadro_rollout'),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('def',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgrelid,t.tgname) FROM pg_trigger t WHERE t.tgrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass) AND NOT t.tgisinternal),
  'constraints',(SELECT jsonb_agg(jsonb_build_object('rel',c.conrelid,'nome',c.conname,'def',pg_get_constraintdef(c.oid)) ORDER BY c.conrelid,c.conname) FROM pg_constraint c WHERE c.conrelid IN('public.quadro_pessoal_alocacao'::regclass,'public.quadro_pessoal_movimentos'::regclass,'public.quadro_dias_revisoes'::regclass,'public.quadro_operacoes'::regclass,'public.quadro_escrita_interna'::regclass,'primeline_quadro_rollout.controlo'::regclass,'primeline_quadro_rollout.validacoes'::regclass))
 )::text);
$$;
CREATE OR REPLACE FUNCTION primeline_quadro_rollout.exigir_privacidade()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE r record; perfil text; privilegio text;
BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_quadro_rollout' AND pg_get_userbyid(nspowner)='postgres') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: owner do schema'; END IF;
 IF EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) x WHERE n.nspname='primeline_quadro_rollout' AND (x.grantee=0 OR pg_get_userbyid(x.grantee) IN('anon','authenticated','service_role'))) THEN RAISE EXCEPTION 'ROLLOUT_INVALID: ACL do schema'; END IF;
 FOR r IN SELECT c.* FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_quadro_rollout' AND c.relname IN('controlo','validacoes') LOOP
  IF pg_get_userbyid(r.relowner)<>'postgres' OR NOT r.relrowsecurity OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=r.oid) THEN RAISE EXCEPTION 'ROLLOUT_INVALID: owner/RLS/policy privada'; END IF;
  IF EXISTS(SELECT 1 FROM aclexplode(coalesce(r.relacl,acldefault('r',r.relowner))) x WHERE x.grantee=0) THEN RAISE EXCEPTION 'ROLLOUT_INVALID: PUBLIC tabela'; END IF;
  FOREACH perfil IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   FOREACH privilegio IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    IF has_table_privilege(perfil,r.oid,privilegio) THEN RAISE EXCEPTION 'ROLLOUT_INVALID: grant privado'; END IF;
   END LOOP;
   IF has_any_column_privilege(perfil,r.oid,'SELECT') OR has_any_column_privilege(perfil,r.oid,'INSERT') OR has_any_column_privilege(perfil,r.oid,'UPDATE') OR has_any_column_privilege(perfil,r.oid,'REFERENCES') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: grant coluna privada'; END IF;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_quadro_rollout' AND c.relname IN('controlo','validacoes'))<>2 THEN RAISE EXCEPTION 'ROLLOUT_INVALID: tabela ausente'; END IF;
 FOR r IN SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='primeline_quadro_rollout' LOOP
  IF pg_get_userbyid(r.proowner)<>'postgres' OR r.prosecdef OR r.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, pg_temp']::text[] THEN RAISE EXCEPTION 'ROLLOUT_INVALID: helper privado'; END IF;
  IF EXISTS(SELECT 1 FROM aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) x WHERE x.grantee=0) THEN RAISE EXCEPTION 'ROLLOUT_INVALID: PUBLIC helper'; END IF;
  FOREACH perfil IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(perfil,r.oid,'EXECUTE') THEN RAISE EXCEPTION 'ROLLOUT_INVALID: EXECUTE helper'; END IF;
  END LOOP;
 END LOOP;
END;
$$;
CREATE OR REPLACE FUNCTION primeline_quadro_rollout.exigir_fase_a()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE c primeline_quadro_rollout.controlo;
BEGIN
 PERFORM primeline_quadro_rollout.exigir_privacidade();
 IF (SELECT count(*) FROM primeline_quadro_rollout.controlo)<>1 THEN RAISE EXCEPTION 'ROLLOUT_INVALID: instalação ausente'; END IF;
 SELECT * INTO STRICT c FROM primeline_quadro_rollout.controlo WHERE singleton;
 IF c.estado<>'a' OR c.contract_version<>1 OR c.frontend_release_id<>'quadro_frontend_contract_v1' OR c.fase_b_aplicada_em IS NOT NULL THEN RAISE EXCEPTION 'ROLLOUT_INVALID: Fase A/contrato incoerente'; END IF;
 IF c.identidade_a IS DISTINCT FROM primeline_quadro_rollout.identidade_a() THEN RAISE EXCEPTION 'ROLLOUT_DRIFT: definições/ACL/policies/triggers/writers da Fase A divergentes'; END IF;
END;
$$;
CREATE OR REPLACE FUNCTION primeline_quadro_rollout.exigir_validacao()
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $$
DECLARE c primeline_quadro_rollout.controlo; v primeline_quadro_rollout.validacoes;
BEGIN
 PERFORM primeline_quadro_rollout.exigir_fase_a();
 SELECT * INTO STRICT c FROM primeline_quadro_rollout.controlo WHERE singleton FOR UPDATE;
 SELECT * INTO v FROM primeline_quadro_rollout.validacoes WHERE instalacao_id=c.instalacao_id AND tentativa=c.tentativa FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'FRONTEND_VALIDATION_REQUIRED: validar operacionalmente e executar script do owner'; END IF;
 IF v.contract_version<>c.contract_version OR v.frontend_release_id<>c.frontend_release_id OR v.frontend_validado_por<>'postgres' OR v.frontend_validado_em<GREATEST(c.instalada_em,c.tentativa_iniciada_em) OR v.frontend_validado_em>clock_timestamp() OR v.identidade_a IS DISTINCT FROM c.identidade_a OR v.consumida_em IS NOT NULL OR v.invalidada_em IS NOT NULL THEN RAISE EXCEPTION 'FRONTEND_VALIDATION_INVALID: contrato/release/instalação/tentativa incoerente ou já consumida'; END IF;
 RETURN v.id;
END;
$$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA primeline_quadro_rollout FROM PUBLIC,anon,authenticated,service_role;
UPDATE primeline_quadro_rollout.validacoes SET invalidada_em=clock_timestamp()
WHERE invalidada_em IS NULL;
UPDATE primeline_quadro_rollout.controlo
SET instalacao_id=gen_random_uuid(),tentativa=tentativa+1,estado='a',identidade_a=primeline_quadro_rollout.identidade_a(),instalada_em=clock_timestamp(),tentativa_iniciada_em=clock_timestamp(),fase_b_aplicada_em=NULL WHERE singleton;
COMMIT;
