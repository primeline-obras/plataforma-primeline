import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
const table='public.folha_avaliacoes_diarias';
const base=JSON.parse(read('tests/fixtures/folha-diaria-catalogo-esperado.json')).find(x=>x.table==='folha_avaliacoes_diarias');
const constraints=base.constraints;
const shape=String.raw`
 jsonb_typeof(a.contexto_snapshot)='object' AND a.contexto_snapshot->>'regra'='diaria_v1'
 AND jsonb_typeof(a.contexto_snapshot->'data_ativacao')='string'
 AND a.contexto_snapshot->>'data_ativacao' ~ '^\d{4}-\d{2}-\d{2}$'
 AND CASE WHEN jsonb_typeof(a.factos_revisoes)='array' THEN
  NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x WHERE
   (jsonb_typeof(x)='object' AND jsonb_typeof(x->'id')='string' AND x->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    AND jsonb_typeof(x->'revision')='number' AND x->>'revision' ~ '^[1-9][0-9]*$') IS NOT TRUE)
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.factos_revisoes) x GROUP BY x->>'id' HAVING count(*)>1)
 ELSE false END
 AND coalesce(array_ndims(a.pendencias),1)=1 AND array_position(a.pendencias,NULL) IS NULL
 AND NOT EXISTS(SELECT 1 FROM unnest(a.pendencias) x WHERE nullif(btrim(x),'') IS NULL)
 AND cardinality(a.pendencias)=(SELECT count(DISTINCT x) FROM unnest(a.pendencias) x)
 AND CASE WHEN a.referencia_estado='pendente' THEN
  a.expected_minutes IS NULL AND a.horario_snapshot IS NULL
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=0
  AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL AND a.referencia_origem='automatico'
 ELSE
  a.expected_minutes IS NOT NULL AND a.expected_minutes BETWEEN 1 AND 1440
  AND num_nonnulls(a.capturado_por,a.capturado_em,a.captura_request_id)=3
  AND CASE WHEN jsonb_typeof(a.horario_snapshot)='object' AND jsonb_typeof(a.horario_snapshot->'intervals')='array' THEN
   jsonb_typeof(a.horario_snapshot->'expected_minutes')='number'
   AND a.horario_snapshot->>'expected_minutes'=a.expected_minutes::text
   AND jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(a.horario_snapshot->'intervals') x WHERE
    (jsonb_typeof(x)='object' AND jsonb_typeof(x->'start')='string' AND jsonb_typeof(x->'end')='string'
     AND x->>'start' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND x->>'end' ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     AND x->>'end'>x->>'start') IS NOT TRUE)
  ELSE false END
  AND CASE WHEN a.referencia_origem='automatico' THEN
   num_nonnulls(a.permanencia_id,a.obra_origem_id,a.horario_versao_id)=3
   AND jsonb_typeof(a.permanencia_snapshot)='object'
   AND a.permanencia_snapshot->>'id'=a.permanencia_id::text
   AND a.permanencia_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.permanencia_snapshot->>'colaborador_id'=a.colaborador_id::text
   AND a.permanencia_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'obra_id'=a.obra_origem_id::text
   AND a.horario_snapshot->>'empresa_id'=a.empresa_id::text
   AND a.horario_snapshot->>'versao_id'=a.horario_versao_id::text
  ELSE
   a.permanencia_id IS NULL AND a.permanencia_snapshot IS NULL AND a.horario_versao_id IS NULL
   AND jsonb_typeof(a.referencia_evidencia)='object' AND a.referencia_evidencia<>'{}'::jsonb
   AND nullif(btrim(a.referencia_motivo),'') IS NOT NULL
  END
 END
 AND CASE WHEN a.he_estado IN('validada','nao_considerada') THEN
  a.excedente_minutes IS NOT NULL AND a.excedente_minutes>0
  AND num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=4
  AND a.decisao_fingerprint ~ '^[0-9a-f]{64}$' AND nullif(btrim(a.he_motivo),'') IS NOT NULL
 ELSE num_nonnulls(a.decisao_fingerprint,a.he_decidido_por,a.he_decidido_em,a.he_motivo)=0 END`;
const final=String.raw`
 a.ativa=(a.estado<>'inativa')
 AND CASE WHEN a.referencia_estado='capturada' AND NOT ('intervalo_aberto'=ANY(a.pendencias)) AND NOT ('conflito_factos'=ANY(a.pendencias)) THEN
  num_nonnulls(a.falta_minutes,a.excedente_minutes)=2
  AND a.falta_minutes=greatest(0,a.expected_minutes-a.realizado_minutes)
  AND a.excedente_minutes=greatest(0,a.realizado_minutes-a.expected_minutes)
  AND CASE WHEN a.excedente_minutes>0 THEN a.he_estado IN('pendente','validada','nao_considerada') ELSE a.he_estado='nenhum' END
 ELSE num_nonnulls(a.falta_minutes,a.excedente_minutes)=0 AND a.he_estado='nao_avaliavel' END
 AND ('referencia_diaria_pendente'=ANY(a.pendencias))=(a.referencia_estado='pendente')
 AND ('horas_em_falta'=ANY(a.pendencias))=coalesce(a.falta_minutes>0,false)
 AND ('he_diaria_pendente'=ANY(a.pendencias))=(a.he_estado='pendente')
 AND ('he_validada_aguarda_processamento'=ANY(a.pendencias))=(a.he_estado='validada')
 AND (a.he_estado NOT IN('validada','nao_considerada') OR a.decisao_fingerprint=folha_privado.diaria_decisao_hash(a.factos_fingerprint,a.referencia_revision,a.horario_snapshot))
 AND a.estado=CASE WHEN NOT a.ativa THEN 'inativa'
  WHEN a.referencia_estado='pendente' THEN 'referencia_pendente'
  WHEN 'conflito_factos'=ANY(a.pendencias) THEN 'conflito'
  WHEN 'intervalo_aberto'=ANY(a.pendencias) THEN 'intervalo_aberto'
  WHEN a.falta_minutes>0 THEN 'horas_em_falta'
  WHEN a.excedente_minutes>0 AND a.he_estado<>'nao_considerada' THEN 'potencial_he'
  WHEN cardinality(a.pendencias)>0 THEN 'outras_pendencias' ELSE 'regular' END`;
const validator=`CREATE FUNCTION folha_privado.diaria_ad14_valida(r public.folha_avaliacoes_diarias,p_final boolean) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $validator$
 SELECT ((${shape}) AND (NOT p_final OR (${final}))) IS TRUE FROM (SELECT (r).*) a
$validator$;`;
const trigger=`CREATE FUNCTION folha_privado.diaria_ad14_final() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $trigger$
DECLARE r public.folha_avaliacoes_diarias;
BEGIN
 SELECT * INTO r FROM public.folha_avaliacoes_diarias WHERE id=NEW.id;
 IF FOUND AND folha_privado.diaria_ad14_valida(r,true) IS NOT TRUE THEN
  RAISE EXCEPTION 'AD14_FINAL_INVARIANT: evaluation %',NEW.id USING ERRCODE='23514',CONSTRAINT='folha_diaria_ad14_final';
 END IF;
 RETURN NULL;
END $trigger$;`;
const helpers=[['folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)',validator],['folha_privado.diaria_ad14_final()',trigger]];
const old15hash=read('supabase/folha_he_tenant_ad15_postcheck.sql').match(/<>'([0-9a-f]{64})'/)[1];
const oldConstraintJson=JSON.stringify(constraints);
const parentGate=`IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure),chr(13),''),'UTF8')),'hex')<>'${old15hash}' THEN RAISE EXCEPTION 'AD14_AD15_REQUIRED_OR_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD14_AD15_METADATA_DRIFT'; END IF;`;
const owner=`IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;`;
const tableGate=`IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='${table}'::regclass AND relowner='postgres'::regrole AND relrowsecurity) OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x WHERE c.oid='${table}'::regclass AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='${table}'::regclass AND attnum>0 AND NOT attisdropped AND attacl IS NOT NULL AND attacl<>'{}'::aclitem[]) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='${table}'::regclass) OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='${table}'::regclass AND tgname='folha_diaria_integridade' AND tgenabled='O') THEN RAISE EXCEPTION 'AD14_TABLE_SECURITY_DRIFT'; END IF;`;
const originalCatalog=`IF (SELECT count(*) FROM pg_constraint WHERE conrelid='${table}'::regclass)<>${constraints.length} THEN RAISE EXCEPTION 'AD14_BASELINE_CONSTRAINT_COUNT_DRIFT'; END IF;
 FOR c IN SELECT value FROM jsonb_array_elements($baseline$${oldConstraintJson}$baseline$::jsonb) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='${table}'::regclass AND conname=c->>'name' AND pg_get_constraintdef(oid)=c->>'definition' AND convalidated) THEN RAISE EXCEPTION 'AD14_BASELINE_CONSTRAINT_DRIFT: %',c->>'name'; END IF;
 END LOOP;`;
const audit=`SELECT string_agg(a.id::text,',' ORDER BY a.id) INTO bad FROM public.folha_avaliacoes_diarias a WHERE ((${shape}) AND (${final})) IS NOT TRUE;
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'AD14_EXISTING_INVALID_EVALUATIONS: %',bad; END IF;`;
const preGate=`DO $gate$ DECLARE c jsonb;bad text; BEGIN
 ${owner}
 ${parentGate}
 IF to_regprocedure('folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)') IS NOT NULL OR to_regprocedure('folha_privado.diaria_ad14_final()') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='${table}'::regclass AND conname='folha_diaria_ad14_shape') OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='${table}'::regclass AND tgname='folha_diaria_ad14_final') THEN RAISE EXCEPTION 'AD14_INSTALLED_OR_PARTIAL'; END IF;
 ${tableGate}
 ${originalCatalog}
 ${audit}
END $gate$;`;
const tables=['folha_avaliacoes_diarias','folha_gestao_historico','folha_registos','folha_he','folha_vencimentos','folha_horarios_versoes','folha_config_empresa'];
const lock=`LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE ${tables.map(x=>'public.'+x).join(',')},folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;`;
const privateCheck=`IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad14_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad14_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad14_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad14_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD14_BACKUP_NOT_PRIVATE'; END IF;`;
const equality=`DO $data$ DECLARE r record;rows_now jsonb; BEGIN
 ${owner}
 ${privateCheck}
 ${parentGate}
 FOR r IN SELECT * FROM primeline_ad14_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD14_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad14_backup.operacoes) THEN RAISE EXCEPTION 'AD14_OPERATIONS_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN primeline_ad14_backup.ad15 b WHERE p.oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure AND pg_get_functiondef(p.oid)=b.definicao AND p.proowner=b.proowner AND p.proacl IS NOT DISTINCT FROM b.proacl AND p.prosecdef=b.prosecdef AND p.proconfig IS NOT DISTINCT FROM b.proconfig) THEN RAISE EXCEPTION 'AD14_AD15_DEFINITION_DRIFT'; END IF;
END $data$;`;
const installed=`DO $installed$ DECLARE bad text;c jsonb; BEGIN
 ${owner}
 ${parentGate}
 ${tableGate}
 ${originalCatalog.replace('<>'+constraints.length+' THEN','<>'+(constraints.length+2)+' THEN')}
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='${table}'::regclass AND conname='folha_diaria_ad14_shape' AND convalidated AND pg_get_constraintdef(oid)='CHECK ((folha_privado.diaria_ad14_valida(folha_avaliacoes_diarias.*, false) IS TRUE))') THEN RAISE EXCEPTION 'AD14_SHAPE_CONSTRAINT_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='${table}'::regclass AND tgname='folha_diaria_ad14_final' AND tgenabled='O' AND tgdeferrable AND tginitdeferred AND tgfoid='folha_privado.diaria_ad14_final()'::regprocedure AND tgtype=21 AND tgnargs=0 AND octet_length(tgargs)=0 AND tgqual IS NULL AND tgattr::text='') THEN RAISE EXCEPTION 'AD14_FINAL_TRIGGER_DRIFT'; END IF;
 ${helpers.map(([sig,sql])=>{const tag=sig.includes('valida')?'$validator$':'$trigger$'; const src=sql.split(tag)[1];const hash=crypto.createHash('sha256').update(src).digest('hex');return `IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE oid='${sig}'::regprocedure AND proowner='postgres'::regrole AND proconfig=ARRAY['search_path=pg_catalog'] AND prosecdef=${sig.includes('valida')?'false':'true'} AND provolatile='${sig.includes('valida')?'i':'v'}' AND prorettype='${sig.includes('valida')?'boolean':'trigger'}'::regtype AND prolang=(SELECT oid FROM pg_language WHERE lanname='${sig.includes('valida')?'sql':'plpgsql'}') AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='${hash}' AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(proacl,acldefault('f',proowner))) x WHERE x.grantee<>proowner)) THEN RAISE EXCEPTION 'AD14_HELPER_DRIFT: ${sig}'; END IF;`;}).join('\n ')}
 ${audit}
END $installed$;`;
const write=(name,sql)=>fs.writeFileSync('supabase/folha_avaliacao_ad14'+name+'.sql',sql+'\n');
write('_precheck',`-- READ ONLY. Existing invalid rows require human reconciliation; report UUIDs only.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${preGate}
SELECT 'AD14_PRECHECK_OK' resultado;
COMMIT;`);
write('_backup',`BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=pg_catalog;
${lock}
${preGate}
CREATE SCHEMA primeline_ad14_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad14_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad14_backup.constraints AS SELECT conname,pg_get_constraintdef(oid) definicao,convalidated FROM pg_constraint WHERE conrelid='${table}'::regclass;
CREATE TABLE primeline_ad14_backup.ad15 AS SELECT pg_get_functiondef(p.oid) definicao,p.proowner,p.proacl,p.prosecdef,p.proconfig FROM pg_proc p WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure;
CREATE TABLE primeline_ad14_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY[${tables.map(x=>"'"+x+"'").join(',')}] LOOP
 EXECUTE format('INSERT INTO primeline_ad14_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP; END $snapshot$;
CREATE TABLE primeline_ad14_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad14_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD14_BACKUP_OK' resultado;
COMMIT;`);
write('',`-- Additive constraints only; AD-15 and every existing function remain unchanged.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=pg_catalog;
${lock}
${preGate}
${equality}
${validator}
${trigger}
REVOKE ALL ON FUNCTION folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean),folha_privado.diaria_ad14_final() FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE ${table} ADD CONSTRAINT folha_diaria_ad14_shape CHECK(folha_privado.diaria_ad14_valida(folha_avaliacoes_diarias.*,false) IS TRUE);
CREATE CONSTRAINT TRIGGER folha_diaria_ad14_final AFTER INSERT OR UPDATE ON ${table} DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION folha_privado.diaria_ad14_final();
${installed}
${equality}
SELECT 'AD14_MIGRATION_OK' resultado;
COMMIT;`);
write('_postcheck',`BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${installed}
${equality}
SELECT 'AD14_POSTCHECK_OK' resultado;
COMMIT;`);
write('_rollback',`-- Manual only. No row rewriting; refuse data/definition drift since backup.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL search_path=pg_catalog;
${lock}
${installed}
${equality}
DROP TRIGGER folha_diaria_ad14_final ON ${table};
ALTER TABLE ${table} DROP CONSTRAINT folha_diaria_ad14_shape;
DROP FUNCTION folha_privado.diaria_ad14_final();
DROP FUNCTION folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean);
${preGate}
SELECT 'AD14_ROLLBACK_OK' resultado;
COMMIT;`);
console.log('AD14_SCRIPTS_GENERATED; original constraints='+constraints.length+'; AD15='+old15hash);
