-- Complemento local: factos administrativos, sem cálculo monetário/consumo presumido.
BEGIN;
DO $$ BEGIN IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501'; END IF; END $$;
ALTER TABLE public.folha_config_empresa ADD COLUMN payroll_rules_ready boolean NOT NULL DEFAULT false;
ALTER TABLE public.folha_config_empresa ADD COLUMN official_template_hash text CHECK(official_template_hash ~ '^[0-9a-f]{64}$');
CREATE TABLE public.folha_direitos_ferias(
 empresa_id uuid NOT NULL REFERENCES public.empresas(id), colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id),
 ano integer NOT NULL CHECK(ano BETWEEN 2000 AND 2200), dias numeric NOT NULL CHECK(dias>=0),
 fonte text NOT NULL CHECK(length(btrim(fonte))>0), revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 PRIMARY KEY(colaborador_id,ano)
);
CREATE TABLE public.folha_ferias_revisoes(
 empresa_id uuid NOT NULL, colaborador_id uuid PRIMARY KEY REFERENCES public.colaboradores(id), revision integer NOT NULL DEFAULT 1
);
CREATE TABLE public.folha_vencimentos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id), competencia date NOT NULL CHECK(extract(day FROM competencia)=1),
 factos jsonb NOT NULL, manuais jsonb NOT NULL DEFAULT '{}',
 estado text NOT NULL CHECK(estado IN('draft','validated','closed','exported')), revision integer NOT NULL DEFAULT 1,
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id), atualizado_por uuid NOT NULL REFERENCES public.utilizadores(id),
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(),
 UNIQUE(colaborador_id,competencia)
);
CREATE TABLE public.folha_tarefas_reportes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id), obra_id uuid NOT NULL REFERENCES public.obras(id),
 tarefa_id uuid NOT NULL REFERENCES public.planeamento_itens(id), estado text NOT NULL CHECK(estado IN('reported','confirmed')),
 reportado_por uuid NOT NULL REFERENCES public.utilizadores(id), reportado_em timestamptz NOT NULL DEFAULT now(),
 confirmado_por uuid REFERENCES public.utilizadores(id), confirmado_em timestamptz, revision integer NOT NULL DEFAULT 1,
 UNIQUE(tarefa_id)
);
CREATE TABLE public.folha_gestao_historico(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, obra_id uuid,
 action text NOT NULL CHECK(action IN('configure_company','configure_schedule','he_approve','he_reject','he_validate','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','task_report','task_confirm','planning_concluded_alerts_resolved')),
 dominio text GENERATED ALWAYS AS (CASE
 WHEN action IN('task_report','task_confirm','planning_concluded_alerts_resolved') THEN 'tarefas'
 WHEN action IN('he_approve','he_reject','he_validate') THEN 'he'
 WHEN action='configure_schedule' THEN 'horario'
 ELSE 'administrativo' END) STORED,
 entidade_id uuid NOT NULL, antes jsonb, depois jsonb,
 ator_id uuid NOT NULL REFERENCES public.utilizadores(id), at timestamptz NOT NULL DEFAULT now(),
 request_id uuid NOT NULL, reason text CHECK(length(reason)<=1000), origem text NOT NULL DEFAULT 'folha_v2'
);
CREATE INDEX folha_gestao_historico_entidade ON public.folha_gestao_historico(empresa_id,entidade_id,at);
CREATE TRIGGER folha_gestao_historico_imutavel BEFORE UPDATE OR DELETE ON public.folha_gestao_historico FOR EACH ROW EXECUTE FUNCTION folha_privado.imutavel();
CREATE TRIGGER folha_integridade BEFORE INSERT OR UPDATE ON public.folha_direitos_ferias FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade();
CREATE TRIGGER folha_integridade BEFORE INSERT OR UPDATE ON public.folha_ferias_revisoes FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade();
CREATE TRIGGER folha_integridade BEFORE INSERT OR UPDATE ON public.folha_vencimentos FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade();
CREATE TRIGGER folha_integridade BEFORE INSERT OR UPDATE ON public.folha_tarefas_reportes FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade();
CREATE FUNCTION folha_privado.payroll_facts(p uuid,m date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'minutes',f.minutes,'state',f.estado,'special_day',f.special_day) ORDER BY f.data,f.id)
 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data>=m AND f.data<(m+interval '1 month')::date),'[]'),
 'absences',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'type',a.tipo,'state',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date),'[]'),
 'pending_days',coalesce((SELECT jsonb_agg(data ORDER BY data) FROM (SELECT DISTINCT q.data FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=m AND q.data<(m+interval '1 month')::date AND q.data<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=q.data AND f.obra_id IS NOT DISTINCT FROM q.obra_id) AND NOT EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=q.data)) missing),'[]'),
 'legacy_days',coalesce((SELECT jsonb_agg(DISTINCT data ORDER BY data) FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data>=m AND data<(m+interval '1 month')::date),'[]'),
 'financial_effect',false,'legacy_not_converted',true)
$$;
CREATE FUNCTION public.fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; req uuid:=(p_dados->>'request_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid;
 person uuid:=(p_dados->>'person_id')::uuid; entity uuid; before jsonb; after jsonb; payload jsonb; op folha_privado.operacoes;
 token text; result jsonb; expected integer; rev integer; d date; m date; dates date[]; scope_dates date[]; a date; item jsonb;
 h public.folha_he; f public.folha_registos; v public.folha_vencimentos; t public.folha_tarefas_reportes; task public.planeamento_itens;
 cfg public.folha_config_empresa; facts jsonb; pending boolean; consumed integer:=0; histids jsonb;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao IN('configure_company','configure_schedule','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export') AND NOT folha_privado.admin()
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao IN('configure_company','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export') AND w IS NOT NULL THEN
  RAISE EXCEPTION 'ADMIN_WORK_SCOPE_INVALID: ação administrativa sem obra' USING ERRCODE='22023';
 END IF;
 -- Replays must obey the actor's CURRENT role and work scope.
 IF p_acao IN('task_report','task_confirm') THEN
  PERFORM folha_privado.obra(w);
  IF p_acao='task_report' AND u.funcao<>'encarregado' OR p_acao='task_confirm' AND u.funcao NOT IN('diretor_obra','adjunto') THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: tarefa' USING ERRCODE='42501';
  END IF;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN
  SELECT * INTO h FROM public.folha_he WHERE id=(p_dados->>'id')::uuid AND empresa_id=u.empresa_id;
  IF NOT FOUND OR p_acao IN('he_approve','he_reject') AND u.funcao NOT IN('diretor_obra','adjunto') OR p_acao='he_validate' AND NOT folha_privado.admin() THEN
   RAISE EXCEPTION 'PERMISSION_DENIED: HE' USING ERRCODE='42501';
  END IF;
  PERFORM folha_privado.obra(h.obra_id);
 END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados,'contract','gestao_v2');
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 expected:=(p_dados->>'expected_revision')::integer;
 IF p_acao='configure_company' THEN
  before:=to_jsonb(cfg); entity:=u.empresa_id; rev:=coalesce(cfg.revision,0);
  IF p_dados ? 'correction_days' AND (p_dados->>'correction_days')::integer<0 THEN RAISE EXCEPTION 'VALIDATION_ERROR: janela'; END IF;
  IF p_dados ? 'office_expected_minutes' AND coalesce((p_dados->>'office_expected_minutes')::integer,0) NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'VALIDATION_ERROR: carga escritório'; END IF;
  after:=jsonb_build_object('office_expected_minutes',coalesce((p_dados->>'office_expected_minutes')::integer,cfg.office_expected_minutes,480),'correction_days',(p_dados->>'correction_days')::integer,'overtime_enabled',coalesce((p_dados->>'overtime_enabled')::boolean,false),
    'calendar_complete',coalesce((p_dados->>'calendar_complete')::boolean,false),'holiday_dates',coalesce(p_dados->'holiday_dates','[]'),
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
  IF f.revision<>h.folha_revision THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
  IF (p_acao IN('he_approve','he_reject') AND (u.funcao NOT IN('diretor_obra','adjunto') OR h.estado<>'potential'))
    OR (p_acao='he_validate' AND (NOT folha_privado.admin() OR h.estado<>'pending_validation'))
  THEN RAISE EXCEPTION 'PERMISSION_DENIED: transição HE' USING ERRCODE='42501'; END IF;
  before:=to_jsonb(h);rev:=h.revision;after:=jsonb_build_object('estado',CASE p_acao WHEN 'he_approve' THEN 'pending_validation' WHEN 'he_reject' THEN 'rejected' ELSE 'validated_pending_rule' END);
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace','vacation_entitlement') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  entity:=person;PERFORM folha_privado.lock_dia(person,(now() AT TIME ZONE 'Europe/Lisbon')::date);
  IF p_acao='vacation_entitlement' THEN
   SELECT to_jsonb(x),revision INTO before,rev FROM public.folha_direitos_ferias x WHERE colaborador_id=person AND ano=(p_dados->>'year')::integer FOR UPDATE;
   rev:=coalesce(rev,0);after:=jsonb_build_object('year',(p_dados->>'year')::integer,'days',(p_dados->>'days')::numeric,'source',p_dados->>'source');
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
   SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.data,x.id),'[]') INTO before FROM public.ausencias x WHERE colaborador_id=person AND data=ANY(scope_dates);
   IF p_acao IN('vacation_set','vacation_replace') AND EXISTS(SELECT 1 FROM unnest(dates) x JOIN public.colaboradores c ON c.id=person WHERE c.data_admissao IS NULL OR c.data_admissao>x OR c.data_saida<=x) THEN RAISE EXCEPTION 'COLLABORATOR_UNAVAILABLE'; END IF;
   IF p_acao IN('vacation_set','vacation_replace') AND (EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=ANY(dates) AND tipo<>'ferias')
    OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=ANY(dates))
    OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=ANY(dates))) AND NOT coalesce((p_dados->>'admin_override')::boolean,false)
   THEN RAISE EXCEPTION 'REGULARIZATION_REQUIRED'; END IF;
   pending:=NOT coalesce(cfg.calendar_complete,false) OR EXISTS(SELECT 1 FROM unnest(dates) x WHERE extract(isodow FROM x)>5 OR x=ANY(cfg.holiday_dates));
   after:=jsonb_build_object('dates',dates,'scope_dates',scope_dates,'consumed_days',CASE WHEN pending THEN NULL ELSE cardinality(dates) END,'pending_rule',pending,'override',coalesce((p_dados->>'admin_override')::boolean,false));
  END IF;
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close','payroll_export') THEN
  PERFORM 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  m:=(p_dados->>'month')::date; IF extract(day FROM m)<>1 OR m IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: competência'; END IF;
  SELECT * INTO v FROM public.folha_vencimentos WHERE colaborador_id=person AND competencia=m FOR UPDATE;
  entity:=coalesce(v.id,req);before:=to_jsonb(v);rev:=coalesce(v.revision,0);facts:=folha_privado.payroll_facts(person,m);
  IF p_acao='payroll_save' THEN
   IF v.estado IS NOT NULL AND v.estado<>'draft' THEN RAISE EXCEPTION 'PAYROLL_FROZEN'; END IF;
   IF jsonb_typeof(coalesce(p_dados->'manual','{}'))<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(coalesce(p_dados->'manual','{}')) x WHERE x NOT IN('premium','km','allowance','note')) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   FOR item IN SELECT jsonb_build_object('k',x.key,'v',x.value) FROM jsonb_each(coalesce(p_dados->'manual','{}')) x LOOP
    IF item->>'k'<>'note' AND item->'v'<>'null'::jsonb AND (jsonb_typeof(item->'v')<>'number' OR (item->>'v')::numeric<0) THEN RAISE EXCEPTION 'MANUAL_FIELDS_INVALID'; END IF;
   END LOOP;
   after:=jsonb_build_object('estado','draft','facts',facts,'manual',coalesce(p_dados->'manual','{}'));
  ELSE
   IF v.id IS NULL OR v.factos<>facts THEN RAISE EXCEPTION 'STALE_SOURCE' USING ERRCODE='40001'; END IF;
   IF p_acao='payroll_validate' AND v.estado='draft' THEN after:=jsonb_build_object('estado','validated','facts',facts,'manual',v.manuais);
   ELSIF p_acao='payroll_close' AND v.estado='validated' THEN
    IF NOT coalesce(cfg.payroll_rules_ready,false) OR jsonb_array_length(facts->'pending_days')>0 OR jsonb_array_length(facts->'legacy_days')>0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(facts->'sheets') x WHERE x->>'state' IN('open','missing','regularization') OR (x->>'special_day')::boolean)
    THEN RAISE EXCEPTION 'PAYROLL_RULES_REQUIRED'; END IF;
    after:=jsonb_build_object('estado','closed','facts',facts,'manual',v.manuais);
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
   IF u.funcao<>'encarregado' OR task.estado='concluido' OR task.arquivado_em IS NOT NULL OR t.id IS NOT NULL THEN RAISE EXCEPTION 'TASK_REPORT_INVALID'; END IF;
   after:=jsonb_build_object('estado','reported');
  ELSE
   IF u.funcao NOT IN('diretor_obra','adjunto') OR t.estado IS DISTINCT FROM 'reported' OR task.estado<>'concluido' THEN RAISE EXCEPTION 'PLANNING_CONFIRMATION_REQUIRED'; END IF;
   after:=jsonb_build_object('estado','confirmed');
  END IF;
 ELSE RAISE EXCEPTION 'ACTION_UNSUPPORTED'; END IF;
 IF expected IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',before,'after',after,'config',to_jsonb(cfg))::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao='configure_company' THEN
  INSERT INTO public.folha_config_empresa(empresa_id,office_expected_minutes,correction_days,overtime_enabled,calendar_complete,holiday_dates,payroll_rules_ready,official_template_hash,revision)
   VALUES(u.empresa_id,(after->>'office_expected_minutes')::integer,(after->>'correction_days')::integer,(after->>'overtime_enabled')::boolean,(after->>'calendar_complete')::boolean,
    ARRAY(SELECT x::date FROM jsonb_array_elements_text(after->'holiday_dates') x),(after->>'payroll_rules_ready')::boolean,after->>'official_template_hash',rev+1)
   ON CONFLICT(empresa_id) DO UPDATE SET office_expected_minutes=excluded.office_expected_minutes,correction_days=excluded.correction_days,overtime_enabled=excluded.overtime_enabled,calendar_complete=excluded.calendar_complete,
    holiday_dates=excluded.holiday_dates,payroll_rules_ready=excluded.payroll_rules_ready,official_template_hash=excluded.official_template_hash,revision=excluded.revision;
 ELSIF p_acao='configure_schedule' THEN
  INSERT INTO public.folha_horarios VALUES(w,u.empresa_id,after->'intervals',(after->>'expected_minutes')::integer,rev+1)
   ON CONFLICT(obra_id) DO UPDATE SET intervals=excluded.intervals,expected_minutes=excluded.expected_minutes,revision=excluded.revision;
 ELSIF p_acao IN('he_approve','he_reject','he_validate') THEN UPDATE public.folha_he SET estado=after->>'estado',revision=rev+1 WHERE id=entity;
 ELSIF p_acao='vacation_entitlement' THEN
  INSERT INTO public.folha_direitos_ferias VALUES(u.empresa_id,person,(after->>'year')::integer,(after->>'days')::numeric,after->>'source',rev+1)
   ON CONFLICT(colaborador_id,ano) DO UPDATE SET dias=excluded.dias,fonte=excluded.fonte,revision=excluded.revision;
 ELSIF p_acao IN('vacation_set','vacation_remove','vacation_replace') THEN
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
 ELSIF p_acao IN('payroll_save','payroll_validate','payroll_close') THEN
  INSERT INTO public.folha_vencimentos(id,empresa_id,colaborador_id,competencia,factos,manuais,estado,revision,criado_por,atualizado_por)
   VALUES(entity,u.empresa_id,person,m,after->'facts',after->'manual',after->>'estado',rev+1,u.id,u.id)
   ON CONFLICT(colaborador_id,competencia) DO UPDATE SET factos=excluded.factos,manuais=excluded.manuais,estado=excluded.estado,revision=excluded.revision,atualizado_por=u.id,atualizado_em=now();
 ELSIF p_acao='task_report' THEN
  INSERT INTO public.folha_tarefas_reportes(empresa_id,obra_id,tarefa_id,estado,reportado_por) VALUES(u.empresa_id,w,entity,'reported',u.id);
  INSERT INTO public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave)
   SELECT u.empresa_id,w,'folha_conclusao_reportada','planeamento_item',entity,'Conclusão reportada: validar no Planeamento',(now() AT TIME ZONE 'Europe/Lisbon')::date,r.utilizador_id,false,req
   FROM public.obra_responsaveis r JOIN public.utilizadores dest ON dest.id=r.utilizador_id WHERE r.obra_id=w AND r.papel IN('diretor_obra','adjunto') AND dest.ativo AND dest.empresa_id=u.empresa_id;
 ELSE
  UPDATE public.folha_tarefas_reportes SET estado='confirmed',confirmado_por=u.id,confirmado_em=now(),revision=rev+1 WHERE tarefa_id=entity;
  UPDATE public.alertas SET estado='resolvido',resolvido_por=u.id,resolvido_em=now() WHERE empresa_id=u.empresa_id AND obra_id=w AND entidade_id=entity AND entidade_tipo='planeamento_item' AND tipo='folha_conclusao_reportada' AND estado='pendente';
 END IF;
 INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,p_acao,entity,before,after,u.id,req,p_dados->>'reason');
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'revision',rev+1,'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());RETURN result;
END $$;
CREATE FUNCTION folha_privado.tarefa_concluida() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE w uuid; u public.utilizadores; ids jsonb; report_before public.folha_tarefas_reportes; report_after public.folha_tarefas_reportes;
BEGIN
 IF NEW.estado IS NOT DISTINCT FROM OLD.estado OR NEW.estado<>'concluido' THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.folha_tarefas_reportes WHERE tarefa_id=NEW.id AND estado='reported') THEN RETURN NEW; END IF;
 SELECT obra_id INTO w FROM public.fases WHERE id=NEW.fase_id;
 BEGIN u:=folha_privado.ator(); PERFORM folha_privado.obra(w); EXCEPTION WHEN insufficient_privilege THEN RETURN NEW; END;
 IF NOT folha_privado.admin() AND u.funcao NOT IN('diretor_obra','adjunto') THEN RETURN NEW; END IF;
 SELECT * INTO report_before FROM public.folha_tarefas_reportes WHERE tarefa_id=NEW.id AND estado='reported' FOR UPDATE;
 UPDATE public.folha_tarefas_reportes SET estado='confirmed',confirmado_por=u.id,confirmado_em=now(),revision=revision+1 WHERE tarefa_id=NEW.id AND estado='reported' RETURNING * INTO report_after;
 SELECT coalesce(jsonb_agg(id ORDER BY id),'[]') INTO ids FROM public.alertas WHERE obra_id=w AND empresa_id=u.empresa_id AND entidade_id=NEW.id AND entidade_tipo='planeamento_item' AND tipo='folha_conclusao_reportada' AND estado='pendente';
 UPDATE public.alertas SET estado='resolvido',resolvido_por=u.id,resolvido_em=now()
 WHERE obra_id=w AND empresa_id=u.empresa_id AND entidade_id=NEW.id AND entidade_tipo='planeamento_item' AND tipo='folha_conclusao_reportada' AND estado='pendente';
 IF report_after.id IS NOT NULL THEN INSERT INTO public.folha_gestao_historico(empresa_id,obra_id,action,entidade_id,antes,depois,ator_id,request_id,origem)
 VALUES(u.empresa_id,w,'planning_concluded_alerts_resolved',NEW.id,jsonb_build_object('task',jsonb_build_object('id',OLD.id,'estado',OLD.estado),'report',to_jsonb(report_before)),jsonb_build_object('task',jsonb_build_object('id',NEW.id,'estado',NEW.estado),'report',to_jsonb(report_after),'resolved_alert_ids',ids),u.id,gen_random_uuid(),'planeamento'); END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_tarefa_concluida AFTER UPDATE OF estado ON public.planeamento_itens FOR EACH ROW EXECUTE FUNCTION folha_privado.tarefa_concluida();
CREATE FUNCTION public.fn_folha_gestao_contexto_v2(p_obra_id uuid DEFAULT NULL,p_colaborador_id uuid DEFAULT NULL,p_competencia date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; rights jsonb; vacations jsonb; payroll jsonb; history jsonb; response jsonb;
BEGIN
 u:=folha_privado.ator();
 IF p_obra_id IS NOT NULL THEN PERFORM folha_privado.obra(p_obra_id); END IF;
 IF NOT folha_privado.admin() AND (p_obra_id IS NULL OR p_colaborador_id IS NOT NULL OR p_competencia IS NOT NULL)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: dados administrativos' USING ERRCODE='42501'; END IF;
 IF p_colaborador_id IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p_colaborador_id AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.ano),'[]') INTO rights FROM public.folha_direitos_ferias x WHERE colaborador_id=p_colaborador_id AND empresa_id=u.empresa_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.data,x.id),'[]') INTO vacations FROM public.ausencias x WHERE colaborador_id=p_colaborador_id AND tipo='ferias';
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.competencia),'[]') INTO payroll FROM public.folha_vencimentos x WHERE colaborador_id=p_colaborador_id AND empresa_id=u.empresa_id AND (p_competencia IS NULL OR competencia=p_competencia);
 END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.at,x.id),'[]') INTO history FROM public.folha_gestao_historico x
 WHERE empresa_id=u.empresa_id
 AND (folha_privado.admin() OR dominio='tarefas' OR dominio IN('he','horario') AND u.funcao IN('diretor_obra','adjunto'))
 AND (p_obra_id IS NULL OR obra_id=p_obra_id OR (folha_privado.admin() AND p_colaborador_id IS NOT NULL))
 AND (p_colaborador_id IS NULL OR entidade_id=p_colaborador_id OR entidade_id IN(SELECT id FROM public.folha_vencimentos WHERE colaborador_id=p_colaborador_id));
 response:=jsonb_build_object('version',2,
 'schedule',(SELECT to_jsonb(h) FROM public.folha_horarios h WHERE h.obra_id=p_obra_id),
 'permissions',jsonb_build_object('admin',folha_privado.admin(),'he_review',u.funcao IN('diretor_obra','adjunto'),'task_report',u.funcao='encarregado','task_review',u.funcao IN('diretor_obra','adjunto')),
 'people',CASE WHEN folha_privado.admin() THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.nome) ORDER BY c.nome,c.id) FROM public.colaboradores c WHERE empresa_id=u.empresa_id),'[]') ELSE '[]'::jsonb END,
 'live_facts',CASE WHEN folha_privado.admin() AND p_colaborador_id IS NOT NULL AND p_competencia IS NOT NULL THEN folha_privado.payroll_facts(p_colaborador_id,p_competencia) END,
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'codigo',to_jsonb(p)->'codigo','descricao',to_jsonb(p)->'descricao','estado',p.estado,'report',(SELECT to_jsonb(r) FROM public.folha_tarefas_reportes r WHERE r.tarefa_id=p.id)) ORDER BY p.id) FROM public.planeamento_itens p JOIN public.fases fase ON fase.id=p.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE o.empresa_id=u.empresa_id AND p_obra_id IS NOT NULL AND fase.obra_id=p_obra_id AND p.arquivado_em IS NULL AND p.estado<>'concluido'),'[]'),
 'config',CASE WHEN folha_privado.admin() THEN (SELECT to_jsonb(x) FROM public.folha_config_empresa x WHERE empresa_id=u.empresa_id) END,
 'vacation_revision',coalesce((SELECT revision FROM public.folha_ferias_revisoes WHERE colaborador_id=p_colaborador_id AND empresa_id=u.empresa_id),0),
 'entitlements',coalesce(rights,'[]'),'vacations',coalesce(vacations,'[]'),'payroll',coalesce(payroll,'[]'),'history',history,
 'overtime',coalesce((SELECT jsonb_agg(to_jsonb(x)||jsonb_build_object('sheet',(SELECT jsonb_build_object('person_id',f.colaborador_id,'date',f.data,'intervals',f.intervals,'revision',f.revision) FROM public.folha_registos f WHERE f.id=x.folha_id),'person_name',(SELECT c.nome FROM public.folha_registos f JOIN public.colaboradores c ON c.id=f.colaborador_id WHERE f.id=x.folha_id)) ORDER BY x.id) FROM public.folha_he x WHERE empresa_id=u.empresa_id AND (folha_privado.admin() OR u.funcao IN('diretor_obra','adjunto')) AND (folha_privado.admin() AND p_obra_id IS NULL OR obra_id=p_obra_id)),'[]'),
 'task_reports',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.folha_tarefas_reportes x WHERE empresa_id=u.empresa_id AND (p_obra_id IS NOT NULL AND obra_id=p_obra_id)),'[]'));
IF NOT folha_privado.admin() THEN
  response:=response-ARRAY['people','live_facts','config','vacation_revision','entitlements','vacations','payroll'];
 END IF;
 RETURN response;
END $$;
DO $$ DECLARE t text; BEGIN
 FOR t IN SELECT unnest(ARRAY['folha_direitos_ferias','folha_ferias_revisoes','folha_vencimentos','folha_tarefas_reportes','folha_gestao_historico']) LOOP
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t); EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION folha_privado.payroll_facts(uuid,date),folha_privado.tarefa_concluida(),public.fn_folha_gestao_v2(text,jsonb,boolean,text),public.fn_folha_gestao_contexto_v2(uuid,uuid,date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_gestao_v2(text,jsonb,boolean,text),public.fn_folha_gestao_contexto_v2(uuid,uuid,date) TO authenticated;
COMMIT;
