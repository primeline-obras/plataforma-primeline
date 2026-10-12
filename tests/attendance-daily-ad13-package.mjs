import fs from 'node:fs';import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
const tableSignature='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)';
const original=read('supabase/folha_he_tenant_ad15.sql');const start=original.indexOf('CREATE OR REPLACE FUNCTION public.fn_folha_diaria_gestao_v2');const end=original.indexOf('END $$;',start)+8;const oldRPC=original.slice(start,end);
const variables='valid boolean; x jsonb; n integer; s integer; e integer; last_end integer; total integer; expected numeric;';
const validation=String.raw`valid:=false;last_end:=-1;total:=0;n:=0;
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
 END validate_snapshot;`;
const validator=`CREATE FUNCTION folha_privado.horario_ad13_valido(p_snapshot jsonb,p_normal boolean) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $validator$
DECLARE ${variables}
BEGIN
 ${validation}
 RETURN valid;
END $validator$;`;
const facts=`CREATE FUNCTION folha_privado.horario_ad13_factos(p_snapshot jsonb,p_normal boolean) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $facts$
BEGIN
 IF folha_privado.horario_ad13_valido(p_snapshot,p_normal) IS NOT TRUE THEN RAISE EXCEPTION 'SCHEDULE_INCOHERENT: intervalos/carga/períodos inválidos' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('minutes',((p_snapshot->>'expected_minutes')::numeric)::integer,'open',false);
END $facts$;`;
const guard=`CREATE FUNCTION folha_privado.horario_ad13_guardar() RETURNS trigger
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
END $guard$;`;
let rpc=oldRPC;
const replacements=[
 ["PERFORM pg_advisory_xact_lock(61001,1);", "PERFORM pg_advisory_xact_lock(61001,1);\n -- Formal templates are serialized before preview/snapshot; actual fact clocks are unchanged.\n LOCK TABLE public.folha_horarios IN SHARE ROW EXCLUSIVE MODE;"],
 ["   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;", "   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;\n   PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',configured.intervals,'expected_minutes',configured.expected_minutes),true) FROM public.folha_horarios configured WHERE configured.obra_id=schedule_row.obra_id AND configured.empresa_id=u.empresa_id;"],
 ["facts:=folha_privado.facts(p_dados->'intervals',today);", "facts:=folha_privado.horario_ad13_factos(p_dados,true);"],
 ["facts:=folha_privado.facts(p_dados->'schedule'->'intervals',today);", "facts:=folha_privado.horario_ad13_factos(p_dados->'schedule',false);"],
 ["PERFORM folha_privado.facts(schedule_row.intervals,today);", "PERFORM folha_privado.horario_ad13_factos(jsonb_build_object('intervals',schedule_row.intervals,'expected_minutes',schedule_row.expected_minutes),true);"]
];
for(const [before,after] of replacements){if(rpc.split(before).length!==2)throw Error('RPC anchor drift: '+before);rpc=rpc.replace(before,after);}
let reversed=rpc;for(const [before,after] of replacements)reversed=reversed.replace(after,before);if(reversed!==oldRPC)throw Error('Unexpected AD15 delta');
const oldHash=crypto.createHash('sha256').update(oldRPC.split('$$')[1]).digest('hex');const newHash=crypto.createHash('sha256').update(rpc.split('$$')[1]).digest('hex');
const helpers=[['folha_privado.horario_ad13_valido(jsonb,boolean)',validator,'$validator$','boolean','i'],['folha_privado.horario_ad13_factos(jsonb,boolean)',facts,'$facts$','jsonb','i'],['folha_privado.horario_ad13_guardar()',guard,'$guard$','trigger','v']];
const owner="IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;";
const parent=`IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='${tableSignature}'::regprocedure AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='${oldHash}' AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred) THEN RAISE EXCEPTION 'AD13_AD14_AD15_REQUIRED_OR_DRIFT'; END IF;`;

const ad14Source=read('supabase/folha_avaliacao_ad14.sql');
const ad14Checks=[['folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)','$validator$',false],['folha_privado.diaria_ad14_final()','$trigger$',true]].map(([sig,tag,sd])=>"IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='"+sig+"'::regprocedure AND proowner='postgres'::regrole AND prosecdef="+sd+" AND provolatile='"+(sd?"v":"i")+"' AND prorettype='"+(sd?"trigger":"boolean")+"'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='"+(sd?"plpgsql":"sql")+"') AND proconfig=ARRAY['search_path=pg_catalog'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='"+crypto.createHash('sha256').update(ad14Source.split(tag)[1]).digest('hex')+"' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_AD14_HELPER_DRIFT'; END IF;").join('\n');
const ad14SchemaChecks="IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass)<>41 OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.diaria_ad14_valida(folha_avaliacoes_diarias.*, false) IS TRUE))') OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred AND tgtype=21 AND tgfoid='folha_privado.diaria_ad14_final()'::regprocedure AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='') THEN RAISE EXCEPTION 'AD13_AD14_SCHEMA_DRIFT'; END IF;";
const fullParent=parent+'\n'+ad14Checks+'\n'+ad14SchemaChecks;

const inventory=`SELECT 'current' kind,h.obra_id::text identity,jsonb_build_object('intervals',h.intervals,'expected_minutes',h.expected_minutes) snapshot,true normal FROM public.folha_horarios h
 UNION ALL SELECT 'version',v.id::text,v.snapshot,true FROM public.folha_horarios_versoes v
 UNION ALL SELECT 'evaluation',a.id::text,a.horario_snapshot,a.referencia_origem='automatico' FROM public.folha_avaliacoes_diarias a WHERE a.referencia_estado='capturada'`;
const inlineCheck=`DO $schedules$ DECLARE r record;p_snapshot jsonb;p_normal boolean;${variables} BEGIN
 FOR r IN ${inventory} LOOP
  p_snapshot:=r.snapshot;p_normal:=r.normal;
  ${validation}
  IF NOT valid THEN RAISE EXCEPTION 'AD13_EXISTING_SCHEDULE_INCOHERENT: % %',r.kind,r.identity; END IF;
 END LOOP;
END $schedules$;`;
const pre=`DO $gate$ BEGIN
 ${owner}
 ${fullParent}
 IF to_regprocedure('folha_privado.horario_ad13_valido(jsonb,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.horario_ad13_factos(jsonb,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.horario_ad13_guardar()') IS NOT NULL THEN RAISE EXCEPTION 'AD13_PRESENT_OR_PARTIAL'; END IF;
END $gate$;
${inlineCheck}`;
const tables=['folha_horarios','folha_horarios_versoes','folha_config_empresa','folha_avaliacoes_diarias','folha_gestao_historico','folha_registos','folha_he','folha_vencimentos'];
const locks=`LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE ${tables.map(t=>'public.'+t).join(',')},folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;`;
const equality=`DO $data$ DECLARE r record;rows_now jsonb; BEGIN
 ${owner}
 IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad13_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad13_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad13_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD13_BACKUP_NOT_PRIVATE'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD13_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad13_backup.operacoes) THEN RAISE EXCEPTION 'AD13_OPERATIONS_DRIFT'; END IF;
 FOR r IN SELECT * FROM primeline_ad13_backup.ad14 LOOP
  IF pg_get_functiondef(r.signature::regprocedure) IS DISTINCT FROM r.definicao OR (SELECT proacl FROM pg_proc WHERE oid=r.signature::regprocedure) IS DISTINCT FROM r.acl THEN RAISE EXCEPTION 'AD13_AD14_DRIFT: %',r.signature; END IF;
 END LOOP;
END $data$;`;
const installed=`DO $installed$ DECLARE r record; BEGIN
 ${owner}
 ${ad14Checks}
 ${ad14SchemaChecks}
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='${tableSignature}'::regprocedure AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='${newHash}' AND proowner='postgres'::regrole AND prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD13_RPC_DRIFT'; END IF;
 ${helpers.map(([sig,sql,tag,type,vol])=>`IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='${sig}'::regprocedure AND proowner='postgres'::regrole AND NOT prosecdef AND proconfig=ARRAY['search_path=pg_catalog'] AND provolatile='${vol}' AND prorettype='${type}'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='${crypto.createHash('sha256').update(sql.split(tag)[1]).digest('hex')}' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD13_HELPER_DRIFT: ${sig}'; END IF;`).join('\n ')}
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_horarios'::regclass AND conname='folha_horario_ad13_coerencia' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.horario_ad13_valido(jsonb_build_object(''intervals'', intervals, ''expected_minutes'', expected_minutes), true) IS TRUE))') OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_horarios_versoes'::regclass AND conname='folha_versao_ad13_coerencia' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.horario_ad13_valido(snapshot, true) IS TRUE))') THEN RAISE EXCEPTION 'AD13_CONSTRAINT_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_config_empresa'::regclass AND tgname='folha_diaria_ad13_ativacao' AND tgenabled='O' AND tgtype=23 AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='' AND tgfoid='folha_privado.horario_ad13_guardar()'::regprocedure) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.folha_avaliacoes_diarias'::regclass AND tgname='folha_diaria_ad13_referencia' AND tgenabled='O' AND tgtype=23 AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='' AND tgfoid='folha_privado.horario_ad13_guardar()'::regprocedure) THEN RAISE EXCEPTION 'AD13_TRIGGER_DRIFT'; END IF;
END $installed$;
${inlineCheck}`;
const write=(name,sql)=>fs.writeFileSync('supabase/folha_horarios_ad13'+name+'.sql',sql+'\n');
write('_precheck',`BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${pre}
SELECT 'AD13_PRECHECK_OK' resultado;
COMMIT;`);
write('_backup',`BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${pre}
CREATE SCHEMA primeline_ad13_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad13_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad13_backup.rpc AS SELECT pg_get_functiondef(p.oid) definicao,p.proowner,p.proacl,p.proconfig,p.prosecdef FROM pg_proc p WHERE oid='${tableSignature}'::regprocedure;
CREATE TABLE primeline_ad13_backup.ad14 AS SELECT p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definicao,p.proacl acl FROM pg_proc p WHERE oid IN('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)'::regprocedure,'folha_privado.diaria_ad14_final()'::regprocedure);
CREATE TABLE primeline_ad13_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY[${tables.map(t=>"'"+t+"'").join(',')}] LOOP
 EXECUTE format('INSERT INTO primeline_ad13_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP;END $snapshot$;
CREATE TABLE primeline_ad13_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad13_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD13_BACKUP_OK' resultado;
COMMIT;`);
write('',`BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${pre}
${equality}
${validator}
${facts}
${guard}
REVOKE ALL ON FUNCTION ${helpers.map(h=>h[0]).join(',')} FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE public.folha_horarios ADD CONSTRAINT folha_horario_ad13_coerencia CHECK(folha_privado.horario_ad13_valido(jsonb_build_object('intervals',intervals,'expected_minutes',expected_minutes),true) IS TRUE);
ALTER TABLE public.folha_horarios_versoes ADD CONSTRAINT folha_versao_ad13_coerencia CHECK(folha_privado.horario_ad13_valido(snapshot,true) IS TRUE);
CREATE TRIGGER folha_diaria_ad13_ativacao BEFORE INSERT OR UPDATE ON public.folha_config_empresa FOR EACH ROW EXECUTE FUNCTION folha_privado.horario_ad13_guardar();
CREATE TRIGGER folha_diaria_ad13_referencia BEFORE INSERT OR UPDATE ON public.folha_avaliacoes_diarias FOR EACH ROW EXECUTE FUNCTION folha_privado.horario_ad13_guardar();
${rpc}
${installed}
${equality}
SELECT 'AD13_MIGRATION_OK' resultado;
COMMIT;`);
write('_postcheck',`BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${installed}
${equality}
SELECT 'AD13_POSTCHECK_OK' resultado;
COMMIT;`);
write('_rollback',`-- Manual only; preserve AD-14/15. Refuse business activity since snapshot.
BEGIN;
SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${installed}
${equality}
DO $restore$ DECLARE r record; BEGIN SELECT * INTO STRICT r FROM primeline_ad13_backup.rpc;EXECUTE r.definicao;END $restore$;
DROP TRIGGER folha_diaria_ad13_ativacao ON public.folha_config_empresa;
DROP TRIGGER folha_diaria_ad13_referencia ON public.folha_avaliacoes_diarias;
ALTER TABLE public.folha_horarios DROP CONSTRAINT folha_horario_ad13_coerencia;
ALTER TABLE public.folha_horarios_versoes DROP CONSTRAINT folha_versao_ad13_coerencia;
DROP FUNCTION folha_privado.horario_ad13_guardar(),folha_privado.horario_ad13_factos(jsonb,boolean),folha_privado.horario_ad13_valido(jsonb,boolean);
${pre}
SELECT 'AD13_ROLLBACK_OK' resultado;
COMMIT;`);
console.log(JSON.stringify({oldHash,newHash,ad15_guard_delta:0,ad14_functions_delta:0}));
