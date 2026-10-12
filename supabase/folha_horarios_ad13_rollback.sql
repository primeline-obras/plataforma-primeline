-- Manual only; preserve AD-14/15. Refuse business activity since snapshot.
BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE public.folha_horarios,public.folha_horarios_versoes,public.folha_config_empresa,public.folha_avaliacoes_diarias,public.folha_gestao_historico,public.folha_registos,public.folha_he,public.folha_vencimentos,folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;
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
DO $restore$ DECLARE r record; BEGIN SELECT * INTO STRICT r FROM primeline_ad13_backup.rpc;EXECUTE r.definicao;END $restore$;
DROP TRIGGER folha_diaria_ad13_ativacao ON public.folha_config_empresa;
DROP TRIGGER folha_diaria_ad13_referencia ON public.folha_avaliacoes_diarias;
ALTER TABLE public.folha_horarios DROP CONSTRAINT folha_horario_ad13_coerencia;
ALTER TABLE public.folha_horarios_versoes DROP CONSTRAINT folha_versao_ad13_coerencia;
DROP FUNCTION folha_privado.horario_ad13_guardar(),folha_privado.horario_ad13_factos(jsonb,boolean),folha_privado.horario_ad13_valido(jsonb,boolean);
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
SELECT 'AD13_ROLLBACK_OK' resultado;
COMMIT;
