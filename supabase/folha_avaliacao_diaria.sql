-- Preparação local. Instalar apenas com autorização separada; não ativa empresas.
BEGIN;
SET LOCAL lock_timeout='10s';
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
DO $$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED'; END IF;
 IF to_regclass('primeline_diaria_backup.funcoes') IS NULL THEN RAISE EXCEPTION 'DAILY_BACKUP_REQUIRED'; END IF;
 IF to_regclass('public.folha_avaliacoes_diarias') IS NOT NULL OR to_regclass('public.folha_horarios_versoes') IS NOT NULL THEN RAISE EXCEPTION 'DAILY_ALREADY_INSTALLED'; END IF;
END $$;
DO $$ DECLARE r record;now_rows jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_diaria_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_diaria_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_diaria_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'DAILY_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_diaria_backup.funcoes LOOP IF pg_get_functiondef(to_regprocedure(r.assinatura)) IS DISTINCT FROM r.definicao OR (SELECT proowner FROM pg_proc WHERE oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.owner_oid OR (SELECT proacl FROM pg_proc WHERE oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.acl THEN RAISE EXCEPTION 'DAILY_BACKUP_FUNCTION_DRIFT: %',r.assinatura; END IF;END LOOP;
 FOR r IN SELECT * FROM primeline_diaria_backup.dados LOOP EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',r.tabela);EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO now_rows;IF now_rows IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'DAILY_BACKUP_DATA_DRIFT: %',r.tabela;END IF;END LOOP;
END $$;
ALTER TABLE public.folha_config_empresa
 ADD COLUMN avaliacao_diaria_data_ativacao date,
 ADD COLUMN avaliacao_diaria_ativada_em timestamptz,
 ADD COLUMN avaliacao_diaria_ativada_por uuid REFERENCES public.utilizadores(id),
 ADD COLUMN avaliacao_diaria_ativacao_request_id uuid,
 ADD CONSTRAINT folha_diaria_ativacao_completa CHECK(num_nonnulls(avaliacao_diaria_data_ativacao,avaliacao_diaria_ativada_em,avaliacao_diaria_ativada_por,avaliacao_diaria_ativacao_request_id) IN(0,4));
CREATE TABLE public.folha_horarios_versoes(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id), revision integer NOT NULL CHECK(revision>0),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object' AND snapshot ? 'intervals' AND snapshot ? 'expected_minutes'),
 vigente_desde date NOT NULL, vigente_ate date, criado_por uuid NOT NULL REFERENCES public.utilizadores(id),
 criado_em timestamptz NOT NULL DEFAULT now(), request_id uuid NOT NULL, motivo text CHECK(length(motivo)<=1000),
 UNIQUE(obra_id,revision), CHECK(vigente_ate IS NULL OR vigente_ate>=vigente_desde)
);
CREATE INDEX folha_horarios_versoes_vigencia ON public.folha_horarios_versoes(empresa_id,obra_id,vigente_desde,vigente_ate);
CREATE TABLE public.folha_avaliacoes_diarias(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id), data date NOT NULL,
 ativa boolean NOT NULL DEFAULT true, modo_dia text NOT NULL CHECK(modo_dia IN('personalizado','misto')), revision integer NOT NULL CHECK(revision>0),
 referencia_estado text NOT NULL CHECK(referencia_estado IN('capturada','pendente')),
 referencia_origem text NOT NULL CHECK(referencia_origem IN('automatico','administrativo')), referencia_revision integer NOT NULL CHECK(referencia_revision>0),
 permanencia_id uuid REFERENCES public.quadro_equipa_permanencias(id) ON DELETE RESTRICT,
 obra_origem_id uuid REFERENCES public.obras(id) ON DELETE RESTRICT,
 horario_versao_id uuid REFERENCES public.folha_horarios_versoes(id) ON DELETE RESTRICT,
 permanencia_snapshot jsonb, horario_snapshot jsonb, contexto_snapshot jsonb NOT NULL,
 expected_minutes integer CHECK(expected_minutes BETWEEN 1 AND 1440), referencia_motivo text CHECK(length(referencia_motivo)<=1000), referencia_evidencia jsonb,
 capturado_por uuid REFERENCES public.utilizadores(id), capturado_em timestamptz, captura_request_id uuid,
 realizado_minutes integer NOT NULL CHECK(realizado_minutes BETWEEN 0 AND 1440), falta_minutes integer CHECK(falta_minutes>=0), excedente_minutes integer CHECK(excedente_minutes>=0),
 estado text NOT NULL CHECK(estado IN('regular','horas_em_falta','potencial_he','referencia_pendente','intervalo_aberto','conflito','outras_pendencias','inativa')),
 he_estado text NOT NULL CHECK(he_estado IN('nenhum','nao_avaliavel','pendente','validada','nao_considerada')),
 pendencias text[] NOT NULL DEFAULT '{}', factos_revisoes jsonb NOT NULL CHECK(jsonb_typeof(factos_revisoes)='array'),
 factos_fingerprint text NOT NULL CHECK(factos_fingerprint ~ '^[0-9a-f]{64}$'),
 fingerprint_version text NOT NULL DEFAULT 'folha_factos_v1' CHECK(fingerprint_version='folha_factos_v1'),
 regra_avaliacao_version text NOT NULL DEFAULT 'diaria_v1' CHECK(regra_avaliacao_version='diaria_v1'),
 decisao_fingerprint text CHECK(decisao_fingerprint ~ '^[0-9a-f]{64}$'), he_decidido_por uuid REFERENCES public.utilizadores(id), he_decidido_em timestamptz, he_motivo text CHECK(length(he_motivo)<=1000),
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id), atualizado_por uuid NOT NULL REFERENCES public.utilizadores(id),
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(),
 avaliado_por uuid NOT NULL REFERENCES public.utilizadores(id), avaliado_em timestamptz NOT NULL DEFAULT now(),
 request_id_inicial uuid NOT NULL, ultimo_request_id uuid NOT NULL,
 UNIQUE(empresa_id,colaborador_id,data),
 CHECK(ativa=(estado<>'inativa')),
 CHECK(num_nonnulls(falta_minutes,excedente_minutes) IN(0,2)),
 CHECK(falta_minutes IS NULL OR expected_minutes IS NOT NULL AND falta_minutes=greatest(0,expected_minutes-realizado_minutes) AND excedente_minutes=greatest(0,realizado_minutes-expected_minutes)),
 CHECK((referencia_estado='pendente' AND expected_minutes IS NULL AND nullif(btrim(referencia_motivo),'') IS NOT NULL) OR
       (referencia_estado='capturada' AND expected_minutes IS NOT NULL AND horario_snapshot IS NOT NULL AND capturado_por IS NOT NULL AND capturado_em IS NOT NULL AND captura_request_id IS NOT NULL)),
 CHECK(referencia_estado<>'capturada' OR referencia_origem<>'automatico' OR num_nonnulls(permanencia_id,obra_origem_id,horario_versao_id,permanencia_snapshot)=4),
 CHECK(referencia_origem<>'administrativo' OR (referencia_evidencia IS NOT NULL AND nullif(btrim(referencia_motivo),'') IS NOT NULL)),
 CHECK((he_estado IN('validada','nao_considerada') AND excedente_minutes>0 AND num_nonnulls(decisao_fingerprint,he_decidido_por,he_decidido_em,he_motivo)=4 AND nullif(btrim(he_motivo),'') IS NOT NULL) OR
       (he_estado NOT IN('validada','nao_considerada') AND num_nonnulls(decisao_fingerprint,he_decidido_por,he_decidido_em,he_motivo)=0)),
 CHECK(NOT ativa OR he_estado<>'pendente' OR 'he_diaria_pendente'=ANY(pendencias)),
 CHECK(NOT ativa OR he_estado<>'validada' OR 'he_validada_aguarda_processamento'=ANY(pendencias))
);
CREATE INDEX folha_diaria_competencia ON public.folha_avaliacoes_diarias(empresa_id,colaborador_id,data) WHERE ativa;
-- Extensão explícita do histórico funcional existente, preservando todas as ações anteriores.
ALTER TABLE public.folha_gestao_historico DROP CONSTRAINT folha_gestao_historico_action_check;
ALTER TABLE public.folha_gestao_historico ADD CONSTRAINT folha_gestao_historico_action_check CHECK(action IN(
 'configure_company','configure_schedule','he_approve','he_reject','he_validate','vacation_set','vacation_remove','vacation_replace','vacation_entitlement','payroll_save','payroll_validate','payroll_close','payroll_export','payroll_reopen','he_process','configure_he_eligibility','absence_confirm','special_review','task_report','task_confirm','planning_concluded_alerts_resolved','payroll_reconcile',
 'daily_activation','daily_evaluation_create','daily_evaluation_recalculate','daily_evaluation_deactivate','daily_evaluation_reactivate','daily_reference_correct','daily_he_validate','daily_he_disregard','daily_he_invalidate','schedule_retro_correct'));
CREATE FUNCTION folha_privado.diaria_guardar() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE e uuid; p uuid; w uuid;
BEGIN
 -- SECURITY INVOKER: current_user identifica o executor, nunca um GUC fornecido pelo cliente.
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'CONTROLLED_DAILY_WRITER_REQUIRED' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'DAILY_HISTORY_IMMUTABLE'; END IF;
 e:=NEW.empresa_id;
 IF TG_TABLE_NAME='folha_avaliacoes_diarias' THEN
  p:=NEW.colaborador_id;w:=NEW.obra_origem_id;
  IF TG_OP='UPDATE' AND ROW(NEW.id,NEW.empresa_id,NEW.colaborador_id,NEW.data,NEW.criado_por,NEW.criado_em,NEW.request_id_inicial) IS DISTINCT FROM ROW(OLD.id,OLD.empresa_id,OLD.colaborador_id,OLD.data,OLD.criado_por,OLD.criado_em,OLD.request_id_inicial) THEN RAISE EXCEPTION 'DAILY_IDENTITY_IMMUTABLE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=e) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT'; END IF;
  IF NEW.permanencia_id IS NOT NULL AND (TG_OP='INSERT' OR ROW(NEW.permanencia_id,NEW.obra_origem_id) IS DISTINCT FROM ROW(OLD.permanencia_id,OLD.obra_origem_id)) AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE id=NEW.permanencia_id AND empresa_id=e AND colaborador_id=p AND obra_id=w AND inicio<=NEW.data AND (fim IS NULL OR fim>NEW.data)) THEN RAISE EXCEPTION 'REFERENCE_MEMBERSHIP_CONFLICT'; END IF;
  IF NEW.horario_versao_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.folha_horarios_versoes WHERE id=NEW.horario_versao_id AND empresa_id=e AND obra_id=w) THEN RAISE EXCEPTION 'REFERENCE_SCHEDULE_CONFLICT'; END IF;
 ELSE
  w:=NEW.obra_id;
  IF TG_OP='UPDATE' AND ROW(NEW.id,NEW.empresa_id,NEW.obra_id,NEW.revision,NEW.snapshot,NEW.vigente_desde,NEW.criado_por,NEW.criado_em,NEW.request_id) IS DISTINCT FROM ROW(OLD.id,OLD.empresa_id,OLD.obra_id,OLD.revision,OLD.snapshot,OLD.vigente_desde,OLD.criado_por,OLD.criado_em,OLD.request_id) THEN RAISE EXCEPTION 'SCHEDULE_VERSION_IMMUTABLE'; END IF;
  PERFORM 1 FROM public.obras WHERE id=w FOR UPDATE;
  IF EXISTS(SELECT 1 FROM public.folha_horarios_versoes v WHERE v.obra_id=w AND v.id<>NEW.id AND daterange(v.vigente_desde,v.vigente_ate,'[)') && daterange(NEW.vigente_desde,NEW.vigente_ate,'[)')) THEN RAISE EXCEPTION 'SCHEDULE_VERSION_OVERLAP'; END IF;
  IF NEW.vigente_desde>(now() AT TIME ZONE 'Europe/Lisbon')::date THEN RAISE EXCEPTION 'FUTURE_SCHEDULE_UNSUPPORTED'; END IF;
 END IF;
 IF w IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras WHERE id=w AND empresa_id=e) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_diaria_integridade BEFORE INSERT OR UPDATE OR DELETE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_guardar();
CREATE TRIGGER folha_horario_versao_integridade BEFORE INSERT OR UPDATE OR DELETE ON public.folha_horarios_versoes FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_guardar();
ALTER TABLE public.folha_avaliacoes_diarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.folha_horarios_versoes ENABLE ROW LEVEL SECURITY;
-- Leitura apenas por RPC autenticada com escopo; nenhum DML/SELECT direto para roles da aplicação.
REVOKE ALL ON public.folha_avaliacoes_diarias,public.folha_horarios_versoes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION folha_privado.diaria_pessoal(p uuid,d date) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) x WHERE f.colaborador_id=p AND f.data=d AND x->>'mode'='personalizado')
$$;
CREATE FUNCTION folha_privado.diaria_referencia(p uuid,d date) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; cut date; m public.quadro_equipa_permanencias; v public.folha_horarios_versoes; reason text;
BEGIN
 u:=folha_privado.ator();
 SELECT avaliacao_diaria_data_ativacao INTO cut FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id;
 IF cut IS NULL THEN RAISE EXCEPTION 'DAILY_NOT_ACTIVATED'; END IF;
 IF d<cut THEN reason:='historico_anterior_ao_corte';
 ELSIF (SELECT count(*) FROM public.quadro_equipa_permanencias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d))<>1 THEN reason:='origem_principal_nao_inequivoca';
 ELSE
  SELECT * INTO m FROM public.quadro_equipa_permanencias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d);
  SELECT * INTO v FROM public.folha_horarios_versoes WHERE obra_id=m.obra_id AND empresa_id=u.empresa_id AND vigente_desde<=d AND (vigente_ate IS NULL OR vigente_ate>d);
  IF v.id IS NULL THEN reason:='horario_sem_vigencia_comprovada'; END IF;
 END IF;
 RETURN jsonb_build_object('referencia_estado',CASE WHEN reason IS NULL THEN 'capturada' ELSE 'pendente' END,'referencia_origem','automatico',
 'permanencia_id',m.id,'obra_origem_id',m.obra_id,'horario_versao_id',v.id,'permanencia_snapshot',CASE WHEN reason IS NULL THEN to_jsonb(m) END,
 'horario_snapshot',CASE WHEN reason IS NULL THEN v.snapshot||jsonb_build_object('obra_id',v.obra_id,'empresa_id',v.empresa_id,'revision',v.revision,'versao_id',v.id,'vigente_desde',v.vigente_desde,'vigente_ate',v.vigente_ate) END,'expected_minutes',CASE WHEN reason IS NULL THEN (v.snapshot->>'expected_minutes')::integer END,
 'referencia_motivo',reason,'contexto_snapshot',jsonb_build_object('data_ativacao',cut,'regra','diaria_v1'));
END $$;
CREATE FUNCTION folha_privado.diaria_factos(p uuid,d date) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('canonical',jsonb_build_array('folha_factos_v1',c.empresa_id,p,d,
 coalesce((SELECT jsonb_agg(jsonb_build_array(f.id,f.revision,f.tipo_local,f.obra_id,
 (SELECT jsonb_agg(jsonb_build_array(i.ordinality,i.x->>'start',i.x->>'end',i.x->>'period',i.x->>'mode') ORDER BY i.ordinality) FROM jsonb_array_elements(f.intervals) WITH ORDINALITY i(x,ordinality)),f.special_day,f.special_reviewed_by,f.special_reviewed_at) ORDER BY f.id::text COLLATE "C") FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),'[]'::jsonb),
 coalesce((SELECT jsonb_agg(jsonb_build_array(a.id,a.tipo,a.estado) ORDER BY a.id::text COLLATE "C") FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=d),'[]'::jsonb)),
 'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision) ORDER BY f.id::text COLLATE "C") FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),'[]'::jsonb),
 'minutes',coalesce((SELECT sum(f.minutes)::integer FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d),0),
 'mixed',EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) i WHERE f.colaborador_id=p AND f.data=d AND i->>'mode' IS DISTINCT FROM 'personalizado'),
 'open',EXISTS(SELECT 1 FROM public.folha_registos f CROSS JOIN LATERAL jsonb_array_elements(f.intervals) i WHERE f.colaborador_id=p AND f.data=d AND i->>'end' IS NULL),
 'conflict',EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=d) OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra a WHERE a.colaborador_id=p AND a.data=d),
 'special_pending',EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=d AND f.special_day AND f.special_reviewed_at IS NULL))
 FROM public.colaboradores c WHERE c.id=p
$$;
CREATE FUNCTION folha_privado.diaria_decisao_hash(fingerprint text,reference_revision integer,reference_snapshot jsonb) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT encode(sha256(convert_to(jsonb_build_array('diaria_v1',fingerprint,reference_revision,reference_snapshot)::text,'UTF8')),'hex')
$$;
CREATE FUNCTION folha_privado.diaria_recalcular(p uuid,d date,req uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
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
  n.referencia_estado:=ref->>'referencia_estado';n.referencia_origem:='automatico';n.permanencia_id:=(ref->>'permanencia_id')::uuid;n.obra_origem_id:=(ref->>'obra_origem_id')::uuid;n.horario_versao_id:=(ref->>'horario_versao_id')::uuid;
  n.permanencia_snapshot:=nullif(ref->'permanencia_snapshot','null'::jsonb);n.horario_snapshot:=nullif(ref->'horario_snapshot','null'::jsonb);n.contexto_snapshot:=ref->'contexto_snapshot';
  n.expected_minutes:=(ref->>'expected_minutes')::integer;n.referencia_motivo:=ref->>'referencia_motivo';
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
CREATE FUNCTION folha_privado.diaria_reconciliar_trigger() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE j jsonb; p uuid; d date; req uuid;
BEGIN
 FOR j IN SELECT DISTINCT value FROM jsonb_array_elements(CASE TG_OP WHEN 'INSERT' THEN jsonb_build_array(to_jsonb(NEW)) WHEN 'DELETE' THEN jsonb_build_array(to_jsonb(OLD)) ELSE jsonb_build_array(to_jsonb(OLD),to_jsonb(NEW)) END) LOOP
  p:=(j->>'colaborador_id')::uuid;d:=(j->>'data')::date;
  IF p IS NOT NULL THEN
   req:=coalesce((j->>'request_id')::uuid,nullif(current_setting('folha.request_id',true),'')::uuid,gen_random_uuid());
   IF folha_privado.diaria_pessoal(p,d) OR EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias WHERE colaborador_id=p AND data=d) THEN PERFORM folha_privado.diaria_recalcular(p,d,req); END IF;
  END IF;
 END LOOP;RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER folha_diaria_factos AFTER INSERT OR UPDATE OR DELETE ON public.folha_registos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_reconciliar_trigger();
CREATE CONSTRAINT TRIGGER folha_diaria_ausencias AFTER INSERT OR UPDATE OR DELETE ON public.ausencias DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_reconciliar_trigger();
CREATE TRIGGER folha_diaria_vencimentos AFTER INSERT OR UPDATE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_vencimentos();
CREATE FUNCTION folha_privado.diaria_config_guardar() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF TG_TABLE_NAME='folha_config_empresa' THEN
  IF TG_OP='UPDATE' AND OLD.avaliacao_diaria_data_ativacao IS NOT NULL AND ROW(NEW.avaliacao_diaria_data_ativacao,NEW.avaliacao_diaria_ativada_em,NEW.avaliacao_diaria_ativada_por,NEW.avaliacao_diaria_ativacao_request_id) IS DISTINCT FROM ROW(OLD.avaliacao_diaria_data_ativacao,OLD.avaliacao_diaria_ativada_em,OLD.avaliacao_diaria_ativada_por,OLD.avaliacao_diaria_ativacao_request_id) THEN RAISE EXCEPTION 'DAILY_ACTIVATION_IMMUTABLE'; END IF;
  IF NEW.avaliacao_diaria_data_ativacao IS NOT NULL AND current_user<>'postgres' THEN RAISE EXCEPTION 'CONTROLLED_DAILY_WRITER_REQUIRED' USING ERRCODE='42501'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=coalesce(NEW.empresa_id,OLD.empresa_id) AND avaliacao_diaria_data_ativacao IS NOT NULL) THEN
   IF current_user<>'postgres' THEN RAISE EXCEPTION 'CONTROLLED_SCHEDULE_REQUIRED' USING ERRCODE='42501'; END IF;
   IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SCHEDULE_VERSION_REQUIRED'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.folha_horarios_versoes v WHERE v.obra_id=NEW.obra_id AND v.empresa_id=NEW.empresa_id AND v.snapshot=jsonb_build_object('intervals',NEW.intervals,'expected_minutes',NEW.expected_minutes) AND v.vigente_desde<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND (v.vigente_ate IS NULL OR v.vigente_ate>(now() AT TIME ZONE 'Europe/Lisbon')::date)) THEN RAISE EXCEPTION 'SCHEDULE_VERSION_REQUIRED'; END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_diaria_config_integridade BEFORE INSERT OR UPDATE ON public.folha_config_empresa FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_config_guardar();
CREATE TRIGGER folha_diaria_horario_integridade BEFORE INSERT OR UPDATE OR DELETE ON public.folha_horarios FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_config_guardar();
CREATE FUNCTION public.fn_folha_diaria_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; cfg public.folha_config_empresa; a public.folha_avaliacoes_diarias; v public.folha_horarios_versoes; h public.folha_horarios;
 req uuid:=(p_dados->>'request_id')::uuid; p uuid:=(p_dados->>'person_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 today date:=(now() AT TIME ZONE 'Europe/Lisbon')::date; before jsonb; after jsonb; payload jsonb; token text; result jsonb; op folha_privado.operacoes; schedule_row record; rev integer; next_rev integer; expected integer; reason text:=nullif(btrim(p_dados->>'reason'),''); facts jsonb;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator();SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo IS TRUE FOR SHARE;IF u.id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501';END IF;IF NOT folha_privado.admin() THEN RAISE EXCEPTION 'PERMISSION_DENIED: administração' USING ERRCODE='42501'; END IF;
 IF p_acao<>'configure_schedule' AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo/Gestão' USING ERRCODE='42501'; END IF;
 IF p IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
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
  rev:=cfg.revision;before:=to_jsonb(cfg);
  after:=jsonb_build_object('activation_date',today,'schedules',(SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.obra_id),'[]') FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id));
 ELSIF p_acao IN('configure_schedule','schedule_retro_correct') THEN
  PERFORM folha_privado.obra(w,true);SELECT * INTO h FROM public.folha_horarios WHERE obra_id=w FOR UPDATE;
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

CREATE OR REPLACE FUNCTION folha_privado.save(p jsonb,w uuid,d date,req uuid,confirmar boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
 row jsonb; f jsonb; state text; expected integer; window_days integer; special boolean; result public.folha_registos;
BEGIN
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p->'intervals') x WHERE x->>'mode'='personalizado') THEN RAISE EXCEPTION 'PERSONALIZED_REQUIRES_PERIODS_SAVE'; END IF;
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
END $$;


-- Definições completas; sem reescrita textual de funções instaladas.
CREATE OR REPLACE FUNCTION folha_privado.save_periodo(p jsonb,w uuid,d date,req uuid,confirmar boolean,plano jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; person uuid:=(p->'key'->>'person_id')::uuid; kind text:=p->'key'->>'kind'; old public.folha_registos;
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
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p->'intervals') x WHERE x->>'mode'='personalizado') THEN expected:=NULL;
 ELSIF w IS NOT NULL THEN SELECT sum((extract(epoch FROM ((h.x->>'end')::time-(h.x->>'start')::time))/60)::integer) INTO expected FROM public.folha_horarios schedule CROSS JOIN LATERAL jsonb_array_elements(schedule.intervals) h(x) WHERE schedule.obra_id=w AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->'intervals') period WHERE period->>'period'=h.x->>'period'); END IF;
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
 IF kind='primeline' AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(plano) target CROSS JOIN LATERAL jsonb_array_elements(target->'intervals') x WHERE x->>'mode'='personalizado') THEN PERFORM folha_privado.reconciliar_he(result); END IF;
 RETURN jsonb_build_object('result',to_jsonb(result));
END $$;

CREATE OR REPLACE FUNCTION folha_privado.operar_periodos(p jsonb,confirmar boolean,versao text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; d date:=(p->>'date')::date; req uuid:=(p->>'request_id')::uuid; person uuid:=(p->'key'->>'person_id')::uuid;
 w uuid:=(p->>'work_id')::uuid; item jsonb; plan jsonb:=p->'sites'; snapshot jsonb:='[]'; xs jsonb; token text; payload jsonb; op folha_privado.operacoes; old public.folha_registos; keys jsonb:='[]'; result jsonb; daily_before jsonb; daily_ref jsonb; personal boolean; daily_after jsonb;
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
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(xs) x WHERE
 (x->>'mode'='personalizado' AND x->>'period' IS NOT NULL) OR
 (x->>'mode' IS DISTINCT FROM 'personalizado' AND (x->>'period' IS NULL OR x->>'period' NOT IN('manha','tarde')))) THEN RAISE EXCEPTION 'PERIOD_REQUIRED'; END IF;
 personal:=EXISTS(SELECT 1 FROM jsonb_array_elements(xs) x WHERE x->>'mode'='personalizado');
 SELECT to_jsonb(a) INTO daily_before FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=person AND a.data=d AND a.empresa_id=u.empresa_id FOR UPDATE;
 IF personal OR daily_before IS NOT NULL THEN
  IF (p->>'expected_daily_revision')::integer IS DISTINCT FROM coalesce((daily_before->>'revision')::integer,0) THEN RAISE EXCEPTION 'STALE_REVISION: avaliação diária' USING ERRCODE='40001'; END IF;
  IF personal AND daily_before IS NULL THEN daily_ref:=folha_privado.diaria_referencia(person,d); ELSE daily_ref:=daily_before; END IF;
  IF personal AND EXISTS(SELECT 1 FROM public.folha_he h JOIN public.folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=person AND f.data=d) THEN RAISE EXCEPTION 'NORMAL_HE_REQUIRES_ADMIN_REVIEW'; END IF;
 END IF;
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
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'snapshot',snapshot,'daily',daily_before,'reference',daily_ref)::text,'UTF8')),'hex');
 IF NOT confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',snapshot,'summary',CASE WHEN personal THEN 'Confirmar obras e intervalos factuais? A equipa permanente não será transferida.' ELSE 'Confirmar obras e horas por período? A equipa permanente não será transferida.' END)||CASE WHEN personal OR daily_before IS NOT NULL THEN jsonb_build_object('daily_reference',daily_ref) ELSE '{}'::jsonb END; END IF;
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
 IF personal OR daily_before IS NOT NULL THEN daily_after:=folha_privado.diaria_recalcular(person,d,req); END IF;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys)||CASE WHEN personal OR daily_before IS NOT NULL THEN jsonb_build_object('daily_evaluation',daily_after) ELSE '{}'::jsonb END;
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now()); RETURN result;
END $$;

CREATE OR REPLACE FUNCTION folha_privado.reconciliar_he(f public.folha_registos) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF f.colaborador_id IS NOT NULL AND folha_privado.diaria_pessoal(f.colaborador_id,f.data) THEN RETURN; END IF;
 UPDATE public.folha_he SET estado='superseded',revision=revision+1 WHERE folha_id=f.id AND estado<>'superseded';
 IF f.obra_id IS NOT NULL AND f.colaborador_id IS NOT NULL AND NOT f.special_day AND f.estado='registered'
 AND f.expected_minutes IS NOT NULL AND f.minutes>f.expected_minutes
 AND EXISTS(SELECT 1 FROM public.colaboradores c JOIN public.folha_config_empresa cfg ON cfg.empresa_id=c.empresa_id WHERE c.id=f.colaborador_id AND lower(btrim(c.funcao))=ANY(cfg.he_eligible_roles))
 AND EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=f.empresa_id AND overtime_enabled AND calendar_complete AND extract(year FROM f.data)::integer=ANY(calendar_validated_years) AND NOT f.data=ANY(holiday_dates))
 AND extract(isodow FROM f.data)<6
 AND NOT EXISTS(SELECT 1 FROM public.horas_extraordinarias WHERE colaborador_id=f.colaborador_id AND data=f.data)
 THEN INSERT INTO public.folha_he(empresa_id,obra_id,folha_id,folha_revision,minutes,estado)
 VALUES(f.empresa_id,f.obra_id,f.id,f.revision,f.minutes-f.expected_minutes,'potential'); END IF;
END $$;

CREATE OR REPLACE FUNCTION folha_privado.reconciliar_dia(p uuid,d date,req uuid,origem text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; f public.folha_registos; antes public.folha_registos; r jsonb; facts jsonb; novo_estado text; conflito boolean;
BEGIN
 IF folha_privado.diaria_pessoal(p,d) OR EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias WHERE colaborador_id=p AND data=d AND ativa) THEN PERFORM folha_privado.diaria_recalcular(p,d,req);RETURN; END IF;
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
END $$;

CREATE OR REPLACE FUNCTION folha_privado.linha(p uuid,w uuid,d date,k text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; nome text; papel text; fornecedor text; s public.folha_registos;
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
  'sheet',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object('id',s.id,'intervals',s.intervals,'note',s.note,'state',coalesce((SELECT CASE a.estado WHEN 'regular' THEN 'registered' WHEN 'intervalo_aberto' THEN 'open' WHEN 'horas_em_falta' THEN 'missing' ELSE 'regularization' END FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=d AND a.ativa AND k='primeline'),s.estado)) END,
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
  'can_write',NOT legacy AND conf IS NULL AND d<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND (d=(now() AT TIME ZONE 'Europe/Lisbon')::date OR folha_privado.adm_operacional() OR d>=(now() AT TIME ZONE 'Europe/Lisbon')::date-1) AND (w IS NULL OR folha_privado.admin() OR u.funcao='encarregado' OR EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND utilizador_id=u.id AND u.funcao IN('diretor_obra','adjunto','preparador'))) AND ((k='external' AND EXISTS(SELECT 1 FROM public.folha_externos WHERE id=p AND empresa_id=u.empresa_id AND ativo)) OR EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d)))) || CASE WHEN k='primeline' AND EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=d AND a.empresa_id=u.empresa_id) THEN jsonb_build_object('daily_evaluation',(SELECT jsonb_build_object('id',a.id,'revision',a.revision,'active',a.ativa,'mode',a.modo_dia,'state',a.estado,'expected_minutes',a.expected_minutes,'minutes',a.realizado_minutes,'missing_minutes',a.falta_minutes,'excess_minutes',a.excedente_minutes,'he_state',a.he_estado,'pending',a.pendencias,'reference_state',a.referencia_estado) FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=d AND a.empresa_id=u.empresa_id AND k='primeline')) ELSE '{}'::jsonb END;
END $$;

CREATE OR REPLACE FUNCTION folha_privado.normal(p uuid,w uuid,d date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r jsonb; xs jsonb; full_day jsonb;
BEGIN
 IF folha_privado.diaria_pessoal(p,d) THEN RAISE EXCEPTION 'PERSONALIZED_DAY_REQUIRES_EDITOR'; END IF;
 IF extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=(folha_privado.ator()).empresa_id AND d=ANY(holiday_dates)) THEN RAISE EXCEPTION 'SPECIAL_DAY_NO_NORMAL_FILL'; END IF;
 r:=folha_privado.linha(p,w,d,'primeline');
 SELECT intervals INTO full_day FROM public.folha_horarios WHERE obra_id=w;
 IF full_day IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(full_day,d);
 SELECT jsonb_agg(jsonb_build_object('start',x->>'start','end',x->>'end') ORDER BY x->>'start') INTO xs
 FROM public.folha_horarios h,jsonb_array_elements(h.intervals) x WHERE h.obra_id=w AND (r->>'period'='dia_inteiro' OR x->>'period'=r->>'period');
 IF xs IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 PERFORM folha_privado.facts(xs,d); RETURN xs;
END $$;

CREATE OR REPLACE FUNCTION folha_privado.payroll_facts(p uuid,m date) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('sheets',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'revision',f.revision,'date',f.data,'minutes',f.minutes,'state',coalesce((SELECT CASE WHEN a.estado='regular' AND cardinality(a.pendencias)=0 THEN 'registered' ELSE 'regularization' END FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=f.data AND a.ativa),f.estado),'special_day',f.special_day,'special_reviewed',f.special_reviewed_at IS NOT NULL) ORDER BY f.data,f.id)
 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data>=m AND f.data<(m+interval '1 month')::date),'[]'),
 'absences',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'type',a.tipo,'state',a.estado) ORDER BY a.data,a.id)
 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date),'[]'),
 'pending_days',coalesce((SELECT jsonb_agg(data ORDER BY data) FROM (SELECT DISTINCT q.data FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=m AND q.data<(m+interval '1 month')::date AND q.data<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND NOT EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data=q.data AND a.ativa) AND NOT EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=p AND f.data=q.data AND f.obra_id IS NOT DISTINCT FROM q.obra_id) AND NOT EXISTS(SELECT 1 FROM public.ausencias a WHERE a.colaborador_id=p AND a.data=q.data) AND NOT EXISTS(SELECT 1 FROM public.ponto_pessoal_obra h WHERE h.colaborador_id=p AND h.data=q.data)) missing),'[]'),
 'legacy_days',coalesce((SELECT jsonb_agg(DISTINCT data ORDER BY data) FROM public.ponto_pessoal_obra WHERE colaborador_id=p AND data>=m AND data<(m+interval '1 month')::date),'[]'),
 'financial_effect',false,'legacy_not_converted',true)
 || CASE WHEN EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date AND a.ativa) THEN
 jsonb_build_object('daily_evaluations',(SELECT jsonb_agg(jsonb_build_object('id',a.id,'date',a.data,'revision',a.revision,'reference_revision',a.referencia_revision,'fingerprint',a.factos_fingerprint,'state',a.estado,'expected_minutes',a.expected_minutes,'minutes',a.realizado_minutes,'he_state',a.he_estado,'pending',a.pendencias) ORDER BY a.data,a.id) FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p AND a.data>=m AND a.data<(m+interval '1 month')::date AND a.ativa)) ELSE '{}'::jsonb END
$$;

CREATE OR REPLACE FUNCTION folha_privado.diaria_gestao_preservada(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; req uuid:=(p_dados->>'request_id')::uuid; w uuid:=(p_dados->>'work_id')::uuid;
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
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_gestao_contexto_v2(p_obra_id uuid DEFAULT NULL,p_colaborador_id uuid DEFAULT NULL,p_competencia date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE response jsonb; u public.utilizadores;
BEGIN
 response:=folha_privado.gestao_contexto_preservado(p_obra_id,p_colaborador_id,p_competencia);u:=folha_privado.ator();
 RETURN response||jsonb_build_object('daily_evaluations',CASE WHEN folha_privado.admin() AND p_colaborador_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p_colaborador_id AND c.empresa_id=u.empresa_id) THEN (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.data),'[]') FROM public.folha_avaliacoes_diarias a WHERE a.colaborador_id=p_colaborador_id AND a.empresa_id=u.empresa_id AND (p_competencia IS NULL OR a.data>=p_competencia AND a.data<(p_competencia+interval '1 month')::date)) ELSE '[]'::jsonb END,'task_reports',coalesce((SELECT jsonb_agg(x.value||jsonb_build_object('reportado_nome',a.nome) ORDER BY x.value->>'id') FROM jsonb_array_elements(response->'task_reports') x LEFT JOIN public.utilizadores a ON a.id=(x.value->>'reportado_por')::uuid AND a.empresa_id=u.empresa_id),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 u:=folha_privado.ator();
 IF p_acao IN('configure_schedule','daily_activation','schedule_retro_correct','daily_reference_correct','daily_he_validate','daily_he_disregard') THEN RETURN public.fn_folha_diaria_gestao_v2(p_acao,p_dados,p_confirmar,p_versao); END IF;
 IF p_acao IN('payroll_validate','payroll_close') AND NOT folha_privado.adm() THEN RAISE EXCEPTION 'PERMISSION_DENIED: somente Administrativo' USING ERRCODE='42501'; END IF;
 IF p_acao IN('payroll_validate','payroll_close') AND EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE a.empresa_id=u.empresa_id AND a.colaborador_id=(p_dados->>'person_id')::uuid AND a.data>=(p_dados->>'month')::date AND a.data<((p_dados->>'month')::date+interval '1 month')::date AND a.ativa AND (cardinality(a.pendencias)>0 OR a.estado<>'regular' OR a.he_estado IN('pendente','validada','nao_avaliavel'))) THEN RAISE EXCEPTION 'PAYROLL_DAILY_PENDING: avaliação diária/HE aguarda regularização ou processamento'; END IF;
 RETURN folha_privado.diaria_gestao_preservada(p_acao,p_dados,p_confirmar,p_versao);
END $$;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND (p.proname LIKE 'diaria_%' OR p.proname IN('save_periodo','operar_periodos','reconciliar_he','reconciliar_dia','linha','normal','payroll_facts')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',r.sig);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text),public.fn_folha_gestao_v2(text,jsonb,boolean,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text),public.fn_folha_gestao_v2(text,jsonb,boolean,text) TO authenticated;
SELECT 'DAILY_INSTALLED_NOT_ACTIVATED' AS resultado;
COMMIT;