BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_registos,public.folha_he,public.folha_vencimentos,public.folha_gestao_historico,public.quadro_equipa_permanencias,public.quadro_pessoal_movimentos,public.colaboradores,public.utilizadores,public.obra_responsaveis,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $gate$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.diaria_referencia(uuid,date)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='92656230c0e08b57cc26a3ad1f470aaad11ac5ea5ebe50aac8ac83ccd45afbc0') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: folha_privado.diaria_referencia(uuid,date)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.diaria_recalcular(uuid,date,uuid)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='f4792d1bd2ff48eb1f5f97892e98173f6eda6c090242affa29864079266c660c') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: folha_privado.diaria_recalcular(uuid,date,uuid)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='3c9c590954b2f6f251fd213536308c4ee0a0b1b871e83aef5073c652d81cd2cf') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.horario_ad13_valido(jsonb,boolean)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='3e668595095a484963096d2186316aa31952eb54702e1033059c187e325a9b97') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: folha_privado.horario_ad13_valido(jsonb,boolean)';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='folha_privado.horario_ad13_guardar()'::regprocedure AND proowner='postgres'::regrole AND prosecdef=false AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='5cc91e6ad5a046b77b0253d7a6ecc04dd9d385a40cce48bbc5421cffe3ee0a50') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: folha_privado.horario_ad13_guardar()';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=true AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='1a94aed677d3c180568bab8f4df993514f938a0bc4c92e20c12fcf55905bd89f') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)';END IF;
IF to_regclass('public.folha_jornadas_individuais_versoes') IS NOT NULL OR to_regprocedure('public.fn_folha_jornadas_v2(text,jsonb,boolean,text)') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_avaliacoes_diarias'::regclass AND attname='jornada_versao_id' AND NOT attisdropped) OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname LIKE 'jornada_ad03_%') THEN RAISE EXCEPTION 'AD03_PRESENT_OR_PARTIAL';END IF;
IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE folha_privado.diaria_ad14_valida(a,true) IS NOT TRUE) THEN RAISE EXCEPTION 'AD03_EXISTING_EVALUATION_INVALID';END IF;
IF EXISTS(SELECT 1 FROM public.folha_horarios WHERE folha_privado.horario_ad13_valido(jsonb_build_object('intervals',intervals,'expected_minutes',expected_minutes),true) IS NOT TRUE) OR EXISTS(SELECT 1 FROM public.folha_horarios_versoes WHERE folha_privado.horario_ad13_valido(snapshot,true) IS NOT TRUE) THEN RAISE EXCEPTION 'AD03_EXISTING_SCHEDULE_INVALID';END IF;
END $gate$;
DO $data$ DECLARE r record;j jsonb;BEGIN
IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad03_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad03_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD03_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_ad03_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD03_DATA_DRIFT: %',r.tabela;END IF;END LOOP;END $data$;
CREATE OR REPLACE FUNCTION folha_privado.horario_ad13_valido(p_snapshot jsonb,p_normal boolean) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $validator$
DECLARE valid boolean; x jsonb; n integer; s integer; e integer; last_end integer; total integer; expected numeric;
BEGIN
 IF p_normal IS FALSE AND jsonb_typeof(p_snapshot)='object' AND p_snapshot->>'day_type'='folga' THEN RETURN (p_snapshot->'expected_minutes'='0'::jsonb AND p_snapshot->'intervals'='[]'::jsonb) IS TRUE;END IF;
 IF p_normal IS FALSE AND p_snapshot ? 'day_type' AND p_snapshot->>'day_type' IS DISTINCT FROM 'prevista' THEN RETURN false;END IF;
 valid:=false;last_end:=-1;total:=0;n:=0;
 <<validate_snapshot>> BEGIN
  IF p_normal IS NULL OR p_snapshot IS NULL OR jsonb_typeof(p_snapshot) IS DISTINCT FROM 'object' OR jsonb_typeof(p_snapshot->'intervals') IS DISTINCT FROM 'array' OR jsonb_typeof(p_snapshot->'expected_minutes') IS DISTINCT FROM 'number' THEN EXIT validate_snapshot; END IF;
  IF p_snapshot->>'expected_minutes' !~ '^[1-9][0-9]*$' THEN EXIT validate_snapshot; END IF;
  expected:=(p_snapshot->>'expected_minutes')::numeric;
  IF expected<>trunc(expected) OR expected NOT BETWEEN 1 AND 1440 OR jsonb_array_length(p_snapshot->'intervals') NOT BETWEEN 1 AND 16 OR (p_normal AND jsonb_array_length(p_snapshot->'intervals')<>2) THEN EXIT validate_snapshot; END IF;
  FOR x IN SELECT value FROM jsonb_array_elements(p_snapshot->'intervals') ORDER BY value->>'start' LOOP
   n:=n+1;
   IF jsonb_typeof(x) IS DISTINCT FROM 'object' OR jsonb_typeof(x->'start') IS DISTINCT FROM 'string' OR jsonb_typeof(x->'end') IS DISTINCT FROM 'string' OR coalesce(x->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(x->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN EXIT validate_snapshot; END IF;
   IF p_normal AND (x->>'period' IS DISTINCT FROM CASE n WHEN 1 THEN 'manha' ELSE 'tarde' END OR (x ? 'mode' AND x->>'mode' IS DISTINCT FROM 'normal')) THEN EXIT validate_snapshot; END IF;
   s:=split_part(x->>'start',':',1)::integer*60+split_part(x->>'start',':',2)::integer;
   e:=split_part(x->>'end',':',1)::integer*60+split_part(x->>'end',':',2)::integer;
   IF e<=s OR s<last_end THEN EXIT validate_snapshot; END IF;
   total:=total+e-s;last_end:=e;
  END LOOP;
  valid:=total=expected;
 END validate_snapshot;
 RETURN valid;
END $validator$;
DO $constraints$ DECLARE r record;def text;BEGIN
FOR r IN SELECT conname,pg_get_constraintdef(oid) def FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND contype='c' AND (pg_get_constraintdef(oid) LIKE '%expected_minutes >= 1%' OR pg_get_constraintdef(oid) LIKE '%referencia_origem = ANY%') LOOP
def:=replace(r.def,'expected_minutes >= 1','expected_minutes >= 0');def:=replace(def,'''administrativo''::text]', '''administrativo''::text, ''individual''::text]');
EXECUTE format('ALTER TABLE public.folha_avaliacoes_diarias DROP CONSTRAINT %I',r.conname);EXECUTE format('ALTER TABLE public.folha_avaliacoes_diarias ADD CONSTRAINT %I %s',r.conname,def);END LOOP;END $constraints$;
DO $history$ DECLARE n text;d text;BEGIN
SELECT conname,pg_get_constraintdef(oid) INTO STRICT n,d FROM pg_constraint WHERE conrelid='public.folha_gestao_historico'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%action = ANY%';
d:=replace(d,'''schedule_retro_correct''::text]', '''schedule_retro_correct''::text, ''jornada_assign''::text]');
EXECUTE format('ALTER TABLE public.folha_gestao_historico DROP CONSTRAINT %I',n);EXECUTE format('ALTER TABLE public.folha_gestao_historico ADD CONSTRAINT %I %s',n,d);END $history$;
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



CREATE OR REPLACE FUNCTION folha_privado.diaria_ad14_valida(r public.folha_avaliacoes_diarias,p_final boolean) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $validator$
 SELECT ((
 jsonb_typeof(a.contexto_snapshot)='object' AND a.contexto_snapshot->>'regra'='diaria_v1'
 AND jsonb_typeof(a.contexto_snapshot->'data_ativacao')='string'
 AND a.contexto_snapshot->>'data_ativacao' ~ '^\d{4}-\d{2}-\d{2}$'
 AND CASE WHEN jsonb_typeof(a.factos_revisoes)='array' THEN
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x WHERE
   (jsonb_typeof(x)='object' AND jsonb_typeof(x->'id')='string' AND x->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND jsonb_typeof(x->'revision')='number' AND x->>'revision' ~ '^[1-9][0-9]*$') IS NOT TRUE)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x GROUP BY x->>'id' HAVING count(*)>1)
 ELSE false END
 AND coalesce(array_ndims(a.pendencias),1)=1 AND array_position(a.pendencias,NULL) IS NULL
 AND NOT EXISTS(SELECT 1 FROM unnest(a.pendencias) x WHERE nullif(btrim(x),'') IS NULL)
 AND cardinality(a.pendencias)=(SELECT count(DISTINCT x) FROM unnest(a.pendencias) x)
 AND CASE WHEN a.referencia_estado='pendente' THEN
  a.expected_minutes IS NULL AND a.horario_snapshot IS NULL
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=0
  AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL AND a.referencia_origem='automatico'
 ELSE
  a.expected_minutes IS NOT NULL AND a.expected_minutes BETWEEN 0 AND 1440
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=3
  AND CASE WHEN jsonb_typeof(a.horario_snapshot)='object' AND jsonb_typeof(a.horario_snapshot->'intervals')='array' THEN
   jsonb_typeof(a.horario_snapshot->'expected_minutes')='number'
   AND a.horario_snapshot->>'expected_minutes'=a.expected_minutes::text
   AND (jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16 OR (a.expected_minutes=0 AND a.horario_snapshot->>'day_type'='folga' AND a.horario_snapshot->'intervals'='[]'::jsonb))
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.horario_snapshot->'intervals') x WHERE
    (jsonb_typeof(x)='object' AND jsonb_typeof(x->'start')='string' AND jsonb_typeof(x->'end')='string'
     AND x->>'start' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND x->>'end' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     AND x->>'end'>x->>'start') IS NOT TRUE)
  ELSE false END
  AND CASE WHEN a.referencia_origem='automatico' THEN
   num_nonnulls(a.permanencia_id,a.obra_origem_id,a.horario_versao_id)=3
   AND jsonb_typeof(a.permanencia_snapshot)='object'
   AND a.permanencia_snapshot->>'id'=a.permanencia_id::text
   AND a.permanencia_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.permanencia_snapshot->>'colaborador_id'=a.colaborador_id::text
   AND a.permanencia_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.horario_snapshot->>'versao_id'=a.horario_versao_id::text
  ELSE
   a.permanencia_id IS NULL AND a.permanencia_snapshot IS NULL AND a.horario_versao_id IS NULL
   AND jsonb_typeof(a.referencia_evidencia)='object' AND a.referencia_evidencia<>'{}'::jsonb
   AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL
  END
 END
 AND CASE WHEN a.he_estado IN('validada','nao_considerada') THEN
  a.excedente_minutes IS NOT NULL AND a.excedente_minutes>0
  AND num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=4
  AND a.decisao_fingerprint ~ '^[0-9a-f]{64}$' AND nullif(btrim(a.he_motivo),'') IS NOT NULL
 ELSE num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=0 END) AND (NOT p_final OR (
 a.ativa=(a.estado<>'inativa')
 AND CASE WHEN a.referencia_estado='capturada' AND NOT ('intervalo_aberto'=ANY(a.pendencias)) AND NOT ('conflito_factos'=ANY(a.pendencias)) THEN
  num_nonnulls(a.falta_minutes,a.excedente_minutes)=2
  AND a.falta_minutes=greatest(0,a.expected_minutes-a.realizado_minutes)
  AND a.excedente_minutes=greatest(0,a.realizado_minutes-a.expected_minutes)
  AND CASE WHEN a.excedente_minutes>0 THEN a.he_estado IN('pendente','validada','nao_considerada') ELSE a.he_estado='nenhum' END
 ELSE num_nonnulls(a.falta_minutes,a.excedente_minutes)=0 AND a.he_estado='nao_avaliavel' END
 AND ('referencia_diaria_pendente'=ANY(a.pendencias))=(a.referencia_estado='pendente')
 AND ('horas_em_falta'=ANY(a.pendencias))=coalesce(a.falta_minutes>0,false)
 AND ('he_diaria_pendente'=ANY(a.pendencias))=(a.he_estado='pendente')
 AND ('he_validada_aguarda_processamento'=ANY(a.pendencias))=(a.he_estado='validada')
 AND (a.he_estado NOT IN('validada','nao_considerada') OR a.decisao_fingerprint=folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot))
 AND a.estado=CASE WHEN NOT a.ativa THEN 'inativa'
  WHEN a.referencia_estado='pendente' THEN 'referencia_pendente'
  WHEN 'conflito_factos'=ANY(a.pendencias) THEN 'conflito'
  WHEN 'intervalo_aberto'=ANY(a.pendencias) THEN 'intervalo_aberto'
  WHEN a.falta_minutes>0 THEN 'horas_em_falta'
  WHEN a.excedente_minutes>0 AND a.he_estado<>'nao_considerada' THEN 'potencial_he'
  WHEN cardinality(a.pendencias)>0 THEN 'outras_pendencias' ELSE 'regular' END))) IS TRUE FROM (SELECT (r).*) a
$validator$;
CREATE OR REPLACE FUNCTION folha_privado.diaria_recalcular(p uuid,d date,req uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; old public.folha_avaliacoes_diarias; n public.folha_avaliacoes_diarias; f jsonb; ref jsonb; hash text; decision text; pend text[]:='{}'; action text; personal boolean;
BEGIN
 u:=folha_privado.ator();PERFORM folha_privado.lock_dia(p,d);
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT'; END IF;
 SELECT * INTO old FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
 personal:=folha_privado.diaria_pessoal(p,d);
 IF NOT personal AND old.id IS NULL THEN RETURN NULL; END IF;
 f:=folha_privado.diaria_factos(p,d); hash:=encode(sha256(convert_to((f->'canonical')::text,'UTF8')),'hex');
 IF old.id IS NOT NULL AND old.factos_fingerprint=hash AND old.ativa=personal THEN RETURN to_jsonb(old); END IF;
 n:=old;
 IF old.id IS NULL THEN
  ref:=folha_privado.diaria_referencia(p,d);
  n.id:=gen_random_uuid();n.empresa_id:=u.empresa_id;n.colaborador_id:=p;n.data:=d;n.referencia_revision:=1;
  n.referencia_estado:=ref->>'referencia_estado';n.referencia_origem:=ref->>'referencia_origem';n.jornada_versao_id:=(ref->>'jornada_versao_id')::uuid;n.permanencia_id:=(ref->>'permanencia_id')::uuid;n.obra_origem_id:=(ref->>'obra_origem_id')::uuid;n.horario_versao_id:=(ref->>'horario_versao_id')::uuid;
  n.permanencia_snapshot:=nullif(ref->'permanencia_snapshot','null'::jsonb);n.horario_snapshot:=nullif(ref->'horario_snapshot','null'::jsonb);n.contexto_snapshot:=ref->'contexto_snapshot';
  n.expected_minutes:=(ref->>'expected_minutes')::integer;n.referencia_motivo:=ref->>'referencia_motivo';n.referencia_evidencia:=ref->'referencia_evidencia';
  IF n.referencia_estado='capturada' THEN n.capturado_por:=u.id;n.capturado_em:=now();n.captura_request_id:=req; END IF;
  n.criado_por:=u.id;n.criado_em:=now();n.request_id_inicial:=req;n.he_estado:='nenhum';
 END IF;
 n.ativa:=personal;n.modo_dia:=CASE WHEN (f->>'mixed')::boolean THEN 'misto' ELSE 'personalizado' END;n.revision:=coalesce(old.revision,0)+1;
 n.realizado_minutes:=(f->>'minutes')::integer;n.factos_fingerprint:=hash;n.factos_revisoes:=f->'revisions';n.fingerprint_version:='folha_factos_v1';n.regra_avaliacao_version:='diaria_v1';
 n.atualizado_por:=u.id;n.avaliado_por:=u.id;n.atualizado_em:=now();n.avaliado_em:=now();n.ultimo_request_id:=req;
 decision:=folha_privado.diaria_decisao_hash(hash,n.referencia_revision,n.horario_snapshot);
 IF old.he_estado IN('validada','nao_considerada') AND old.decisao_fingerprint IS DISTINCT FROM decision THEN
  INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason) VALUES(u.empresa_id,'daily_he_invalidate',n.id,to_jsonb(old),jsonb_build_object('facts',hash),u.id,req,'Factos/referência alterados');
  n.he_estado:='nenhum';n.decisao_fingerprint:=NULL;n.he_decidido_por:=NULL;n.he_decidido_em:=NULL;n.he_motivo:=NULL;
 END IF;
 n.falta_minutes:=NULL;n.excedente_minutes:=NULL;
 IF n.referencia_estado='pendente' THEN pend:=array_append(pend,'referencia_diaria_pendente'); END IF;
 IF (f->>'open')::boolean THEN pend:=array_append(pend,'intervalo_aberto'); END IF;
 IF (f->>'conflict')::boolean THEN pend:=array_append(pend,'conflito_factos'); END IF;
 IF (f->>'special_pending')::boolean THEN pend:=array_append(pend,'dia_especial_pendente'); END IF;
 IF n.expected_minutes IS NOT NULL AND NOT (f->>'open')::boolean AND NOT (f->>'conflict')::boolean THEN
  n.falta_minutes:=greatest(0,n.expected_minutes-n.realizado_minutes);n.excedente_minutes:=greatest(0,n.realizado_minutes-n.expected_minutes);
  IF n.falta_minutes>0 THEN pend:=array_append(pend,'horas_em_falta'); END IF;
  IF n.excedente_minutes>0 THEN
   IF n.he_estado NOT IN('validada','nao_considerada') THEN n.he_estado:='pendente'; END IF;
   IF n.he_estado='pendente' THEN pend:=array_append(pend,'he_diaria_pendente'); ELSIF n.he_estado='validada' THEN pend:=array_append(pend,'he_validada_aguarda_processamento'); END IF;
  ELSE n.he_estado:='nenhum'; END IF;
 ELSE n.he_estado:='nao_avaliavel'; END IF;
 IF n.he_estado NOT IN('validada','nao_considerada') THEN n.decisao_fingerprint:=NULL;n.he_decidido_por:=NULL;n.he_decidido_em:=NULL;n.he_motivo:=NULL; END IF;
 n.pendencias:=pend;
 n.estado:=CASE WHEN NOT personal THEN 'inativa' WHEN n.referencia_estado='pendente' THEN 'referencia_pendente' WHEN (f->>'conflict')::boolean THEN 'conflito' WHEN (f->>'open')::boolean THEN 'intervalo_aberto' WHEN n.falta_minutes>0 THEN 'horas_em_falta' WHEN n.excedente_minutes>0 AND n.he_estado<>'nao_considerada' THEN 'potencial_he' WHEN cardinality(pend)>0 THEN 'outras_pendencias' ELSE 'regular' END;
 action:=CASE WHEN old.id IS NULL THEN 'daily_evaluation_create' WHEN NOT personal THEN 'daily_evaluation_deactivate' WHEN NOT old.ativa THEN 'daily_evaluation_reactivate' ELSE 'daily_evaluation_recalculate' END;
 IF old.id IS NULL THEN INSERT INTO public.folha_avaliacoes_diarias SELECT (n).*;
 ELSE UPDATE public.folha_avaliacoes_diarias SET (ativa,modo_dia,revision,realizado_minutes,falta_minutes,excedente_minutes,estado,he_estado,pendencias,factos_revisoes,factos_fingerprint,decisao_fingerprint,he_decidido_por,he_decidido_em,he_motivo,atualizado_por,atualizado_em,avaliado_por,avaliado_em,ultimo_request_id) =
 (n.ativa,n.modo_dia,n.revision,n.realizado_minutes,n.falta_minutes,n.excedente_minutes,n.estado,n.he_estado,n.pendencias,n.factos_revisoes,n.factos_fingerprint,n.decisao_fingerprint,n.he_decidido_por,n.he_decidido_em,n.he_motivo,n.atualizado_por,n.atualizado_em,n.avaliado_por,n.avaliado_em,n.ultimo_request_id) WHERE id=n.id; END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id) VALUES(u.empresa_id,action,n.id,CASE WHEN old.id IS NOT NULL THEN to_jsonb(old) END,to_jsonb(n),u.id,req);
 RETURN to_jsonb(n);
END $$;
CREATE OR REPLACE FUNCTION public.fn_folha_diaria_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; cfg public.folha_config_empresa; a public.folha_avaliacoes_diarias; v public.folha_horarios_versoes; h public.folha_horarios;
 req uuid:=(p_dados->>'request_id')::uuid; p uuid:=(p_dados->>'person_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date; before jsonb; after jsonb; payload jsonb; token text; result jsonb; op folha_privado.operacoes; schedule_row record; rev integer; next_rev integer; expected integer; reason text:=nullif(btrim(p_dados->>'reason'),''); facts jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 -- Formal templates are serialized before preview/snapshot; actual fact clocks are unchanged.
 LOCK TABLE public.folha_horarios IN SHARE ROW EXCLUSIVE MODE;
 u:=folha_privado.ator();SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo IS TRUE FOR SHARE;IF u.id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;IF NOT folha_privado.admin() THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao<>'configure_schedule' AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo/Gestão' USING ERRCODE='42501'; END IF;
 -- AD-15: session actor is the only tenant authority; revalidate before replay.
 IF u.empresa_id IS NULL OR (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'DAILY_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 IF p_acao IN('daily_activation','daily_he_validate','daily_he_disregard') AND w IS NOT NULL THEN RAISE EXCEPTION 'DAILY_GLOBAL_WORK_CONTEXT_FORBIDDEN' USING ERRCODE='42501'; END IF;
 IF p IS NOT NULL THEN
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
 END IF;
 IF w IS NOT NULL THEN
  PERFORM 1 FROM public.obras o WHERE o.id=w AND o.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_WORK_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 END IF;
 IF p_acao IN('daily_reference_correct','daily_he_validate','daily_he_disregard') THEN
  PERFORM folha_privado.lock_dia(p,d);
  SELECT * INTO a FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
  IF a.id IS NULL OR (p_dados ? 'evaluation_id' AND (p_dados->>'evaluation_id')::uuid IS DISTINCT FROM a.id) THEN RAISE EXCEPTION 'DAILY_EVALUATION_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  IF a.obra_origem_id IS NOT NULL THEN
   PERFORM 1 FROM public.obras o WHERE o.id=a.obra_origem_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_REFERENCE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  END IF;
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF (p_dados->>'version')::integer IS DISTINCT FROM 2 OR req IS NULL OR p_confirmar IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato diário'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;RETURN op.resultado;
 END IF;
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id FOR UPDATE;
 IF cfg.empresa_id IS NULL AND p_acao<>'configure_schedule' THEN RAISE EXCEPTION 'COMPANY_CONFIGURATION_REQUIRED'; END IF;
 IF p_acao='daily_activation' THEN
  IF cfg.avaliacao_diaria_data_ativacao IS NOT NULL THEN RAISE EXCEPTION 'DAILY_ALREADY_ACTIVATED'; END IF;
  IF d IS DISTINCT FROM today THEN RAISE EXCEPTION 'ACTIVATION_MUST_BE_TODAY'; END IF;
  -- Validate/lock the real schedule-work references, without changing hours.
  FOR schedule_row IN SELECT s.obra_id FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id ORDER BY s.obra_id FOR SHARE LOOP
   PERFORM 1 FROM public.obras o WHERE o.id=schedule_row.obra_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
   PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',configured.intervals,'expected_minutes',configured.expected_minutes),true) FROM public.folha_horarios configured WHERE configured.obra_id=schedule_row.obra_id AND configured.empresa_id=u.empresa_id;
  END LOOP;
  rev:=cfg.revision;before:=to_jsonb(cfg);
  after:=jsonb_build_object('activation_date',today,'schedules',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.obra_id),'[]') FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id));
 ELSIF p_acao IN('configure_schedule','schedule_retro_correct') THEN
  PERFORM folha_privado.obra(w,true);SELECT * INTO h FROM public.folha_horarios WHERE obra_id=w FOR UPDATE;
  IF h.obra_id IS NOT NULL AND h.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  IF p_acao='configure_schedule' THEN
   IF p_dados ? 'vigente_desde' AND (p_dados->>'vigente_desde')::date IS DISTINCT FROM today THEN RAISE EXCEPTION 'SCHEDULE_EFFECTIVE_TODAY_ONLY'; END IF;
   d:=today;before:=to_jsonb(h);rev:=coalesce(h.revision,0);
   SELECT * INTO v FROM public.folha_horarios_versoes WHERE obra_id=w AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d) FOR UPDATE;
  ELSE
   d:=(p_dados->>'vigente_desde')::date;
   IF d IS NULL OR d>=today OR d<cfg.avaliacao_diaria_data_ativacao OR cfg.avaliacao_diaria_data_ativacao IS NULL OR reason IS NULL THEN RAISE EXCEPTION 'RETRO_SCHEDULE_REASON_AND_VALID_DATE_REQUIRED'; END IF;
   SELECT * INTO v FROM public.folha_horarios_versoes WHERE id=(p_dados->>'version_id')::uuid AND obra_id=w AND empresa_id=u.empresa_id AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d) FOR UPDATE;
   IF v.id IS NULL THEN RAISE EXCEPTION 'SCHEDULE_VERSION_NOT_FOUND'; END IF;
   rev:=v.revision;before:=to_jsonb(v);
  END IF;
  facts:=folha_privado.horario_ad13_factos(p_dados,true);
  IF (facts->>'open')::boolean OR (p_dados->>'expected_minutes')::integer IS DISTINCT FROM (facts->>'minutes')::integer OR jsonb_array_length(p_dados->'intervals')<>2 OR (SELECT count(DISTINCT x->>'period') FROM jsonb_array_elements(p_dados->'intervals') x WHERE x->>'period' IN('manha','tarde'))<>2 THEN RAISE EXCEPTION 'SCHEDULE_INVALID'; END IF;
  expected:=(p_dados->>'expected_minutes')::integer;
  next_rev:=greatest(coalesce(h.revision,0),coalesce((SELECT max(revision) FROM public.folha_horarios_versoes WHERE obra_id=w),0))+1;
  after:=jsonb_build_object('intervals',p_dados->'intervals','expected_minutes',(p_dados->>'expected_minutes')::integer,'vigente_desde',d,'revision',CASE WHEN p_acao='configure_schedule' THEN rev+1 ELSE next_rev END,'version_revision',next_rev,'previous_version',to_jsonb(v),'affected_evaluations',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.data,'revision',e.revision) ORDER BY e.data,e.id),'[]') FROM public.folha_avaliacoes_diarias e WHERE e.empresa_id=u.empresa_id AND e.obra_origem_id=w AND e.data>=d AND (v.vigente_ate IS NULL OR e.data<v.vigente_ate)));
 ELSE
  IF p_acao NOT IN('daily_reference_correct','daily_he_validate','daily_he_disregard') THEN RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
  PERFORM folha_privado.lock_dia(p,d);
  SELECT * INTO a FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
  IF a.id IS NULL OR NOT a.ativa THEN RAISE EXCEPTION 'DAILY_EVALUATION_NOT_ACTIVE'; END IF;
  IF EXISTS(SELECT 1 FROM public.folha_vencimentos WHERE colaborador_id=p AND competencia=date_trunc('month',d)::date AND estado IN('closed','exported')) THEN RAISE EXCEPTION 'PAYROLL_CLOSED_FACTS_CHANGED'; END IF;
  facts:=folha_privado.diaria_factos(p,d);
  IF a.factos_fingerprint IS DISTINCT FROM encode(sha256(convert_to((facts->'canonical')::text,'UTF8')),'hex') THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  rev:=a.revision;before:=to_jsonb(a);
  IF reason IS NULL OR length(reason)>1000 THEN RAISE EXCEPTION 'ADMIN_REASON_REQUIRED'; END IF;
  IF p_acao='daily_reference_correct' THEN
   facts:=folha_privado.horario_ad13_factos(p_dados->'schedule',false);
   expected:=(p_dados->'schedule'->>'expected_minutes')::integer;
   IF (facts->>'open')::boolean OR expected IS DISTINCT FROM (facts->>'minutes')::integer OR expected NOT BETWEEN 0 AND 1440 OR jsonb_typeof(p_dados->'evidence') IS DISTINCT FROM 'object' OR p_dados->'evidence'='{}'::jsonb THEN RAISE EXCEPTION 'REFERENCE_EVIDENCE_REQUIRED'; END IF;
   IF w IS NOT NULL THEN PERFORM folha_privado.obra(w); END IF;
   after:=jsonb_build_object('schedule',p_dados->'schedule','evidence',p_dados->'evidence','reason',reason,'work_id',w);
  ELSE
   IF a.excedente_minutes IS NULL OR a.excedente_minutes<=0 OR a.he_estado NOT IN('pendente','validada','nao_considerada') THEN RAISE EXCEPTION 'DAILY_HE_NOT_EVALUABLE'; END IF;
   after:=jsonb_build_object('he_estado',CASE p_acao WHEN 'daily_he_validate' THEN 'validada' ELSE 'nao_considerada' END,'reason',reason,'minutes',a.excedente_minutes,'fingerprint',folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot));
  END IF;
 END IF;
 IF (p_dados->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 token:=encode(sha256(convert_to(jsonb_build_array(payload,before,after,to_jsonb(cfg))::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='daily_activation' THEN
  UPDATE public.folha_config_empresa SET avaliacao_diaria_data_ativacao=today,avaliacao_diaria_ativada_em=now(),avaliacao_diaria_ativada_por=u.id,avaliacao_diaria_ativacao_request_id=req,revision=revision+1 WHERE empresa_id=u.empresa_id;
  FOR schedule_row IN SELECT * FROM public.folha_horarios WHERE empresa_id=u.empresa_id ORDER BY obra_id LOOP
   PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',schedule_row.intervals,'expected_minutes',schedule_row.expected_minutes),true);
   INSERT INTO public.folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,criado_por,request_id) VALUES(u.empresa_id,schedule_row.obra_id,schedule_row.revision,jsonb_build_object('intervals',schedule_row.intervals,'expected_minutes',schedule_row.expected_minutes),today,u.id,req);
  END LOOP;
 ELSIF p_acao IN('configure_schedule','schedule_retro_correct') THEN
  IF cfg.avaliacao_diaria_data_ativacao IS NOT NULL THEN
   IF v.id IS NOT NULL THEN UPDATE public.folha_horarios_versoes SET vigente_ate=d WHERE id=v.id; END IF;
   INSERT INTO public.folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,vigente_ate,criado_por,request_id,motivo) VALUES(u.empresa_id,w,next_rev,jsonb_build_object('intervals',after->'intervals','expected_minutes',expected),d,CASE WHEN p_acao='schedule_retro_correct' THEN v.vigente_ate END,u.id,req,reason);
  END IF;
  IF p_acao='configure_schedule' OR v.vigente_ate IS NULL THEN
   INSERT INTO public.folha_horarios(obra_id,empresa_id,intervals,expected_minutes,revision) VALUES(w,u.empresa_id,after->'intervals',(after->>'expected_minutes')::integer,coalesce(h.revision,0)+1)
   ON CONFLICT(obra_id) DO UPDATE SET intervals=excluded.intervals,expected_minutes=excluded.expected_minutes,revision=excluded.revision;
  END IF;
 ELSIF p_acao='daily_reference_correct' THEN
  IF a.he_estado IN('validada','nao_considerada') THEN
   INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
   VALUES(u.empresa_id,'daily_he_invalidate',a.id,to_jsonb(a),jsonb_build_object('reason','Referência administrativa alterada'),u.id,req,reason);
  END IF;
  UPDATE public.folha_avaliacoes_diarias SET referencia_estado='capturada',referencia_origem='administrativo',jornada_versao_id=NULL,referencia_revision=referencia_revision+1,falta_minutes=NULL,excedente_minutes=NULL,he_estado='nao_avaliavel',decisao_fingerprint=NULL,he_decidido_por=NULL,he_decidido_em=NULL,he_motivo=NULL,pendencias=array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'),permanencia_id=NULL,permanencia_snapshot=NULL,obra_origem_id=w,horario_versao_id=NULL,horario_snapshot=p_dados->'schedule',expected_minutes=expected,referencia_motivo=reason,referencia_evidencia=p_dados->'evidence',capturado_por=u.id,capturado_em=now(),captura_request_id=req,factos_fingerprint=repeat('0',64),atualizado_por=u.id,atualizado_em=now(),ultimo_request_id=req WHERE id=a.id;
  after:=folha_privado.diaria_recalcular(p,d,req);
 ELSE
  UPDATE public.folha_avaliacoes_diarias SET he_estado=after->>'he_estado',he_motivo=reason,he_decidido_por=u.id,he_decidido_em=now(),decisao_fingerprint=after->>'fingerprint',revision=revision+1,atualizado_por=u.id,atualizado_em=now(),ultimo_request_id=req,
   pendencias=array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento')||CASE WHEN p_acao='daily_he_validate' THEN ARRAY['he_validada_aguarda_processamento'] ELSE '{}'::text[] END,
   estado=CASE WHEN p_acao='daily_he_validate' THEN 'potencial_he' WHEN cardinality(array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'))>0 THEN 'outras_pendencias' ELSE 'regular' END WHERE id=a.id;
  SELECT to_jsonb(x) INTO after FROM public.folha_avaliacoes_diarias x WHERE id=a.id;
 END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,reason) VALUES(u.empresa_id,w,p_acao,coalesce(a.id,v.id,w,u.empresa_id),before,after,u.id,req,reason);
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',coalesce((after->>'revision')::integer,rev+1),'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $$;
DO $data$ DECLARE r record;j jsonb;BEGIN
IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad03_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad03_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD03_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_ad03_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg((to_jsonb(x)-''jornada_versao_id'') ORDER BY (to_jsonb(x)-''jornada_versao_id'')::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD03_DATA_DRIFT: %',r.tabela;END IF;END LOOP;END $data$;
SELECT 'AD03_MIGRATION_OK' resultado;COMMIT;
