-- Pacote 2. Instalação LOCAL proposta; não executa conversão nem reconciliação histórica.
BEGIN;
-- Explicit legacy projection: fail closed if required source columns are absent.
DO $legacy_projection$
DECLARE missing text[];
BEGIN
 SELECT array_agg(required ORDER BY required) INTO missing
 FROM unnest(ARRAY['id','empresa_id','obra_id','colaborador_id','data','horas','entrada_manha','saida_manha','entrada_tarde','saida_tarde','periodos_alocados','estado','registado_por','atualizado_por','criado_em','atualizado_em']) required
 WHERE NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.ponto_pessoal_obra'::regclass AND attname=required AND attnum>0 AND NOT attisdropped);
 IF missing IS NOT NULL THEN RAISE EXCEPTION 'LEGACY_PROJECTION_COLUMNS_MISSING: %',missing; END IF;
END $legacy_projection$;

SET LOCAL lock_timeout='10s';
DO $$ BEGIN
 IF current_user <> 'postgres' OR session_user <> 'postgres' THEN
  RAISE EXCEPTION 'ROLLOUT_OWNER_REQUIRED' USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)') IS NULL
 THEN RAISE EXCEPTION 'QUADRO_V1_REQUIRED'; END IF;
END $$;
DO $$ DECLARE t text; b text; changed boolean; BEGIN
 IF to_regclass('primeline_folha_v2_backup.funcoes') IS NULL THEN RAISE EXCEPTION 'FOLHA_BACKUP_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_folha_v2_backup' AND nspowner='postgres'::regrole)
 OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) x WHERE n.nspname='primeline_folha_v2_backup' AND x.grantee<>'postgres'::regrole)
 THEN RAISE EXCEPTION 'FOLHA_BACKUP_NOT_PRIVATE'; END IF;
 IF md5(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)'::regprocedure),chr(13),''))<>'611f044e9903a3ba9ed7c02417120830' THEN RAISE EXCEPTION 'QUADRO_CORE_DRIFT'; END IF;
 FOR t,b IN VALUES ('quadro_pessoal_alocacao','alocacoes'),('quadro_pessoal_movimentos','movimentos'),('ponto_pessoal_obra','ponto'),('ausencias','ausencias'),('colaboradores','colaboradores'),('horas_extraordinarias','he'),('planeamento_itens','planeamento'),('alertas','alertas') LOOP
  EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE',t);
  EXECUTE format('SELECT (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM public.%I x) IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM primeline_folha_v2_backup.%I x)',t,b) INTO changed;
  IF changed THEN RAISE EXCEPTION 'FOLHA_BACKUP_DRIFT: %',t; END IF;
 END LOOP;
END $$;
CREATE SCHEMA folha_privado;
REVOKE ALL ON SCHEMA folha_privado FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE public.folha_config_empresa(
 empresa_id uuid PRIMARY KEY REFERENCES public.empresas(id),
 office_expected_minutes integer NOT NULL DEFAULT 480 CHECK(office_expected_minutes BETWEEN 1 AND 1440),
 correction_days integer NOT NULL DEFAULT 1 CHECK(correction_days=1),
 overtime_enabled boolean NOT NULL DEFAULT false,
 he_eligible_roles text[] NOT NULL DEFAULT ARRAY['pedreiro','servente'],
 holiday_dates date[] NOT NULL DEFAULT '{}',
 calendar_complete boolean NOT NULL DEFAULT false,
 calendar_validated_years integer[] NOT NULL DEFAULT '{}',
 revision integer NOT NULL DEFAULT 1 CHECK(revision>0)
);
CREATE TABLE public.folha_horarios(
 obra_id uuid PRIMARY KEY REFERENCES public.obras(id),
 empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 intervals jsonb NOT NULL CHECK(jsonb_typeof(intervals)='array'),
 expected_minutes integer NOT NULL CHECK(expected_minutes BETWEEN 1 AND 1440),
 revision integer NOT NULL DEFAULT 1 CHECK(revision>0)
);
CREATE TABLE public.folha_externos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 fornecedor_id uuid NOT NULL REFERENCES public.fornecedores(id),
 nome text NOT NULL CHECK(length(btrim(nome)) BETWEEN 1 AND 160), ativo boolean NOT NULL DEFAULT true,
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id), criado_em timestamptz NOT NULL DEFAULT now(),
 origem_request uuid NOT NULL
);
CREATE TABLE public.folha_externos_dias(
 externo_id uuid NOT NULL REFERENCES public.folha_externos(id), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid NOT NULL REFERENCES public.obras(id), data date NOT NULL,
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id), criado_em timestamptz NOT NULL DEFAULT now(), request_id uuid NOT NULL,
 PRIMARY KEY(externo_id,obra_id,data)
);
CREATE UNIQUE INDEX folha_externos_identidade ON public.folha_externos(empresa_id,fornecedor_id,lower(btrim(nome)));
CREATE TABLE public.folha_registos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 obra_id uuid REFERENCES public.obras(id), tipo_local text NOT NULL DEFAULT 'obra' CHECK(tipo_local IN('obra','escritorio')), data date NOT NULL,
 colaborador_id uuid REFERENCES public.colaboradores(id), externo_id uuid REFERENCES public.folha_externos(id),
 intervals jsonb NOT NULL CHECK(jsonb_typeof(intervals)='array' AND jsonb_array_length(intervals)>0),
 minutes integer NOT NULL CHECK(minutes>=0), estado text NOT NULL CHECK(estado IN('open','registered','missing','regularization')),
 special_day boolean NOT NULL, special_reviewed_by uuid REFERENCES public.utilizadores(id), special_reviewed_at timestamptz, expected_minutes integer CHECK(expected_minutes>0), revision integer NOT NULL CHECK(revision>0), note text CHECK(length(note)<=1000),
 criado_por uuid NOT NULL REFERENCES public.utilizadores(id), atualizado_por uuid NOT NULL REFERENCES public.utilizadores(id),
 criado_em timestamptz NOT NULL DEFAULT now(), atualizado_em timestamptz NOT NULL DEFAULT now(), request_id uuid NOT NULL,
 CHECK(num_nonnulls(colaborador_id,externo_id)=1),
 CHECK((tipo_local='obra' AND obra_id IS NOT NULL) OR (tipo_local='escritorio' AND obra_id IS NULL AND externo_id IS NULL)),
 CONSTRAINT folha_local_check CHECK(tipo_local<>'escritorio' OR colaborador_id IS NOT NULL)
);
CREATE UNIQUE INDEX folha_primeline_facto ON public.folha_registos(colaborador_id,obra_id,data) NULLS NOT DISTINCT WHERE colaborador_id IS NOT NULL;
CREATE UNIQUE INDEX folha_externo_facto ON public.folha_registos(externo_id,obra_id,data) WHERE externo_id IS NOT NULL;
CREATE INDEX folha_registos_dia ON public.folha_registos(empresa_id,data,obra_id);
CREATE TABLE public.folha_historico(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, obra_id uuid, tipo_local text NOT NULL DEFAULT 'obra' CHECK((tipo_local='obra' AND obra_id IS NOT NULL) OR (tipo_local='escritorio' AND obra_id IS NULL)),
 person_id uuid NOT NULL, kind text NOT NULL CHECK(kind IN('primeline','external')), data date NOT NULL,
 action text NOT NULL, antes jsonb, depois jsonb, revision integer NOT NULL,
 ator_id uuid NOT NULL REFERENCES public.utilizadores(id), at timestamptz NOT NULL DEFAULT now(),
 request_id uuid NOT NULL, reason text CHECK(length(reason)<=1000), origem text NOT NULL DEFAULT 'folha_v2'
);
CREATE INDEX folha_historico_chave ON public.folha_historico(empresa_id,obra_id,person_id,data,at);
CREATE FUNCTION folha_privado.invalidar_review_especial() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF ROW(NEW.intervals,NEW.minutes,NEW.estado,NEW.special_day,NEW.expected_minutes,NEW.obra_id,NEW.colaborador_id,NEW.externo_id,NEW.data,NEW.tipo_local)
 IS DISTINCT FROM ROW(OLD.intervals,OLD.minutes,OLD.estado,OLD.special_day,OLD.expected_minutes,OLD.obra_id,OLD.colaborador_id,OLD.externo_id,OLD.data,OLD.tipo_local)
 THEN NEW.special_reviewed_at:=NULL;NEW.special_reviewed_by:=NULL; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER trg_folha_invalidar_review BEFORE UPDATE ON public.folha_registos FOR EACH ROW EXECUTE FUNCTION folha_privado.invalidar_review_especial();
REVOKE ALL ON FUNCTION folha_privado.invalidar_review_especial() FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE public.folha_he(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), empresa_id uuid NOT NULL, obra_id uuid NOT NULL,
 folha_id uuid NOT NULL REFERENCES public.folha_registos(id), folha_revision integer NOT NULL,
 minutes integer NOT NULL CHECK(minutes>0), estado text NOT NULL CHECK(estado IN('potential','pending_validation','rejected','validated_pending_rule','superseded')),
 revision integer NOT NULL DEFAULT 1, UNIQUE(folha_id,folha_revision)
);
CREATE TABLE folha_privado.operacoes(
 empresa_id uuid NOT NULL, ator_id uuid NOT NULL, request_id uuid NOT NULL,
 payload jsonb NOT NULL, token text NOT NULL, resultado jsonb NOT NULL,
 criado_em timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(empresa_id,ator_id,request_id)
);
ALTER TABLE folha_privado.operacoes ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION folha_privado.ator() RETURNS public.utilizadores
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: utilizador inativo ou sem empresa' USING ERRCODE='42501'; END IF;
 RETURN u;
END $$;
CREATE FUNCTION folha_privado.integridade() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE x jsonb:=to_jsonb(NEW); company uuid:=(x->>'empresa_id')::uuid;
BEGIN
 IF x->>'obra_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.obras WHERE id=(x->>'obra_id')::uuid AND empresa_id=company)
 OR x->>'colaborador_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=(x->>'colaborador_id')::uuid AND empresa_id=company)
 OR x->>'fornecedor_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.fornecedores WHERE id=(x->>'fornecedor_id')::uuid AND empresa_id=company)
 OR x->>'externo_id' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.folha_externos WHERE id=(x->>'externo_id')::uuid AND empresa_id=company)
 THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN FOR t IN SELECT unnest(ARRAY['folha_horarios','folha_externos','folha_externos_dias','folha_registos']) LOOP
 EXECUTE format('CREATE TRIGGER folha_integridade BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade()',t);
END LOOP; END $$;
CREATE FUNCTION folha_privado.admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT (folha_privado.ator()).funcao IN('administrativo','gestao_plataforma','gerencia')
$$;
-- Functional superuser remains subject to ator(), tenant and all fact gates.
CREATE FUNCTION folha_privado.superuser() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT (folha_privado.ator()).funcao='gestao_plataforma'
$$;
CREATE FUNCTION folha_privado.adm_operacional() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT (folha_privado.ator()).funcao IN('administrativo','gestao_plataforma')
$$;
CREATE FUNCTION folha_privado.obra(p uuid, escrita boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores;
BEGIN
 u:=folha_privado.ator();
 IF escrita THEN
  PERFORM 1 FROM public.utilizadores WHERE id=u.id FOR SHARE;
  PERFORM 1 FROM public.obras WHERE id=p AND empresa_id=u.empresa_id FOR SHARE;
 ELSE PERFORM 1 FROM public.obras WHERE id=p AND empresa_id=u.empresa_id; END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: obra fora da empresa' USING ERRCODE='42501'; END IF;
 IF folha_privado.admin() THEN RETURN; END IF;
 IF u.funcao NOT IN('encarregado','diretor_obra','adjunto') OR (escrita AND u.funcao<>'encarregado')
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: perfil' USING ERRCODE='42501'; END IF;
 IF escrita THEN PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=p AND utilizador_id=u.id AND papel=u.funcao FOR SHARE;
 ELSE PERFORM 1 FROM public.obra_responsaveis WHERE obra_id=p AND utilizador_id=u.id AND papel=u.funcao; END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: responsabilidade' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION folha_privado.local(p uuid,w uuid,escrita boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; linked uuid; n integer;
BEGIN
 u:=folha_privado.ator();
 IF w IS NOT NULL THEN PERFORM folha_privado.obra(w,escrita); RETURN; END IF;
 IF escrita THEN SELECT * INTO u FROM public.utilizadores WHERE id=u.id AND ativo FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF; END IF;
 IF folha_privado.admin() THEN
  IF p IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  RETURN;
 END IF;
 IF escrita THEN
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ligação própria alterada' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT count(*),min(c.id::text)::uuid INTO n,linked FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id;
 IF u.funcao NOT IN('diretor_obra','adjunto','preparador') OR n<>1 OR (p IS NOT NULL AND p<>linked)
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas a própria Folha de escritório' USING ERRCODE='42501'; END IF;
END $$;
CREATE FUNCTION folha_privado.quadro_autorizado(p uuid,d date,b jsonb,a jsonb) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; x jsonb;
BEGIN
 u:=folha_privado.ator();
 IF u.funcao<>'encarregado' AND NOT public.fn_quadro_pode_gerir_v1(NULL) THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RETURN false; END IF;
 IF jsonb_typeof(b) IS DISTINCT FROM 'array' OR jsonb_typeof(a) IS DISTINCT FROM 'array' OR jsonb_array_length(b)>1 THEN RETURN false; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(b||a) LOOP
  IF x->>'tipo_alocacao' IS DISTINCT FROM 'obra' OR x->>'colaborador_id' IS DISTINCT FROM p::text OR x->>'data' IS DISTINCT FROM d::text
  OR NOT EXISTS(SELECT 1 FROM public.obras WHERE id=(x->>'obra_id')::uuid AND empresa_id=u.empresa_id) THEN RETURN false; END IF;
 END LOOP;
 -- Existing source retained in an opposite half-day is not a new destination.
 FOR x IN SELECT value FROM jsonb_array_elements(a) LOOP
  IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND NOT public.fn_quadro_minha_obra_v1((x->>'obra_id')::uuid)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(b) old WHERE old->>'id'=x->>'id' AND old->>'obra_id'=x->>'obra_id' AND old->>'periodo'='dia_inteiro' AND x->>'periodo' IN('manha','tarde'))
  THEN RETURN false; END IF;
 END LOOP;
 IF a='[]'::jsonb AND NOT public.fn_quadro_pode_gerir_v1(NULL) AND NOT public.fn_quadro_minha_obra_v1((b->0->>'obra_id')::uuid) THEN RETURN false; END IF;
 RETURN true;
END
$$;
CREATE FUNCTION folha_privado.facts(xs jsonb,d date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE x jsonb; s integer; e integer; last_end integer:=-1; total integer:=0; opened boolean:=false;
 n timestamp:=now() AT TIME ZONE 'Europe/Lisbon';
BEGIN
 IF d IS NULL OR d>n::date OR jsonb_typeof(xs) IS DISTINCT FROM 'array' OR jsonb_array_length(xs) NOT BETWEEN 1 AND 16
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: data/intervalos'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(xs) ORDER BY value->>'start' LOOP
  IF coalesce(x->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
   OR (x->>'end' IS NOT NULL AND x->>'end' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
  THEN RAISE EXCEPTION 'VALIDATION_ERROR: hora'; END IF;
  s:=extract(hour from (x->>'start')::time)::integer*60+extract(minute from (x->>'start')::time)::integer;
  e:=CASE WHEN x->>'end' IS NULL THEN NULL ELSE extract(hour from (x->>'end')::time)::integer*60+extract(minute from (x->>'end')::time)::integer END;
  IF opened OR s<last_end OR e<=s THEN RAISE EXCEPTION 'INTERVAL_CONFLICT'; END IF;
  IF d=n::date AND greatest(s,coalesce(e,s))>extract(hour from n)::integer*60+extract(minute from n)::integer
  THEN RAISE EXCEPTION 'FUTURE_TIME'; END IF;
  opened:=e IS NULL; last_end:=coalesce(e,1440); total:=total+coalesce(e-s,0);
 END LOOP;
 RETURN jsonb_build_object('minutes',total,'open',opened);
END $$;
CREATE FUNCTION folha_privado.lock_dia(p uuid,d date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 -- Mesmo primeiro lock do núcleo Quadro; nenhuma ordem inversa entre os dois motores.
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 PERFORM pg_advisory_xact_lock(hashtextextended(p::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(p::text||':'||d::text,0));
END $$;
CREATE FUNCTION folha_privado.proteger_legado() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=NEW.colaborador_id AND data=NEW.data)
 THEN RAISE EXCEPTION 'LEGACY_CONFLICT: não misturar escritores'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_legacy_conflict BEFORE INSERT OR UPDATE ON public.ponto_pessoal_obra
 FOR EACH ROW EXECUTE FUNCTION folha_privado.proteger_legado();
CREATE FUNCTION folha_privado.lock_legado() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1); RETURN NULL;
END $$;
-- Coordena também escritores antigos; não altera linhas, sem herança temporal.
CREATE TRIGGER trg_00_folha_absencias_lock BEFORE INSERT OR UPDATE OR DELETE ON public.ausencias
 FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.lock_legado();
CREATE TRIGGER trg_00_folha_alocacao_lock BEFORE INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao
 FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.lock_legado();
CREATE TRIGGER trg_00_folha_ponto_lock BEFORE INSERT OR UPDATE OR DELETE ON public.ponto_pessoal_obra
 FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.lock_legado();
CREATE TRIGGER trg_00_folha_he_lock BEFORE INSERT OR UPDATE OR DELETE ON public.horas_extraordinarias
 FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.lock_legado();
CREATE FUNCTION folha_privado.proteger_he_legado() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.folha_he h JOIN public.folha_registos f ON f.id=h.folha_id
 WHERE f.colaborador_id=NEW.colaborador_id AND f.data=NEW.data AND h.estado<>'superseded')
 THEN RAISE EXCEPTION 'OVERTIME_ORIGIN_CONFLICT'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_he_origin_conflict BEFORE INSERT OR UPDATE ON public.horas_extraordinarias
 FOR EACH ROW EXECUTE FUNCTION folha_privado.proteger_he_legado();
CREATE FUNCTION folha_privado.imutavel() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'HISTORY_IMMUTABLE'; END $$;
CREATE TRIGGER folha_historico_imutavel BEFORE UPDATE OR DELETE ON public.folha_historico
 FOR EACH ROW EXECUTE FUNCTION folha_privado.imutavel();
CREATE FUNCTION folha_privado.linha(p uuid,w uuid,d date,k text) RETURNS jsonb
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
  SELECT coalesce(jsonb_agg(q.id ORDER BY q.id),'[]'),CASE WHEN count(DISTINCT q.periodo)>1 THEN 'dia_inteiro' ELSE min(q.periodo) END INTO ids,period FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data=d AND q.obra_id=w;
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
 RETURN jsonb_build_object('tipo_local',CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,'person_id',p,'name',nome,'role',papel,'provider_name',fornecedor,
  'sheet',CASE WHEN s.id IS NULL THEN NULL ELSE jsonb_build_object('id',s.id,'intervals',s.intervals,'note',s.note,'state',s.estado) END,
  'absence',a,'legacy',legacy,'conflict',conf,'special_day',s.special_day,'special_reviewed',s.special_reviewed_at IS NOT NULL,'special_review_pending',s.special_day AND s.special_reviewed_at IS NULL,'revision',coalesce(s.revision,0),'allocation_revision',coalesce(rev,0),
  'allocation_ids',coalesce(ids,'[]'),'period',coalesce(period,'dia_inteiro'),'expected_minutes',expected,
  'can_remove',w IS NOT NULL AND NOT legacy AND conf IS NULL AND s.id IS NULL AND a IS NULL AND NOT EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=p AND data=d) AND jsonb_array_length(coalesce(ids,'[]'))=1
   AND EXISTS(SELECT 1 FROM public.obras WHERE id=w AND situacao='em_curso')
   AND EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d))
   AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),
  'overtime',CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('estado',coalesce((SELECT h.estado FROM public.folha_he h WHERE h.folha_id=s.id AND h.folha_revision=s.revision AND h.estado<>'superseded'),CASE WHEN s.special_day AND s.special_reviewed_at IS NULL AND s.estado<>'regularization' THEN 'pending_rule' ELSE 'none' END)) END,
  'can_write',NOT legacy AND conf IS NULL AND d<=(now() AT TIME ZONE 'Europe/Lisbon')::date AND (d=(now() AT TIME ZONE 'Europe/Lisbon')::date OR folha_privado.adm_operacional() OR d>=(now() AT TIME ZONE 'Europe/Lisbon')::date-1) AND (w IS NULL OR folha_privado.admin() OR u.funcao='encarregado') AND ((k='external' AND EXISTS(SELECT 1 FROM public.folha_externos WHERE id=p AND empresa_id=u.empresa_id AND ativo)) OR EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.data_admissao<=d AND (c.data_saida IS NULL OR c.data_saida>d))));
END $$;
CREATE FUNCTION folha_privado.estado_efetivo(minutos integer,aberto boolean,esperado integer,ausencia boolean,conflito boolean) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT CASE WHEN ausencia OR conflito THEN 'regularization' WHEN aberto THEN 'open'
 WHEN esperado IS NULL THEN 'regularization' WHEN minutos<esperado THEN 'missing' ELSE 'registered' END
$$;
CREATE FUNCTION folha_privado.reconciliar_he(f public.folha_registos) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
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
CREATE FUNCTION folha_privado.reconciliar_dia(p uuid,d date,req uuid,origem text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; f public.folha_registos; antes public.folha_registos; r jsonb; facts jsonb; novo_estado text; conflito boolean;
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
END $$;
CREATE FUNCTION folha_privado.reconciliar_dependencia() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE req uuid:=coalesce(nullif(current_setting('folha.request_id',true),'')::uuid,gen_random_uuid()); origem text;
BEGIN
 origem:=CASE WHEN TG_TABLE_NAME='ausencias' THEN CASE WHEN (TG_OP<>'DELETE' AND to_jsonb(NEW)->>'tipo'='ferias') OR (TG_OP<>'INSERT' AND to_jsonb(OLD)->>'tipo'='ferias') THEN 'vacation_reconciliation' ELSE 'absence_reconciliation' END ELSE 'allocation_reconciliation' END;
 IF TG_OP<>'INSERT' THEN PERFORM folha_privado.reconciliar_dia(OLD.colaborador_id,OLD.data,req,origem); END IF;
 IF TG_OP<>'DELETE' AND (TG_OP='INSERT' OR NEW.colaborador_id IS DISTINCT FROM OLD.colaborador_id OR NEW.data IS DISTINCT FROM OLD.data)
 THEN PERFORM folha_privado.reconciliar_dia(NEW.colaborador_id,NEW.data,req,origem); END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER trg_folha_ausencia_reconciliar AFTER INSERT OR UPDATE OR DELETE ON public.ausencias FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_dependencia();
CREATE TRIGGER trg_folha_alocacao_reconciliar AFTER INSERT OR UPDATE OR DELETE ON public.quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION folha_privado.reconciliar_dependencia();
CREATE FUNCTION public.fn_folha_contexto_v2(p_data date,p_obra_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; works jsonb; rows jsonb:='[]'; ext jsonb:='[]'; sched jsonb; providers jsonb:='[]'; x record; special boolean;
 office boolean:=false; self_id uuid; summary jsonb; r jsonb; registered integer:=0; opened integer:=0; pending integer:=0; total integer; worked integer; status text;
BEGIN
 u:=folha_privado.ator();
 SELECT min(c.id::text)::uuid INTO self_id FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id HAVING count(*)=1;
 office:=folha_privado.admin() OR (u.funcao IN('diretor_obra','adjunto','preparador') AND self_id IS NOT NULL);
 IF p_data IS NULL THEN RAISE EXCEPTION 'VALIDATION_ERROR: data'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',o.id,'number',o.numero,'name',o.nome) ORDER BY o.numero),'[]') INTO works
 FROM public.obras o WHERE o.empresa_id=u.empresa_id AND
 (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=o.id AND r.utilizador_id=u.id AND r.papel=u.funcao AND u.funcao IN('encarregado','diretor_obra','adjunto')));
 IF p_obra_id IS NOT NULL THEN
  PERFORM folha_privado.obra(p_obra_id);
  FOR x IN SELECT DISTINCT q.colaborador_id FROM public.quadro_pessoal_alocacao q JOIN public.colaboradores c ON c.id=q.colaborador_id AND c.empresa_id=u.empresa_id WHERE q.obra_id=p_obra_id AND q.data=p_data
   UNION SELECT f.colaborador_id FROM public.folha_registos f JOIN public.colaboradores c ON c.id=f.colaborador_id AND c.empresa_id=u.empresa_id WHERE f.obra_id=p_obra_id AND f.data=p_data AND f.empresa_id=u.empresa_id
   UNION SELECT h.colaborador_id FROM public.ponto_pessoal_obra h JOIN public.colaboradores c ON c.id=h.colaborador_id AND c.empresa_id=u.empresa_id WHERE h.obra_id=p_obra_id AND h.data=p_data AND h.empresa_id=u.empresa_id LOOP
   rows:=rows||jsonb_build_array(folha_privado.linha(x.colaborador_id,p_obra_id,p_data,'primeline'));
  END LOOP;
  FOR x IN SELECT e.id FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id
   AND (EXISTS(SELECT 1 FROM public.folha_externos_dias ed WHERE ed.externo_id=e.id AND ed.obra_id=p_obra_id AND ed.data=p_data)
   OR EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.externo_id=e.id AND f.data=p_data AND f.obra_id=p_obra_id)) LOOP
   ext:=ext||jsonb_build_array(folha_privado.linha(x.id,p_obra_id,p_data,'external'));
  END LOOP;
  SELECT jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes,'revision',h.revision) INTO sched FROM public.folha_horarios h WHERE h.obra_id=p_obra_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'name',f.nome)),'[]') INTO providers FROM public.fornecedores f
   WHERE f.empresa_id=u.empresa_id AND (folha_privado.admin() OR u.funcao='encarregado') AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=p_obra_id));
 ELSIF office THEN
  PERFORM folha_privado.local(self_id,NULL);
  FOR x IN SELECT c.id colaborador_id FROM public.colaboradores c WHERE c.empresa_id=u.empresa_id AND (c.id=self_id OR folha_privado.admin() AND (EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=c.id AND q.data=p_data AND q.tipo_alocacao='escritorio') OR EXISTS(SELECT 1 FROM public.folha_registos f WHERE f.colaborador_id=c.id AND f.obra_id IS NULL AND f.data=p_data))) LOOP
   rows:=rows||jsonb_build_array(folha_privado.linha(x.colaborador_id,NULL,p_data,'primeline'));
  END LOOP;
  sched:=jsonb_build_object('intervals','[]'::jsonb,'expected_minutes',coalesce((SELECT office_expected_minutes FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),480));
 END IF;
 special:=extract(isodow FROM p_data)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND p_data=ANY(holiday_dates));
 FOR r IN SELECT value FROM jsonb_array_elements(rows||ext) LOOP
  IF r->'sheet'<>'null'::jsonb THEN status:=r->'sheet'->>'state';
  ELSIF r->>'conflict' IS NOT NULL THEN status:='regularization';
  ELSIF r->'absence'<>'null'::jsonb THEN status:=CASE WHEN r->'sheet'<>'null'::jsonb THEN 'regularization' WHEN r->'absence'->>'estado'='ausente_pendente' THEN 'absence_pending' ELSE 'absence' END;
  ELSIF (r->>'legacy')::boolean THEN status:='legacy';
  ELSIF r->'sheet'='null'::jsonb THEN status:='none';
  ELSIF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'sheet'->'intervals') i WHERE i->>'end' IS NULL) THEN status:='open';
  ELSE
   SELECT sum((extract(epoch FROM ((i->>'end')::time-(i->>'start')::time))/60)::integer) INTO worked FROM jsonb_array_elements(r->'sheet'->'intervals') i;
   status:=CASE WHEN r->>'expected_minutes' IS NULL THEN 'regularization' WHEN worked<(r->>'expected_minutes')::integer THEN 'missing' ELSE 'registered' END;
  END IF;
  registered:=registered+CASE WHEN status='registered' THEN 1 ELSE 0 END; opened:=opened+CASE WHEN status='open' THEN 1 ELSE 0 END;
  pending:=pending+CASE WHEN status IN('registered','absence','legacy') AND NOT coalesce((r->>'special_review_pending')::boolean,false) THEN 0 ELSE 1 END;
 END LOOP;
 summary:=jsonb_build_object('people',jsonb_array_length(rows||ext),'registered',registered,'open',opened,'pending',pending,'complete',pending=0);
 RETURN jsonb_build_object('version',2,'date',p_data,'work_id',p_obra_id,'works',works,'rows',rows,'external_rows',ext,
  'tipo_local',CASE WHEN p_obra_id IS NULL THEN 'escritorio' ELSE 'obra' END,'office_available',office,'self_person_id',self_id,'correction_days',1,'admin',folha_privado.admin(),'summary',summary,'schedule',sched,'special_day',special,'providers',providers,
  'external_people',coalesce((SELECT jsonb_agg(jsonb_build_object('id',e.id,'name',e.nome,'provider_id',e.fornecedor_id)) FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id AND e.ativo AND (folha_privado.admin() OR u.funcao='encarregado') AND EXISTS(SELECT 1 FROM public.fornecedores f WHERE f.id=e.fornecedor_id AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=p_obra_id)))
   AND NOT EXISTS(SELECT 1 FROM public.folha_externos_dias ed WHERE ed.externo_id=e.id AND ed.data=p_data AND ed.obra_id=p_obra_id)),'[]'),
  'management',folha_privado.admin() OR p_obra_id IS NOT NULL AND u.funcao IN('encarregado','diretor_obra','adjunto'),
  'calendar_verified',coalesce((SELECT calendar_complete FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),false),
  'overtime_generation',CASE WHEN EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND overtime_enabled AND calendar_complete AND extract(year FROM p_data)::integer=ANY(calendar_validated_years)) THEN 'enabled' ELSE 'disabled_pending_compatibility' END,
  'permissions',jsonb_build_object('write',CASE WHEN p_obra_id IS NULL THEN office ELSE folha_privado.admin() OR u.funcao='encarregado' END,'allocation_write',p_obra_id IS NOT NULL AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),'external_write',p_obra_id IS NOT NULL AND (folha_privado.admin() OR u.funcao='encarregado')));
END $$;
CREATE FUNCTION public.fn_folha_pessoas_v2(p_data date,p_obra_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; people jsonb;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.obra(p_obra_id);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: alocação' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('person_id',c.id,'name',c.nome,
 'current_work',CASE WHEN q.id IS NULL THEN NULL ELSE jsonb_build_object('id',q.obra_id,'type',q.tipo_alocacao,'label',CASE WHEN q.obra_id IS NULL THEN q.tipo_alocacao ELSE 'Obra '||o.numero END) END,
 'allocation_revision',coalesce(r.revisao,0),'can_allocate',q.id IS NULL AND NOT a.blocked,
 'can_transfer',q.id IS NOT NULL AND q.tipo_alocacao='obra' AND o.empresa_id=u.empresa_id AND NOT a.blocked)),'[]') INTO people
 FROM public.colaboradores c
 LEFT JOIN LATERAL(SELECT * FROM public.quadro_pessoal_alocacao WHERE colaborador_id=c.id AND data=p_data ORDER BY id LIMIT 1) q ON true
 LEFT JOIN public.obras o ON o.id=q.obra_id LEFT JOIN public.quadro_dias_revisoes r ON r.colaborador_id=c.id AND r.data=p_data
 CROSS JOIN LATERAL(SELECT EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=c.id AND data=p_data)
 OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=c.id AND data=p_data)
 OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=c.id AND data=p_data)
 OR (SELECT count(*) FROM public.quadro_pessoal_alocacao WHERE colaborador_id=c.id AND data=p_data)>1 blocked) a
 WHERE c.empresa_id=u.empresa_id AND c.data_admissao<=p_data AND (c.data_saida IS NULL OR c.data_saida>p_data);
 RETURN jsonb_build_object('version',2,'people',people);
END $$;
CREATE FUNCTION public.fn_folha_historico_v2(p_chave jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid:=(p_chave->>'work_id')::uuid; p uuid:=(p_chave->>'person_id')::uuid; d date:=(p_chave->>'date')::date; k text:=p_chave->>'kind'; events jsonb; legacy jsonb;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.linha(p,w,d,k);
 -- Pessoa sem alocação só é consultável pelo responsável se existir histórico naquela obra.
 IF w IS NOT NULL AND NOT folha_privado.admin() AND NOT EXISTS(SELECT 1 FROM public.folha_historico WHERE obra_id=w AND person_id=p AND data=d AND kind=k)
 AND NOT EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao WHERE obra_id=w AND colaborador_id=p AND data=d)
 AND NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE obra_id=w AND externo_id=p AND data=d)
 AND NOT EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE empresa_id=u.empresa_id AND obra_id=w AND colaborador_id=p AND data=d AND k='primeline')
 THEN RAISE EXCEPTION 'PERMISSION_DENIED: histórico fora da equipa' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.at,h.id),'[]') INTO events FROM public.folha_historico h
 WHERE empresa_id=u.empresa_id AND obra_id IS NOT DISTINCT FROM w AND person_id=p AND data=d AND kind=k;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',h.id,'data',h.data,'obra_id',h.obra_id,
 'horas',h.horas,'entrada_manha',h.entrada_manha,'saida_manha',h.saida_manha,
 'entrada_tarde',h.entrada_tarde,'saida_tarde',h.saida_tarde,'periodos_alocados',h.periodos_alocados,
 'estado',h.estado,'registado_por',h.registado_por,'atualizado_por',h.atualizado_por,
 'criado_em',h.criado_em,'atualizado_em',h.atualizado_em) ORDER BY h.criado_em,h.id),'[]') INTO legacy FROM public.ponto_pessoal_obra h
 WHERE empresa_id=u.empresa_id AND obra_id IS NOT DISTINCT FROM w AND colaborador_id=p AND data=d AND k='primeline';
 RETURN jsonb_build_object('version',2,'events',events,'legacy',legacy,'legacy_interpretation','original');
END $$;
CREATE FUNCTION folha_privado.save(p jsonb,w uuid,d date,req uuid,confirmar boolean) RETURNS jsonb
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
  IF w IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao WHERE colaborador_id=person AND data=d AND obra_id=w) THEN RAISE EXCEPTION 'ALLOCATION_REQUIRED'; END IF;
 ELSE
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND ativo FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo indisponível' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=w))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor não autorizado' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'EXTERNAL_DAY_REQUIRED'; END IF;
 END IF;
 IF row->>'conflict' IS NOT NULL THEN RAISE EXCEPTION '%',row->>'conflict'; END IF;
 SELECT * INTO old FROM public.folha_registos WHERE obra_id IS NOT DISTINCT FROM w AND data=d AND CASE WHEN kind='primeline' THEN colaborador_id=person ELSE externo_id=person END FOR UPDATE;
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
 IF NOT confirmar THEN RETURN jsonb_build_object('before',to_jsonb(old),'revision',coalesce(old.revision,0),'row',row,'facts',f,'state',state); END IF;
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
 PERFORM folha_privado.reconciliar_he(result);
 RETURN jsonb_build_object('result',to_jsonb(result));
END $$;
CREATE FUNCTION folha_privado.normal(p uuid,w uuid,d date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE r jsonb; xs jsonb; full_day jsonb;
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
END $$;
CREATE FUNCTION folha_privado.alocar(p_acao text,p jsonb,w uuid,d date,req uuid,confirmar boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; person uuid:=(p->>'person_id')::uuid; b jsonb; a jsonb; x jsonb; period text:=p->>'period'; rev integer; result jsonb;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.obra(w,true); PERFORM folha_privado.lock_dia(person,d);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: alocação' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id AND situacao='em_curso') THEN RAISE EXCEPTION 'WORK_UNAVAILABLE'; END IF;
 b:=public.fn_quadro_dia_explicito(person,d);
 SELECT coalesce(revisao,0) INTO rev FROM public.quadro_dias_revisoes WHERE colaborador_id=person AND data=d;
 IF (p->>'expected_allocation_revision')::integer IS DISTINCT FROM coalesce(rev,0) THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=d)
 OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=person AND data=d)
 OR EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=person AND data=d) THEN RAISE EXCEPTION 'REGULARIZATION_REQUIRED'; END IF;
 IF jsonb_array_length(b)>1 THEN RAISE EXCEPTION 'ALLOCATION_CONFLICT'; END IF;
 IF p_acao='remove_from_day' THEN
  IF jsonb_array_length(b)<>1 OR b->0->>'obra_id' IS DISTINCT FROM w::text
   OR p->'ids' IS DISTINCT FROM jsonb_build_array(b->0->'id') THEN RAISE EXCEPTION 'STALE_ALLOCATION'; END IF;
  a:='[]';
 ELSE
  IF period IS NULL OR period NOT IN('manha','tarde','dia_inteiro') THEN RAISE EXCEPTION 'VALIDATION_ERROR: período'; END IF;
  IF p_acao='allocate' AND b<>'[]'::jsonb THEN RAISE EXCEPTION 'ALLOCATION_CONFLICT'; END IF;
  IF p_acao='transfer' THEN
   IF jsonb_array_length(b)<>1 OR b->0->>'tipo_alocacao'<>'obra' OR b->0->>'obra_id' IS DISTINCT FROM p->>'source_work_id'
    OR b->0->>'obra_id'=w::text THEN RAISE EXCEPTION 'SOURCE_CONFLICT'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=(b->0->>'obra_id')::uuid AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: origem' USING ERRCODE='42501'; END IF;
   -- Partial transfer preserves the opposite half-day in the original work.
   IF period<>'dia_inteiro' AND b->0->>'periodo'='dia_inteiro' THEN
    a:=jsonb_build_array(jsonb_set(b->0,'{periodo}',to_jsonb(CASE WHEN period='manha' THEN 'tarde'::text ELSE 'manha'::text END)));
   ELSIF period<>'dia_inteiro' AND b->0->>'periodo'<>period THEN RAISE EXCEPTION 'PERIOD_CONFLICT';
   ELSE a:='[]'; END IF;
  ELSE a:='[]'; END IF;
  x:=jsonb_build_object('id',req,'colaborador_id',person,'obra_id',w,'data',d,'periodo',period,'tipo_alocacao','obra','descricao_livre',NULL);
  a:=a||jsonb_build_array(x);
 END IF;
 -- Origin chosen only here. Private core independently verifies tenant and destinations.
 result:=public.fn_quadro_aplicar_interno(person,d,b,a,'folha_v2',req,NOT confirmar);
 IF confirmar THEN
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
 VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,'primeline',d,p_acao,b,a,(result->>'revision')::integer,u.id,req,p->>'reason');
 END IF;
 RETURN jsonb_build_object('before',b,'after',a,'allocation_revision',coalesce(rev,0),'result',result);
END $$;
-- Authorization only: replay must not repeat revision/absence/state checks changed by its commit.
CREATE FUNCTION folha_privado.autorizar_replay(acao text,p jsonb,w uuid,d date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; item jsonb; person uuid; kind text; provider uuid;
BEGIN
 u:=folha_privado.ator();
 IF acao IN('save','bulk') THEN
  FOR item IN SELECT value FROM jsonb_array_elements(CASE WHEN acao='save' THEN jsonb_build_array(p) ELSE p->'items' END) LOOP
   person:=(item->'key'->>'person_id')::uuid; kind:=item->'key'->>'kind';
   PERFORM folha_privado.local(person,w,true);
   IF kind='primeline' THEN
    IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
   ELSE
    IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.fornecedores f ON f.id=e.fornecedor_id WHERE e.id=person AND e.empresa_id=u.empresa_id AND e.ativo AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.obra_id=w AND s.fornecedor_id=e.fornecedor_id))) THEN RAISE EXCEPTION 'PERMISSION_DENIED: externo' USING ERRCODE='42501'; END IF;
   END IF;
  END LOOP;
  IF (now() AT TIME ZONE 'Europe/Lisbon')::date-d>1 AND NOT folha_privado.adm_operacional() THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 ELSIF acao IN('allocate','transfer','remove_from_day') THEN
  IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: alocação' USING ERRCODE='42501'; END IF;
  person:=(p->>'person_id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=person AND empresa_id=u.empresa_id AND data_admissao<=d AND (data_saida IS NULL OR data_saida>d)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: pessoa' USING ERRCODE='42501'; END IF;
  IF acao='transfer' AND NOT EXISTS(SELECT 1 FROM public.obras WHERE id=(p->>'source_work_id')::uuid AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: origem' USING ERRCODE='42501'; END IF;
 ELSE
  provider:=(p->>'provider_id')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.fornecedores WHERE id=provider AND empresa_id=u.empresa_id) OR (NOT folha_privado.admin() AND NOT EXISTS(SELECT 1 FROM public.subempreitadas WHERE obra_id=w AND fornecedor_id=provider)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor' USING ERRCODE='42501'; END IF;
 END IF;
END $$;
CREATE FUNCTION public.fn_folha_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid:=(p_dados->>'work_id')::uuid; d date:=(p_dados->>'date')::date;
 req uuid:=(p_dados->>'request_id')::uuid; payload jsonb; op folha_privado.operacoes; preview jsonb:='[]'; keys jsonb:='[]';
 item jsonb; token text; result jsonb; person uuid; provider uuid; old_count integer;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE FOR SHARE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF w IS NULL THEN
  IF p_acao<>'save' OR p_dados->'key'->>'kind' IS DISTINCT FROM 'primeline' THEN RAISE EXCEPTION 'PERMISSION_DENIED: escritório apenas Folha própria' USING ERRCODE='42501'; END IF;
  PERFORM folha_privado.local((p_dados->'key'->>'person_id')::uuid,w,true);
 ELSE PERFORM folha_privado.obra(w,true); END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR d IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 OR p_acao IS NULL OR p_acao NOT IN('save','bulk','allocate','transfer','remove_from_day','external_register') THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  PERFORM folha_privado.autorizar_replay(p_acao,p_dados,w,d);
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token,'summary','Operação já registada; confirmar recupera o resultado.'); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF p_acao IN('save','bulk') THEN
  IF p_acao='save' THEN preview:=jsonb_build_array(folha_privado.save(p_dados,w,d,req,false));
  ELSE
   IF (p_dados->>'operation' IS DISTINCT FROM 'normal' AND (d<>(now() AT TIME ZONE 'Europe/Lisbon')::date OR p_dados->>'effective_time' IS NULL OR p_dados->>'effective_time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'))
   OR p_dados->>'operation' IS NULL OR p_dados->>'operation' NOT IN('start','finish','normal') OR jsonb_typeof(p_dados->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'items') NOT BETWEEN 1 AND 200
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'items') x GROUP BY x->'key'->>'person_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'VALIDATION_ERROR: bulk'; END IF;
   FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'items') ORDER BY value->'key'->>'person_id' LOOP
    IF item->'key'->>'kind'<>'primeline' OR EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=(item->'key'->>'person_id')::uuid AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT'; END IF;
    person:=(item->'key'->>'person_id')::uuid;
    IF p_dados->>'operation'='normal' THEN
     IF EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d)
      OR item->'intervals' IS DISTINCT FROM folha_privado.normal(person,w,d) THEN RAISE EXCEPTION 'NORMAL_DAY_CONFLICT'; END IF;
    ELSIF p_dados->>'operation'='start' THEN
     IF d<>(now() AT TIME ZONE 'Europe/Lisbon')::date OR EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND data=d)
      OR jsonb_array_length(item->'intervals')<>1 OR item->'intervals'->0->>'end' IS NOT NULL OR item->'intervals'->0->>'start' IS DISTINCT FROM p_dados->>'effective_time' THEN RAISE EXCEPTION 'BULK_START_CONFLICT'; END IF;
    ELSE
     IF NOT EXISTS(SELECT 1 FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d AND estado='open')
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(item->'intervals') x WHERE x->>'end' IS NULL)
      OR EXISTS(SELECT 1 FROM public.folha_registos f,jsonb_array_elements(f.intervals) x WHERE f.colaborador_id=person AND f.obra_id=w AND f.data=d
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(item->'intervals') n WHERE n->>'start'=x->>'start' AND (CASE WHEN x->>'end' IS NULL THEN n->>'end'=p_dados->>'effective_time' ELSE n->>'end'=x->>'end' END)))
      OR (SELECT jsonb_array_length(intervals) FROM public.folha_registos WHERE colaborador_id=person AND obra_id=w AND data=d)<>jsonb_array_length(item->'intervals')
     THEN RAISE EXCEPTION 'BULK_FINISH_CONFLICT'; END IF;
    END IF;
    preview:=preview||jsonb_build_array(folha_privado.save(item,w,d,req,false));
   END LOOP;
  END IF;
 ELSIF p_acao IN('allocate','transfer','remove_from_day') THEN preview:=folha_privado.alocar(p_acao,p_dados,w,d,req,false);
 ELSE
  provider:=(p_dados->>'provider_id')::uuid;
  PERFORM 1 FROM public.fornecedores f WHERE f.id=provider AND f.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND OR (NOT folha_privado.admin() AND NOT EXISTS(SELECT 1 FROM public.subempreitadas WHERE obra_id=w AND fornecedor_id=provider)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor' USING ERRCODE='42501'; END IF;
  IF length(btrim(coalesce(p_dados->>'name',''))) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'VALIDATION_ERROR: nome'; END IF;
  person:=coalesce((p_dados->>'external_id')::uuid,req);
  IF p_dados->>'external_id' IS NULL AND EXISTS(SELECT 1 FROM public.folha_externos WHERE empresa_id=u.empresa_id AND fornecedor_id=provider AND lower(btrim(nome))=lower(btrim(p_dados->>'name')))
  THEN RAISE EXCEPTION 'EXTERNAL_IDENTITY_EXISTS: reutilize a identidade existente; homónimos precisam de identificação operacional distinta'; END IF;
  IF p_dados->>'external_id' IS NOT NULL THEN
   PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND fornecedor_id=provider AND ativo AND nome=btrim(p_dados->>'name') FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: identidade externa' USING ERRCODE='42501'; END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM public.folha_externos_dias WHERE externo_id=person AND obra_id=w AND data=d) THEN RAISE EXCEPTION 'EXTERNAL_DAY_EXISTS'; END IF;
  preview:=jsonb_build_object('provider',provider,'work',w,'person_id',person);
 END IF;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'snapshot',preview)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'summary',CASE WHEN p_acao='bulk' THEN format('Registar %s pessoas; %s excluídas. Exclusões: férias/ausências, conflitos, sem autorização ou ponto não elegível para esta ação. Confirmar?',jsonb_array_length(p_dados->'items'),jsonb_array_length(public.fn_folha_contexto_v2(d,w)->'rows')-jsonb_array_length(p_dados->'items')) WHEN p_acao='remove_from_day' THEN 'Retirar exclusivamente esta pessoa da equipa deste dia? O histórico será preservado.' WHEN p_acao='transfer' THEN 'Transferir da obra indicada para esta obra? O movimento e eventuais alertas serão preservados.' ELSE 'Confirmar estes factos na Folha de Ponto?' END,'preview',preview); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF p_acao IN('save','bulk') THEN
  FOR item IN SELECT value FROM jsonb_array_elements(CASE WHEN p_acao='save' THEN jsonb_build_array(p_dados) ELSE p_dados->'items' END) ORDER BY value->'key'->>'person_id' LOOP
   result:=folha_privado.save(item,w,d,req,true); keys:=keys||jsonb_build_array(item->'key');
  END LOOP;
 ELSIF p_acao IN('allocate','transfer','remove_from_day') THEN
  result:=folha_privado.alocar(p_acao,p_dados,w,d,req,true);
  keys:=jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p_dados->>'person_id','work_id',w,'date',d));
 ELSE
  IF p_dados->>'external_id' IS NULL THEN
   INSERT INTO public.folha_externos(id,empresa_id,fornecedor_id,nome,criado_por,origem_request)
   VALUES(person,u.empresa_id,provider,btrim(p_dados->>'name'),u.id,req);
  END IF;
  INSERT INTO public.folha_externos_dias VALUES(person,u.empresa_id,w,d,u.id,now(),req);
  INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
   VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,'external',d,p_acao,NULL,jsonb_build_object('name',p_dados->>'name','provider_id',provider),0,u.id,req,NULL);
  keys:=jsonb_build_array(jsonb_build_object('kind','external','person_id',person,'work_id',w,'date',d));
 END IF;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys,'result',result);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;
DO $$ DECLARE t text; f record; BEGIN
 FOR t IN SELECT unnest(ARRAY['folha_config_empresa','folha_horarios','folha_externos','folha_externos_dias','folha_registos','folha_historico','folha_he']) LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' OR (n.nspname='public' AND p.proname IN('fn_folha_contexto_v2','fn_folha_pessoas_v2','fn_folha_operar_v2','fn_folha_historico_v2')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',f.sig);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.fn_folha_contexto_v2(date,uuid),public.fn_folha_pessoas_v2(date,uuid),public.fn_folha_operar_v2(text,jsonb,boolean,text),public.fn_folha_historico_v2(jsonb) TO authenticated;
-- The exact reviewed Quadro core replacement is appended before COMMIT by the build source.

CREATE OR REPLACE FUNCTION public.fn_quadro_aplicar_interno(p_colaborador_id uuid,p_data date,
 p_antes jsonb,p_depois jsonb,p_origem text,p_request_id uuid DEFAULT NULL,p_simular boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; c public.colaboradores; q public.quadro_pessoal_alocacao;
 v_antes jsonb; v_revisao integer; v_row jsonb;
BEGIN
 SELECT * INTO u FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo IS TRUE;
 IF u.id IS NULL OR u.empresa_id IS NULL THEN RAISE EXCEPTION 'PERMISSION_DENIED: sessão sem utilizador ativo.' USING ERRCODE='42501'; END IF;
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 SELECT * INTO c FROM public.colaboradores WHERE id=p_colaborador_id AND empresa_id=u.empresa_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador de outra empresa ou inexistente.' USING ERRCODE='42501'; END IF;
 IF p_data IS NULL OR p_origem NOT IN('quadro','cadastro_rh','importacao_rh','folha_v2') THEN RAISE EXCEPTION 'VALIDATION_ERROR: data/origem inválida.'; END IF;
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
  IF NOT ((p_origem='folha_v2' AND folha_privado.quadro_autorizado(p_colaborador_id,p_data,p_antes,p_depois)) OR public.fn_quadro_pode_gerir_v1(NULL) OR (p_origem IN('cadastro_rh','importacao_rh') AND public.fn_rh_empresa(false)=u.empresa_id)) AND
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
COMMIT;
