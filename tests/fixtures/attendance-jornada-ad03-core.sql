-- AD-03: private, versioned individual references. No assignments or activation on install.
CREATE FUNCTION folha_privado.jornada_ad03_semana_valida(s jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $week$
DECLARE i integer;d jsonb;
BEGIN
 IF jsonb_typeof(s) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(s))<>7 THEN RETURN false; END IF;
 FOR i IN 1..7 LOOP
  d:=s->i::text;
  IF jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  IF d->>'day_type'='desconhecida' THEN
   IF d->'intervals' IS DISTINCT FROM '[]'::jsonb OR d->'expected_minutes' IS DISTINCT FROM 'null'::jsonb THEN RETURN false; END IF;
  ELSIF d->>'day_type' IN('prevista','folga') THEN
   IF folha_privado.horario_ad13_valido(d,false) IS NOT TRUE OR (d->>'day_type'='prevista' AND (d->>'expected_minutes')::integer<=0) THEN RETURN false; END IF;
  ELSE RETURN false; END IF;
 END LOOP;
 RETURN true;
END $week$;
CREATE FUNCTION folha_privado.jornada_ad03_modelo(m text) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $model$
DECLARE s jsonb:='{}';d jsonb;i integer;
BEGIN
 IF m NOT IN('operacional','tecnica') OR m IS NULL THEN RAISE EXCEPTION 'JORNADA_MODEL_REQUIRED'; END IF;
 FOR i IN 1..7 LOOP
  IF i>5 THEN d:=jsonb_build_object('day_type','folga','intervals','[]'::jsonb,'expected_minutes',0);
  ELSE
   d:=jsonb_build_object('day_type','prevista','expected_minutes',480,'intervals',
    CASE WHEN m='tecnica' AND i<5 THEN '[{"start":"09:00","end":"13:00","period":"manha"},{"start":"14:00","end":"18:00","period":"tarde"}]'::jsonb
     WHEN m='tecnica' THEN '[{"start":"08:00","end":"13:00","period":"manha"},{"start":"14:00","end":"17:00","period":"tarde"}]'::jsonb
     ELSE '[{"start":"08:00","end":"12:00","period":"manha"},{"start":"13:00","end":"17:00","period":"tarde"}]'::jsonb END);
  END IF;s:=s||jsonb_build_object(i::text,d);
 END LOOP;RETURN s;
END $model$;
CREATE TABLE public.folha_jornadas_individuais_versoes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id),modelo text NOT NULL CHECK(modelo IN('operacional','tecnica','personalizado')),
 semana jsonb NOT NULL CHECK(folha_privado.jornada_ad03_semana_valida(semana) IS TRUE),
 revision integer NOT NULL CHECK(revision>0),vigente_desde date NOT NULL,vigente_ate date,
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id),criado_em timestamptz NOT NULL DEFAULT now(),
 request_id uuid NOT NULL,motivo text NOT NULL CHECK(length(btrim(motivo)) BETWEEN 1 AND 1000),
 evidencia jsonb NOT NULL CHECK(jsonb_typeof(evidencia)='object' AND evidencia<>'{}'),
 CHECK(modelo='personalizado' OR semana=folha_privado.jornada_ad03_modelo(modelo)),
 UNIQUE(empresa_id,colaborador_id,revision),CHECK(vigente_ate IS NULL OR vigente_ate>vigente_desde)
);
ALTER TABLE public.folha_jornadas_individuais_versoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.folha_jornadas_individuais_versoes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION folha_privado.jornada_ad03_guardar() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $guard$
DECLARE cut date;
BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'CONTROLLED_JORNADA_WRITER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'JORNADA_HISTORY_IMMUTABLE'; END IF;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=NEW.colaborador_id AND empresa_id=NEW.empresa_id)
  OR NOT EXISTS(SELECT 1 FROM public.utilizadores WHERE id=NEW.criado_por AND empresa_id=NEW.empresa_id AND (TG_OP='UPDATE' OR (ativo AND funcao IN('administrativo','gestao_plataforma')))) THEN RAISE EXCEPTION 'JORNADA_TENANT_ACTOR_CONFLICT' USING ERRCODE='42501'; END IF;
 SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=NEW.empresa_id;
 IF cut IS NULL OR NEW.vigente_desde<cut THEN RAISE EXCEPTION 'JORNADA_ACTIVATION_BOUNDARY'; END IF;
 IF TG_OP='UPDATE' AND ROW(NEW.id,NEW.empresa_id,NEW.colaborador_id,NEW.modelo,NEW.semana,NEW.revision,NEW.vigente_desde,NEW.criado_por,NEW.criado_em,NEW.request_id,NEW.motivo,NEW.evidencia)
 IS DISTINCT FROM ROW(OLD.id,OLD.empresa_id,OLD.colaborador_id,OLD.modelo,OLD.semana,OLD.revision,OLD.vigente_desde,OLD.criado_por,OLD.criado_em,OLD.request_id,OLD.motivo,OLD.evidencia) THEN RAISE EXCEPTION 'JORNADA_HISTORY_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND OLD.vigente_ate IS NOT NULL AND NEW.vigente_ate IS DISTINCT FROM OLD.vigente_ate THEN RAISE EXCEPTION 'JORNADA_HISTORY_IMMUTABLE'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_jornadas_individuais_versoes v WHERE v.empresa_id=NEW.empresa_id AND v.colaborador_id=NEW.colaborador_id AND v.id<>NEW.id AND daterange(v.vigente_desde,v.vigente_ate,'[)') && daterange(NEW.vigente_desde,NEW.vigente_ate,'[)')) THEN RAISE EXCEPTION 'JORNADA_VERSION_OVERLAP'; END IF;
 IF TG_OP='UPDATE' AND EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias WHERE jornada_versao_id=NEW.id AND data>=NEW.vigente_ate) THEN RAISE EXCEPTION 'JORNADA_FROZEN_REFERENCE_CONFLICT'; END IF;
 RETURN NEW;
END $guard$;
ALTER TABLE public.folha_avaliacoes_diarias ADD COLUMN jornada_versao_id uuid REFERENCES public.folha_jornadas_individuais_versoes(id) ON DELETE RESTRICT;
CREATE TRIGGER folha_jornada_ad03_guardar BEFORE INSERT OR UPDATE OR DELETE ON public.folha_jornadas_individuais_versoes FOR EACH ROW EXECUTE FUNCTION folha_privado.jornada_ad03_guardar();
CREATE FUNCTION folha_privado.jornada_ad03_avaliacao_valida(a public.folha_avaliacoes_diarias) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $reference$
 SELECT (CASE WHEN a.referencia_origem='individual' THEN
  a.referencia_estado='capturada' AND a.jornada_versao_id IS NOT NULL AND a.permanencia_id IS NULL AND a.permanencia_snapshot IS NULL AND a.obra_origem_id IS NULL AND a.horario_versao_id IS NULL
  AND EXISTS(SELECT 1 FROM public.folha_jornadas_individuais_versoes v WHERE v.id=a.jornada_versao_id AND v.empresa_id=a.empresa_id AND v.colaborador_id=a.colaborador_id
   AND v.vigente_desde<=a.data AND (v.vigente_ate IS NULL OR v.vigente_ate>a.data)
   AND a.horario_snapshot=v.semana->extract(isodow FROM a.data)::integer::text
   AND a.expected_minutes=(a.horario_snapshot->>'expected_minutes')::integer
   AND a.referencia_evidencia=v.evidencia||jsonb_build_object('jornada_versao_id',v.id,'modelo',v.modelo,'revision',v.revision))
 ELSE a.jornada_versao_id IS NULL END
 AND (a.referencia_estado<>'capturada' OR folha_privado.horario_ad13_valido(a.horario_snapshot,a.referencia_origem='automatico') IS TRUE)) IS TRUE
$reference$;
ALTER TABLE public.folha_avaliacoes_diarias ADD CONSTRAINT folha_jornada_ad03_reference CHECK(folha_privado.jornada_ad03_avaliacao_valida(folha_avaliacoes_diarias.*) IS TRUE);
CREATE OR REPLACE FUNCTION folha_privado.diaria_referencia(p uuid,d date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $resolver$
DECLARE u public.utilizadores;cut date;m public.quadro_equipa_permanencias;v public.folha_horarios_versoes;j public.folha_jornadas_individuais_versoes;s jsonb;reason text;
BEGIN
 u:=folha_privado.ator();
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 IF cut IS NULL THEN RAISE EXCEPTION 'DAILY_NOT_ACTIVATED'; END IF;
 IF d<cut THEN reason:='historico_anterior_ao_corte';
 ELSE
  SELECT * INTO j FROM public.folha_jornadas_individuais_versoes WHERE empresa_id=u.empresa_id AND colaborador_id=p AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d);
  IF j.id IS NOT NULL THEN
   s:=j.semana->extract(isodow FROM d)::integer::text;
   IF s->>'day_type'='desconhecida' THEN reason:='jornada_individual_desconhecida';
   ELSE RETURN jsonb_build_object('referencia_estado','capturada','referencia_origem','individual','jornada_versao_id',j.id,
    'horario_snapshot',s,'expected_minutes',s->'expected_minutes','referencia_motivo',j.motivo,
    'referencia_evidencia',j.evidencia||jsonb_build_object('jornada_versao_id',j.id,'modelo',j.modelo,'revision',j.revision),
    'contexto_snapshot',jsonb_build_object('data_ativacao',cut,'regra','diaria_v1','fonte','jornada_individual','modelo',j.modelo,'revision',j.revision)); END IF;
  ELSIF (SELECT count(*) FROM public.quadro_equipa_permanencias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d))<>1 THEN reason:='origem_principal_nao_inequivoca';
  ELSE
   SELECT * INTO m FROM public.quadro_equipa_permanencias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d);
   SELECT * INTO v FROM public.folha_horarios_versoes WHERE obra_id=m.obra_id AND empresa_id=u.empresa_id AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d);
   IF v.id IS NULL THEN reason:='horario_sem_vigencia_comprovada'; END IF;
  END IF;
 END IF;
 RETURN jsonb_build_object('referencia_estado',CASE WHEN reason IS NULL THEN 'capturada' ELSE 'pendente' END,'referencia_origem','automatico',
 'permanencia_id',m.id,'obra_origem_id',m.obra_id,'horario_versao_id',v.id,'permanencia_snapshot',CASE WHEN reason IS NULL THEN to_jsonb(m) END,
 'horario_snapshot',CASE WHEN reason IS NULL THEN v.snapshot||jsonb_build_object('obra_id',v.obra_id,'empresa_id',v.empresa_id,'revision',v.revision,'versao_id',v.id,'vigente_desde',v.vigente_desde,'vigente_ate',v.vigente_ate) END,
 'expected_minutes',CASE WHEN reason IS NULL THEN (v.snapshot->>'expected_minutes')::integer END,'referencia_motivo',reason,
 'contexto_snapshot',jsonb_build_object('data_ativacao',cut,'regra','diaria_v1'));
END $resolver$;
CREATE FUNCTION public.fn_folha_jornadas_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $rpc$
DECLARE u public.utilizadores;c public.colaboradores;v public.folha_jornadas_individuais_versoes;req uuid;person uuid;cut date;d date;today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date;
 item jsonb;week jsonb;model text;reason text;before jsonb:='[]';preview jsonb:='[]';payload jsonb;token text;outcome jsonb;op folha_privado.operacoes;result_items jsonb:='[]';rev integer;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator();SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL OR (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) OR p_dados ? 'work_id' THEN RAISE EXCEPTION 'JORNADA_TENANT_CONTEXT' USING ERRCODE='42501'; END IF;
 IF p_acao='read' THEN
  person:=(p_dados->>'person_id')::uuid;
  SELECT * INTO c FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR SHARE;
  IF c.id IS NULL OR (u.funcao NOT IN('administrativo','gestao_plataforma','gerencia') AND NOT (u.funcao IN('encarregado','diretor_obra','adjunto','preparador') AND c.utilizador_id=u.id)) THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('version',2,'committed',false,'versions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY revision) FROM public.folha_jornadas_individuais_versoes x WHERE empresa_id=u.empresa_id AND colaborador_id=person),'[]'::jsonb));
 END IF;
 IF u.funcao NOT IN('administrativo','gestao_plataforma') THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo/Gestão' USING ERRCODE='42501'; END IF;
 IF p_acao='propose' THEN
  RETURN jsonb_build_object('version',2,'committed',false,'people',coalesce((SELECT jsonb_agg(jsonb_build_object('person_id',x.id,'name',x.nome,'role',x.funcao,
   'proposed_model',CASE WHEN lower(btrim(x.funcao)) IN('encarregado','pedreiro','servente') THEN 'operacional' WHEN lower(btrim(x.funcao)) IN('diretor de obra','diretor_obra','adjunto','adjunta','preparador') THEN 'tecnica' ELSE NULL END,
   'requires_role_confirmation',true,'already_approved',EXISTS(SELECT 1 FROM public.folha_jornadas_individuais_versoes j WHERE j.empresa_id=u.empresa_id AND j.colaborador_id=x.id)) ORDER BY x.nome,x.id)
   FROM public.colaboradores x WHERE x.empresa_id=u.empresa_id AND x.data_admissao<=today AND (x.data_saida IS NULL OR x.data_saida>today)),'[]'::jsonb));
 END IF;
 IF p_acao<>'assign' THEN RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF p_confirmar IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 OR jsonb_typeof(p_dados->'people') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'people') NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 req:=(p_dados->>'request_id')::uuid;d:=(p_dados->>'effective_from')::date;reason:=nullif(btrim(p_dados->>'reason'),'');
 IF req IS NULL OR d IS NULL OR reason IS NULL OR length(reason)>1000 OR jsonb_typeof(p_dados->'evidence') IS DISTINCT FROM 'object' OR p_dados->'evidence'='{}' THEN RAISE EXCEPTION 'JORNADA_EVIDENCE_REQUIRED'; END IF;
 SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id FOR SHARE;
 IF cut IS NULL OR d<cut THEN RAISE EXCEPTION 'JORNADA_ACTIVATION_BOUNDARY'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'people') x GROUP BY x->>'person_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'DUPLICATE_PERSON'; END IF;
 -- Every target is authorized before idempotency replay. Tenant never comes from the payload.
 FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'person_id' LOOP
  person:=(item->>'person_id')::uuid;SELECT * INTO c FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR SHARE;
  IF c.id IS NULL OR c.data_admissao IS NULL OR c.data_admissao>d OR (c.data_saida IS NOT NULL AND c.data_saida<=d) THEN RAISE EXCEPTION 'JORNADA_PERSON_DENIED' USING ERRCODE='42501'; END IF;
 END LOOP;
 payload:=jsonb_build_object('action','jornada_assign','data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;RETURN op.resultado; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'person_id' LOOP
  person:=(item->>'person_id')::uuid;
  SELECT * INTO c FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR SHARE;
  SELECT * INTO v FROM public.folha_jornadas_individuais_versoes WHERE empresa_id=u.empresa_id AND colaborador_id=person ORDER BY revision DESC LIMIT 1 FOR UPDATE;
  rev:=coalesce(v.revision,0);
  IF (item->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
  IF rev=0 AND d<>cut THEN RAISE EXCEPTION 'INITIAL_JORNADA_MUST_START_AT_ACTIVATION'; END IF;
  IF rev>0 AND (d<=v.vigente_desde OR d<today) THEN RAISE EXCEPTION 'JORNADA_HISTORICAL_CORRECTION_REQUIRES_DAILY_ACTION'; END IF;
  -- Existing evaluations keep their frozen source. The version guard refuses crossing references to the previous individual version.
  model:=item->>'model';
  week:=CASE WHEN model='personalizado' THEN item->'week' ELSE folha_privado.jornada_ad03_modelo(model) END;
  IF folha_privado.jornada_ad03_semana_valida(week) IS NOT TRUE THEN RAISE EXCEPTION 'JORNADA_WEEK_INCOHERENT' USING ERRCODE='23514'; END IF;
  before:=before||jsonb_build_array(to_jsonb(v));
  preview:=preview||jsonb_build_array(jsonb_build_object('person_id',person,'name',c.nome,'role',c.funcao,'model',model,'week',week,'effective_from',d,'revision',rev+1));
 END LOOP;
 token:=encode(sha256(convert_to(jsonb_build_array(payload,before,preview,cut)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',preview); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(preview) LOOP
  person:=(item->>'person_id')::uuid;
  UPDATE public.folha_jornadas_individuais_versoes SET vigente_ate=d WHERE empresa_id=u.empresa_id AND colaborador_id=person AND vigente_ate IS NULL;
  INSERT INTO public.folha_jornadas_individuais_versoes(empresa_id,colaborador_id,modelo,semana,revision,vigente_desde,criado_por,request_id,motivo,evidencia)
  VALUES(u.empresa_id,person,item->>'model',item->'week',(item->>'revision')::integer,d,u.id,req,reason,p_dados->'evidence') RETURNING * INTO v;
  INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason) VALUES(u.empresa_id,'jornada_assign',v.id,before,to_jsonb(v),u.id,req,reason);
  result_items:=result_items||jsonb_build_array(to_jsonb(v));
 END LOOP;
 outcome:=jsonb_build_object('version',2,'committed',true,'request_id',req,'result',result_items);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,outcome,now());RETURN outcome;
END $rpc$;
REVOKE ALL ON FUNCTION public.fn_folha_jornadas_v2(text,jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_jornadas_v2(text,jsonb,boolean,text) TO authenticated;
REVOKE ALL ON FUNCTION folha_privado.jornada_ad03_semana_valida(jsonb),folha_privado.jornada_ad03_modelo(text),folha_privado.jornada_ad03_guardar(),folha_privado.jornada_ad03_avaliacao_valida(public.folha_avaliacoes_diarias) FROM PUBLIC,anon,authenticated,service_role;
