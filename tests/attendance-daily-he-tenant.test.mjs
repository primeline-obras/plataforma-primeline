// Reuse the existing disposable PostgreSQL bootstrap and regressions unchanged.
// Only the AD-15 hotfix and scoped synthetic checks are added to its in-memory runner.
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
assert.ok(process.env.QUADRO_PG_BIN&&process.env.QUADRO_TEST_DEPS,'PostgreSQL local required; no silent SKIP');
const base=resolve('tests/attendance-daily-backend.test.mjs');
let suite=fs.readFileSync(base,'utf8');
const marker=" const readRollback=await read('../supabase/folha_avaliacao_diaria_rollback.sql');";
assert.equal(suite.split(marker).length,2);
suite=suite.replace(marker,`
 await t.test('AD-15 scripts: precheck/backup/migration/postcheck/rollback/reinstall, no data change',async()=>{
  await q(await read('../supabase/folha_he_tenant_ad15_precheck.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15_backup.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15_postcheck.sql'));
  await q('GRANT EXECUTE ON FUNCTION public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text) TO anon');try{await assert.rejects(q(await read('../supabase/folha_he_tenant_ad15_postcheck.sql')),/AD15_FUNCTION_METADATA_DRIFT/);}finally{await q('ROLLBACK');await q('REVOKE EXECUTE ON FUNCTION public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text) FROM anon');}
  await q('GRANT SELECT ON primeline_ad15_backup.funcao TO authenticated');try{await assert.rejects(q(await read('../supabase/folha_he_tenant_ad15_postcheck.sql')),/AD15_BACKUP_NOT_PRIVATE/);}finally{await q('ROLLBACK');await q('REVOKE SELECT ON primeline_ad15_backup.funcao FROM authenticated');}
  await q(await read('../supabase/folha_he_tenant_ad15_postcheck.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15_rollback.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15_precheck.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15.sql'));
  await q(await read('../supabase/folha_he_tenant_ad15_postcheck.sql'));
 });
${marker}`);
const extra=String.raw`
 // Every rejection checks after-images, history and idempotency ledger.
 const snapshot=async()=> (await q("SELECT jsonb_build_object('evaluations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM folha_avaliacoes_diarias x),'history',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM folha_gestao_historico x),'ops',(SELECT jsonb_agg(to_jsonb(x) ORDER BY request_id) FROM folha_privado.operacoes x)) v")).rows[0].v;
 const heBody=async extra=>({version:2,request_id:id(seq++),person_id:id(33),date:today,expected_revision:(await daily(33)).revision,reason:'AD-15 teste sintético',...extra});
 async function rejectNoChange(action,body,actor=10,endpoint='fn_folha_diaria_gestao_v2'){
  const before=await snapshot();
  for(const confirm of [false,true])await assert.rejects(call(a,actor,endpoint,[action,body,confirm,null]),e=>e.code==='42501');
  assert.deepEqual(await snapshot(),before);
 }
 await t.test('AD-15 original: empresa 1/work empresa 2 rejected 42501 with zero partial writes',async()=>{
  await rejectNoChange('daily_he_validate',await heBody({work_id:id(103)}));
  console.log('AD15_ORIGINAL_AFTER '+JSON.stringify({sqlstate:'42501',partial_writes:false,contract:'PASS'}));
 });
 await t.test('AD-15 HE disregard and public wrapper reject foreign work',async()=>{
  await rejectNoChange('daily_he_disregard',await heBody({work_id:id(103)}));
  await rejectNoChange('daily_he_validate',await heBody({work_id:id(103)}),10,'fn_folha_gestao_v2');
 });
 await t.test('AD-15 same-tenant arbitrary work also rejected; global decision has no fabricated work',async()=>{
  await rejectNoChange('daily_he_validate',await heBody({work_id:id(100)}));
 });
 await t.test('AD-15 foreign person/evaluation/company rejected on preview and confirm',async()=>{
  await rejectNoChange('daily_he_validate',await heBody({person_id:id(49)}));
  const foreign=(await q('SELECT id FROM folha_avaliacoes_diarias WHERE colaborador_id=$1',[id(49)])).rows[0];
  await rejectNoChange('daily_he_validate',await heBody({evaluation_id:foreign.id}));
  await rejectNoChange('daily_he_validate',await heBody({empresa_id:id(2)}));
 });
 await t.test('AD-15 other daily operations: foreign reference/work and activation arbitrary work rejected',async()=>{
  await rejectNoChange('daily_reference_correct',await heBody({work_id:id(103),schedule:{intervals:schedule,expected_minutes:480},evidence:{document:'sintético'}}));
  await rejectNoChange('configure_schedule',{version:2,request_id:id(seq++),work_id:id(103),expected_revision:0,intervals:schedule,expected_minutes:480});
  await rejectNoChange('schedule_retro_correct',{version:2,request_id:id(seq++),work_id:id(103),expected_revision:0});
  await rejectNoChange('daily_activation',{version:2,request_id:id(seq++),work_id:id(103),date:today,expected_revision:0});
 });
 await t.test('AD-15 legitimate no-work decision: consistent history and true actor; pending HE preserved until decided',async()=>{
  await savePlan(33,[[100,[custom('09:00','18:15')]]]);const pending=await daily(33);assert.equal(pending.he_estado,'pendente');
  const payload=await heBody({ator_id:id(17),he_decidido_por:id(17)});const pre=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,false,null]);
  assert.deepEqual(await daily(33),pending,'preview cannot decide HE');
  const done=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,true,pre.versao]);assert.equal(done.committed,true);
  const row=(await q('SELECT * FROM folha_gestao_historico WHERE request_id=$1',[payload.request_id])).rows[0];assert.equal(row.obra_id,null);assert.equal(row.empresa_id,id(1));assert.equal(row.ator_id,id(10));assert.equal(row.entidade_id,pending.id);assert.equal(row.antes.colaborador_id,id(33));assert.equal(row.depois.empresa_id,id(1));
  const ev=await daily(33);assert.equal(ev.he_decidido_por,id(10));assert.equal(ev.revision,pending.revision+1);assert.equal(ev.realizado_minutes,pending.realizado_minutes);assert.equal(ev.expected_minutes,pending.expected_minutes);assert.ok(ev.pendencias.includes('he_validada_aguarda_processamento'));
  await assert.rejects(call(a,10,'fn_folha_gestao_v2',['payroll_close',{version:2,request_id:id(seq++),person_id:id(33),month:today.slice(0,7)+'-01',expected_revision:0},false,null]),/PAYROLL_DAILY_PENDING/);
  const stable=await snapshot();assert.deepEqual(await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,true,pre.versao]),done);assert.deepEqual(await snapshot(),stable);
 });
 await t.test('AD-15 disregard removes only HE pending; facts and other pending unchanged',async()=>{
  await q("UPDATE folha_avaliacoes_diarias SET pendencias=array_append(pendencias,'pendencia_sintetica_ad15') WHERE colaborador_id=$1 AND data=$2",[id(33),today]);const before=await daily(33);
  await adminOp('daily_he_disregard',{person_id:id(33),date:today,expected_revision:before.revision,reason:'AD-15 decisão sintética'});
  const after=await daily(33);assert.deepEqual(after.pendencias,['pendencia_sintetica_ad15']);assert.equal(after.he_estado,'nao_considerada');assert.equal(after.realizado_minutes,before.realizado_minutes);assert.equal(after.expected_minutes,before.expected_minutes);
 });
 await t.test('AD-15 concurrency: same request confirms once; distinct stale decision refuses atomically',async()=>{
  const payload=await heBody({});const pre=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,false,null]);
  const results=await Promise.all([call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,true,pre.versao]),call(b,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,true,pre.versao])]);assert.deepEqual(results[0],results[1]);assert.equal((await q('SELECT count(*)::int n FROM folha_gestao_historico WHERE request_id=$1',[payload.request_id])).rows[0].n,1);
  const old=await heBody({});const oldPreview=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_disregard',old,false,null]);
  await adminOp('daily_he_validate',{person_id:id(33),date:today,expected_revision:old.expected_revision,reason:'Concorrência legítima'});
  const stable=await snapshot();await assert.rejects(call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_disregard',old,true,oldPreview.versao]),e=>e.code==='40001');assert.deepEqual(await snapshot(),stable);
 });
 await t.test('AD-15 replay revalidates person and source-work tenant',async()=>{
  const saved=await adminOp('daily_he_validate',{person_id:id(33),date:today,expected_revision:(await daily(33)).revision,reason:'Replay seguro'});
  try{await q('UPDATE colaboradores SET empresa_id=$1 WHERE id=$2',[id(2),id(33)]);await assert.rejects(call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',saved.payload,true,saved.preview.versao]),e=>e.code==='42501');}finally{await q('UPDATE colaboradores SET empresa_id=$1 WHERE id=$2',[id(1),id(33)]);}
  try{await q('UPDATE obras SET empresa_id=$1 WHERE id=$2',[id(2),id(100)]);await assert.rejects(call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',saved.payload,true,saved.preview.versao]),e=>e.code==='42501');}finally{await q('UPDATE obras SET empresa_id=$1 WHERE id=$2',[id(1),id(100)]);}
 });

 await t.test('AD-15 person/source-work locks prevent tenant changes during confirm transaction',async()=>{
  const payload=await heBody({});const pre=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,false,null]);
  await a.query('BEGIN');await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',payload,true,pre.versao]);
  await b.query('BEGIN');await b.query("SET LOCAL lock_timeout='250ms'");
  try{await assert.rejects(b.query('UPDATE colaboradores SET empresa_id=$1 WHERE id=$2',[id(2),id(33)]),e=>e.code==='55P03');}finally{await b.query('ROLLBACK');}
  await b.query('BEGIN');await b.query("SET LOCAL lock_timeout='250ms'");
  try{await assert.rejects(b.query('UPDATE obras SET empresa_id=$1 WHERE id=$2',[id(2),id(100)]),e=>e.code==='55P03');}finally{await b.query('ROLLBACK');await a.query('ROLLBACK');}
  assert.equal((await q('SELECT empresa_id FROM colaboradores WHERE id=$1',[id(33)])).rows[0].empresa_id,id(1));
  assert.equal((await q('SELECT empresa_id FROM obras WHERE id=$1',[id(100)])).rows[0].empresa_id,id(1));
 });
 await t.test('AD-15 RLS/direct grants/private helper and SD stay closed',async()=>{
  await assert.rejects(as(a,10,'INSERT INTO folha_gestao_historico(empresa_id,action,entidade_id,ator_id,request_id) VALUES($1,$2,$3,$4,$5)',[id(1),'daily_he_validate',id(33),id(10),id(seq++)]),e=>e.code==='42501');
  await assert.rejects(as(a,10,"UPDATE folha_avaliacoes_diarias SET he_estado='validada' WHERE colaborador_id=$1",[id(33)]),e=>e.code==='42501');
  await assert.rejects(as(a,10,'SELECT folha_privado.diaria_recalcular($1,$2,$3)',[id(33),today,id(seq++)]),e=>e.code==='42501');
  for(const actor of [11,13,14,15,16,18])await assert.rejects(call(a,actor,'fn_folha_diaria_gestao_v2',['daily_he_validate',await heBody({}),false,null]),e=>e.code==='42501');
  const cfg=(await q("SELECT prosecdef,proconfig,proacl::text FROM pg_proc WHERE oid='public.fn_folha_diaria_gestao_v2(text,jsonb,boolean,text)'::regprocedure")).rows[0];assert.equal(cfg.prosecdef,true);assert.deepEqual(cfg.proconfig,['search_path=pg_catalog']);
 });
 await t.test('AD-15 Gestão legitimate decision preserves administrative permissions',async()=>{
  const payload=await heBody({});const pre=await call(a,12,'fn_folha_diaria_gestao_v2',['daily_he_disregard',payload,false,null]);const done=await call(a,12,'fn_folha_diaria_gestao_v2',['daily_he_disregard',payload,true,pre.versao]);assert.equal(done.committed,true);assert.equal(done.result.he_decidido_por,id(12));
 });
 await t.test('AD-15 rollback after use refuses drift without destroying history',async()=>{
  const before=await snapshot();await assert.rejects(q(await read('../supabase/folha_he_tenant_ad15_rollback.sql')),/AD15_DATA_DRIFT/);await q('ROLLBACK');assert.deepEqual(await snapshot(),before);
 });
`;
assert.equal(suite.split(' }finally{for(const c of clients)').length,2);
suite=suite.replace(' }finally{for(const c of clients)',extra+' }finally{for(const c of clients)');
suite=suite.replaceAll('import.meta.url',JSON.stringify(pathToFileURL(base).href));
suite=suite.replace(/import\('([.][.][/][^']+)'\)/g,(_,p)=>'import('+JSON.stringify(new URL(p,pathToFileURL(base)).href)+')');
const folder=fs.mkdtempSync(join(tmpdir(),'primeline-ad15-test-'));const path=join(folder,'suite.mjs');fs.writeFileSync(path,suite);
const result=spawnSync(process.execPath,['--test',path],{stdio:'inherit',env:process.env,windowsHide:true,timeout:300000});
process.exit(result.status??1);
