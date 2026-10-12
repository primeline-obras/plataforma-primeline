import fs from 'node:fs';
import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
const signature='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)';
const source=read('supabase/folha_avaliacao_diaria.sql');
let rpc=source.slice(source.indexOf('CREATE FUNCTION public.fn_folha_diaria_gestao_v2'),source.indexOf('CREATE OR REPLACE FUNCTION folha_privado.save(')).trim();
rpc=rpc.replace('CREATE FUNCTION public.', 'CREATE OR REPLACE FUNCTION public.');
const anchor=" IF p IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.colaboradores WHERE id=p AND empresa_id=u.empresa_id) THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;";
if(!rpc.includes(anchor))throw Error('Source contract changed');
rpc=rpc.replace(anchor,` -- AD-15: session actor is the only tenant authority; revalidate before replay.
 IF u.empresa_id IS NULL OR (p_dados ? 'empresa_id' AND (p_dados->>'empresa_id')::uuid IS DISTINCT FROM u.empresa_id) THEN RAISE EXCEPTION 'DAILY_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 IF p_acao IN('daily_activation','daily_he_validate','daily_he_disregard') AND w IS NOT NULL THEN RAISE EXCEPTION 'DAILY_GLOBAL_WORK_CONTEXT_FORBIDDEN' USING ERRCODE='42501'; END IF;
 IF p IS NOT NULL THEN
  PERFORM 1 FROM public.colaboradores c WHERE c.id=p AND c.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERMISSION_DENIED: colaborador' USING ERRCODE='42501'; END IF;
 END IF;
 IF w IS NOT NULL THEN
  PERFORM 1 FROM public.obras o WHERE o.id=w AND o.empresa_id=u.empresa_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_WORK_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
 END IF;
 IF p_acao IN('daily_reference_correct','daily_he_validate','daily_he_disregard') THEN
  PERFORM folha_privado.lock_dia(p,d);
  SELECT * INTO a FROM public.folha_avaliacoes_diarias WHERE empresa_id=u.empresa_id AND colaborador_id=p AND data=d FOR UPDATE;
  IF a.id IS NULL OR (p_dados ? 'evaluation_id' AND (p_dados->>'evaluation_id')::uuid IS DISTINCT FROM a.id) THEN RAISE EXCEPTION 'DAILY_EVALUATION_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  IF a.obra_origem_id IS NOT NULL THEN
   PERFORM 1 FROM public.obras o WHERE o.id=a.obra_origem_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_REFERENCE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  END IF;
 END IF;`);
rpc=rpc.replace("  rev:=cfg.revision;before:=to_jsonb(cfg);", `  -- Validate/lock the real schedule-work references, without changing hours.
  FOR schedule_row IN SELECT s.obra_id FROM public.folha_horarios s WHERE s.empresa_id=u.empresa_id ORDER BY s.obra_id FOR SHARE LOOP
   PERFORM 1 FROM public.obras o WHERE o.id=schedule_row.obra_id AND o.empresa_id=u.empresa_id FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;
  END LOOP;
  rev:=cfg.revision;before:=to_jsonb(cfg);`);
rpc=rpc.replace("  PERFORM folha_privado.obra(w,true);SELECT * INTO h FROM public.folha_horarios WHERE obra_id=w FOR UPDATE;", `  PERFORM folha_privado.obra(w,true);SELECT * INTO h FROM public.folha_horarios WHERE obra_id=w FOR UPDATE;
  IF h.obra_id IS NOT NULL AND h.empresa_id IS DISTINCT FROM u.empresa_id THEN RAISE EXCEPTION 'DAILY_SCHEDULE_TENANT_MISMATCH' USING ERRCODE='42501'; END IF;`);
const body=rpc.slice(rpc.indexOf('AS $$')+5,rpc.lastIndexOf('$$;'));
const hash=crypto.createHash('sha256').update(body).digest('hex');
const baseline=JSON.parse(read('tests/fixtures/folha-diaria-funcoes-esperadas.json')).find(f=>f.sig===signature).hash;
const tables=['folha_avaliacoes_diarias','folha_gestao_historico','folha_horarios','folha_horarios_versoes','folha_config_empresa','folha_registos','folha_he','folha_vencimentos'];
const metadata=`IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='${signature}'::regprocedure AND p.proowner='postgres'::regrole AND p.prosecdef AND p.proconfig=ARRAY['search_path=pg_catalog'] AND p.prolang=(SELECT oid FROM pg_language WHERE lanname='plpgsql') AND p.prorettype='jsonb'::regtype AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(p.proacl) x)=ARRAY['authenticated=X/postgres','postgres=X/postgres']) THEN RAISE EXCEPTION 'AD15_FUNCTION_METADATA_DRIFT'; END IF;`;
const check=`DO $gate$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED'; END IF;
 IF to_regprocedure('${signature}') IS NULL THEN RAISE EXCEPTION 'AD15_DAILY_PACKAGE_REQUIRED'; END IF;
 IF encode(sha256(convert_to(btrim(replace((SELECT prosrc FROM pg_proc WHERE oid='${signature}'::regprocedure),chr(13),''),E' \\n\\t'),'UTF8')),'hex')<>'${baseline}' THEN RAISE EXCEPTION 'AD15_BASELINE_DRIFT'; END IF;
 ${metadata}
 IF EXISTS(SELECT 1 FROM public.folha_gestao_historico h LEFT JOIN public.utilizadores u ON u.id=h.ator_id LEFT JOIN public.obras o ON o.id=h.obra_id LEFT JOIN public.folha_avaliacoes_diarias a ON a.id=h.entidade_id LEFT JOIN public.colaboradores c ON c.id=a.colaborador_id WHERE h.action IN('daily_he_validate','daily_he_disregard','daily_reference_correct') AND (u.empresa_id IS DISTINCT FROM h.empresa_id OR a.empresa_id IS DISTINCT FROM h.empresa_id OR c.empresa_id IS DISTINCT FROM h.empresa_id OR (h.obra_id IS NOT NULL AND (o.empresa_id IS DISTINCT FROM h.empresa_id OR h.action IN('daily_he_validate','daily_he_disregard'))))) THEN RAISE EXCEPTION 'AD15_HISTORICAL_CONTEXT_REQUIRES_RECONCILIATION'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_gestao_historico'::regclass) AND NOT relrowsecurity) OR has_table_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE,DELETE') OR has_any_column_privilege('authenticated','public.folha_avaliacoes_diarias','INSERT,UPDATE') OR has_any_column_privilege('authenticated','public.folha_gestao_historico','INSERT,UPDATE') THEN RAISE EXCEPTION 'AD15_DIRECT_WRITER_EXPOSED'; END IF;
END $gate$;`;
const privateCheck=`IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad15_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE n.nspname='primeline_ad15_backup' AND a.grantee<>'postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad15_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD15_BACKUP_NOT_PRIVATE'; END IF;`;
const equality=`DO $data$ DECLARE r record; rows_now jsonb; BEGIN
 ${privateCheck}
 FOR r IN SELECT * FROM primeline_ad15_backup.dados LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',r.tabela) INTO rows_now;
  IF rows_now IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD15_DATA_DRIFT: %',r.tabela; END IF;
 END LOOP;
 IF (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') FROM folha_privado.operacoes x) IS DISTINCT FROM (SELECT linhas FROM primeline_ad15_backup.operacoes) THEN RAISE EXCEPTION 'AD15_OPERATIONS_DRIFT'; END IF;
END $data$;`;
const locks=`LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;
SELECT pg_advisory_xact_lock(61001,1);
LOCK TABLE ${tables.map(t=>'public.'+t).join(',')},folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;`;
const write=(name,sql)=>fs.writeFileSync('supabase/folha_he_tenant_ad15_'+name+'.sql',sql+'\n');
write('precheck',`-- READ ONLY; any drift requires STOP. No reconciliation.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${check}
SELECT 'AD15_PRECHECK_OK' resultado;
COMMIT;`);
write('backup',`-- Specific private backup. No business rows modified.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
${locks}
${check}
CREATE SCHEMA primeline_ad15_backup AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA primeline_ad15_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad15_backup.funcao AS SELECT pg_get_functiondef(p.oid) definicao,p.prosrc,p.proowner,p.proacl,p.proconfig,p.prosecdef FROM pg_proc p WHERE p.oid='${signature}'::regprocedure;
CREATE TABLE primeline_ad15_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $snapshot$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY[${tables.map(t=>"'"+t+"'").join(',')}] LOOP
 EXECUTE format('INSERT INTO primeline_ad15_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM public.%I x',t,t);
END LOOP; END $snapshot$;
CREATE TABLE primeline_ad15_backup.operacoes AS SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),'[]') linhas FROM folha_privado.operacoes x;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad15_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD15_BACKUP_OK' resultado;
COMMIT;`);
const functionCheck=`DO $function$ BEGIN
 ${metadata}
 IF encode(sha256(convert_to(replace((SELECT prosrc FROM pg_proc WHERE oid='${signature}'::regprocedure),chr(13),''),'UTF8')),'hex')<>'${hash}' THEN RAISE EXCEPTION 'AD15_FIXED_FUNCTION_DRIFT'; END IF;
END $function$;`;
fs.writeFileSync('supabase/folha_he_tenant_ad15.sql',`-- Complete definition. No activation, no historical writes; application ACL preserved.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
${locks}
${check}
${equality}
${rpc}
${functionCheck}
${equality}
SELECT 'AD15_MIGRATION_OK' resultado;
COMMIT;\n`);
write('postcheck',`BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog;
${functionCheck}
${equality}
SELECT 'AD15_POSTCHECK_OK' resultado;
COMMIT;`);
write('rollback',`-- Manual only. Recuses drift/use since backup; never overwrite operational data.
BEGIN;
SET LOCAL search_path=pg_catalog;
SET LOCAL lock_timeout='10s';
${locks}
${functionCheck}
${equality}
DO $restore$ DECLARE r record; BEGIN
 SELECT * INTO STRICT r FROM primeline_ad15_backup.funcao;
 EXECUTE r.definicao;
END $restore$;
${check}
SELECT 'AD15_ROLLBACK_OK' resultado;
COMMIT;`);
console.log(JSON.stringify({signature,baseline,prosrc_sha256:hash}));
