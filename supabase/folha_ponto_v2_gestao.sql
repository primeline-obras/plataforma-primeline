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
 action text NOT NULL CHECK(action IN('configure_company','configure_schedule','he_approve','he_reject','he_validate','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','he_process','configure_he_eligibility','absence_confirm','special_review','task_report','task_confirm','planning_concluded_alerts_resolved','payroll_reconcile')),
 dominio text GENERATED ALWAYS AS (CASE
 WHEN action IN('task_report','task_confirm','planning_concluded_alerts_resolved') THEN 'tarefas'
 WHEN action IN('he_approve','he_reject') THEN 'he'
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
 SELECT jsonb_build_object('sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'minutes',f.minutes,'state',f.estado,'special_day',f.special_day,'special_reviewed',f.special_reviewed_at IS NOT NULL) ORDER BY f.data,f.id)
 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data>=m AND f.data<(m+interval '1 month')::date),'[]'),
 'absences',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'type',a.tipo,'state',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date),'[]'),
 'pending_days',coalesce((SELECT jsonb_agg(data ORDER BY data) FROM (SELECT DISTINCT q.data FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=m AND q.data<(m+interval '1 month')::date AND q.data<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=q.data AND f.obra_id IS NOT DISTINCT FROM q.obra_id) AND NOT EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=q.data) AND NOT EXISTS(SELECT 1 FROM public.ponto_pessoal_obra h WHERE h.colaborador_id=p AND h.data=q.data)) missing),'[]'),
 'legacy_days',coalesce((SELECT jsonb_agg(DISTINCT data ORDER BY data) FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data>=m AND data<(m+interval '1 month')::date),'[]'),
 'financial_effect',false,'legacy_not_converted',true)
$$;
-- Factual snapshots cannot keep a prior validation after their source changes.
CREATE FUNCTION folha_privado.reconciliar_vencimentos() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE x jsonb; p uuid; d date; u public.utilizadores; v public.folha_vencimentos; antes jsonb; facts jsonb; req uuid;
BEGIN
 FOR x IN SELECT DISTINCT value FROM jsonb_array_elements(CASE WHEN TG_OP='INSERT' THEN jsonb_build_array(to_jsonb(NEW)) WHEN TG_OP='DELETE' THEN jsonb_build_array(to_jsonb(OLD)) ELSE jsonb_build_array(to_jsonb(OLD),to_jsonb(NEW)) END) LOOP
  p:=(x->>'colaborador_id')::uuid;d:=(x->>'data')::date;
  IF p IS NULL OR NOT EXISTS(SELECT 1 FROM public.folha_vencimentos WHERE colaborador_id=p AND competencia=date_trunc('month',d)::date) THEN CONTINUE; END IF;
  u:=folha_privado.ator();PERFORM folha_privado.lock_dia(p,d);
  IF EXISTS(SELECT 1 FROM public.folha_vencimentos WHERE colaborador_id=p AND empresa_id<>u.empresa_id)
  THEN RAISE EXCEPTION 'TENANT_RECONCILIATION_DENIED' USING ERRCODE='42501'; END IF;
  req:=coalesce(nullif(current_setting('folha.request_id',true),'')::uuid,CASE WHEN TG_TABLE_NAME='folha_registos' THEN (x->>'request_id')::uuid END,gen_random_uuid());
  FOR v IN SELECT * FROM public.folha_vencimentos WHERE colaborador_id=p AND empresa_id=u.empresa_id AND competencia=date_trunc('month',d)::date FOR UPDATE LOOP
   facts:=folha_privado.payroll_facts(p,v.competencia);
   IF v.factos IS NOT DISTINCT FROM facts THEN CONTINUE; END IF;
   IF v.estado IN('closed','exported') THEN RAISE EXCEPTION 'PAYROLL_CLOSED_FACTS_CHANGED' USING ERRCODE='40001'; END IF;
   antes:=to_jsonb(v);
   UPDATE public.folha_vencimentos SET factos=facts,estado='draft',revision=revision+1,atualizado_por=u.id,atualizado_em=now() WHERE id=v.id RETURNING * INTO v;
   INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,origem)
   VALUES(v.empresa_id,'payroll_reconcile',v.id,antes,to_jsonb(v),u.id,req,'facts_reconciliation');
  END LOOP;
 END LOOP;
 RETURN NULL;
END $$;
CREATE TRIGGER trg_folha_vencimentos_ausencia AFTER INSERT OR UPDATE OR DELETE ON public.ausencias FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos();
CREATE TRIGGER trg_folha_vencimentos_facto AFTER INSERT OR UPDATE OR DELETE ON public.folha_registos FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos();
CREATE TRIGGER trg_folha_vencimentos_alocacao AFTER INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos();
CREATE TRIGGER trg_folha_vencimentos_legado AFTER INSERT OR UPDATE OR DELETE ON public.ponto_pessoal_obra FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos();
REVOKE ALL ON FUNCTION folha_privado.reconciliar_vencimentos() FROM PUBLIC,anon,authenticated,service_role;
-- Fragmento de instalação local, incorporado pela migration de gestão.
-- Não executar isoladamente nem contra produção.
ALTER TABLE public.folha_config_empresa ADD COLUMN calendar_validated_years integer[] NOT NULL DEFAULT '{}';
ALTER TABLE public.folha_direitos_ferias ADD COLUMN saldo_transitado integer NOT NULL DEFAULT 0 CHECK(saldo_transitado>=0);
ALTER TABLE public.folha_direitos_ferias ADD COLUMN validade_transitado date;
ALTER TABLE public.folha_direitos_ferias ADD COLUMN dias_adicionais integer NOT NULL DEFAULT 0 CHECK(dias_adicionais>=0);
ALTER TABLE public.folha_direitos_ferias ADD COLUMN autorizacao text;
ALTER TABLE public.folha_direitos_ferias ADD CHECK(dias=trunc(dias));
ALTER TABLE public.folha_direitos_ferias ADD CHECK(saldo_transitado=0 OR validade_transitado=make_date(ano,4,30));
ALTER TABLE public.folha_direitos_ferias ADD CHECK((saldo_transitado=0 AND dias_adicionais=0) OR nullif(btrim(autorizacao),'') IS NOT NULL);
ALTER TABLE public.folha_vencimentos ADD COLUMN recibos_recebidos_em timestamptz;
ALTER TABLE public.folha_vencimentos ADD COLUMN recibos_recebidos_por uuid REFERENCES public.utilizadores(id);
ALTER TABLE public.folha_he ADD COLUMN processado_em timestamptz;
ALTER TABLE public.folha_he ADD COLUMN processado_por uuid REFERENCES public.utilizadores(id);
ALTER TABLE public.folha_he ADD COLUMN prazo_processamento date;

CREATE FUNCTION folha_privado.adm() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo AND empresa_id IS NOT NULL AND funcao='administrativo')
$$;
CREATE FUNCTION folha_privado.prazo_he(empresa uuid,d date) RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE cfg public.folha_config_empresa; x date:=date_trunc('month',d)::date+interval '1 month'; n integer:=0; last_day date;
BEGIN
 SELECT * INTO cfg FROM public.folha_config_empresa WHERE empresa_id=empresa;
 IF NOT coalesce(cfg.calendar_complete,false) OR NOT extract(year FROM x)::integer=ANY(cfg.calendar_validated_years) THEN RETURN NULL; END IF;
 last_day:=(x+interval '1 month')::date;
 WHILE x<last_day LOOP
  IF extract(isodow FROM x)<6 AND NOT x=ANY(cfg.holiday_dates) THEN n:=n+1; END IF;
  IF n=3 THEN RETURN x; END IF;
  x:=x+1;
 END LOOP;
 RETURN NULL;
END $$;

-- Legacy checks are preserved verbatim and extended only for the new occupational types.
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname,pg_get_expr(conbin,conrelid) expr FROM pg_constraint WHERE conrelid='public.ausencias'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%tipo%' LOOP
  EXECUTE format('ALTER TABLE public.ausencias DROP CONSTRAINT %I',c.conname);
  EXECUTE format('ALTER TABLE public.ausencias ADD CONSTRAINT %I CHECK ((%s) OR (tipo IN (''baixa_doenca'',''baixa_maternidade'',''baixa_parental'') AND estado IN (''ausente_pendente'',''confirmada'',''justificada'')))',c.conname,c.expr);
 END LOOP;
END $$;
CREATE FUNCTION folha_privado.guardar_confirmacao_ausencia() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 IF NEW.tipo='ferias' AND (TG_OP='INSERT' OR NEW.data IS DISTINCT FROM OLD.data OR NEW.tipo IS DISTINCT FROM OLD.tipo)
 AND (extract(isodow FROM NEW.data)>5 OR EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.folha_config_empresa cfg ON cfg.empresa_id=c.empresa_id WHERE c.id=NEW.colaborador_id AND NEW.data=ANY(cfg.holiday_dates)))
 THEN RAISE EXCEPTION 'VACATION_NON_WORKING_DAY: fins de semana e feriados não consomem férias'; END IF;
 IF NEW.estado NOT IN('justificada','confirmada') OR (TG_OP='UPDATE' AND NEW.estado=OLD.estado AND NEW.tipo=OLD.tipo AND NEW.colaborador_id=OLD.colaborador_id) THEN RETURN NEW; END IF;
 u:=folha_privado.ator();
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=NEW.colaborador_id AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: ausência' USING ERRCODE='42501'; END IF;
 -- Existing administrative vacation flows keep their scope; justification is ADM only.
 IF NEW.tipo<>'ferias' AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: confirmação administrativa' USING ERRCODE='42501'; END IF;
 IF NEW.tipo='baixa_doenca' AND NOT EXISTS(SELECT 1 FROM public.ausencias_anexos WHERE ausencia_id=NEW.id AND nullif(btrim(arquivo_url),'') IS NOT NULL) THEN RAISE EXCEPTION 'DOCUMENTO_PENDENTE: baixa por doença exige documento'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_zz_folha_confirmacao_ausencia BEFORE INSERT OR UPDATE ON public.ausencias FOR EACH ROW EXECUTE FUNCTION folha_privado.guardar_confirmacao_ausencia();
CREATE FUNCTION folha_privado.guardar_anexo_doenca() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.ausencias WHERE id=OLD.ausencia_id AND tipo='baixa_doenca' AND estado IN('confirmada','justificada'))
 AND (TG_OP='DELETE' OR NEW.ausencia_id IS DISTINCT FROM OLD.ausencia_id OR nullif(btrim(NEW.arquivo_url),'') IS NULL)
 AND NOT EXISTS(SELECT 1 FROM public.ausencias_anexos WHERE ausencia_id=OLD.ausencia_id AND id<>OLD.id AND nullif(btrim(arquivo_url),'') IS NOT NULL)
 THEN RAISE EXCEPTION 'DOCUMENTO_OBRIGATORIO: preserve o último anexo da baixa confirmada'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER trg_00_folha_anexo_lock BEFORE INSERT OR UPDATE OR DELETE ON public.ausencias_anexos FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.lock_legado();
CREATE TRIGGER trg_folha_anexo_doenca BEFORE UPDATE OR DELETE ON public.ausencias_anexos FOR EACH ROW EXECUTE FUNCTION folha_privado.guardar_anexo_doenca();
REVOKE ALL ON FUNCTION folha_privado.adm(),folha_privado.prazo_he(uuid,date),folha_privado.guardar_confirmacao_ausencia(),folha_privado.guardar_anexo_doenca() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; req uuid:=(p_dados->>'request_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid;
 person uuid:=(p_dados->>'person_id')::uuid; entity uuid; before jsonb; after jsonb; payload jsonb; op folha_privado.operacoes; previous_request text;
 token text; result jsonb; expected integer; rev integer; d date; m date; dates date[]; scope_dates date[]; a date; item jsonb;
 h public.folha_he; f public.folha_registos; v public.folha_vencimentos; t public.folha_tarefas_reportes; task public.planeamento_itens;
 cfg public.folha_config_empresa; ab public.ausencias; facts jsonb; pending boolean; consumed integer:=0; histids jsonb;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
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
  IF (p_acao IN('he_approve','he_reject') AND (u.funcao NOT IN('diretor_obra','adjunto') OR h.estado<>'potential'))
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
CREATE FUNCTION folha_privado.he_operacional(x jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT CASE WHEN x IS NULL THEN NULL ELSE jsonb_build_object('id',x->'id','obra_id',x->'obra_id','folha_id',x->'folha_id','folha_revision',x->'folha_revision','minutes',x->'minutes','estado',x->'estado','revision',x->'revision') END
$$;
REVOKE ALL ON FUNCTION folha_privado.he_operacional(jsonb) FROM PUBLIC,anon,authenticated,service_role;
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
 SELECT coalesce(jsonb_agg(CASE WHEN NOT folha_privado.admin() AND x.dominio='he' THEN to_jsonb(x)||jsonb_build_object('antes',folha_privado.he_operacional(x.antes),'depois',folha_privado.he_operacional(x.depois)) ELSE to_jsonb(x) END ORDER BY x.at,x.id),'[]') INTO history FROM public.folha_gestao_historico x
 WHERE empresa_id=u.empresa_id
 AND (folha_privado.admin() OR dominio='tarefas' OR dominio IN('he','horario') AND u.funcao IN('diretor_obra','adjunto'))
 AND (p_obra_id IS NULL OR obra_id=p_obra_id OR (folha_privado.admin() AND p_colaborador_id IS NOT NULL))
 AND (p_colaborador_id IS NULL OR entidade_id=p_colaborador_id OR entidade_id IN(SELECT id FROM public.folha_vencimentos WHERE colaborador_id=p_colaborador_id));
 response:=jsonb_build_object('version',2,
 'schedule',(SELECT to_jsonb(h) FROM public.folha_horarios h WHERE h.obra_id=p_obra_id),
 'permissions',jsonb_build_object('admin',folha_privado.admin(),'adm',folha_privado.adm(),'he_review',u.funcao IN('diretor_obra','adjunto'),'task_report',u.funcao='encarregado','task_review',u.funcao IN('diretor_obra','adjunto')),
 'people',CASE WHEN folha_privado.admin() THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'name',c.nome) ORDER BY c.nome,c.id) FROM public.colaboradores c WHERE empresa_id=u.empresa_id),'[]') ELSE '[]'::jsonb END,
 'live_facts',CASE WHEN folha_privado.admin() AND p_colaborador_id IS NOT NULL AND p_competencia IS NOT NULL THEN folha_privado.payroll_facts(p_colaborador_id,p_competencia) END,
 'tasks',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'codigo',to_jsonb(p)->'codigo','descricao',to_jsonb(p)->'descricao','estado',p.estado,'report',(SELECT to_jsonb(r) FROM public.folha_tarefas_reportes r WHERE r.tarefa_id=p.id)) ORDER BY p.id) FROM public.planeamento_itens p JOIN public.fases fase ON fase.id=p.fase_id JOIN public.obras o ON o.id=fase.obra_id WHERE o.empresa_id=u.empresa_id AND p_obra_id IS NOT NULL AND fase.obra_id=p_obra_id AND p.arquivado_em IS NULL AND p.estado<>'concluido'),'[]'),
 'absences',CASE WHEN folha_privado.adm() AND p_colaborador_id IS NOT NULL THEN coalesce((SELECT jsonb_agg(to_jsonb(a)||jsonb_build_object('document_pending',a.tipo='baixa_doenca' AND NOT EXISTS(SELECT 1 FROM public.ausencias_anexos an WHERE an.ausencia_id=a.id AND nullif(btrim(an.arquivo_url),'') IS NOT NULL))) FROM public.ausencias a WHERE a.colaborador_id=p_colaborador_id),'[]') ELSE '[]'::jsonb END,
 'config',CASE WHEN folha_privado.admin() THEN (SELECT to_jsonb(x) FROM public.folha_config_empresa x WHERE empresa_id=u.empresa_id) END,
 'vacation_revision',coalesce((SELECT revision FROM public.folha_ferias_revisoes WHERE colaborador_id=p_colaborador_id AND empresa_id=u.empresa_id),0),
 'entitlements',coalesce(rights,'[]'),'vacations',coalesce(vacations,'[]'),'payroll',coalesce(payroll,'[]'),'history',history,
 'overtime',coalesce((SELECT jsonb_agg(folha_privado.he_operacional(to_jsonb(x))||CASE WHEN folha_privado.admin() THEN jsonb_build_object('empresa_id',x.empresa_id,'processado_em',x.processado_em,'processado_por',x.processado_por,'prazo_processamento',x.prazo_processamento) ELSE '{}'::jsonb END||jsonb_build_object('sheet',(SELECT jsonb_build_object('person_id',f.colaborador_id,'date',f.data,'intervals',f.intervals,'revision',f.revision) FROM public.folha_registos f WHERE f.id=x.folha_id),'person_name',(SELECT c.nome FROM public.folha_registos f JOIN public.colaboradores c ON c.id=f.colaborador_id WHERE f.id=x.folha_id)) ORDER BY x.id) FROM public.folha_he x WHERE empresa_id=u.empresa_id AND (folha_privado.admin() OR u.funcao IN('diretor_obra','adjunto')) AND (folha_privado.admin() AND p_obra_id IS NULL OR obra_id=p_obra_id)),'[]'),
 'task_reports',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.folha_tarefas_reportes x WHERE empresa_id=u.empresa_id AND (p_obra_id IS NOT NULL AND obra_id=p_obra_id)),'[]'));
IF NOT folha_privado.admin() THEN
  response:=response-ARRAY['people','live_facts','config','vacation_revision','entitlements','vacations','payroll','absences'];
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
