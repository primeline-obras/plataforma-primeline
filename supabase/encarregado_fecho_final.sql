-- Pacote único local. Aplicar somente após PRECHECK e BACKUP aprovados.
BEGIN;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
DO $$ DECLARE r record; actual jsonb; BEGIN
 IF current_user<>'postgres' OR to_regclass('primeline_encarregado_final_backup.funcoes') IS NULL THEN RAISE EXCEPTION 'PRIVATE_BACKUP_REQUIRED'; END IF;
 IF to_regclass('public.folha_externos_permanencias') IS NOT NULL THEN RAISE EXCEPTION 'ALREADY_INSTALLED'; END IF;
 FOR r IN SELECT * FROM (VALUES
('folha_privado.facts(jsonb,date)','6f1b77b09ce6c0bd93182a4ca09b98f73a10a83a213b7e9ae5411aad1b4bcaec','{"owner":"postgres","security_definer":false,"proconfig":["search_path=pg_catalog"],"volatility":"s","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"xs jsonb, d date","argumentos_identidade":"xs jsonb, d date","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('folha_privado.linha(uuid,uuid,date,text)','0e7668583f3c3b78a4e9007515a9caceae70b491c9cdb4300f6d3ac4de25c100','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p uuid, w uuid, d date, k text","argumentos_identidade":"p uuid, w uuid, d date, k text","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('folha_privado.local(uuid,uuid,boolean)','17d473f2cf300bc4dc4f64cf3920dc394dcd8284b317bf737b40abaf458ccec3','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p uuid, w uuid, escrita boolean DEFAULT false","argumentos_identidade":"p uuid, w uuid, escrita boolean","retorno":"void","tipo_retorno":"void","acl_efetiva":[{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('folha_privado.normal(uuid,uuid,date)','ecd9239207649502d787aba88d5361f68a906a3f1c199dd9b6199b7e0f6f8b7c','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p uuid, w uuid, d date","argumentos_identidade":"p uuid, w uuid, d date","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('folha_privado.save(jsonb,uuid,date,uuid,boolean)','915febb0e4d9a88dffb0f145d75f7d9113c2eac34da4d9e35706806e698ffae9','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p jsonb, w uuid, d date, req uuid, confirmar boolean","argumentos_identidade":"p jsonb, w uuid, d date, req uuid, confirmar boolean","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('public.fn_equipa_operar_v2(text,jsonb,boolean,text)','089d09f54c6ccdeea061e00c2b66df23999c8f22a4a21e377d8ac3f2b61f61e3','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL::text","argumentos_identidade":"p_acao text, p_dados jsonb, p_confirmar boolean, p_versao text","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"authenticated","grantor":"postgres","grantable":false,"privilege":"EXECUTE"},{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('public.fn_folha_contexto_v2(date,uuid)','075ff7cd2c48b93e64f2b00ac750d9fc74d3950e1f22b5fa2b583f958dc8ae2b','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p_data date, p_obra_id uuid DEFAULT NULL::uuid","argumentos_identidade":"p_data date, p_obra_id uuid","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"authenticated","grantor":"postgres","grantable":false,"privilege":"EXECUTE"},{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('public.fn_folha_operar_v2(text,jsonb,boolean,text)','1f04f313dfe5b29944d4448cbdf24277bbeca4b1e3ddab34de3ebf1b055c273b','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL::text","argumentos_identidade":"p_acao text, p_dados jsonb, p_confirmar boolean, p_versao text","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"authenticated","grantor":"postgres","grantable":false,"privilege":"EXECUTE"},{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('public.fn_folha_pessoas_v2(date,uuid)','41b62dfce8084230a2fbaea09321c8547edb6b3a1426cb5305cc86cc23079300','{"owner":"postgres","security_definer":true,"proconfig":["search_path=pg_catalog"],"volatility":"v","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"plpgsql","argumentos":"p_data date, p_obra_id uuid","argumentos_identidade":"p_data date, p_obra_id uuid","retorno":"jsonb","tipo_retorno":"jsonb","acl_efetiva":[{"grantee":"authenticated","grantor":"postgres","grantable":false,"privilege":"EXECUTE"},{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb),
('public.fn_listar_colegas_agenda()','d86c1f1219cb919d0827d916981ab5f1b8caaa427903a67e6f469d1b0d00cbf8','{"owner":"postgres","security_definer":true,"proconfig":["search_path=public"],"volatility":"s","parallel":"u","strict":false,"leakproof":false,"kind":"f","linguagem":"sql","argumentos":"","argumentos_identidade":"","retorno":"TABLE(id uuid, nome text, funcao text)","tipo_retorno":"record","acl_efetiva":[{"grantee":"authenticated","grantor":"postgres","grantable":false,"privilege":"EXECUTE"},{"grantee":"postgres","grantor":"postgres","grantable":false,"privilege":"EXECUTE"}]}'::jsonb)
) x(sig,definition_sha256,metadata) LOOP
 IF to_regprocedure(r.sig) IS NULL OR (SELECT encode(sha256(convert_to(replace(pg_get_functiondef(p.oid),E'\r\n',E'\n'),'UTF8')),'hex') FROM pg_proc p WHERE p.oid=to_regprocedure(r.sig)) IS DISTINCT FROM r.definition_sha256 OR (SELECT jsonb_build_object('owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'proconfig',p.proconfig,'volatility',p.provolatile,'parallel',p.proparallel,'strict',p.proisstrict,'leakproof',p.proleakproof,'kind',p.prokind,'linguagem',l.lanname,'argumentos',pg_get_function_arguments(p.oid),'argumentos_identidade',pg_get_function_identity_arguments(p.oid),'retorno',pg_get_function_result(p.oid),'tipo_retorno',p.prorettype::regtype::text,'acl_efetiva',(SELECT coalesce(jsonb_agg(jsonb_build_object('grantee',CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,'grantor',pg_get_userbyid(gate_acl.grantor),'privilege',gate_acl.privilege_type,'grantable',gate_acl.is_grantable) ORDER BY CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,pg_get_userbyid(gate_acl.grantor),gate_acl.privilege_type,gate_acl.is_grantable),'[]'::jsonb) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) gate_acl)) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(r.sig)) IS DISTINCT FROM r.metadata THEN RAISE EXCEPTION 'BASELINE_DIVERGENCE: %',r.sig; END IF;
 END LOOP;
 FOR r IN SELECT * FROM primeline_encarregado_final_backup.dados LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO actual;
 IF actual IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'BACKUP_OPERATIONAL_DIVERGENCE: %',r.tabela; END IF;
 END LOOP;
 FOR r IN SELECT * FROM primeline_encarregado_final_backup.privado LOOP
 EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM folha_privado.%I x',r.tabela) INTO actual;
 IF actual IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'BACKUP_PRIVATE_DIVERGENCE: %',r.tabela; END IF;
 END LOOP;
 FOR r IN SELECT * FROM primeline_encarregado_final_backup.funcoes LOOP
 IF (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.definicao OR (SELECT jsonb_build_object('owner',pg_get_userbyid(p.proowner),'security_definer',p.prosecdef,'proconfig',p.proconfig,'volatility',p.provolatile,'parallel',p.proparallel,'strict',p.proisstrict,'leakproof',p.proleakproof,'kind',p.prokind,'linguagem',l.lanname,'argumentos',pg_get_function_arguments(p.oid),'argumentos_identidade',pg_get_function_identity_arguments(p.oid),'retorno',pg_get_function_result(p.oid),'tipo_retorno',p.prorettype::regtype::text,'acl_efetiva',(SELECT coalesce(jsonb_agg(jsonb_build_object('grantee',CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,'grantor',pg_get_userbyid(gate_acl.grantor),'privilege',gate_acl.privilege_type,'grantable',gate_acl.is_grantable) ORDER BY CASE WHEN gate_acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(gate_acl.grantee) END,pg_get_userbyid(gate_acl.grantor),gate_acl.privilege_type,gate_acl.is_grantable),'[]'::jsonb) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) gate_acl)) FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(r.assinatura)) IS DISTINCT FROM r.metadata THEN RAISE EXCEPTION 'BACKUP_FUNCTION_DIVERGENCE: %',r.assinatura; END IF;
 END LOOP;
END $$;
CREATE TABLE public.folha_externos_permanencias(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid NOT NULL REFERENCES public.empresas(id),
 externo_id uuid NOT NULL REFERENCES public.folha_externos(id) ON DELETE RESTRICT,
 obra_id uuid NOT NULL REFERENCES public.obras(id) ON DELETE RESTRICT,funcao text NOT NULL CHECK(funcao IN('pedreiro','servente')),
 inicio date NOT NULL,fim date CHECK(fim>=inicio),criado_em timestamptz NOT NULL DEFAULT now(),criado_por uuid NOT NULL REFERENCES public.utilizadores(id),request_id uuid NOT NULL,encerrado_por uuid REFERENCES public.utilizadores(id));
CREATE INDEX folha_externos_permanencias_dia ON public.folha_externos_permanencias(obra_id,inicio,fim);
ALTER TABLE public.folha_externos_permanencias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.folha_externos_permanencias FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE folha_privado.externos_revisoes(externo_id uuid PRIMARY KEY REFERENCES public.folha_externos(id),revision integer NOT NULL CHECK(revision>0));
ALTER TABLE folha_privado.externos_revisoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON folha_privado.externos_revisoes FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE folha_privado.periodos_revisoes(colaborador_id uuid NOT NULL REFERENCES public.colaboradores(id),obra_id uuid REFERENCES public.obras(id),data date NOT NULL,revision integer NOT NULL CHECK(revision>0),id uuid PRIMARY KEY DEFAULT gen_random_uuid(),UNIQUE NULLS NOT DISTINCT(colaborador_id,obra_id,data));
ALTER TABLE folha_privado.periodos_revisoes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON folha_privado.periodos_revisoes FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION folha_privado.integridade_externo() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(61001,1);
 IF NOT EXISTS(SELECT 1 FROM public.folha_externos e JOIN public.obras o ON o.id=NEW.obra_id WHERE e.id=NEW.externo_id AND e.empresa_id=NEW.empresa_id AND o.empresa_id=NEW.empresa_id) THEN RAISE EXCEPTION 'TENANT_INTEGRITY_CONFLICT' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.folha_externos_permanencias m WHERE m.externo_id=NEW.externo_id AND m.id<>NEW.id AND daterange(m.inicio,m.fim,'[)')&&daterange(NEW.inicio,NEW.fim,'[)')) THEN RAISE EXCEPTION 'EXTERNAL_TEAM_CONFLICT'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER folha_externo_integridade BEFORE INSERT OR UPDATE ON public.folha_externos_permanencias FOR EACH ROW EXECUTE FUNCTION folha_privado.integridade_externo();
CREATE OR REPLACE FUNCTION folha_privado.facts(xs jsonb,d date) RETURNS jsonb
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
   opened:=e IS NULL; last_end:=coalesce(e,1440); total:=total+coalesce(e-s,0);
 END LOOP;
 RETURN jsonb_build_object('minutes',total,'open',opened);
END $$;

CREATE OR REPLACE FUNCTION folha_privado.local(p uuid,w uuid,escrita boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; linked uuid; n integer;
BEGIN
 u:=folha_privado.ator();
 IF w IS NOT NULL THEN
 IF u.funcao IN('encarregado','diretor_obra','adjunto','preparador') AND p IS NOT NULL
 AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id)
 AND (SELECT count(*) FROM public.colaboradores c WHERE c.utilizador_id=u.id AND c.empresa_id=u.empresa_id)=1
 AND EXISTS(SELECT 1 FROM public.obras o JOIN public.obra_responsaveis r ON r.obra_id=o.id WHERE o.id=w AND o.empresa_id=u.empresa_id AND r.utilizador_id=u.id AND r.papel=u.funcao)
 THEN
  IF escrita THEN
   PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.utilizador_id=u.id AND c.empresa_id=u.empresa_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: ligação própria alterada' USING ERRCODE='42501'; END IF;
   PERFORM 1 FROM public.obras o JOIN public.obra_responsaveis r ON r.obra_id=o.id WHERE o.id=w AND o.empresa_id=u.empresa_id AND r.utilizador_id=u.id AND r.papel=u.funcao FOR SHARE OF o,r;
   IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: responsabilidade alterada' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN;
 END IF;
 PERFORM folha_privado.obra(w,escrita); RETURN;
 END IF;
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
END $$;

CREATE OR REPLACE FUNCTION folha_privado.save(p jsonb,w uuid,d date,req uuid,confirmar boolean) RETURNS jsonb
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

CREATE OR REPLACE FUNCTION folha_privado.normal(p uuid,w uuid,d date) RETURNS jsonb
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

CREATE OR REPLACE FUNCTION public.fn_equipa_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid; d date; req uuid; item jsonb; p uuid; current_team public.quadro_equipa_permanencias;
 rev integer; before jsonb:='[]'; after jsonb:='[]'; token text; payload jsonb; op folha_privado.operacoes; result jsonb; keys jsonb:='[]'; new_id uuid;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
 PERFORM pg_advisory_xact_lock(61001,1);
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 SELECT * INTO u FROM public.utilizadores WHERE id=(folha_privado.ator()).id AND ativo FOR SHARE; w:=(p_dados->>'work_id')::uuid; d:=(p_dados->>'date')::date; req:=(p_dados->>'request_id')::uuid;
 PERFORM folha_privado.obra(w,true);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF req IS NULL OR d IS NULL OR w IS NULL OR p_confirmar IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2
 OR p_acao IS NULL OR p_acao NOT IN('team_add','team_remove','team_transfer') OR jsonb_typeof(p_dados->'people') IS DISTINCT FROM 'array'
 OR jsonb_array_length(p_dados->'people') NOT BETWEEN 1 AND 200
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_dados->'people') x GROUP BY x->>'person_id' HAVING count(*)>1)
 THEN RAISE EXCEPTION 'VALIDATION_ERROR: equipa'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id AND situacao='em_curso') THEN RAISE EXCEPTION 'WORK_UNAVAILABLE'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload IS DISTINCT FROM payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') LOOP
   IF NOT folha_privado.elegivel_equipa((item->>'person_id')::uuid,d) THEN RAISE EXCEPTION 'PERMISSION_DENIED: elegibilidade' USING ERRCODE='42501'; END IF;
  END LOOP;
  IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token,'summary','Operação já registada.'); END IF;
  IF p_versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
  RETURN op.resultado;
 END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_dados->'people') ORDER BY value->>'person_id' LOOP
  p:=(item->>'person_id')::uuid;
  PERFORM 1 FROM public.colaboradores WHERE id=p FOR UPDATE;
  IF NOT folha_privado.elegivel_equipa(p,d) THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas Pedreiro/Servente interno ativo' USING ERRCODE='42501'; END IF;
  SELECT coalesce((SELECT revision FROM folha_privado.equipa_revisoes WHERE colaborador_id=p),0) INTO rev;
  IF (item->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
  SELECT * INTO current_team FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio<=d AND (fim IS NULL OR fim>d) FOR UPDATE;
  IF p_acao='team_add' AND (current_team.id IS NOT NULL OR EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio>d)) THEN RAISE EXCEPTION 'TEAM_CONFLICT'; END IF;
  IF p_acao IN('team_remove','team_transfer') AND (current_team.id IS NULL OR current_team.obra_id IS DISTINCT FROM (CASE WHEN p_acao='team_remove' THEN w ELSE (item->>'source_work_id')::uuid END)) THEN RAISE EXCEPTION 'STALE_TEAM'; END IF;
  IF p_acao='team_transfer' THEN
   IF EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=p AND inicio>d) THEN RAISE EXCEPTION 'TEAM_FUTURE_CONFLICT'; END IF;
   PERFORM folha_privado.obra(current_team.obra_id,true);
   IF current_team.obra_id=w THEN RAISE EXCEPTION 'TEAM_SAME_WORK'; END IF;
  END IF;
  IF p_acao<>'team_remove' AND EXISTS(SELECT 1 FROM public.quadro_pessoal_alocacao q WHERE q.colaborador_id=p AND q.data>=d
   AND (q.tipo_alocacao<>'obra' OR q.obra_id IS DISTINCT FROM w AND NOT (p_acao='team_transfer' AND q.obra_id=current_team.obra_id))) THEN RAISE EXCEPTION 'SCHEDULED_ALLOCATION_CONFLICT: rever alocações explícitas'; END IF;
  IF EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=p AND data=d) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT'; END IF;
  before:=before||jsonb_build_array(jsonb_build_object('person_id',p,'revision',rev,'membership',to_jsonb(current_team)));
  after:=after||jsonb_build_array(jsonb_build_object('person_id',p,'revision',rev+1,'work_id',CASE WHEN p_acao='team_remove' THEN NULL ELSE w END,'date',d));
 END LOOP;
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',before,'after',after)::text,'UTF8')),'hex');
 IF NOT p_confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'preview',after,
 'summary',format('%s: %s pessoas a partir de %s. O histórico é preservado; a permanência continua até retirada/transferência. Confirmar?',CASE p_acao WHEN 'team_add' THEN 'Adicionar à equipa' WHEN 'team_remove' THEN 'Retirar da equipa' ELSE 'Transferir equipa' END,jsonb_array_length(after),d)); END IF;
 IF p_versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(before) LOOP
  p:=(item->>'person_id')::uuid;
  IF p_acao IN('team_remove','team_transfer') THEN
   UPDATE public.quadro_equipa_permanencias SET fim=d,encerrado_por=u.id WHERE id=(item->'membership'->>'id')::uuid;
  END IF;
  IF p_acao<>'team_remove' THEN
   INSERT INTO public.quadro_equipa_permanencias(empresa_id,colaborador_id,obra_id,inicio,criado_por,request_id)
   VALUES(u.empresa_id,p,w,d,u.id,req) RETURNING id INTO new_id;
  END IF;
  INSERT INTO folha_privado.equipa_revisoes VALUES(p,(item->>'revision')::integer+1)
  ON CONFLICT(colaborador_id) DO UPDATE SET revision=excluded.revision;
  INSERT INTO public.quadro_pessoal_movimentos(empresa_id,colaborador_id,data,periodo,acao,obra_origem_id,obra_destino_id,alterado_por,perfil_autor,antes,depois,origem_operacao,request_id)
  VALUES(u.empresa_id,p,d,'dia_inteiro',CASE WHEN p_acao='team_remove' THEN 'retirada' WHEN p_acao='team_transfer' THEN 'alterada' ELSE 'adicionada' END,
  (item->'membership'->>'obra_id')::uuid,CASE WHEN p_acao='team_remove' THEN NULL ELSE w END,u.id,u.funcao,item,
  jsonb_build_object('request_id',req,'membership_id',new_id,'effective_date',d,'action',p_acao),'folha_v2',req);
  IF p_acao<>'team_remove' THEN
   INSERT INTO public.quadro_escrita_interna VALUES(txid_current(),p,d,u.id,'folha_v2',req);
   PERFORM public.fn_quadro_notificar_controlado_v1(p,d,(item->'membership'->>'obra_id')::uuid,w,new_id);
   DELETE FROM public.quadro_escrita_interna WHERE transacao=txid_current() AND colaborador_id=p AND data=d;
  END IF;
  INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
  VALUES(u.empresa_id,w,'obra',p,'primeline',d,CASE p_acao WHEN 'team_remove' THEN 'remove_from_day' WHEN 'team_transfer' THEN 'transfer' ELSE 'allocate' END,item,
  jsonb_build_object('action',p_acao,'effective_date',d,'work_id',CASE WHEN p_acao='team_remove' THEN NULL ELSE w END),(item->>'revision')::integer+1,u.id,req,p_dados->>'reason');
  keys:=keys||jsonb_build_array(jsonb_build_object('kind','primeline','person_id',p,'work_id',w,'date',d));
 END LOOP;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys,'result',after);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_pessoas_v2(p_data date,p_obra_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; people jsonb;
BEGIN
 u:=folha_privado.ator(); PERFORM folha_privado.obra(p_obra_id);
 IF NOT public.fn_quadro_pode_gerir_v1(NULL) AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED: alocação' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('person_id',c.id,'name',c.nome,
 'role',c.funcao,'delegation',c.delegacao,'team_revision',coalesce(er.revision,0),
 'current_work',CASE WHEN q.id IS NULL THEN NULL ELSE jsonb_build_object('id',q.obra_id,'type',q.tipo_alocacao,'label',CASE WHEN q.obra_id IS NULL THEN q.tipo_alocacao ELSE 'Obra '||o.numero END) END,
 'help_row',CASE WHEN q.obra_id IS NOT NULL AND q.obra_id<>p_obra_id AND NOT a.blocked AND EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias m WHERE m.colaborador_id=c.id AND m.obra_id=q.obra_id AND m.inicio<=p_data AND (m.fim IS NULL OR m.fim>p_data)) AND (folha_privado.admin() OR public.fn_quadro_minha_obra_v1(q.obra_id)) THEN folha_privado.linha(c.id,p_obra_id,p_data,'primeline') END,
 'allocation_revision',coalesce(r.revisao,0),'can_allocate',(q.id IS NULL OR q.obra_id=p_obra_id AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND inicio<=p_data AND (fim IS NULL OR fim>p_data))) AND NOT a.blocked,
 'can_transfer',EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND inicio<=p_data AND (fim IS NULL OR fim>p_data)) AND (folha_privado.admin() OR public.fn_quadro_minha_obra_v1(q.obra_id)) AND q.id IS NOT NULL AND q.tipo_alocacao='obra' AND o.empresa_id=u.empresa_id AND NOT a.blocked)),'[]') INTO people
 FROM public.colaboradores c LEFT JOIN folha_privado.equipa_revisoes er ON er.colaborador_id=c.id
 LEFT JOIN LATERAL(SELECT * FROM public.fn_quadro_resolver_data(p_data) WHERE colaborador_id=c.id ORDER BY id LIMIT 1) q ON true
 LEFT JOIN public.obras o ON o.id=q.obra_id LEFT JOIN public.quadro_dias_revisoes r ON r.colaborador_id=c.id AND r.data=p_data
 CROSS JOIN LATERAL(SELECT EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=c.id AND data=p_data)
 OR EXISTS(SELECT 1 FROM public.ponto_pessoal_obra WHERE colaborador_id=c.id AND data=p_data)
 OR (SELECT count(*) FROM public.quadro_pessoal_alocacao WHERE colaborador_id=c.id AND data=p_data)>1 blocked) a
 WHERE folha_privado.elegivel_equipa(c.id,p_data) AND NOT EXISTS(SELECT 1 FROM public.quadro_equipa_permanencias WHERE colaborador_id=c.id AND obra_id=p_obra_id AND inicio<=p_data AND (fim IS NULL OR fim>p_data));
 RETURN jsonb_build_object('version',2,'people',people);
END $$;

CREATE OR REPLACE FUNCTION public.fn_folha_contexto_v2(p_data date,p_obra_id uuid DEFAULT NULL) RETURNS jsonb
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
 (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.obra_responsaveis r WHERE r.obra_id=o.id AND r.utilizador_id=u.id AND r.papel=u.funcao AND u.funcao IN('encarregado','diretor_obra','adjunto','preparador')));
 IF p_obra_id IS NOT NULL THEN
  PERFORM folha_privado.local(self_id,p_obra_id);
  FOR x IN SELECT c.id colaborador_id FROM public.colaboradores c WHERE c.id=self_id AND u.funcao IN('encarregado','diretor_obra','adjunto','preparador')
 UNION SELECT DISTINCT q.colaborador_id FROM public.fn_quadro_resolver_data(p_data) q JOIN public.colaboradores c ON c.id=q.colaborador_id AND c.empresa_id=u.empresa_id WHERE q.obra_id=p_obra_id AND q.data=p_data
   UNION SELECT f.colaborador_id FROM public.folha_registos f JOIN public.colaboradores c ON c.id=f.colaborador_id AND c.empresa_id=u.empresa_id WHERE f.obra_id=p_obra_id AND f.data=p_data AND f.empresa_id=u.empresa_id
   UNION SELECT h.colaborador_id FROM public.ponto_pessoal_obra h JOIN public.colaboradores c ON c.id=h.colaborador_id AND c.empresa_id=u.empresa_id WHERE h.obra_id=p_obra_id AND h.data=p_data AND h.empresa_id=u.empresa_id LOOP
   IF (folha_privado.admin() OR u.funcao='encarregado' OR x.colaborador_id=self_id) AND EXISTS(SELECT 1 FROM public.colaboradores c WHERE c.id=x.colaborador_id AND (lower(btrim(c.funcao)) IN('pedreiro','servente') OR c.utilizador_id=u.id)) THEN
 rows:=rows||jsonb_build_array(folha_privado.linha(x.colaborador_id,p_obra_id,p_data,'primeline')); END IF;
  END LOOP;
  FOR x IN SELECT e.id FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id AND (folha_privado.admin() OR u.funcao='encarregado')
   AND (EXISTS(SELECT 1 FROM public.folha_externos_permanencias m WHERE m.externo_id=e.id AND m.obra_id=p_obra_id AND m.inicio<=p_data AND (m.fim IS NULL OR m.fim>p_data)) OR EXISTS(SELECT 1 FROM public.folha_externos_dias ed WHERE ed.externo_id=e.id AND ed.obra_id=p_obra_id AND ed.data=p_data)
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
 summary:=jsonb_build_object('people',jsonb_array_length(rows||ext),'registered',registered,'open',opened,'pending',pending,'complete',jsonb_array_length(rows||ext)>0 AND pending=0);
 RETURN jsonb_build_object('version',2,'date',p_data,'work_id',p_obra_id,'works',works,'rows',rows,'external_rows',ext,
  'tipo_local',CASE WHEN p_obra_id IS NULL THEN 'escritorio' ELSE 'obra' END,'office_available',office,'self_person_id',self_id,'correction_days',1,'admin',folha_privado.admin(),'summary',summary,'schedule',sched,'special_day',special,'providers',providers,
  'external_people',coalesce((SELECT jsonb_agg(jsonb_build_object('id',e.id,'name',e.nome,'provider_id',e.fornecedor_id,'revision',coalesce((SELECT revision FROM folha_privado.externos_revisoes WHERE externo_id=e.id),0))) FROM public.folha_externos e WHERE e.empresa_id=u.empresa_id AND e.ativo AND (folha_privado.admin() OR u.funcao='encarregado') AND EXISTS(SELECT 1 FROM public.fornecedores f WHERE f.id=e.fornecedor_id AND f.empresa_id=u.empresa_id AND (folha_privado.admin() OR EXISTS(SELECT 1 FROM public.subempreitadas s WHERE s.fornecedor_id=f.id AND s.obra_id=p_obra_id)))
   AND NOT EXISTS(SELECT 1 FROM public.folha_externos_permanencias ed WHERE ed.externo_id=e.id AND ed.inicio<=p_data AND (ed.fim IS NULL OR ed.fim>p_data))),'[]'),
  'final_contract',1,'actor_role',u.funcao,'team_contract',1,'delegation',coalesce((SELECT delegacao FROM public.obras WHERE id=p_obra_id),u.delegacao),'management',folha_privado.admin() OR p_obra_id IS NOT NULL AND u.funcao IN('diretor_obra','adjunto'),
  'calendar_verified',coalesce((SELECT calendar_complete AND extract(year FROM p_data)::integer=ANY(calendar_validated_years) FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id),false),
  'overtime_generation',CASE WHEN EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=u.empresa_id AND overtime_enabled AND calendar_complete AND extract(year FROM p_data)::integer=ANY(calendar_validated_years)) THEN 'enabled' ELSE 'disabled_pending_compatibility' END,
  'permissions',jsonb_build_object('write',CASE WHEN p_obra_id IS NULL THEN office ELSE folha_privado.admin() OR u.funcao='encarregado' OR (u.funcao IN('diretor_obra','adjunto','preparador') AND self_id IS NOT NULL) END,'allocation_write',p_obra_id IS NOT NULL AND (public.fn_quadro_pode_gerir_v1(NULL) OR u.funcao='encarregado'),'external_write',p_obra_id IS NOT NULL AND (folha_privado.admin() OR u.funcao='encarregado')));
END $$;

CREATE OR REPLACE FUNCTION folha_privado.operar_final_base(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb
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
 ELSIF p_acao='save' THEN PERFORM folha_privado.local((p_dados->'key'->>'person_id')::uuid,w,true);
 ELSIF p_acao='bulk' AND u.funcao IN('diretor_obra','adjunto','preparador') THEN
  IF jsonb_typeof(p_dados->'items') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'items')<>1 OR p_dados->'items'->0->'key'->>'kind' IS DISTINCT FROM 'primeline' THEN RAISE EXCEPTION 'PERMISSION_DENIED: apenas a própria Folha' USING ERRCODE='42501'; END IF;
  PERFORM folha_privado.local((p_dados->'items'->0->'key'->>'person_id')::uuid,w,true);
 ELSE PERFORM folha_privado.obra(w,true); END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF p_confirmar IS NULL OR req IS NULL OR d IS NULL OR (p_dados->>'version')::integer IS DISTINCT FROM 2 OR p_acao IS NULL OR p_acao NOT IN('save','bulk','allocate','transfer','remove_from_day','external_register') THEN RAISE EXCEPTION 'VALIDATION_ERROR: contrato'; END IF;
 IF p_acao IN('allocate','transfer','remove_from_day') THEN RAISE EXCEPTION 'TEAM_CONTRACT_REQUIRED: use fn_equipa_operar_v2'; END IF;
 payload:=jsonb_build_object('action',p_acao,'data',p_dados);
 PERFORM pg_advisory_xact_lock(hashtextextended(u.empresa_id::text||':'||u.id::text||':'||req::text,0));
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT (p_acao='bulk' AND u.funcao IN('diretor_obra','adjunto','preparador')) THEN PERFORM folha_privado.autorizar_replay(p_acao,p_dados,w,d); END IF;
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
    IF item->'key'->>'kind' NOT IN('primeline','external') OR (item->'key'->>'kind'='primeline' AND EXISTS(SELECT 1 FROM public.ausencias WHERE colaborador_id=(item->'key'->>'person_id')::uuid AND data=d)) THEN RAISE EXCEPTION 'ABSENCE_CONFLICT'; END IF;
    person:=(item->'key'->>'person_id')::uuid;
    IF p_dados->>'operation'='normal' THEN
     IF EXISTS(SELECT 1 FROM public.folha_registos WHERE (CASE WHEN item->'key'->>'kind'='primeline' THEN colaborador_id=person ELSE externo_id=person END) AND obra_id=w AND data=d)
      OR item->'intervals' IS DISTINCT FROM (CASE WHEN item->'key'->>'kind'='external' THEN folha_privado.normal_externo(w,d) ELSE folha_privado.normal(person,w,d) END) THEN RAISE EXCEPTION 'NORMAL_DAY_CONFLICT'; END IF;
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
  IF p_dados->>'role' IS NULL OR p_dados->>'role' NOT IN('pedreiro','servente') THEN RAISE EXCEPTION 'VALIDATION_ERROR: função externa'; END IF;
  result:=folha_privado.facts(p_dados->'intervals',d);
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
  preview:=jsonb_build_object('provider',provider,'work',w,'person_id',person,'role',p_dados->>'role','facts',result);
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
  INSERT INTO public.folha_externos_dias(externo_id,empresa_id,obra_id,data,criado_por,criado_em,request_id,funcao) VALUES(person,u.empresa_id,w,d,u.id,now(),req,p_dados->>'role');
  result:=folha_privado.save(jsonb_build_object('key',jsonb_build_object('person_id',person,'kind','external','work_id',w,'date',d),'intervals',p_dados->'intervals','expected_revision',0,'reason',p_dados->>'reason','note',p_dados->>'note'),w,d,req,true);
  INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason)
   VALUES(u.empresa_id,w,CASE WHEN w IS NULL THEN 'escritorio' ELSE 'obra' END,person,'external',d,p_acao,NULL,jsonb_build_object('name',p_dados->>'name','provider_id',provider),0,u.id,req,NULL);
  keys:=jsonb_build_array(jsonb_build_object('kind','external','person_id',person,'work_id',w,'date',d));
 END IF;
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',keys,'result',result);
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now());
 RETURN result;
END $$;
CREATE FUNCTION folha_privado.normal_externo(w uuid,d date) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE xs jsonb; BEGIN
 PERFORM folha_privado.obra(w);
 IF extract(isodow FROM d)>5 OR EXISTS(SELECT 1 FROM public.folha_config_empresa WHERE empresa_id=(folha_privado.ator()).empresa_id AND d=ANY(holiday_dates)) THEN RAISE EXCEPTION 'SPECIAL_DAY_NO_NORMAL_FILL'; END IF;
 SELECT jsonb_agg(jsonb_build_object('start',x->>'start','end',x->>'end') ORDER BY x->>'start') INTO xs FROM public.folha_horarios h,jsonb_array_elements(h.intervals) x WHERE h.obra_id=w;
 IF xs IS NULL THEN RAISE EXCEPTION 'SCHEDULE_REQUIRED'; END IF;
 IF jsonb_array_length(xs)>2 THEN RAISE EXCEPTION 'TWO_PERIODS_REQUIRED'; END IF;
 PERFORM folha_privado.facts(xs,d); RETURN xs;
END $$;
-- Atomic multiwork facts. The additional plan argument is private, never an RPC.
DO $$ DECLARE s text; BEGIN
 s:=pg_get_functiondef('folha_privado.save(jsonb,uuid,date,uuid,boolean)'::regprocedure);
 s:=replace(s,'folha_privado.save(p jsonb, w uuid, d date, req uuid, confirmar boolean)','folha_privado.save_periodo(p jsonb, w uuid, d date, req uuid, confirmar boolean, plano jsonb)');
 s:=replace(s,'other.data=d AND other.obra_id IS DISTINCT FROM w','other.data=d AND other.obra_id IS DISTINCT FROM w AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(plano) target WHERE target->>''work_id'' IS NOT DISTINCT FROM other.obra_id::text)'); s:=replace(s,'expected:=(row->>''expected_minutes'')::integer;', 'expected:=(row->>''expected_minutes'')::integer; IF w IS NOT NULL THEN SELECT sum((extract(epoch FROM ((h.x->>''end'')::time-(h.x->>''start'')::time))/60)::integer) INTO expected FROM public.folha_horarios schedule CROSS JOIN LATERAL jsonb_array_elements(schedule.intervals) h(x) WHERE schedule.obra_id=w AND EXISTS(SELECT 1 FROM jsonb_array_elements(p->''intervals'') period WHERE period->>''period''=h.x->>''period''); END IF;');
 s:=replace(s,'SET intervals=p->''intervals'',minutes=', 'SET expected_minutes=expected,intervals=p->''intervals'',minutes=');
 EXECUTE s;
END $$;
CREATE FUNCTION folha_privado.operar_periodos(p jsonb,confirmar boolean,versao text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; d date:=(p->>'date')::date; req uuid:=(p->>'request_id')::uuid; person uuid:=(p->'key'->>'person_id')::uuid;
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
END $$;
CREATE FUNCTION folha_privado.operar_externo(action text,p jsonb,confirmar boolean,versao text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE u public.utilizadores; w uuid:=(p->>'work_id')::uuid; d date:=(p->>'date')::date; req uuid:=(p->>'request_id')::uuid; person uuid:=coalesce((p->>'external_id')::uuid,req); provider uuid:=(p->>'provider_id')::uuid;
 old public.folha_externos_permanencias; rev integer; after jsonb; payload jsonb; token text; result jsonb; op folha_privado.operacoes;
BEGIN
 LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE; PERFORM pg_advisory_xact_lock(61001,1);
 u:=folha_privado.ator(); PERFORM folha_privado.obra(w,true);
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'RETRY_READ_COMMITTED' USING ERRCODE='40001'; END IF;
 IF NOT folha_privado.admin() AND u.funcao<>'encarregado' THEN RAISE EXCEPTION 'PERMISSION_DENIED' USING ERRCODE='42501'; END IF;
 IF confirmar IS NULL OR req IS NULL OR (p->>'version')::integer IS DISTINCT FROM 2 OR d IS NULL OR d>(now() AT TIME ZONE 'Europe/Lisbon')::date OR (d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND NOT folha_privado.adm_operacional()) THEN RAISE EXCEPTION 'CORRECTION_WINDOW_EXCEEDED'; END IF;
 IF d<(now() AT TIME ZONE 'Europe/Lisbon')::date-1 AND nullif(btrim(p->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'CORRECTION_REASON_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.obras WHERE id=w AND empresa_id=u.empresa_id AND situacao='em_curso') THEN RAISE EXCEPTION 'WORK_CLOSED'; END IF;
 IF action='external_team_add' THEN
  IF p->>'role' IS NULL OR p->>'role' NOT IN('pedreiro','servente') OR length(btrim(coalesce(p->>'name',''))) NOT BETWEEN 1 AND 160 THEN RAISE EXCEPTION 'VALIDATION_ERROR: externo'; END IF;
  PERFORM 1 FROM public.fornecedores WHERE id=provider AND empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND OR (NOT folha_privado.admin() AND NOT EXISTS(SELECT 1 FROM public.subempreitadas WHERE obra_id=w AND fornecedor_id=provider)) THEN RAISE EXCEPTION 'PERMISSION_DENIED: fornecedor' USING ERRCODE='42501'; END IF;
  IF p->>'external_id' IS NULL AND EXISTS(SELECT 1 FROM public.folha_externos WHERE empresa_id=u.empresa_id AND fornecedor_id=provider AND lower(btrim(nome))=lower(btrim(p->>'name'))) THEN RAISE EXCEPTION 'EXTERNAL_IDENTITY_EXISTS'; END IF;
 END IF;
 IF p->>'external_id' IS NOT NULL THEN
  PERFORM 1 FROM public.folha_externos WHERE id=person AND empresa_id=u.empresa_id AND ativo AND (action='external_team_remove' OR fornecedor_id=provider AND nome=btrim(p->>'name')) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: identidade' USING ERRCODE='42501'; END IF;
 END IF;
 payload:=jsonb_build_object('action',action,'data',p);
 SELECT * INTO op FROM folha_privado.operacoes WHERE empresa_id=u.empresa_id AND ator_id=u.id AND request_id=req;
 IF FOUND THEN
  IF op.payload<>payload THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
  IF NOT confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',op.token); END IF;
  IF versao IS DISTINCT FROM op.token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF; RETURN op.resultado;
 END IF;
 SELECT coalesce((SELECT revision FROM folha_privado.externos_revisoes WHERE externo_id=person),0) INTO rev;
 IF (p->>'expected_revision')::integer IS DISTINCT FROM rev THEN RAISE EXCEPTION 'STALE_REVISION' USING ERRCODE='40001'; END IF;
 SELECT * INTO old FROM public.folha_externos_permanencias WHERE externo_id=person AND inicio<=d AND (fim IS NULL OR fim>d) FOR UPDATE;
 IF action='external_team_add' AND (old.id IS NOT NULL OR EXISTS(SELECT 1 FROM public.folha_externos_permanencias WHERE externo_id=person AND inicio>d)) THEN RAISE EXCEPTION 'EXTERNAL_TEAM_CONFLICT'; END IF;
 IF action='external_team_remove' AND (old.id IS NULL OR old.obra_id<>w) THEN RAISE EXCEPTION 'STALE_TEAM'; END IF;
 after:=jsonb_build_object('action',action,'person_id',person,'work_id',w,'date',d,'revision',rev+1);
 token:=encode(sha256(convert_to(jsonb_build_object('payload',payload,'before',to_jsonb(old),'after',after)::text,'UTF8')),'hex');
 IF NOT confirmar THEN RETURN jsonb_build_object('version',2,'committed',false,'versao',token,'summary','Confirmar permanência? Horas e histórico serão preservados; não cria ponto nem ausência.'); END IF;
 IF versao IS DISTINCT FROM token THEN RAISE EXCEPTION 'STALE_PREVIEW' USING ERRCODE='40001'; END IF;
 IF action='external_team_add' THEN
  IF p->>'external_id' IS NULL THEN INSERT INTO public.folha_externos(id,empresa_id,fornecedor_id,nome,criado_por,origem_request) VALUES(person,u.empresa_id,provider,btrim(p->>'name'),u.id,req); END IF;
  INSERT INTO public.folha_externos_permanencias(empresa_id,externo_id,obra_id,funcao,inicio,criado_por,request_id) VALUES(u.empresa_id,person,w,p->>'role',d,u.id,req);
 ELSE UPDATE public.folha_externos_permanencias SET fim=d,encerrado_por=u.id WHERE id=old.id; END IF;
 INSERT INTO folha_privado.externos_revisoes VALUES(person,rev+1) ON CONFLICT(externo_id) DO UPDATE SET revision=excluded.revision;
 INSERT INTO public.folha_historico(empresa_id,obra_id,tipo_local,person_id,kind,data,action,antes,depois,revision,ator_id,request_id,reason) VALUES(u.empresa_id,w,'obra',person,'external',d,action,to_jsonb(old),after,rev+1,u.id,req,p->>'reason');
 result:=jsonb_build_object('version',2,'committed',true,'request_id',req,'changed_keys',jsonb_build_array(jsonb_build_object('kind','external','person_id',person,'work_id',w,'date',d)));
 INSERT INTO folha_privado.operacoes VALUES(u.empresa_id,u.id,req,payload,token,result,now()); RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.fn_folha_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean DEFAULT false,p_versao text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF p_acao='periods_save' THEN RETURN folha_privado.operar_periodos(p_dados,p_confirmar,p_versao);
 ELSIF p_acao IN('external_team_add','external_team_remove') THEN RETURN folha_privado.operar_externo(p_acao,p_dados,p_confirmar,p_versao);
 ELSE RETURN folha_privado.operar_final_base(p_acao,p_dados,p_confirmar,p_versao); END IF;
END $$;
CREATE OR REPLACE FUNCTION public.fn_listar_colegas_agenda() RETURNS TABLE(id uuid,nome text,funcao text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 WITH people AS (
 SELECT u.id,u.nome,coalesce(nullif(btrim(c.funcao),''),CASE WHEN u.funcao<>'gestao_plataforma' THEN u.funcao ELSE 'Colaborador' END) papel,coalesce(u.auth_user_id,c.id,u.id) identidade,u.funcao acesso,c.id IS NOT NULL formal
 FROM public.utilizadores u JOIN public.utilizadores atual ON atual.id=public.fn_utilizador_atual_id() AND atual.ativo IS TRUE
 LEFT JOIN LATERAL(SELECT min(x.id::text)::uuid id,min(x.funcao) funcao FROM public.colaboradores x WHERE x.utilizador_id=u.id AND x.empresa_id=u.empresa_id HAVING count(*)=1) c ON true
 WHERE u.ativo IS TRUE AND u.empresa_id=atual.empresa_id AND u.id<>atual.id AND (u.funcao<>'gestao_plataforma' OR c.id IS NOT NULL)
 ), canonical AS (SELECT DISTINCT ON(identidade) id,nome,papel FROM people ORDER BY identidade,formal DESC,(acesso='gestao_plataforma'),id)
 SELECT id,nome,papel FROM canonical ORDER BY nome,id;
$$;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname IN('facts','local','linha','save','normal','integridade_externo','save_periodo','normal_externo','operar_periodos','operar_externo','operar_final_base') LOOP EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role',r.sig); END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.fn_folha_operar_v2(text,jsonb,boolean,text),public.fn_listar_colegas_agenda() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.fn_folha_operar_v2(text,jsonb,boolean,text),public.fn_listar_colegas_agenda() TO authenticated;
COMMIT;
