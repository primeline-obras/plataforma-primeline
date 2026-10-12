BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_registos,public.folha_he,public.folha_vencimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $gate$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='e5dc4c1c3aea0720fcf142e4d52121c40e61d0b1308f87a81e23f5eaf66f2fef' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred) THEN RAISE EXCEPTION 'AD13_AD14_AD15_REQUIRED_OR_DRIFT'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=false AND provolatile='i' AND prorettype='boolean'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='sql') AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='3c9c590954b2f6f251fd213536308c4ee0a0b1b871e83aef5073c652d81cd2cf' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_AD14_HELPER_DRIFT'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.diaria_ad14_final()'::regprocedure AND proowner='postgres'::regrole AND prosecdef=true AND provolatile='v' AND prorettype='trigger'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='6f9a9f5b731ef17b590e0df9e7a604aa6c5fc4bbe31d4b072e7fdd75d437befc' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_AD14_HELPER_DRIFT'; END IF;
IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass)<>41 OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.diaria_ad14_valida(folha_avaliacoes_diarias.*, false) IS TRUE))') OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred AND tgtype=21 AND tgfoid='folha_privado.diaria_ad14_final()'::regprocedure AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='') THEN RAISE EXCEPTION 'AD13_AD14_SCHEMA_DRIFT'; END IF;
 IF to_regprocedure('folha_privado.horario_ad13_valido(jsonb,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.horario_ad13_factos(jsonb,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.horario_ad13_guardar()') IS NOT NULL THEN RAISE EXCEPTION 'AD13_PRESENT_OR_PARTIAL'; END IF;
END $gate$;
DO $schedules$ DECLARE r record;p_snapshot jsonb;p_normal boolean;valid boolean; x jsonb; n integer; s integer; e integer; last_end integer; total integer; expected numeric; BEGIN
 FOR r IN SELECT 'current' kind,h.obra_id::text identity,jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes) snapshot,true normal FROM public.folha_horarios h
 UNION ALL SELECT 'version',v.id::text,v.snapshot,true FROM public.folha_horarios_versoes v
 UNION ALL SELECT 'evaluation',a.id::text,a.horario_snapshot,a.referencia_origem='automatico' FROM public.folha_avaliacoes_diarias a WHERE a.referencia_estado='capturada' LOOP
  p_snapshot:=r.snapshot;p_normal:=r.normal;
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
  IF NOT valid THEN RAISE EXCEPTION 'AD13_EXISTING_SCHEDULE_INCOHERENT: % %',r.kind,r.identity; END IF;
 END LOOP;
END $schedules$;
DO $data$ DECLARE r record;rows_now jsonb; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad13_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad13_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD13_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD13_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad13_backup.operacoes) THEN RAISE EXCEPTION 'AD13_OPERATIONS_DRIFT'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.ad14 LOOP
  IF pg_get_functiondef(r.signature::regprocedure) IS DISTINCT FROM r.definicao OR (SELECT proacl FROM pg_proc WHERE oid=r.signature::regprocedure) IS DISTINCT FROM r.acl THEN RAISE EXCEPTION 'AD13_AD14_DRIFT: %',r.signature; END IF;
 END LOOP;
END $data$;
CREATE FUNCTION folha_privado.horario_ad13_valido(p_snapshot jsonb,p_normal boolean) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $validator$
DECLARE valid boolean; x jsonb; n integer; s integer; e integer; last_end integer; total integer; expected numeric;
BEGIN
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
CREATE FUNCTION folha_privado.horario_ad13_factos(p_snapshot jsonb,p_normal boolean) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $facts$
BEGIN
 IF folha_privado.horario_ad13_valido(p_snapshot,p_normal) IS NOT TRUE THEN RAISE EXCEPTION 'SCHEDULE_INCOHERENT: intervalos/carga/períodos inválidos' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('minutes',((p_snapshot->>'expected_minutes')::numeric)::integer,'open',false);
END $facts$;
CREATE FUNCTION folha_privado.horario_ad13_guardar() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $guard$
DECLARE h record;
BEGIN
 IF TG_TABLE_NAME='folha_config_empresa' THEN
  IF NEW.avaliacao_diaria_data_ativacao IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND NEW.avaliacao_diaria_data_ativacao IS NOT DISTINCT FROM OLD.avaliacao_diaria_data_ativacao THEN RETURN NEW; END IF;
  LOCK TABLE public.folha_horarios IN SHARE MODE;
  FOR h IN SELECT * FROM public.folha_horarios WHERE empresa_id=NEW.empresa_id ORDER BY obra_id FOR SHARE LOOP
   IF folha_privado.horario_ad13_valido(jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes),true) IS NOT TRUE THEN RAISE EXCEPTION 'ACTIVATION_SCHEDULE_INCOHERENT: work %',h.obra_id USING ERRCODE='23514'; END IF;
  END LOOP;
 ELSE
  IF NEW.referencia_estado='capturada' AND (folha_privado.horario_ad13_valido(NEW.horario_snapshot,NEW.referencia_origem='automatico') IS NOT TRUE OR (NEW.horario_snapshot->>'expected_minutes')::numeric IS DISTINCT FROM NEW.expected_minutes::numeric) THEN RAISE EXCEPTION 'REFERENCE_SNAPSHOT_INCOHERENT' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION folha_privado.horario_ad13_valido(jsonb,boolean),folha_privado.horario_ad13_factos(jsonb,boolean),folha_privado.horario_ad13_guardar() FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.folha_horarios ADD CONSTRAINT folha_horario_ad13_coerencia CHECK(folha_privado.horario_ad13_valido(jsonb_build_object('intervals',intervals,'expected_minutes',expected_minutes),true) IS TRUE);
ALTER TABLE public.folha_horarios_versoes ADD CONSTRAINT folha_versao_ad13_coerencia CHECK(folha_privado.horario_ad13_valido(snapshot,true) IS TRUE);
CREATE TRIGGER folha_diaria_ad13_ativacao BEFORE INSERT OR UPDATE ON public.folha_config_empresa FOR EACH ROW EXECUTE FUNCTION folha_privado.horario_ad13_guardar();
CREATE TRIGGER folha_diaria_ad13_referencia BEFORE INSERT OR UPDATE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.horario_ad13_guardar();
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
   IF (facts->>'open')::boolean OR expected IS DISTINCT FROM (facts->>'minutes')::integer OR expected NOT BETWEEN 1 AND 1440 OR jsonb_typeof(p_dados->'evidence') IS DISTINCT FROM 'object' OR p_dados->'evidence'='{}'::jsonb THEN RAISE EXCEPTION 'REFERENCE_EVIDENCE_REQUIRED'; END IF;
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
  UPDATE public.folha_avaliacoes_diarias SET referencia_estado='capturada',referencia_origem='administrativo',referencia_revision=referencia_revision+1,permanencia_id=NULL,permanencia_snapshot=NULL,obra_origem_id=w,horario_versao_id=NULL,horario_snapshot=p_dados->'schedule',expected_minutes=expected,referencia_motivo=reason,referencia_evidencia=p_dados->'evidence',capturado_por=u.id,capturado_em=now(),captura_request_id=req,factos_fingerprint=repeat('0',64),atualizado_por=u.id,atualizado_em=now(),ultimo_request_id=req WHERE id=a.id;
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

DO $installed$ DECLARE r record; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'::regprocedure AND proowner='postgres'::regrole AND prosecdef=false AND provolatile='i' AND prorettype='boolean'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='sql') AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='3c9c590954b2f6f251fd213536308c4ee0a0b1b871e83aef5073c652d81cd2cf' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_AD14_HELPER_DRIFT'; END IF;
IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.diaria_ad14_final()'::regprocedure AND proowner='postgres'::regrole AND prosecdef=true AND provolatile='v' AND prorettype='trigger'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='6f9a9f5b731ef17b590e0df9e7a604aa6c5fc4bbe31d4b072e7fdd75d437befc' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_AD14_HELPER_DRIFT'; END IF;
 IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass)<>41 OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.diaria_ad14_valida(folha_avaliacoes_diarias.*, false) IS TRUE))') OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred AND tgtype=21 AND tgfoid='folha_privado.diaria_ad14_final()'::regprocedure AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='') THEN RAISE EXCEPTION 'AD13_AD14_SCHEMA_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='1a94aed677d3c180568bab8f4df993514f938a0bc4c92e20c12fcf55905bd89f' AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD13_RPC_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.horario_ad13_valido(jsonb,boolean)'::regprocedure AND proowner='postgres'::regrole AND NOT prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND provolatile='i' AND prorettype='boolean'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='3e668595095a484963096d2186316aa31952eb54702e1033059c187e325a9b97' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_HELPER_DRIFT: folha_privado.horario_ad13_valido(jsonb,boolean)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.horario_ad13_factos(jsonb,boolean)'::regprocedure AND proowner='postgres'::regrole AND NOT prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND provolatile='i' AND prorettype='jsonb'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='701d3a571010f24c78ded445066f230f0ba1574ff99dc239ffde4057fbacaefd' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_HELPER_DRIFT: folha_privado.horario_ad13_factos(jsonb,boolean)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='folha_privado.horario_ad13_guardar()'::regprocedure AND proowner='postgres'::regrole AND NOT prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND provolatile='v' AND prorettype='trigger'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='5cc91e6ad5a046b77b0253d7a6ecc04dd9d385a40cce48bbc5421cffe3ee0a50' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_HELPER_DRIFT: folha_privado.horario_ad13_guardar()'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_horarios'::regclass AND conname='folha_horario_ad13_coerencia' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.horario_ad13_valido(jsonb_build_object(''intervals'', intervals, ''expected_minutes'', expected_minutes), true) IS TRUE))') OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_horarios_versoes'::regclass AND conname='folha_versao_ad13_coerencia' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.horario_ad13_valido(snapshot, true) IS TRUE))') THEN RAISE EXCEPTION 'AD13_CONSTRAINT_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_config_empresa'::regclass AND tgname='folha_diaria_ad13_ativacao' AND tgenabled='O' AND tgtype=23 AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='' AND tgfoid='folha_privado.horario_ad13_guardar()'::regprocedure) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad13_referencia' AND tgenabled='O' AND tgtype=23 AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='' AND tgfoid='folha_privado.horario_ad13_guardar()'::regprocedure) THEN RAISE EXCEPTION 'AD13_TRIGGER_DRIFT'; END IF;
END $installed$;
DO $schedules$ DECLARE r record;p_snapshot jsonb;p_normal boolean;valid boolean; x jsonb; n integer; s integer; e integer; last_end integer; total integer; expected numeric; BEGIN
 FOR r IN SELECT 'current' kind,h.obra_id::text identity,jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes) snapshot,true normal FROM public.folha_horarios h
 UNION ALL SELECT 'version',v.id::text,v.snapshot,true FROM public.folha_horarios_versoes v
 UNION ALL SELECT 'evaluation',a.id::text,a.horario_snapshot,a.referencia_origem='automatico' FROM public.folha_avaliacoes_diarias a WHERE a.referencia_estado='capturada' LOOP
  p_snapshot:=r.snapshot;p_normal:=r.normal;
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
  IF NOT valid THEN RAISE EXCEPTION 'AD13_EXISTING_SCHEDULE_INCOHERENT: % %',r.kind,r.identity; END IF;
 END LOOP;
END $schedules$;
DO $data$ DECLARE r record;rows_now jsonb; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad13_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad13_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD13_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD13_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad13_backup.operacoes) THEN RAISE EXCEPTION 'AD13_OPERATIONS_DRIFT'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.ad14 LOOP
  IF pg_get_functiondef(r.signature::regprocedure) IS DISTINCT FROM r.definicao OR (SELECT proacl FROM pg_proc WHERE oid=r.signature::regprocedure) IS DISTINCT FROM r.acl THEN RAISE EXCEPTION 'AD13_AD14_DRIFT: %',r.signature; END IF;
 END LOOP;
END $data$;
SELECT 'AD13_MIGRATION_OK' resultado;
COMMIT;
