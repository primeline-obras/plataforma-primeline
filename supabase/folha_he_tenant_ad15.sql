-- Complete definition. No activation, no historical writes; application ACL preserved.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_registos,public.folha_he,public.folha_vencimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
DO $gate$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regprocedure('public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)') IS NULL THEN RAISE EXCEPTION 'AD15_DAILY_PACKAGE_REQUIRED'; END IF;
 IF encode(sha256(convert_to(btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),E' \n\t'),'UTF8')),'hex')<>'189eb93caeea512629b5823403657032ddabab49358d9b66901caaf244d357fb' THEN RAISE EXCEPTION 'AD15_BASELINE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico h LEFT JOIN public.utilizadores u ON u.id=h.ator_id LEFT JOIN public.obras o ON o.id=h.obra_id LEFT JOIN public.folha_avaliacoes_diarias a ON a.id=h.entidade_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE h.action IN('daily_he_validate','daily_he_disregard','daily_reference_correct') AND (u.empresa_id IS DISTINCT FROM h.empresa_id OR a.empresa_id IS DISTINCT FROM h.empresa_id OR c.empresa_id IS DISTINCT FROM h.empresa_id OR (h.obra_id IS NOT NULL AND (o.empresa_id IS DISTINCT FROM h.empresa_id OR h.action IN('daily_he_validate','daily_he_disregard'))))) THEN RAISE EXCEPTION 'AD15_HISTORICAL_CONTEXT_REQUIRES_RECONCILIATION'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_gestao_historico'::regclass) AND NOT relrowsecurity) OR has_table_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE,DELETE') OR has_any_column_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE') OR has_any_column_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE') THEN RAISE EXCEPTION 'AD15_DIRECT_WRITER_EXPOSED'; END IF;
END $gate$;
DO $data$ DECLARE r record; rows_now jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad15_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad15_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD15_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad15_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD15_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad15_backup.operacoes) THEN RAISE EXCEPTION 'AD15_OPERATIONS_DRIFT'; END IF;
END $data$;
CREATE OR REPLACE FUNCTION public.fn_folha_diaria_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; cfg public.folha_config_empresa; a public.folha_avaliacoes_diarias; v public.folha_horarios_versoes; h public.folha_horarios;
 req uuid:=(p_dados->>'request_id')::uuid; p uuid:=(p_dados->>'person_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date; before jsonb; after jsonb; payload jsonb; token text; result jsonb; op folha_privado.operacoes; schedule_row record; rev integer; next_rev integer; expected integer; reason text:=nullif(btrim(p_dados->>'reason'),''); facts jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
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
  facts:=folha_privado.facts(p_dados->'intervals',today);
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
   facts:=folha_privado.facts(p_dados->'schedule'->'intervals',today);
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
   PERFORM folha_privado.facts(schedule_row.intervals,today);
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
DO $function$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex')<>'e5dc4c1c3aea0720fcf142e4d52121c40e61d0b1308f87a81e23f5eaf66f2fef' THEN RAISE EXCEPTION 'AD15_FIXED_FUNCTION_DRIFT'; END IF;
END $function$;
DO $data$ DECLARE r record; rows_now jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad15_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad15_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD15_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad15_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD15_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad15_backup.operacoes) THEN RAISE EXCEPTION 'AD15_OPERATIONS_DRIFT'; END IF;
END $data$;
SELECT 'AD15_MIGRATION_OK' resultado;
COMMIT;
