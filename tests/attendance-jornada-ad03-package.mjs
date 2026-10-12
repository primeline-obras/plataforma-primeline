import fs from 'node:fs';import crypto from 'node:crypto';
const read=p=>fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n'),hash=s=>crypto.createHash('sha256').update(s).digest('hex');
function fn(f,n,t='$$'){const s=read(f),a=s.indexOf('FUNCTION '+n),b=s.indexOf(t,a);return s.slice(s.lastIndexOf('CREATE',a),s.indexOf(t+';',b+t.length)+t.length+1);}
const body=s=>s.split(/(\$[a-z]*\$)/)[2];function edit(s,a,b){if(s.split(a).length!==2)throw Error('anchor '+a);return s.replace(a,b);}
const p='supabase/folha_avaliacao_diaria.sql',h='supabase/folha_horarios_ad13.sql',a='supabase/folha_avaliacao_ad14.sql';
const old=[['folha_privado.diaria_referencia(uuid,date)',fn(p,'folha_privado.diaria_referencia')],['folha_privado.diaria_recalcular(uuid,date,uuid)',fn(p,'folha_privado.diaria_recalcular')],['folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean)',fn(a,'folha_privado.diaria_ad14_valida','$validator$')],['folha_privado.horario_ad13_valido(jsonb,boolean)',fn(h,'folha_privado.horario_ad13_valido','$validator$')],['folha_privado.horario_ad13_guardar()',fn(h,'folha_privado.horario_ad13_guardar','$guard$')],['public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)',fn(h,'public.fn_folha_diaria_gestao_v2')]];
const tables=['folha_avaliacoes_diarias','folha_horarios','folha_horarios_versoes','folha_config_empresa','folha_registos','folha_he','folha_vencimentos','folha_gestao_historico','quadro_equipa_permanencias','quadro_pessoal_alocacao','quadro_pessoal_movimentos','colaboradores','utilizadores','obra_responsaveis'];
const owner="IF current_user<>'postgres' OR session_user<>'postgres' THEN RAISE EXCEPTION 'OWNER_REQUIRED';END IF;";
const locks="LOCK TABLE public.quadro_pessoal_alocacao IN ROW EXCLUSIVE MODE;SELECT pg_advisory_xact_lock(61001,1);\nLOCK TABLE "+tables.filter(t=>t!=='quadro_pessoal_alocacao').map(t=>'public.'+t).join(',')+",folha_privado.operacoes IN SHARE ROW EXCLUSIVE MODE;";
const checks=old.map(([sig,s])=>"IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='"+sig+"'::regprocedure AND proowner='postgres'::regrole AND prosecdef="+(/SECURITY DEFINER/.test(s)?'true':'false')+" AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY["+(sig.startsWith('public.')?"'authenticated=X/postgres',":"")+"'postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='"+hash(body(s))+"') THEN RAISE EXCEPTION 'AD03_BASELINE_DRIFT: "+sig+"';END IF;").join('\n');
const pre="DO $gate$ BEGIN "+owner+'\n'+checks+`
IF to_regclass('public.folha_jornadas_individuais_versoes') IS NOT NULL OR to_regprocedure('public.fn_folha_jornadas_v2(text,jsonb,boolean,text)') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.folha_avaliacoes_diarias'::regclass AND attname='jornada_versao_id' AND NOT attisdropped) OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND p.proname LIKE 'jornada_ad03_%') THEN RAISE EXCEPTION 'AD03_PRESENT_OR_PARTIAL';END IF;
IF EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE folha_privado.diaria_ad14_valida(a,true) IS NOT TRUE) THEN RAISE EXCEPTION 'AD03_EXISTING_EVALUATION_INVALID';END IF;
IF EXISTS(SELECT 1 FROM public.folha_horarios WHERE folha_privado.horario_ad13_valido(jsonb_build_object('intervals',intervals,'expected_minutes',expected_minutes),true) IS NOT TRUE) OR EXISTS(SELECT 1 FROM public.folha_horarios_versoes WHERE folha_privado.horario_ad13_valido(snapshot,true) IS NOT TRUE) THEN RAISE EXCEPTION 'AD03_EXISTING_SCHEDULE_INVALID';END IF;
END $gate$;`;
const data=`DO $data$ DECLARE r record;j jsonb;BEGIN
${owner}
IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='primeline_ad03_backup' AND nspowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(n.nspacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>n.nspowner) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(c.relacl) x WHERE n.nspname='primeline_ad03_backup' AND x.grantee<>c.relowner) OR EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='primeline_ad03_backup' AND a.attacl IS NOT NULL AND a.attacl<>'{}'::aclitem[]) THEN RAISE EXCEPTION 'AD03_BACKUP_NOT_PRIVATE';END IF;
FOR r IN SELECT * FROM primeline_ad03_backup.dados LOOP EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',r.tabela::regclass) INTO j;IF j IS DISTINCT FROM r.linhas THEN RAISE EXCEPTION 'AD03_DATA_DRIFT: %',r.tabela;END IF;END LOOP;END $data$;`;
const after=data.replace('to_jsonb(x) ORDER BY to_jsonb(x)::text',"(to_jsonb(x)-''jornada_versao_id'') ORDER BY (to_jsonb(x)-''jornada_versao_id'')::text");
let validator=edit(old[3][1].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION'),' valid:=false;last_end:=-1;total:=0;n:=0;',` IF p_normal IS FALSE AND jsonb_typeof(p_snapshot)='object' AND p_snapshot->>'day_type'='folga' THEN RETURN (p_snapshot->'expected_minutes'='0'::jsonb AND p_snapshot->'intervals'='[]'::jsonb) IS TRUE;END IF;
 IF p_normal IS FALSE AND p_snapshot ? 'day_type' AND p_snapshot->>'day_type' IS DISTINCT FROM 'prevista' THEN RETURN false;END IF;
 valid:=false;last_end:=-1;total:=0;n:=0;`);
const shape=old[2][1].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION').replace('a.expected_minutes BETWEEN 1 AND 1440','a.expected_minutes BETWEEN 0 AND 1440').replace("jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16","(jsonb_array_length(a.horario_snapshot->'intervals') BETWEEN 1 AND 16 OR (a.expected_minutes=0 AND a.horario_snapshot->>'day_type'='folga' AND a.horario_snapshot->'intervals'='[]'::jsonb))");
let recalc=edit(old[1][1].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION'),"n.referencia_origem:='automatico';","n.referencia_origem:=ref->>'referencia_origem';n.jornada_versao_id:=(ref->>'jornada_versao_id')::uuid;");
recalc=edit(recalc,"n.referencia_motivo:=ref->>'referencia_motivo';","n.referencia_motivo:=ref->>'referencia_motivo';n.referencia_evidencia:=ref->'referencia_evidencia';");
let rpc=edit(old[5][1],"expected NOT BETWEEN 1 AND 1440 OR jsonb_typeof(p_dados->'evidence')","expected NOT BETWEEN 0 AND 1440 OR jsonb_typeof(p_dados->'evidence')");
rpc=edit(rpc,"referencia_origem='administrativo',referencia_revision=referencia_revision+1,","referencia_origem='administrativo',jornada_versao_id=NULL,referencia_revision=referencia_revision+1,");

rpc=edit(rpc," ELSIF p_acao='daily_reference_correct' THEN\n  UPDATE",` ELSIF p_acao='daily_reference_correct' THEN
  IF a.he_estado IN('validada','nao_considerada') THEN
   INSERT INTO public.folha_gestao_historico(empresa_id,action,entidade_id,antes,depois,ator_id,request_id,reason)
   VALUES(u.empresa_id,'daily_he_invalidate',a.id,to_jsonb(a),jsonb_build_object('reason','Referência administrativa alterada'),u.id,req,reason);
  END IF;
  UPDATE`);
rpc=edit(rpc,"jornada_versao_id=NULL,referencia_revision=referencia_revision+1,","jornada_versao_id=NULL,referencia_revision=referencia_revision+1,falta_minutes=NULL,excedente_minutes=NULL,he_estado='nao_avaliavel',decisao_fingerprint=NULL,he_decidido_por=NULL,he_decidido_em=NULL,he_motivo=NULL,pendencias=array_remove(array_remove(pendencias,'he_diaria_pendente'),'he_validada_aguarda_processamento'),");


const core=read('tests/fixtures/attendance-jornada-ad03-core.sql');
const cons=`DO $constraints$ DECLARE r record;def text;BEGIN
FOR r IN SELECT conname,pg_get_constraintdef(oid) def FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND contype='c' AND (pg_get_constraintdef(oid) LIKE '%expected_minutes >= 1%' OR pg_get_constraintdef(oid) LIKE '%referencia_origem = ANY%') LOOP
def:=replace(r.def,'expected_minutes >= 1','expected_minutes >= 0');def:=replace(def,'''administrativo''::text]', '''administrativo''::text, ''individual''::text]');
EXECUTE format('ALTER TABLE public.folha_avaliacoes_diarias DROP CONSTRAINT %I',r.conname);EXECUTE format('ALTER TABLE public.folha_avaliacoes_diarias ADD CONSTRAINT %I %s',r.conname,def);END LOOP;END $constraints$;
DO $history$ DECLARE n text;d text;BEGIN
SELECT conname,pg_get_constraintdef(oid) INTO STRICT n,d FROM pg_constraint WHERE conrelid='public.folha_gestao_historico'::regclass AND contype='c' AND pg_get_constraintdef(oid) LIKE '%action = ANY%';
d:=replace(d,'''schedule_retro_correct''::text]', '''schedule_retro_correct''::text, ''jornada_assign''::text]');
EXECUTE format('ALTER TABLE public.folha_gestao_historico DROP CONSTRAINT %I',n);EXECUTE format('ALTER TABLE public.folha_gestao_historico ADD CONSTRAINT %I %s',n,d);END $history$;`;
const functions=[validator,shape,recalc,rpc,...Array.from(core.matchAll(/CREATE(?: OR REPLACE)? FUNCTION[\s\S]*?\$[a-z]*\$;/g),x=>x[0])];
const signatureMap=new Map([...old.map(([sig])=>[sig.split('(')[0],sig]),...[
 ['folha_privado.jornada_ad03_semana_valida','folha_privado.jornada_ad03_semana_valida(jsonb)'],
 ['folha_privado.jornada_ad03_modelo','folha_privado.jornada_ad03_modelo(text)'],
 ['folha_privado.jornada_ad03_guardar','folha_privado.jornada_ad03_guardar()'],
 ['folha_privado.jornada_ad03_avaliacao_valida','folha_privado.jornada_ad03_avaliacao_valida(public.folha_avaliacoes_diarias)'],
 ['public.fn_folha_jornadas_v2','public.fn_folha_jornadas_v2(text,jsonb,boolean,text)']
]]);
const inst=functions.map(s=>{const n=s.match(/FUNCTION ([^(]+)/)[1],sig=signatureMap.get(n),header=s.slice(0,s.indexOf('$'));if(!sig)throw Error(n);
 return "IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='"+sig+"'::regprocedure AND proowner='postgres'::regrole AND prosecdef="+(/SECURITY DEFINER/.test(header)?'true':'false')+" AND provolatile='"+(/IMMUTABLE/.test(header)?'i':/STABLE/.test(header)?'s':'v')+"' AND proconfig=ARRAY['search_path=pg_catalog'] AND (SELECT array_agg(x::text ORDER BY x::text) FROM unnest(proacl) x)=ARRAY["+(sig.startsWith('public.')?"'authenticated=X/postgres',":"")+"'postgres=X/postgres'] AND encode(sha256(convert_to(replace(prosrc,chr(13),''),'UTF8')),'hex')='"+hash(body(s))+"') THEN RAISE EXCEPTION 'AD03_FUNCTION_DRIFT: "+sig+"';END IF;";}).join('\n');
const installed="DO $installed$ DECLARE r record;d text;BEGIN "+owner+'\n'+inst+`

IF (SELECT count(*) FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass)<>43 THEN RAISE EXCEPTION 'AD03_CONSTRAINT_COUNT_DRIFT';END IF;
FOR r IN SELECT * FROM primeline_ad03_backup.constraints LOOP
 d:=replace(r.definicao,'expected_minutes >= 1','expected_minutes >= 0');d:=replace(d,'''administrativo''::text]', '''administrativo''::text, ''individual''::text]');d:=replace(d,'''schedule_retro_correct''::text]', '''schedule_retro_correct''::text, ''jornada_assign''::text]');
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=r.tabela::regclass AND conname=r.conname AND convalidated AND pg_get_constraintdef(oid)=d) THEN RAISE EXCEPTION 'AD03_CONSTRAINT_DRIFT: %',r.conname;END IF;
END LOOP;
IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.folha_jornadas_individuais_versoes'::regclass AND relrowsecurity AND relowner='postgres'::regrole) OR EXISTS(SELECT 1 FROM aclexplode((SELECT relacl FROM pg_class WHERE oid='public.folha_jornadas_individuais_versoes'::regclass)) x WHERE x.grantee<>'postgres'::regrole) THEN RAISE EXCEPTION 'AD03_TABLE_ACL_DRIFT';END IF;
IF EXISTS(SELECT 1 FROM public.folha_jornadas_individuais_versoes WHERE folha_privado.jornada_ad03_semana_valida(semana) IS NOT TRUE) OR EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias a WHERE folha_privado.diaria_ad14_valida(a,true) IS NOT TRUE OR folha_privado.jornada_ad03_avaliacao_valida(a) IS NOT TRUE) THEN RAISE EXCEPTION 'AD03_INVALID_REFERENCE';END IF;
IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='folha_jornada_ad03_guardar' AND tgrelid='public.folha_jornadas_individuais_versoes'::regclass AND tgenabled='O') OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.folha_avaliacoes_diarias'::regclass AND conname='folha_jornada_ad03_reference' AND convalidated) THEN RAISE EXCEPTION 'AD03_SCHEMA_DRIFT';END IF;
IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE n.nspname='folha_privado' AND p.proname LIKE 'jornada_ad03_%' AND x.grantee<>p.proowner) THEN RAISE EXCEPTION 'AD03_PRIVATE_HELPER_GRANT';END IF;
IF (SELECT array_agg(x::text ORDER BY x::text) FROM pg_proc p CROSS JOIN LATERAL unnest(p.proacl) x WHERE p.oid='public.fn_folha_jornadas_v2(text,jsonb,boolean,text)'::regprocedure) IS DISTINCT FROM ARRAY['authenticated=X/postgres','postgres=X/postgres'] THEN RAISE EXCEPTION 'AD03_RPC_GRANT';END IF;
END $installed$;`;
const backup=`BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${pre}
CREATE SCHEMA primeline_ad03_backup;REVOKE ALL ON SCHEMA primeline_ad03_backup FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE primeline_ad03_backup.funcoes AS SELECT oid::regprocedure::text assinatura,pg_get_functiondef(oid) definicao,proacl acl FROM pg_proc WHERE oid IN (${old.map(([sig])=>"'"+sig+"'::regprocedure").join(',')});
CREATE TABLE primeline_ad03_backup.constraints AS SELECT conrelid::regclass::text tabela,conname,pg_get_constraintdef(oid) definicao FROM pg_constraint WHERE conrelid IN('public.folha_avaliacoes_diarias'::regclass,'public.folha_gestao_historico'::regclass);
CREATE TABLE primeline_ad03_backup.dados(tabela text PRIMARY KEY,linhas jsonb NOT NULL);
DO $copy$ DECLARE t text;BEGIN FOREACH t IN ARRAY ARRAY[${[...tables.map(t=>'public.'+t),'folha_privado.operacoes'].map(t=>"'"+t+"'").join(',')}] LOOP EXECUTE format('INSERT INTO primeline_ad03_backup.dados SELECT %L,coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE "C"),''[]''::jsonb) FROM %s x',t,t::regclass);END LOOP;END $copy$;
REVOKE ALL ON ALL TABLES IN SCHEMA primeline_ad03_backup FROM PUBLIC,anon,authenticated,service_role;
SELECT 'AD03_BACKUP_OK' resultado;COMMIT;`;
const migration=`BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${pre}
${data}
${validator}
${cons}
${core}
${shape}
${recalc}
${rpc}
${after}
SELECT 'AD03_MIGRATION_OK' resultado;COMMIT;`;
const rollback=`BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL search_path=pg_catalog;
${locks}
${installed}
${after}
DO $unused$ BEGIN IF EXISTS(SELECT 1 FROM public.folha_jornadas_individuais_versoes) OR EXISTS(SELECT 1 FROM public.folha_avaliacoes_diarias WHERE jornada_versao_id IS NOT NULL) THEN RAISE EXCEPTION 'AD03_ROLLBACK_AFTER_USE_FORBIDDEN';END IF;END $unused$;
ALTER TABLE public.folha_avaliacoes_diarias DROP CONSTRAINT folha_jornada_ad03_reference;ALTER TABLE public.folha_avaliacoes_diarias DROP COLUMN jornada_versao_id;
DO $restore$ DECLARE r record;BEGIN FOR r IN SELECT * FROM primeline_ad03_backup.funcoes LOOP EXECUTE r.definicao;END LOOP;
FOR r IN SELECT b.* FROM primeline_ad03_backup.constraints b JOIN pg_constraint c ON c.conrelid=b.tabela::regclass AND c.conname=b.conname WHERE pg_get_constraintdef(c.oid) IS DISTINCT FROM b.definicao LOOP EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I',r.tabela::regclass,r.conname);EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s',r.tabela::regclass,r.conname,r.definicao);END LOOP;END $restore$;
DROP FUNCTION public.fn_folha_jornadas_v2(text,jsonb,boolean,text);DROP TABLE public.folha_jornadas_individuais_versoes;
DROP FUNCTION folha_privado.jornada_ad03_avaliacao_valida(public.folha_avaliacoes_diarias),folha_privado.jornada_ad03_guardar(),folha_privado.jornada_ad03_semana_valida(jsonb),folha_privado.jornada_ad03_modelo(text);
${pre}
${data}
SELECT 'AD03_ROLLBACK_OK' resultado;COMMIT;`;
const ro=(s,label)=>"BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;SET LOCAL search_path=pg_catalog;\n"+s+"\nSELECT '"+label+"' resultado;COMMIT;";
for(const [suffix,sql] of [['precheck',ro(pre,'AD03_PRECHECK_OK')],['backup',backup],['',migration],['postcheck',ro(installed+'\n'+after,'AD03_POSTCHECK_OK')],['rollback',rollback]])fs.writeFileSync('supabase/folha_jornada_ad03'+(suffix?'_'+suffix:'')+'.sql',sql+'\n');
console.log('AD03 SQL generated locally.');
