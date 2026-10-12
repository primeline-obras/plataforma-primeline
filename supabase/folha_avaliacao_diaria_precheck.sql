-- Estritamente read-only. Executar inteiro, sem retirar o READ ONLY.
BEGIN READ ONLY;
SET LOCAL search_path=pg_catalog;
DO $$ DECLARE r record; BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regnamespace('primeline_diaria_backup') IS NOT NULL OR to_regclass('public.folha_avaliacoes_diarias') IS NOT NULL OR to_regclass('public.folha_horarios_versoes') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_config_empresa'::regclass AND attname='avaliacao_diaria_data_ativacao' AND NOT attisdropped) THEN RAISE EXCEPTION 'DAILY_NAME_CONFLICT'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname LIKE 'diaria_%' OR n.nspname='public' AND p.proname='fn_folha_diaria_gestao_v2') THEN RAISE EXCEPTION 'DAILY_FUNCTION_NAME_CONFLICT'; END IF;
 FOR r IN SELECT unnest(ARRAY['folha_privado.operar_periodos(jsonb,boolean,text)','folha_privado.reconciliar_he(public.folha_registos)','folha_privado.reconciliar_dia(uuid,date,uuid,text)','folha_privado.linha(uuid,uuid,date,text)','folha_privado.normal(uuid,uuid,date)','folha_privado.payroll_facts(uuid,date)','public.fn_folha_gestao_v2(text,jsonb,boolean,text)','public.fn_folha_gestao_contexto_v2(uuid,uuid,date)','folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)','folha_privado.save(jsonb,uuid,date,uuid,boolean)']) sig LOOP IF to_regprocedure(r.sig) IS NULL THEN RAISE EXCEPTION 'DAILY_BASELINE_MISSING: %',r.sig; END IF; IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig) AND (p.proowner<>'postgres'::regrole OR p.proisstrict OR p.proleakproof OR p.prokind<>'f' OR p.proparallel<>'u' OR p.provolatile<>CASE WHEN r.sig='folha_privado.payroll_facts(uuid,date)' THEN 's' ELSE 'v' END OR NOT p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'])) THEN RAISE EXCEPTION 'DAILY_BASELINE_SECURITY_DRIFT: %',r.sig; END IF; IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl WHERE p.oid=to_regprocedure(r.sig) AND acl.grantee<>p.proowner AND (r.sig NOT LIKE 'public.%' OR acl.grantee<>'authenticated'::regrole OR acl.privilege_type<>'EXECUTE' OR acl.is_grantable)) THEN RAISE EXCEPTION 'DAILY_BASELINE_ACL_DRIFT: %',r.sig; END IF; END LOOP;
 IF EXISTS(SELECT 1 FROM public.folha_horarios h JOIN public.obras o ON o.id=h.obra_id WHERE h.empresa_id<>o.empresa_id OR h.expected_minutes NOT BETWEEN 1 AND 1440 OR jsonb_array_length(h.intervals)<>2) THEN RAISE EXCEPTION 'SCHEDULE_BASELINE_INVALID'; END IF;
 IF has_table_privilege('authenticated','public.folha_registos','INSERT,UPDATE,DELETE') OR has_any_column_privilege('authenticated','public.folha_registos','INSERT,UPDATE') THEN RAISE EXCEPTION 'DAILY_FACT_WRITER_NOT_CLOSED'; END IF;
 FOR r IN SELECT * FROM public.folha_horarios LOOP
 IF (folha_privado.facts(r.intervals,(now() AT TIME ZONE 'Europe/Lisbon')::date)->>'open')::boolean OR (folha_privado.facts(r.intervals,(now() AT TIME ZONE 'Europe/Lisbon')::date)->>'minutes')::integer IS DISTINCT FROM r.expected_minutes OR (SELECT count(DISTINCT x->>'period') FROM jsonb_array_elements(r.intervals) x WHERE x->>'period' IN('manha','tarde'))<>2 THEN RAISE EXCEPTION 'SCHEDULE_BASELINE_INVALID'; END IF;
 END LOOP;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.operar_periodos(jsonb,boolean,text)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; d date:=(p->>'date')::date; req uuid:=(p->>'request_id')::uuid; person uuid:=(p->'key'->>'person_id')::uuid;
 w uuid:=(p->>'work_id')::uuid; item jsonb; plan jsonb:=p->'sites'; snapshot jsonb:='[]'; xs jsonb; token text; payload jsonb; op folha_privado.operacoes; old public.folha_registos; keys jsonb:='[]'; result jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE; PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator(); PERFORM folha_privado.local(person,w,true); PERFORM folha_privado.lock_dia(person,d);
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF confirmar IS NULL OR req IS NULL OR (p->>'version')::integer IS DISTINCT FROM 2 OR p->'key'->>'kind' IS DISTINCT FROM 'primeline' OR p->'key'->>'work_id' IS DISTINCT FROM w::text OR p->'key'->>'date' IS DISTINCT FROM d::text OR jsonb_typeof(plan) IS DISTINCT FROM 'array' OR jsonb_array_length(plan) NOT BETWEEN 1 AND 4 OR EXISTS(SELECT 1 FROM jsonb_array_elements(plan) x GROUP BY x->>'work_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'VALIDATION_ERROR: períodos'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(plan) ORDER BY value->>'work_id' LOOP
  PERFORM folha_privado.local(person,(item->>'work_id')::uuid,true);
 END LOOP;
 payload:=jsonb_build_object('action','periods_save','data',p);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF; RETURN op.resultado;
 END IF;
 IF EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=person AND f.data=d AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(plan) x WHERE x->>'work_id' IS NOT DISTINCT FROM f.obra_id::text)) THEN RAISE EXCEPTION 'DAY_FACTS_CHANGED' USING ERRCODE='40001'; END IF;
 SELECT jsonb_agg(x.value ORDER BY x.value->>'start') INTO xs FROM jsonb_array_elements(plan) target CROSS JOIN LATERAL jsonb_array_elements(target->'intervals') x;
 IF xs IS NULL OR jsonb_array_length(xs)>16 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalos'; END IF; PERFORM folha_privado.facts(xs,d);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(xs) x WHERE x->>'period' IS NULL OR x->>'period' NOT IN('manha','tarde')) THEN RAISE EXCEPTION 'PERIOD_REQUIRED'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(plan) ORDER BY value->>'work_id' LOOP
  SELECT * INTO old FROM public.folha_registos WHERE colaborador_id=person AND data=d AND obra_id IS NOT DISTINCT FROM (item->>'work_id')::uuid FOR UPDATE;
  IF old.id IS NULL THEN SELECT revision INTO old.revision FROM folha_privado.periodos_revisoes WHERE colaborador_id=person AND obra_id IS NOT DISTINCT FROM (item->>'work_id')::uuid AND data=d; END IF;
  IF (item->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
  IF jsonb_array_length(item->'intervals')>0 THEN
   snapshot:=snapshot||jsonb_build_array(folha_privado.save_periodo(jsonb_build_object('key',jsonb_build_object('kind','primeline','person_id',person,'work_id',item->>'work_id','date',d),'intervals',item->'intervals','expected_revision',item->'expected_revision','note',p->>'note','reason',p->>'reason'),(item->>'work_id')::uuid,d,req,false,plan));
  ELSE
   IF old.id IS NULL THEN RAISE EXCEPTION 'EMPTY_PERIOD_TARGET'; END IF;
   IF d>(now() AT TIME ZONE 'Europe/Lisbon')::date OR (d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND NOT folha_privado.adm_operacional()) THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
   IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
   IF EXISTS(SELECT 1 FROM public.folha_he WHERE folha_id=old.id) THEN RAISE EXCEPTION 'HE_REVIEW_REQUIRED'; END IF;
   snapshot:=snapshot||jsonb_build_array(jsonb_build_object('before',to_jsonb(old),'after',NULL));
  END IF;
 END LOOP;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'snapshot',snapshot)::text,'UTF8')),'hex');
 IF NOT confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',snapshot,'summary','Confirmar obras e horas por período? A equipa permanente não será transferida.'); END IF;
 IF versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(plan) ORDER BY value->>'work_id' LOOP
  IF jsonb_array_length(item->'intervals')>0 THEN
   PERFORM folha_privado.save_periodo(jsonb_build_object('key',jsonb_build_object('kind','primeline','person_id',person,'work_id',item->>'work_id','date',d),'intervals',item->'intervals','expected_revision',item->'expected_revision','note',p->>'note','reason',p->>'reason'),(item->>'work_id')::uuid,d,req,true,plan);
  ELSE
   DELETE FROM public.folha_registos WHERE colaborador_id=person AND data=d AND obra_id IS NOT DISTINCT FROM (item->>'work_id')::uuid RETURNING * INTO old;
   INSERT INTO folha_privado.periodos_revisoes VALUES(person,old.obra_id,d,old.revision+1) ON CONFLICT(colaborador_id,obra_id,data) DO UPDATE SET revision=excluded.revision;
   INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason) VALUES(u.empresa_id,old.obra_id,CASE WHEN old.obra_id IS NULL THEN 'escritorio' ELSE 'obra' END,person,'primeline',d,'period_relocation',to_jsonb(old),jsonb_build_object('sites',plan),old.revision+1,u.id,req,p->>'reason');
  END IF;
  keys:=keys||jsonb_build_array(jsonb_build_object('kind','primeline','person_id',person,'work_id',item->>'work_id','date',d));
 END LOOP;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now()); RETURN result;
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.operar_periodos(jsonb,boolean,text)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.reconciliar_he(public.folha_registos)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$BEGIN
 UPDATE public.folha_he SET estado='superseded',revision=revision+1 WHERE folha_id=f.id AND estado<>'superseded';
 IF f.obra_id IS NOT NULL AND f.colaborador_id IS NOT NULL AND NOT f.special_day AND f.estado='registered'
 AND f.expected_minutes IS NOT NULL AND f.minutes>f.expected_minutes
 AND EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.folha_config_empresa cfg ON cfg.empresa_id=c.empresa_id WHERE c.id=f.colaborador_id AND lower(btrim(c.funcao))=ANY(cfg.he_eligible_roles))
 AND EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=f.empresa_id AND overtime_enabled AND calendar_complete AND extract(year FROM f.data)::integer=ANY(calendar_validated_years) AND NOT f.data=ANY(holiday_dates))
 AND extract(isodow FROM f.data)<6
 AND NOT EXISTS(SELECT 1 FROM public.horas_extraordinarias WHERE colaborador_id=f.colaborador_id AND data=f.data)
 THEN INSERT INTO public.folha_he(empresa_id,obra_id,folha_id,folha_revision,minutes,estado)
 VALUES(f.empresa_id,f.obra_id,f.id,f.revision,f.minutes-f.expected_minutes,'potential'); END IF;
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.reconciliar_he(public.folha_registos)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.reconciliar_dia(uuid,date,uuid,text)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; f public.folha_registos; antes public.folha_registos; r jsonb; facts jsonb; novo_estado text; conflito boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d) THEN RETURN; END IF;
 u:=folha_privado.ator();
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id)
 OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d AND empresa_id<>u.empresa_id)
 THEN RAISE EXCEPTION 'TENANT_RECONCILIATION_DENIED' USING ERRCODE='42501'; END IF;
 PERFORM folha_privado.lock_dia(p,d);
 FOR f IN SELECT * FROM public.folha_registos WHERE colaborador_id=p AND data=d AND empresa_id=u.empresa_id ORDER BY id FOR UPDATE LOOP
  r:=folha_privado.linha(p,f.obra_id,d,'primeline');facts:=folha_privado.facts(f.intervals,d);
  conflito:=r->>'conflict' IS NOT NULL OR EXISTS(SELECT 1 FROM public.folha_registos other,jsonb_array_elements(other.intervals) x,jsonb_array_elements(f.intervals) y
   WHERE other.colaborador_id=p AND other.data=d AND other.id<>f.id AND other.obra_id IS DISTINCT FROM f.obra_id
   AND (x->>'start')::time<coalesce((y->>'end')::time,'24:00'::time) AND (y->>'start')::time<coalesce((x->>'end')::time,'24:00'::time));
  novo_estado:=folha_privado.estado_efetivo((facts->>'minutes')::integer,(facts->>'open')::boolean,f.expected_minutes,r->'absence'<>'null'::jsonb,conflito);
  IF novo_estado IS DISTINCT FROM f.estado THEN
   antes:=f;
   UPDATE public.folha_registos SET estado=novo_estado,revision=revision+1,atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=f.id RETURNING * INTO f;
   INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,origem)
   VALUES(f.empresa_id,f.obra_id,f.tipo_local,p,'primeline',d,'reconcile',to_jsonb(antes),to_jsonb(f),f.revision,u.id,req,origem);
   PERFORM folha_privado.reconciliar_he(f);
  END IF;
 END LOOP;
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.reconciliar_dia(uuid,date,uuid,text)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.linha(uuid,uuid,date,text)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; nome text; papel text; fornecedor text; s public.folha_registos;
 a jsonb; expected integer; conf text; rev integer; ids jsonb; period text; legacy boolean:=false;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.local(p,w);
 IF k='primeline' THEN
  SELECT c.nome,c.funcao INTO nome,papel FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('id',x.id,'data',x.data,'tipo',x.tipo,'estado',x.estado) INTO a FROM public.ausencias x WHERE x.colaborador_id=p AND x.data=d ORDER BY x.criado_em DESC,x.id LIMIT 1;
  legacy:=EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND obra_id IS NOT DISTINCT FROM w AND data=d AND empresa_id=u.empresa_id);
  -- The existing writer guard covers the whole person/day. Expose only its block,
  -- never the other work or its legacy details, when the selected fact differs.
  IF NOT legacy AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data=d) THEN conf:='LEGACY_WRITER_BLOCKED'; END IF;
  SELECT coalesce(jsonb_agg(q.id ORDER BY q.id),'[]'),CASE WHEN count(DISTINCT q.periodo)>1 THEN 'dia_inteiro' ELSE min(q.periodo) END INTO ids,period FROM public.fn_quadro_resolver_data(d) q WHERE q.colaborador_id=p AND q.obra_id=w;
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q JOIN public.quadro_pessoal_alocacao other ON q.colaborador_id=other.colaborador_id AND q.data=other.data AND q.id<other.id
   WHERE q.colaborador_id=p AND q.data=d AND (q.periodo='dia_inteiro' OR other.periodo='dia_inteiro' OR q.periodo=other.periodo))
  THEN conf:='ALLOCATION_CONFLICT'; END IF;
  SELECT coalesce(revisao,0) INTO rev FROM public.quadro_dias_revisoes WHERE colaborador_id=p AND data=d;
 ELSE
  SELECT e.nome,f.nome INTO nome,fornecedor FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id
   WHERE e.id=p AND e.empresa_id=u.empresa_id AND f.empresa_id=u.empresa_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT * INTO s FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND (CASE WHEN k='primeline' THEN colaborador_id=p ELSE externo_id=p END);
 IF legacy AND s.id IS NOT NULL THEN conf:='LEGACY_CONFLICT'; END IF;
 SELECT CASE WHEN period IN('manha','tarde') THEN
  (SELECT sum((extract(epoch from ((x->>'end')::time-(x->>'start')::time))/60)::integer) FROM jsonb_array_elements(h.intervals) x WHERE x->>'period'=period)
 ELSE h.expected_minutes END INTO expected FROM public.folha_horarios h WHERE h.obra_id=w;
 IF w IS NULL THEN
  expected:=coalesce((SELECT office_expected_minutes FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),480);
  IF EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao WHERE colaborador_id=p AND data=d AND obra_id IS NOT NULL) THEN conf:='ALLOCATION_CONFLICT'; END IF;
 END IF;
 IF s.id IS NOT NULL THEN expected:=s.expected_minutes; END IF;
 IF k='external' THEN expected:=NULL; SELECT coalesce((SELECT funcao FROM public.folha_externos_permanencias WHERE externo_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)),(SELECT funcao FROM public.folha_externos_dias WHERE externo_id=p AND obra_id=w AND data=d)) INTO papel; END IF;
 RETURN jsonb_build_object('tipo_local',CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,'person_id',p,'name',nome,'role',papel,'provider_name',fornecedor,
  'sheet',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object('id',s.id,'intervals',s.intervals,'note',s.note,'state',s.estado) END,
  'absence',a,'legacy',legacy,'conflict',conf,'special_day',s.special_day,'special_reviewed',s.special_reviewed_at IS NOT NULL,'special_review_pending',s.special_day AND s.special_reviewed_at IS NULL,'revision',coalesce(s.revision,(SELECT revision FROM folha_privado.periodos_revisoes WHERE colaborador_id=p AND data=d AND obra_id IS NOT DISTINCT FROM w),0),'allocation_revision',coalesce(rev,0),
  'allocation_ids',coalesce(ids,'[]'),'period',coalesce(period,'dia_inteiro'),'expected_minutes',expected,
  'self',p=(SELECT min(c.id::text)::uuid FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id HAVING count(*)=1),'self_role',CASE WHEN u.funcao='encarregado' THEN 'ENCARREGADO · VOCÊ' ELSE 'VOCÊ' END,
 'external_membership_id',(SELECT id FROM public.folha_externos_permanencias WHERE externo_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)),
 'external_team_revision',coalesce((SELECT revision FROM folha_privado.externos_revisoes WHERE externo_id=p),0),
 'can_external_remove',k='external' AND EXISTS(SELECT 1 FROM public.folha_externos_permanencias WHERE externo_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)) AND (folha_privado.admin() OR u.funcao='encarregado'),
 'day_revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('work_id',v.obra_id,'revision',v.revision)) FROM folha_privado.periodos_revisoes v WHERE v.colaborador_id=p AND v.data=d AND (folha_privado.admin() OR v.obra_id IS NULL AND EXISTS(SELECT 1 FROM public.colaboradores own WHERE own.id=p AND own.utilizador_id=u.id AND u.funcao IN('diretor_obra','adjunto','preparador')) OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=v.obra_id AND r.utilizador_id=u.id AND r.papel=u.funcao))),'[]'),
 'day_sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('work_id',f.obra_id,'revision',f.revision,'intervals',f.intervals) ORDER BY f.obra_id) FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR f.obra_id IS NULL AND EXISTS(SELECT 1 FROM public.colaboradores own WHERE own.id=p AND own.utilizador_id=u.id AND u.funcao IN('diretor_obra','adjunto','preparador')) OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=f.obra_id AND r.utilizador_id=u.id AND r.papel=u.funcao))),'[]'),
 'team_revision',coalesce((SELECT revision FROM folha_privado.equipa_revisoes WHERE colaborador_id=p),0),
 'delegation',(SELECT delegacao FROM public.colaboradores WHERE id=p),
 'membership_id',(SELECT id FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)),
 'can_remove',EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d)) AND w IS NOT NULL AND NOT legacy AND conf IS NULL AND a IS NULL
   AND EXISTS(SELECT 1 FROM public.obras WHERE id=w AND situacao='em_curso')
   AND EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d))
   AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),
  'overtime',CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('estado',coalesce((SELECT h.estado FROM public.folha_he h WHERE h.folha_id=s.id AND h.folha_revision=s.revision AND h.estado<>'superseded'),CASE WHEN s.special_day AND s.special_reviewed_at IS NULL AND s.estado<>'regularization' THEN 'pending_rule' ELSE 'none' END)) END,
  'can_write',NOT legacy AND conf IS NULL AND d<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND (d=(now() AT TIME ZONE 'Europe/Lisbon')::date OR folha_privado.adm_operacional() OR d>=(now() AT TIME ZONE 'Europe/Lisbon')::date-1) AND (w IS NULL OR folha_privado.admin() OR u.funcao='encarregado' OR EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND utilizador_id=u.id AND u.funcao IN('diretor_obra','adjunto','preparador'))) AND ((k='external' AND EXISTS(SELECT 1 FROM public.folha_externos WHERE id=p AND empresa_id=u.empresa_id AND ativo)) OR EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d))));
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.linha(uuid,uuid,date,text)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.normal(uuid,uuid,date)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE r jsonb; xs jsonb; full_day jsonb;
BEGIN
 IF extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=(folha_privado.ator()).empresa_id AND d=ANY(holiday_dates)) THEN RAISE EXCEPTION 'SPECIAL_DAY_NO_NORMAL_FILL'; END IF;
 r:=folha_privado.linha(p,w,d,'primeline');
 SELECT intervals INTO full_day FROM public.folha_horarios WHERE obra_id=w;
 IF full_day IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(full_day,d);
 SELECT jsonb_agg(jsonb_build_object('start',x->>'start','end',x->>'end') ORDER BY x->>'start') INTO xs
 FROM public.folha_horarios h,jsonb_array_elements(h.intervals) x WHERE h.obra_id=w AND (r->>'period'='dia_inteiro' OR x->>'period'=r->>'period');
 IF xs IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(xs,d); RETURN xs;
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.normal(uuid,uuid,date)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.payroll_facts(uuid,date)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$SELECT jsonb_build_object('sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'minutes',f.minutes,'state',f.estado,'special_day',f.special_day,'special_reviewed',f.special_reviewed_at IS NOT NULL) ORDER BY f.data,f.id)
 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data>=m AND f.data<(m+interval '1 month')::date),'[]'),
 'absences',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'type',a.tipo,'state',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date),'[]'),
 'pending_days',coalesce((SELECT jsonb_agg(data ORDER BY data) FROM (SELECT DISTINCT q.data FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=m AND q.data<(m+interval '1 month')::date AND q.data<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=q.data AND f.obra_id IS NOT DISTINCT FROM q.obra_id) AND NOT EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=q.data) AND NOT EXISTS(SELECT 1 FROM public.ponto_pessoal_obra h WHERE h.colaborador_id=p AND h.data=q.data)) missing),'[]'),
 'legacy_days',coalesce((SELECT jsonb_agg(DISTINCT data ORDER BY data) FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data>=m AND data<(m+interval '1 month')::date),'[]'),
 'financial_effect',false,'legacy_not_converted',true)$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.payroll_facts(uuid,date)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; req uuid:=(p_dados->>'request_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid;
 person uuid:=(p_dados->>'person_id')::uuid; entity uuid; before jsonb; after jsonb; payload jsonb; op folha_privado.operacoes; previous_request text;
 token text; result jsonb; expected integer; rev integer; d date; m date; dates date[]; scope_dates date[]; a date; item jsonb;
 h public.folha_he; f public.folha_registos; v public.folha_vencimentos; t public.folha_tarefas_reportes; task public.planeamento_itens;
 cfg public.folha_config_empresa; ab public.ausencias; facts jsonb; pending boolean; consumed integer:=0; histids jsonb;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao IN('payroll_validate','payroll_close','payroll_reopen','he_validate','he_process','configure_he_eligibility','absence_confirm','special_review') AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo' USING ERRCODE='42501'; END IF;
 IF p_acao IN('configure_company','configure_schedule','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','configure_he_eligibility','absence_confirm','special_review') AND NOT folha_privado.admin()
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao IN('configure_company','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','configure_he_eligibility','absence_confirm','special_review') AND w IS NOT NULL THEN
  RAISE EXCEPTION 'ADMIN_WORK_SCOPE_INVALID: ação administrativa sem obra' USING ERRCODE='22023';
 END IF;
 IF p_acao='configure_schedule' THEN PERFORM folha_privado.obra(w); END IF;
 -- Replays must obey the actor's CURRENT role and work scope.
 IF p_acao IN('task_report','task_confirm') THEN
  PERFORM folha_privado.obra(w);
  IF p_acao='task_report' AND (u.funcao<>'encarregado' AND NOT folha_privado.superuser()) OR p_acao='task_confirm' AND (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501';
  END IF;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
  IF NOT FOUND OR p_acao IN('he_approve','he_reject') AND (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR p_acao='he_validate' AND NOT folha_privado.admin() THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501';
  END IF;
  PERFORM folha_privado.obra(h.obra_id);
 END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados,'contract','gestao_v2');
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  -- Recheck entity tenant/scope without revisiting completed transition/revision.
  IF person IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  IF p_acao='he_process' THEN
   SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501'; END IF;
   PERFORM folha_privado.obra(h.obra_id);
  ELSIF p_acao='special_review' THEN
   SELECT * INTO f FROM public.folha_registos WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: Folha' USING ERRCODE='42501'; END IF;
  ELSIF p_acao='absence_confirm' AND NOT EXISTS(SELECT 1 FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=(p_dados->>'id')::uuid AND c.empresa_id=u.empresa_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501';
  ELSIF p_acao IN('task_report','task_confirm') AND NOT EXISTS(SELECT 1 FROM public.planeamento_itens pi JOIN public.fases fase ON fase.id=pi.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE pi.id=(p_dados->>'task_id')::uuid AND fase.obra_id=w AND o.empresa_id=u.empresa_id) THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501';
  END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 expected:=(p_dados->>'expected_revision')::integer;
 IF p_acao='configure_he_eligibility' THEN
  before:=to_jsonb(cfg);entity:=u.empresa_id;rev:=coalesce(cfg.revision,0);
  IF jsonb_typeof(p_dados->'roles') IS DISTINCT FROM 'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'roles') x WHERE jsonb_typeof(x)<>'string' OR length(btrim(x#>>'{}')) NOT BETWEEN 1 AND 100) THEN RAISE EXCEPTION 'HE_ELIGIBILITY_INVALID'; END IF;
  after:=jsonb_build_object('roles',(SELECT coalesce(jsonb_agg(DISTINCT lower(btrim(x))),'[]') FROM jsonb_array_elements_text(p_dados->'roles') x));
 ELSIF p_acao='absence_confirm' THEN
  SELECT a.* INTO ab FROM public.ausencias a JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE a.id=(p_dados->>'id')::uuid AND c.empresa_id=u.empresa_id FOR UPDATE OF a;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501'; END IF;
  IF ab.estado<>'ausente_pendente' THEN RAISE EXCEPTION 'ABSENCE_TRANSITION_INVALID'; END IF;
  IF ab.tipo='baixa_doenca' AND NOT EXISTS(SELECT 1 FROM public.ausencias_anexos WHERE ausencia_id=ab.id AND nullif(btrim(arquivo_url),'') IS NOT NULL) THEN RAISE EXCEPTION 'DOCUMENTO_PENDENTE'; END IF;
  entity:=ab.id;before:=to_jsonb(ab);rev:=0;
  IF p_dados->>'expected_state' IS DISTINCT FROM ab.estado OR p_dados->>'expected_type' IS DISTINCT FROM ab.tipo THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  after:=jsonb_build_object('estado',CASE WHEN ab.tipo IN('baixa_doenca','baixa_maternidade','baixa_parental','falta_justificada_com_remuneracao') THEN 'confirmada' ELSE 'justificada' END);
  IF nullif(btrim(p_dados->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'ABSENCE_REASON_REQUIRED'; END IF;
 ELSIF p_acao='special_review' THEN
  SELECT * INTO f FROM public.folha_registos WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND OR NOT f.special_day THEN RAISE EXCEPTION 'SPECIAL_REVIEW_INVALID'; END IF;
  entity:=f.id;before:=to_jsonb(f);rev:=f.revision;after:=jsonb_build_object('reviewed',true);
 ELSIF p_acao='he_process' THEN
  SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND OR h.estado<>'validated_pending_rule' OR h.processado_em IS NOT NULL THEN RAISE EXCEPTION 'HE_PROCESS_INVALID'; END IF;
  SELECT * INTO f FROM public.folha_registos WHERE id=h.folha_id FOR SHARE;
  IF f.revision<>h.folha_revision THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  entity:=h.id;w:=h.obra_id;before:=to_jsonb(h);rev:=h.revision;after:=jsonb_build_object('processado',true,'financial_effect',false);
 ELSIF p_acao='configure_company' THEN
  before:=to_jsonb(cfg); entity:=u.empresa_id; rev:=coalesce(cfg.revision,0);
  IF p_dados ? 'correction_days' AND (p_dados->>'correction_days')::integer IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'VALIDATION_ERROR: janela'; END IF;
  IF p_dados ? 'office_expected_minutes' AND coalesce((p_dados->>'office_expected_minutes')::integer,0) NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'VALIDATION_ERROR: carga escritório'; END IF;
  after:=jsonb_build_object('office_expected_minutes',coalesce((p_dados->>'office_expected_minutes')::integer,cfg.office_expected_minutes,480),'correction_days',1,'overtime_enabled',coalesce((p_dados->>'overtime_enabled')::boolean,false),
    'calendar_complete',coalesce((p_dados->>'calendar_complete')::boolean,false),'holiday_dates',coalesce(p_dados->'holiday_dates','[]'),'calendar_validated_years',coalesce(p_dados->'calendar_validated_years',to_jsonb(cfg.calendar_validated_years),'[]'),
    'payroll_rules_ready',coalesce((p_dados->>'payroll_rules_ready')::boolean,false),'official_template_hash',p_dados->>'official_template_hash');
  IF after->>'official_template_hash' IS NOT NULL AND after->>'official_template_hash' !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'VALIDATION_ERROR: hash'; END IF;
 ELSIF p_acao='configure_schedule' THEN
  PERFORM folha_privado.obra(w); entity:=w;
  SELECT to_jsonb(x),x.revision INTO before,rev FROM public.folha_horarios x WHERE obra_id=w FOR UPDATE;rev:=coalesce(rev,0);
  facts:=folha_privado.facts(p_dados->'intervals',least((now() AT TIME ZONE 'Europe/Lisbon')::date-1,'2026-01-01'::date));
  IF (facts->>'open')::boolean OR (p_dados->>'expected_minutes')::integer IS NULL OR (p_dados->>'expected_minutes')::integer<>(facts->>'minutes')::integer
   OR jsonb_array_length(p_dados->'intervals')<>2
   OR (SELECT count(DISTINCT x->>'period') FROM jsonb_array_elements(p_dados->'intervals') x WHERE x->>'period' IN('manha','tarde'))<>2
  THEN RAISE EXCEPTION 'SCHEDULE_INVALID'; END IF;
  after:=jsonb_build_object('intervals',p_dados->'intervals','expected_minutes',(p_dados->>'expected_minutes')::integer);
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  entity:=(p_dados->>'id')::uuid;
  SELECT * INTO h FROM public.folha_he WHERE id=entity AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501'; END IF;
  w:=h.obra_id; PERFORM folha_privado.obra(w); SELECT * INTO f FROM public.folha_registos WHERE id=h.folha_id;
  IF p_acao<>'he_reject' THEN
   PERFORM 1 FROM public.colaboradores c WHERE c.id=f.colaborador_id AND c.empresa_id=u.empresa_id AND lower(btrim(c.funcao))=ANY(coalesce(cfg.he_eligible_roles,ARRAY['pedreiro','servente'])) FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'HE_ROLE_NOT_ELIGIBLE'; END IF;
  END IF;
  IF f.revision<>h.folha_revision THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  IF (p_acao IN('he_approve','he_reject') AND ((u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR h.estado<>'potential'))
    OR (p_acao='he_validate' AND (NOT folha_privado.admin() OR h.estado<>'pending_validation'))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: transição HE' USING ERRCODE='42501'; END IF;
  before:=to_jsonb(h);rev:=h.revision;after:=jsonb_build_object('estado',CASE p_acao WHEN 'he_approve' THEN 'pending_validation' WHEN 'he_reject' THEN 'rejected' ELSE 'validated_pending_rule' END);
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace','vacation_entitlement') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  entity:=person;PERFORM folha_privado.lock_dia(person,(now() AT TIME ZONE 'Europe/Lisbon')::date);
  IF p_acao='vacation_entitlement' THEN
   IF (p_dados->>'days')::numeric IS NULL OR (p_dados->>'year')::integer IS NULL OR (p_dados->>'year')::integer NOT BETWEEN 2000 AND 2200
   OR EXISTS(SELECT 1 FROM jsonb_each(p_dados) x WHERE x.key IN('days','carry','additional') AND (jsonb_typeof(x.value)<>'number' OR (x.value#>>'{}')::numeric<>trunc((x.value#>>'{}')::numeric))) THEN RAISE EXCEPTION 'ENTITLEMENT_FULL_DAYS_REQUIRED'; END IF;
   SELECT to_jsonb(x),revision INTO before,rev FROM public.folha_direitos_ferias x WHERE colaborador_id=person AND ano=(p_dados->>'year')::integer FOR UPDATE;
   rev:=coalesce(rev,0);after:=jsonb_build_object('year',(p_dados->>'year')::integer,'days',(p_dados->>'days')::numeric,'source',p_dados->>'source');
   after:=after||jsonb_build_object('carry',coalesce((p_dados->>'carry')::integer,0),'additional',coalesce((p_dados->>'additional')::integer,0),'authorization',p_dados->>'authorization','carry_expires',make_date((p_dados->>'year')::integer,4,30));
   IF (after->>'days')::numeric<>trunc((after->>'days')::numeric) OR (after->>'carry')::integer<0 OR (after->>'additional')::integer<0 OR ((after->>'carry')::integer>0 OR (after->>'additional')::integer>0) AND nullif(btrim(after->>'authorization'),'') IS NULL THEN RAISE EXCEPTION 'ENTITLEMENT_ADJUSTMENT_INVALID'; END IF;
   IF after->>'source' IS NULL OR btrim(after->>'source')='' OR (after->>'days')::numeric<0 THEN RAISE EXCEPTION 'ENTITLEMENT_SOURCE_REQUIRED'; END IF;
  ELSE
   SELECT revision INTO rev FROM public.folha_ferias_revisoes WHERE colaborador_id=person FOR UPDATE;rev:=coalesce(rev,0);
   SELECT ARRAY(SELECT DISTINCT x::date FROM jsonb_array_elements_text(coalesce(p_dados->'dates','[]')) x ORDER BY x::date) INTO dates;
   IF p_dados ? 'from' THEN
    IF (p_dados->>'to')::date IS NULL OR (p_dados->>'to')::date<(p_dados->>'from')::date OR (p_dados->>'to')::date-(p_dados->>'from')::date>366 THEN RAISE EXCEPTION 'VALIDATION_ERROR: intervalo'; END IF;
    SELECT array_agg(DISTINCT x ORDER BY x) INTO dates FROM (SELECT unnest(dates) x UNION SELECT x::date FROM generate_series((p_dados->>'from')::date,(p_dados->>'to')::date,'1 day') x) s;
   END IF;
   scope_dates:=dates;
   IF p_acao='vacation_replace' THEN
    SELECT ARRAY(SELECT DISTINCT x::date FROM jsonb_array_elements_text(p_dados->'scope_dates') x ORDER BY x::date) INTO scope_dates;
    IF coalesce(cardinality(scope_dates),0) NOT BETWEEN 1 AND 367 OR EXISTS(SELECT 1 FROM unnest(dates) x WHERE NOT x=ANY(scope_dates)) THEN RAISE EXCEPTION 'VALIDATION_ERROR: âmbito férias'; END IF;
   ELSIF coalesce(cardinality(dates),0) NOT BETWEEN 1 AND 367 THEN RAISE EXCEPTION 'VALIDATION_ERROR: datas'; END IF;
   IF p_dados ? 'fraction' OR p_dados ? 'hours' OR p_dados ? 'period' THEN RAISE EXCEPTION 'VACATION_FULL_DAYS_ONLY'; END IF;
   IF p_acao IN('vacation_set','vacation_replace') THEN SELECT ARRAY(SELECT x FROM unnest(dates) x WHERE extract(isodow FROM x)<6 AND NOT x=ANY(coalesce(cfg.holiday_dates,'{}')) ORDER BY x) INTO dates; END IF;
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.data,x.id),'[]') INTO before FROM public.ausencias x WHERE colaborador_id=person AND data=ANY(scope_dates);
   IF p_acao IN('vacation_set','vacation_replace') AND EXISTS(SELECT 1 FROM unnest(dates) x JOIN public.colaboradores c ON c.id=person WHERE c.data_admissao IS NULL OR c.data_admissao>x OR c.data_saida<=x) THEN RAISE EXCEPTION 'COLLABORATOR_UNAVAILABLE'; END IF;
   IF p_acao IN('vacation_set','vacation_replace') AND (EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=ANY(dates) AND tipo<>'ferias')
    OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=ANY(dates))
    OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=ANY(dates))) AND NOT coalesce((p_dados->>'admin_override')::boolean,false)
   THEN RAISE EXCEPTION 'REGULARIZATION_REQUIRED'; END IF;
   pending:=NOT coalesce(cfg.calendar_complete,false) OR EXISTS(SELECT 1 FROM unnest(dates) x WHERE NOT extract(year FROM x)::integer=ANY(coalesce(cfg.calendar_validated_years,'{}')));
   after:=jsonb_build_object('dates',dates,'scope_dates',scope_dates,'consumed_days',CASE WHEN pending THEN NULL ELSE cardinality(dates) END,'pending_rule',false,'calendar_pending',pending,'override',coalesce((p_dados->>'admin_override')::boolean,false));
  END IF;
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  m:=(p_dados->>'month')::date; IF extract(day FROM m)<>1 OR m IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: competência'; END IF;
  SELECT * INTO v FROM public.folha_vencimentos WHERE colaborador_id=person AND competencia=m FOR UPDATE;
  entity:=coalesce(v.id,req);before:=to_jsonb(v);rev:=coalesce(v.revision,0);facts:=folha_privado.payroll_facts(person,m);
  IF p_acao='payroll_save' THEN
   IF v.estado IS NOT NULL AND v.estado<>'draft' THEN RAISE EXCEPTION 'PAYROLL_FROZEN'; END IF;
   IF jsonb_typeof(coalesce(p_dados->'manual','{}'))<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(p_dados->'manual','{}')) x WHERE x NOT IN('km','allowance','note')) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   FOR item IN SELECT jsonb_build_object('k',x.key,'v',x.value) FROM jsonb_each(coalesce(p_dados->'manual','{}')) x LOOP
    IF item->>'k'<>'note' AND item->'v'<>'null'::jsonb AND (jsonb_typeof(item->'v')<>'number' OR (item->>'v')::numeric<0) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   END LOOP;
   after:=jsonb_build_object('estado','draft','facts',facts,'manual',coalesce(p_dados->'manual','{}'));
  ELSE
   IF v.id IS NULL OR v.factos<>facts THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
   IF p_acao IN('payroll_validate','payroll_close') AND (NOT coalesce(cfg.calendar_complete,false) OR NOT extract(year FROM m)::integer=ANY(cfg.calendar_validated_years) OR jsonb_array_length(facts->'pending_days')>0 OR jsonb_array_length(facts->'legacy_days')>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'sheets') x WHERE x->>'state'<>'registered' OR (x->>'special_day')::boolean AND NOT coalesce((x->>'special_reviewed')::boolean,false)) OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'absences') x WHERE x->>'state'='ausente_pendente') OR v.manuais->>'km' IS NULL OR v.manuais->>'allowance' IS NULL) THEN RAISE EXCEPTION 'PAYROLL_PENDING_FACTS: regularize factos, calendário, quilómetros e ajudas de custo'; END IF;
   IF p_acao='payroll_reopen' AND v.estado IN('validated','closed') THEN after:=jsonb_build_object('estado','draft','facts',facts,'manual',v.manuais);
   ELSIF p_acao='payroll_validate' AND v.estado='draft' THEN after:=jsonb_build_object('estado','validated','facts',facts,'manual',v.manuais);
   ELSIF p_acao='payroll_close' AND v.estado='validated' THEN
    after:=jsonb_build_object('estado','closed','facts',facts,'manual',v.manuais,'recibos_recebidos',true);
   ELSIF p_acao='payroll_export' THEN RAISE EXCEPTION 'OFFICIAL_EXPORTER_REQUIRED: modelo e exportador oficial ainda não instalados';
   ELSE RAISE EXCEPTION 'PAYROLL_TRANSITION_INVALID'; END IF;
  END IF;
 ELSIF p_acao IN('task_report','task_confirm') THEN
  entity:=(p_dados->>'task_id')::uuid;
  SELECT p.* INTO task FROM public.planeamento_itens p JOIN public.fases fase ON fase.id=p.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE p.id=entity AND o.empresa_id=u.empresa_id AND fase.obra_id=w FOR UPDATE OF p FOR SHARE OF fase,o;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501'; END IF;
  PERFORM folha_privado.obra(w);
  SELECT * INTO t FROM public.folha_tarefas_reportes WHERE tarefa_id=entity FOR UPDATE;before:=to_jsonb(t);rev:=coalesce(t.revision,0);
  IF p_acao='task_report' THEN
   IF (u.funcao<>'encarregado' AND NOT folha_privado.superuser()) OR task.estado='concluido' OR task.arquivado_em IS NOT NULL OR t.id IS NOT NULL THEN RAISE EXCEPTION 'TASK_REPORT_INVALID'; END IF;
   after:=jsonb_build_object('estado','reported');
  ELSE
   IF (u.funcao NOT IN('diretor_obra','adjunto') AND NOT folha_privado.superuser()) OR t.estado IS DISTINCT FROM 'reported' OR task.estado<>'concluido' THEN RAISE EXCEPTION 'PLANNING_CONFIRMATION_REQUIRED'; END IF;
   after:=jsonb_build_object('estado','confirmed');
  END IF;
 ELSE RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
 IF expected IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',before,'after',after,'config',to_jsonb(cfg))::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='configure_he_eligibility' THEN
  INSERT INTO public.folha_config_empresa(empresa_id,he_eligible_roles,revision) VALUES(u.empresa_id,ARRAY(SELECT x FROM jsonb_array_elements_text(after->'roles') x),rev+1) ON CONFLICT(empresa_id) DO UPDATE SET he_eligible_roles=excluded.he_eligible_roles,revision=excluded.revision;
 ELSIF p_acao='absence_confirm' THEN
  previous_request:=current_setting('folha.request_id',true);PERFORM set_config('folha.request_id',req::text,true);
  UPDATE public.ausencias SET estado=after->>'estado',comentario=p_dados->>'reason' WHERE id=entity;
  PERFORM set_config('folha.request_id',coalesce(previous_request,''),true);
 ELSIF p_acao='special_review' THEN
  UPDATE public.folha_registos SET special_reviewed_by=u.id,special_reviewed_at=now(),revision=revision+1,atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=entity RETURNING * INTO f;
  after:=after||to_jsonb(f)||jsonb_build_object('special_reviewed',true);
 ELSIF p_acao='he_process' THEN
  UPDATE public.folha_he SET processado_em=now(),processado_por=u.id,revision=revision+1 WHERE id=entity;
  UPDATE public.alertas SET estado='resolvido',resolvido_em=now(),resolvido_por=u.id WHERE empresa_id=u.empresa_id AND entidade_id=entity AND tipo='folha_he_processamento' AND estado='pendente';
 ELSIF p_acao='configure_company' THEN
  INSERT INTO public.folha_config_empresa(empresa_id,office_expected_minutes,correction_days,overtime_enabled,calendar_complete,holiday_dates,payroll_rules_ready,official_template_hash,revision)
   VALUES(u.empresa_id,(after->>'office_expected_minutes')::integer,(after->>'correction_days')::integer,(after->>'overtime_enabled')::boolean,(after->>'calendar_complete')::boolean,
    ARRAY(SELECT x::date FROM jsonb_array_elements_text(after->'holiday_dates') x),(after->>'payroll_rules_ready')::boolean,after->>'official_template_hash',rev+1)
   ON CONFLICT(empresa_id) DO UPDATE SET office_expected_minutes=excluded.office_expected_minutes,correction_days=excluded.correction_days,overtime_enabled=excluded.overtime_enabled,calendar_complete=excluded.calendar_complete,
    holiday_dates=excluded.holiday_dates,payroll_rules_ready=excluded.payroll_rules_ready,official_template_hash=excluded.official_template_hash,revision=excluded.revision;
  UPDATE public.folha_config_empresa SET calendar_validated_years=ARRAY(SELECT x::integer FROM jsonb_array_elements_text(after->'calendar_validated_years') x) WHERE empresa_id=u.empresa_id;
 ELSIF p_acao='configure_schedule' THEN
  INSERT INTO public.folha_horarios VALUES(w,u.empresa_id,after->'intervals',(after->>'expected_minutes')::integer,rev+1)
   ON CONFLICT(obra_id) DO UPDATE SET intervals=excluded.intervals,expected_minutes=excluded.expected_minutes,revision=excluded.revision;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  UPDATE public.folha_he SET estado=after->>'estado',revision=rev+1,prazo_processamento=CASE WHEN p_acao='he_validate' THEN folha_privado.prazo_he(u.empresa_id,f.data) ELSE prazo_processamento END WHERE id=entity RETURNING * INTO h;
  IF p_acao='he_validate' AND h.prazo_processamento IS NOT NULL THEN
   INSERT INTO public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave)
   SELECT u.empresa_id,NULL,'folha_he_processamento','folha_he',h.id,'HE validada: processamento pendente',h.prazo_processamento,dest.id,false,req FROM public.utilizadores dest WHERE dest.empresa_id=u.empresa_id AND dest.ativo AND dest.funcao='administrativo';
  END IF;
 ELSIF p_acao='vacation_entitlement' THEN
  INSERT INTO public.folha_direitos_ferias(empresa_id,colaborador_id,ano,dias,fonte,revision,saldo_transitado,validade_transitado,dias_adicionais,autorizacao) VALUES(u.empresa_id,person,(after->>'year')::integer,(after->>'days')::numeric,after->>'source',rev+1,(after->>'carry')::integer,(after->>'carry_expires')::date,(after->>'additional')::integer,after->>'authorization')
   ON CONFLICT(colaborador_id,ano) DO UPDATE SET dias=excluded.dias,fonte=excluded.fonte,revision=excluded.revision,saldo_transitado=excluded.saldo_transitado,validade_transitado=excluded.validade_transitado,dias_adicionais=excluded.dias_adicionais,autorizacao=excluded.autorizacao;
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace') THEN
  -- Correlation only; this setting never grants permissions. Triggers resolve actor/tenant independently.
  previous_request:=current_setting('folha.request_id',true);PERFORM set_config('folha.request_id',req::text,true);
  IF p_acao='vacation_remove' THEN DELETE FROM public.ausencias WHERE colaborador_id=person AND data=ANY(dates) AND tipo='ferias';
  ELSE
   IF p_acao='vacation_replace' THEN DELETE FROM public.ausencias WHERE colaborador_id=person AND data=ANY(scope_dates) AND NOT data=ANY(dates) AND tipo='ferias'; END IF;
   FOREACH a IN ARRAY dates LOOP
    IF NOT EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=a AND tipo='ferias') THEN
     INSERT INTO public.ausencias(colaborador_id,data,tipo,estado,comentario) VALUES(person,a,'ferias','confirmada',p_dados->>'reason');
    END IF;
   END LOOP;
  END IF;
  INSERT INTO public.folha_ferias_revisoes VALUES(u.empresa_id,person,rev+1) ON CONFLICT(colaborador_id) DO UPDATE SET revision=excluded.revision;
  PERFORM set_config('folha.request_id',coalesce(previous_request,''),true);
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close','payroll_reopen') THEN
  INSERT INTO public.folha_vencimentos(id,empresa_id,colaborador_id,competencia,factos,manuais,estado,revision,criado_por,atualizado_por)
   VALUES(entity,u.empresa_id,person,m,after->'facts',after->'manual',after->>'estado',rev+1,u.id,u.id)
   ON CONFLICT(colaborador_id,competencia) DO UPDATE SET factos=excluded.factos,manuais=excluded.manuais,estado=excluded.estado,revision=excluded.revision,atualizado_por=u.id,atualizado_em=now();
  IF p_acao='payroll_close' THEN UPDATE public.folha_vencimentos SET recibos_recebidos_em=now(),recibos_recebidos_por=u.id WHERE id=entity; ELSIF p_acao='payroll_reopen' THEN UPDATE public.folha_vencimentos SET recibos_recebidos_em=NULL,recibos_recebidos_por=NULL WHERE id=entity; END IF;
 ELSIF p_acao='task_report' THEN
  INSERT INTO public.folha_tarefas_reportes(empresa_id,obra_id,tarefa_id,estado,reportado_por) VALUES(u.empresa_id,w,entity,'reported',u.id);
  INSERT INTO public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave)
   SELECT u.empresa_id,w,'folha_conclusao_reportada','planeamento_item',entity,'Conclusão reportada: validar no Planeamento',
   format('Obra %s · tarefa %s · %s. Reportado por %s em %s. Aguarda confirmação no Planeamento.',(SELECT numero FROM public.obras WHERE id=w),coalesce(to_jsonb(task)->>'codigo',entity::text),coalesce(to_jsonb(task)->>'descricao',''),u.nome,now()),
   (now() AT TIME ZONE 'Europe/Lisbon')::date,r.utilizador_id,false,req
   FROM public.obra_responsaveis r JOIN public.utilizadores dest ON dest.id=r.utilizador_id WHERE r.obra_id=w AND r.papel IN('diretor_obra','adjunto') AND dest.ativo AND dest.empresa_id=u.empresa_id;
 ELSE
  UPDATE public.folha_tarefas_reportes SET estado='confirmed',confirmado_por=u.id,confirmado_em=now(),revision=rev+1 WHERE tarefa_id=entity;
  UPDATE public.alertas SET estado='resolvido',resolvido_por=u.id,resolvido_em=now() WHERE empresa_id=u.empresa_id AND obra_id=w AND entidade_id=entity AND entidade_tipo='planeamento_item' AND tipo='folha_conclusao_reportada' AND estado='pendente';
 END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,p_acao,entity,before,after,u.id,req,p_dados->>'reason');
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',rev+1,'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: public.fn_folha_gestao_v2(text,jsonb,boolean,text)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_gestao_contexto_v2(uuid,uuid,date)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE response jsonb; u public.utilizadores;
BEGIN
 response:=folha_privado.gestao_contexto_preservado(p_obra_id,p_colaborador_id,p_competencia);u:=folha_privado.ator();
 RETURN response||jsonb_build_object('task_reports',coalesce((SELECT jsonb_agg(x.value||jsonb_build_object('reportado_nome',a.nome) ORDER BY x.value->>'id') FROM jsonb_array_elements(response->'task_reports') x LEFT JOIN public.utilizadores a ON a.id=(x.value->>'reportado_por')::uuid AND a.empresa_id=u.empresa_id),'[]'::jsonb));
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: public.fn_folha_gestao_contexto_v2(uuid,uuid,date)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.save(jsonb,uuid,date,uuid,boolean)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
 row jsonb; f jsonb; state text; expected integer; window_days integer; special boolean; result public.folha_registos;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.local(person,w,true); PERFORM folha_privado.lock_dia(person,d);
 IF p->'key'->>'work_id' IS DISTINCT FROM w::text OR p->'key'->>'date' IS DISTINCT FROM d::text OR kind IS NULL OR kind NOT IN('primeline','external')
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: chave'; END IF;
 row:=folha_privado.linha(person,w,d,kind);
 IF kind='primeline' AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'LEGACY_CONFLICT: não misturar escritores'; END IF;
 IF kind='primeline' THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador indisponível' USING ERRCODE='42501'; END IF;
  IF u.funcao='encarregado' AND NOT folha_privado.elegivel_equipa(person,d) AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND (SELECT count(*) FROM public.colaboradores WHERE utilizador_id=u.id AND empresa_id=u.empresa_id)=1) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas equipa operacional elegível' USING ERRCODE='42501'; END IF;
  IF w IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.fn_quadro_resolver_data(d) WHERE colaborador_id=person AND obra_id=w)
 AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND u.funcao IN('encarregado','diretor_obra','adjunto','preparador')) AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias m WHERE m.colaborador_id=person AND m.empresa_id=u.empresa_id AND m.inicio<=d AND (m.fim IS NULL OR m.fim>d) AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=m.obra_id AND r.utilizador_id=u.id AND r.papel=u.funcao))) THEN RAISE EXCEPTION 'ALLOCATION_REQUIRED'; END IF;
 ELSE
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND ativo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo indisponível' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=w))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor não autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d AND empresa_id=u.empresa_id) AND NOT EXISTS(SELECT 1 FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND empresa_id=u.empresa_id AND inicio<=d AND (fim IS NULL OR fim>d)) THEN RAISE EXCEPTION 'EXTERNAL_DAY_REQUIRED'; END IF;
 END IF;
 IF row->>'conflict' IS NOT NULL THEN RAISE EXCEPTION '%',row->>'conflict'; END IF;
 SELECT * INTO old FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND CASE WHEN kind='primeline' THEN colaborador_id=person ELSE externo_id=person END FOR UPDATE;
 IF kind='primeline' AND old.id IS NULL THEN SELECT revision INTO old.revision FROM folha_privado.periodos_revisoes WHERE colaborador_id=person AND obra_id IS NOT DISTINCT FROM w AND data=d; END IF;
 IF (p->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT folha_privado.adm_operacional() THEN
  window_days:=1;
  IF window_days IS NULL THEN RAISE EXCEPTION 'CORRECTION_WINDOW_UNCONFIGURED'; END IF;
  IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>window_days THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 END IF;
 IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>1 AND folha_privado.adm_operacional() AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
 f:=folha_privado.facts(p->'intervals',d); expected:=(row->>'expected_minutes')::integer;
 special:=extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND d=ANY(holiday_dates));
 IF EXISTS(SELECT 1 FROM public.folha_registos other,jsonb_array_elements(other.intervals) x,jsonb_array_elements(p->'intervals') y
 WHERE other.data=d AND other.obra_id IS DISTINCT FROM w AND (CASE WHEN kind='primeline' THEN other.colaborador_id=person ELSE other.externo_id=person END)
 AND (x->>'start')::time<coalesce((y->>'end')::time,'24:00'::time) AND (y->>'start')::time<coalesce((x->>'end')::time,'24:00'::time))
 THEN RAISE EXCEPTION 'INTERVAL_CONFLICT: outra obra'; END IF;
 state:=folha_privado.estado_efetivo((f->>'minutes')::integer,(f->>'open')::boolean,expected,row->'absence'<>'null'::jsonb,row->>'conflict' IS NOT NULL);
 IF kind='external' THEN state:=CASE WHEN row->>'conflict' IS NOT NULL OR coalesce(row->'absence'<>'null'::jsonb,false) THEN 'regularization' WHEN (f->>'open')::boolean THEN 'open' ELSE 'registered' END; expected:=NULL; END IF;
 IF kind='external' AND jsonb_array_length(p->'intervals')>2 THEN RAISE EXCEPTION 'TWO_PERIODS_REQUIRED'; END IF;
 IF NOT confirmar THEN RETURN jsonb_build_object('before',to_jsonb(old),'revision',coalesce(old.revision,0),'row',row,'facts',f,'state',state); END IF;
 IF kind='external' THEN INSERT INTO public.folha_externos_dias(externo_id,empresa_id,obra_id,data,criado_por,request_id,funcao) SELECT person,u.empresa_id,w,d,u.id,req,funcao FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d) ON CONFLICT DO NOTHING; END IF;
 IF old.id IS NOT NULL THEN
 UPDATE public.folha_registos SET intervals=p->'intervals',minutes=(f->>'minutes')::integer,estado=state,special_day=old.special_day,special_reviewed_at=NULL,special_reviewed_by=NULL,
 revision=old.revision+1,note=p->>'note',atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=old.id RETURNING * INTO result;
 ELSE
 INSERT INTO public.folha_registos(empresa_id,obra_id,tipo_local,data,colaborador_id,externo_id,intervals,minutes,estado,special_day,expected_minutes,revision,note,criado_por,atualizado_por,request_id)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,d,CASE WHEN kind='primeline' THEN person END,CASE WHEN kind='external' THEN person END,p->'intervals',(f->>'minutes')::integer,state,special,expected,coalesce(old.revision,0)+1,p->>'note',u.id,u.id,req)
 RETURNING * INTO result;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,kind,d,'save',to_jsonb(old),to_jsonb(result),result.revision,u.id,req,p->>'reason');
 IF kind='primeline' THEN PERFORM folha_privado.reconciliar_he(result); END IF;
 RETURN jsonb_build_object('result',to_jsonb(result));
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.save(jsonb,uuid,date,uuid,boolean)'; END IF;
 IF btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)'::regprocedure),chr(13),''),E' \n\t') IS DISTINCT FROM $baseline$DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
 row jsonb; f jsonb; state text; expected integer; window_days integer; special boolean; result public.folha_registos;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.local(person,w,true); PERFORM folha_privado.lock_dia(person,d);
 IF p->'key'->>'work_id' IS DISTINCT FROM w::text OR p->'key'->>'date' IS DISTINCT FROM d::text OR kind IS NULL OR kind NOT IN('primeline','external')
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: chave'; END IF;
 row:=folha_privado.linha(person,w,d,kind);
 IF kind='primeline' AND EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'LEGACY_CONFLICT: não misturar escritores'; END IF;
 IF kind='primeline' THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador indisponível' USING ERRCODE='42501'; END IF;
  IF u.funcao='encarregado' AND NOT folha_privado.elegivel_equipa(person,d) AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND (SELECT count(*) FROM public.colaboradores WHERE utilizador_id=u.id AND empresa_id=u.empresa_id)=1) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas equipa operacional elegível' USING ERRCODE='42501'; END IF;
  IF w IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.fn_quadro_resolver_data(d) WHERE colaborador_id=person AND obra_id=w)
 AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND utilizador_id=u.id AND empresa_id=u.empresa_id AND u.funcao IN('encarregado','diretor_obra','adjunto','preparador')) AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias m WHERE m.colaborador_id=person AND m.empresa_id=u.empresa_id AND m.inicio<=d AND (m.fim IS NULL OR m.fim>d) AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=m.obra_id AND r.utilizador_id=u.id AND r.papel=u.funcao))) THEN RAISE EXCEPTION 'ALLOCATION_REQUIRED'; END IF;
 ELSE
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND ativo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo indisponível' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=w))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor não autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d AND empresa_id=u.empresa_id) AND NOT EXISTS(SELECT 1 FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND empresa_id=u.empresa_id AND inicio<=d AND (fim IS NULL OR fim>d)) THEN RAISE EXCEPTION 'EXTERNAL_DAY_REQUIRED'; END IF;
 END IF;
 IF row->>'conflict' IS NOT NULL THEN RAISE EXCEPTION '%',row->>'conflict'; END IF;
 SELECT * INTO old FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND CASE WHEN kind='primeline' THEN colaborador_id=person ELSE externo_id=person END FOR UPDATE;
 IF kind='primeline' AND old.id IS NULL THEN SELECT revision INTO old.revision FROM folha_privado.periodos_revisoes WHERE colaborador_id=person AND obra_id IS NOT DISTINCT FROM w AND data=d; END IF;
 IF (p->>'expected_revision')::integer IS DISTINCT FROM coalesce(old.revision,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT folha_privado.adm_operacional() THEN
  window_days:=1;
  IF window_days IS NULL THEN RAISE EXCEPTION 'CORRECTION_WINDOW_UNCONFIGURED'; END IF;
  IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>window_days THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 END IF;
 IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>1 AND folha_privado.adm_operacional() AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
 f:=folha_privado.facts(p->'intervals',d); expected:=(row->>'expected_minutes')::integer; IF w IS NOT NULL THEN SELECT sum((extract(epoch FROM ((h.x->>'end')::time-(h.x->>'start')::time))/60)::integer) INTO expected FROM public.folha_horarios schedule CROSS JOIN LATERAL jsonb_array_elements(schedule.intervals) h(x) WHERE schedule.obra_id=w AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->'intervals') period WHERE period->>'period'=h.x->>'period'); END IF;
 special:=extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND d=ANY(holiday_dates));
 IF EXISTS(SELECT 1 FROM public.folha_registos other,jsonb_array_elements(other.intervals) x,jsonb_array_elements(p->'intervals') y
 WHERE other.data=d AND other.obra_id IS DISTINCT FROM w AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(plano) target WHERE target->>'work_id' IS NOT DISTINCT FROM other.obra_id::text) AND (CASE WHEN kind='primeline' THEN other.colaborador_id=person ELSE other.externo_id=person END)
 AND (x->>'start')::time<coalesce((y->>'end')::time,'24:00'::time) AND (y->>'start')::time<coalesce((x->>'end')::time,'24:00'::time))
 THEN RAISE EXCEPTION 'INTERVAL_CONFLICT: outra obra'; END IF;
 state:=folha_privado.estado_efetivo((f->>'minutes')::integer,(f->>'open')::boolean,expected,row->'absence'<>'null'::jsonb,row->>'conflict' IS NOT NULL);
 IF kind='external' THEN state:=CASE WHEN row->>'conflict' IS NOT NULL OR coalesce(row->'absence'<>'null'::jsonb,false) THEN 'regularization' WHEN (f->>'open')::boolean THEN 'open' ELSE 'registered' END; expected:=NULL; END IF;
 IF kind='external' AND jsonb_array_length(p->'intervals')>2 THEN RAISE EXCEPTION 'TWO_PERIODS_REQUIRED'; END IF;
 IF NOT confirmar THEN RETURN jsonb_build_object('before',to_jsonb(old),'revision',coalesce(old.revision,0),'row',row,'facts',f,'state',state); END IF;
 IF kind='external' THEN INSERT INTO public.folha_externos_dias(externo_id,empresa_id,obra_id,data,criado_por,request_id,funcao) SELECT person,u.empresa_id,w,d,u.id,req,funcao FROM public.folha_externos_permanencias WHERE externo_id=person AND obra_id=w AND inicio<=d AND (fim IS NULL OR fim>d) ON CONFLICT DO NOTHING; END IF;
 IF old.id IS NOT NULL THEN
 UPDATE public.folha_registos SET expected_minutes=expected,intervals=p->'intervals',minutes=(f->>'minutes')::integer,estado=state,special_day=old.special_day,special_reviewed_at=NULL,special_reviewed_by=NULL,
 revision=old.revision+1,note=p->>'note',atualizado_por=u.id,atualizado_em=now(),request_id=req WHERE id=old.id RETURNING * INTO result;
 ELSE
 INSERT INTO public.folha_registos(empresa_id,obra_id,tipo_local,data,colaborador_id,externo_id,intervals,minutes,estado,special_day,expected_minutes,revision,note,criado_por,atualizado_por,request_id)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,d,CASE WHEN kind='primeline' THEN person END,CASE WHEN kind='external' THEN person END,p->'intervals',(f->>'minutes')::integer,state,special,expected,coalesce(old.revision,0)+1,p->>'note',u.id,u.id,req)
 RETURNING * INTO result;
 END IF;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,kind,d,'save',to_jsonb(old),to_jsonb(result),result.revision,u.id,req,p->>'reason');
 IF kind='primeline' THEN PERFORM folha_privado.reconciliar_he(result); END IF;
 RETURN jsonb_build_object('result',to_jsonb(result));
END$baseline$ THEN RAISE EXCEPTION 'DAILY_BASELINE_DRIFT: folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)'; END IF;
END $$;
SELECT 'DAILY_PRECHECK_PASS' resultado,clock_timestamp() verificado_em;
SELECT h.obra_id,h.empresa_id,h.revision,h.expected_minutes,h.intervals FROM public.folha_horarios h ORDER BY h.obra_id;
SELECT c.relname,c.relowner::regrole owner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
 (SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'acl',a.attacl) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) colunas,
 (SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid) constraints,
 (SELECT jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal) triggers,
 (SELECT jsonb_agg(to_jsonb(pol)) FROM pg_policies pol WHERE pol.schemaname='public' AND pol.tablename=c.relname) policies
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN('folha_config_empresa','folha_horarios','folha_registos','folha_historico','folha_he','folha_vencimentos','folha_gestao_historico','quadro_equipa_permanencias','ausencias','quadro_pessoal_alocacao','ponto_pessoal_obra');
SELECT p.oid::regprocedure assinatura,pg_get_functiondef(p.oid) definicao,p.proowner::regrole owner,p.proacl FROM pg_proc p WHERE p.oid=ANY(ARRAY['folha_privado.operar_periodos(jsonb,boolean,text)','folha_privado.reconciliar_he(public.folha_registos)','folha_privado.reconciliar_dia(uuid,date,uuid,text)','folha_privado.linha(uuid,uuid,date,text)','folha_privado.normal(uuid,uuid,date)','folha_privado.payroll_facts(uuid,date)','public.fn_folha_gestao_v2(text,jsonb,boolean,text)','public.fn_folha_gestao_contexto_v2(uuid,uuid,date)','folha_privado.save_periodo(jsonb,uuid,date,uuid,boolean,jsonb)','folha_privado.save(jsonb,uuid,date,uuid,boolean)']::regprocedure[]);
COMMIT;
