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
CREATE SCHEMA primeline_ad13_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad13_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad13_backup.rpc AS SELECT pg_get_functiondef(p.oid) definicao,p.proowner,p.proacl,p.proconfig,p.prosecdef FROM pg_proc p WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure;
CREATE TABLE primeline_ad13_backup.ad14 AS SELECT p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definicao,p.proacl acl FROM pg_proc p WHERE oid IN('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'::regprocedure,'folha_privado.diaria_ad14_final()'::regprocedure);
CREATE TABLE primeline_ad13_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['folha_horarios','folha_horarios_versoes','folha_config_empresa','folha_avaliacoes_diarias','folha_gestao_historico','folha_registos','folha_he','folha_vencimentos'] LOOP
 EXECUTE format('INSERT INTO primeline_ad13_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP;END $snapshot$;
CREATE TABLE primeline_ad13_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad13_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD13_BACKUP_OK' resultado;
COMMIT;
