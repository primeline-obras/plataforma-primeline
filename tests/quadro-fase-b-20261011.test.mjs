// Reuse the approved current synthetic bootstrap and full operational matrix.
// The expanded suite is written outside Git; localhost disposable PostgreSQL only.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';

const read=p=>readFile(new URL(p,import.meta.url),'utf8');
test('Fase B isolated from frontend and obsolete gates',async()=>{
 const scripts=await Promise.all(['precheck','backup','','postcheck','rollback'].map(x=>read('../supabase/quadro_fase_b_20261011'+(x?'_'+x:'')+'.sql')));
 assert.match(scripts[0],/REPEATABLE READ READ ONLY/);
 assert.match(scripts[3],/REPEATABLE READ READ ONLY/);
 assert.doesNotMatch(scripts.join('\n'),/DROP POLICY|CREATE POLICY|SET ROLE|exigir_validacao\(|primeline_pacote2_gate|consumed_at/);
 assert.doesNotMatch(scripts[2],/GRANT\s/i);
 assert.doesNotMatch(scripts[4],/DELETE FROM public\.|INSERT INTO public\.|DROP TABLE/);
 assert.match(scripts[2],/BACKUP_DRIFT/);
 assert.match(scripts[2],/LEGACY_COLUMN_DML_STILL_GRANTED/);
 const app=await read('../src/app.js');
 const body=app.match(/function canManageWorkforce\(\) \{([\s\S]*?)\n\}/)?.[1];
 assert.ok(body);
 const check=new Function('accessContext','effectiveRole','teamData',body);
 assert.equal(check({profile:{ativo:true}},()=> 'encarregado',{quadroContext:{can_manage_global:true,edit_work_ids:['any']},quadroReady:true}),false);
});

const extension=String.raw`
 const bRead=async suffix=>read('../supabase/quadro_fase_b_20261011'+(suffix?'_'+suffix:'')+'.sql');
 async function encBehavior(){
  const behavior={};
  behavior.context=await context(13,100,today);
  behavior.board=await as(a,13,'SELECT fn_quadro_contexto_v1($1::date,$2::date) v',[today,today]);
  behavior.candidates=await as(a,13,'SELECT fn_folha_pessoas_v2($1::date,$2::uuid) v',[today,id(100)]);
  behavior.addPreview=await call(a,13,'fn_equipa_operar_v2',['team_add',{version:2,date:today,work_id:id(100),request_id:id(900001),people:[member(29)]},false,null]);
  for(const [label,sql,params] of [
   ['teamCompatibilityV1Preview','SELECT fn_quadro_operar_v1($1,$2,false,NULL) v',['alocar',{version:1,request_id:id(900002),colaborador_id:id(29),data:today,obra_id:id(100),tipo_alocacao:'obra',periodo:'dia_inteiro',expected_revision:0}]],
   ['otherWork','SELECT fn_folha_contexto_v2($1,$2) v',[today,id(102)]],
   ['privateMarker','INSERT INTO quadro_escrita_interna DEFAULT VALUES RETURNING colaborador_id v',[]],
   ['directBoardInsert','INSERT INTO quadro_pessoal_alocacao DEFAULT VALUES RETURNING id v',[]],
   ['directBoardUpdate','UPDATE quadro_pessoal_alocacao SET descricao_livre=descricao_livre WHERE false RETURNING id v',[]],
   ['directBoardDelete','DELETE FROM quadro_pessoal_alocacao WHERE false RETURNING id v',[]],
  ]){try{const value=await as(a,13,sql,params);behavior[label]=label.startsWith('directBoard')&&value===undefined?'BLOCKED_NO_CHANGE':'ALLOWED';}catch(e){behavior[label]=label.startsWith('directBoard')&&e.code==='42501'?'BLOCKED_NO_CHANGE':e.code;}}
  return behavior;
 }
 await q('GRANT UPDATE(descricao_livre) ON quadro_pessoal_alocacao TO authenticated WITH GRANT OPTION; GRANT SELECT(descricao_livre) ON quadro_pessoal_alocacao TO authenticated; GRANT INSERT(acao) ON quadro_pessoal_movimentos TO service_role');
 const beforeBehavior=await encBehavior();
 const beforePublicPermissions=(await q("SELECT oid::regprocedure::text signature,has_function_privilege('authenticated',oid,'EXECUTE') allowed FROM pg_proc WHERE pronamespace IN('public'::regnamespace,'folha_privado'::regnamespace) ORDER BY 1")).rows;
 await t.test('B precheck rejects contract drift, unlisted writer, exposed marker and open legacy',async()=>{
  for(const sql of [
   "ALTER FUNCTION fn_equipa_operar_v2(text,jsonb,boolean,text) SECURITY INVOKER",
   "GRANT EXECUTE ON FUNCTION fn_equipa_operar_v2(text,jsonb,boolean,text) TO anon",
   "CREATE FUNCTION fn_unknown_writer() RETURNS void LANGUAGE plpgsql AS $$ BEGIN DELETE FROM quadro_pessoal_alocacao; END $$",
   "GRANT INSERT ON quadro_escrita_interna TO authenticated",
   "ALTER TABLE ponto_pessoal_obra DISABLE TRIGGER trg_01_folha_legacy_closed"
  ]){await q('BEGIN');await q(sql);const check=(await bRead('precheck')).replace(/^BEGIN TRANSACTION.*;$/m,'').replace(/^COMMIT;$/m,'');await assert.rejects(q(check),/CURRENT_CONTRACT_DRIFT|UNINVENTORIED_WRITER|PRIVATE_WRITER_EXPOSED|LEGACY_NOT_CLOSED/);await q('ROLLBACK');}
 });
 await t.test('inherited legacy DML aborts B instead of broadening revocations',async()=>{
  await q('CREATE ROLE local_legacy_dml; GRANT INSERT ON quadro_pessoal_alocacao TO local_legacy_dml; GRANT local_legacy_dml TO authenticated');
  await q(await bRead('precheck'));await q(await bRead('backup'));
  await assert.rejects(q(await bRead('')),/LEGACY_DML_STILL_GRANTED/);await q('ROLLBACK');
  assert.equal((await q('SELECT estado FROM primeline_quadro_rollout.controlo')).rows[0].estado,'a');
  await q('REVOKE local_legacy_dml FROM authenticated; REVOKE INSERT ON quadro_pessoal_alocacao FROM local_legacy_dml; DROP ROLE local_legacy_dml');
  await q('ALTER SCHEMA primeline_quadro_b_20261011 RENAME TO local_inherited_rejected_backup');
 });
 await q(await bRead('precheck'));
 await q(await bRead('backup'));
 await t.test('B rejects stale data and catalog backup atomically',async()=>{
  const guard=(await q("SELECT pg_get_functiondef('fn_quadro_proteger_escrita()'::regprocedure) v")).rows[0].v;
  for(const sql of ["UPDATE obras SET nome=nome||' drift' WHERE id='"+id(100)+"'",'GRANT UPDATE(nome) ON colaboradores TO anon']){
   await q('BEGIN');await q(sql);await assert.rejects(q(await bRead('')),/BACKUP_DRIFT/);await q('ROLLBACK');
   assert.equal((await q("SELECT pg_get_functiondef('fn_quadro_proteger_escrita()'::regprocedure) v")).rows[0].v,guard);
   assert.equal((await q('SELECT estado FROM primeline_quadro_rollout.controlo')).rows[0].estado,'a');
  }
 });
 await q(await bRead(''));
 await q(await bRead('postcheck'));
 await t.test('postcheck rejects exposed private backup and data drift, READ ONLY',async()=>{
  for(const sql of ['GRANT SELECT(singleton) ON primeline_quadro_b_20261011.snapshot TO anon',"UPDATE obras SET nome=nome||' drift' WHERE id='"+id(100)+"'"]){
   await q('BEGIN');await q(sql);const check=(await bRead('postcheck')).replace(/^BEGIN TRANSACTION.*;$/m,'').replace(/^COMMIT;$/m,'');
   await assert.rejects(q(check),/BACKUP_NOT_PRIVATE|OPERATIONAL_DATA_CHANGED/);await q('ROLLBACK');
  }
 });
 await t.test('ENCARREGADO_BEHAVIOR_UNCHANGED = YES; only obsolete RPC loses EXECUTE',async()=>{
  assert.deepEqual(await encBehavior(),beforeBehavior);
  assert.equal(beforeBehavior.teamCompatibilityV1Preview,'ALLOWED'); for(const label of ['directBoardInsert','directBoardUpdate','directBoardDelete'])assert.equal(beforeBehavior[label],'BLOCKED_NO_CHANGE');
  for(const label of ['otherWork','privateMarker'])assert.equal(beforeBehavior[label],'42501');
  const after=(await q("SELECT oid::regprocedure::text signature,has_function_privilege('authenticated',oid,'EXECUTE') allowed FROM pg_proc WHERE pronamespace IN('public'::regnamespace,'folha_privado'::regnamespace) ORDER BY 1")).rows;
  assert.deepEqual(after.filter(x=>x.signature!=='fn_quadro_operar(text,jsonb,boolean,text)'),beforePublicPermissions.filter(x=>x.signature!=='fn_quadro_operar(text,jsonb,boolean,text)'));
 });
 await t.test('all application roles denied old RPC / DML, owner direct DML denied by trigger',async()=>{
  for(const role of ['anon','authenticated','service_role']){
   for(const table of ['quadro_pessoal_alocacao','quadro_pessoal_movimentos'])for(const privilege of ['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'])assert.equal((await q('SELECT has_table_privilege($1,$2,$3) v',[role,table,privilege])).rows[0].v,false);
   assert.equal((await q("SELECT has_function_privilege($1,'fn_quadro_operar(text,jsonb,boolean,text)','EXECUTE') v",[role])).rows[0].v,false);
  }
  await assert.rejects(as(a,12,'SELECT fn_quadro_operar($1,$2,false,NULL) v',['adicionar',{}]),e=>e.code==='42501');
  await assert.rejects(as(a,12,'UPDATE quadro_pessoal_alocacao SET descricao_livre=descricao_livre WHERE false RETURNING id v'),e=>e.code==='42501');
  await q("SELECT set_config('test.actor',$1,false)",[id(12)]);
  await assert.rejects(q('UPDATE quadro_pessoal_alocacao SET descricao_livre=descricao_livre WHERE id=$1',[id(1004)]),e=>e.code==='42501'&&/CONTROLLED_WRITE_REQUIRED/.test(e.message));
 });
 await t.test('exact rollback restores catalog and preserves data; no automatic reinstallation',async()=>{
  const hashes=(await q('SELECT primeline_quadro_b_20261011.data_hashes() v')).rows[0].v;
  await q(await bRead('rollback'));
  assert.deepEqual((await q('SELECT primeline_quadro_b_20261011.data_hashes() v')).rows[0].v,hashes);
  assert.deepEqual(await encBehavior(),beforeBehavior);
  await assert.rejects(q(await bRead('')),/BACKUP_NOT_PREPARED/);await q('ROLLBACK');
  // Keep first local backup intact; create a fresh second local rollout cycle.
  await q('ALTER SCHEMA primeline_quadro_b_20261011 RENAME TO local_first_cycle_backup');
  await q(await bRead('precheck'));await q(await bRead('backup'));await q(await bRead(''));await q(await bRead('postcheck'));
 });
 await t.test('Gestão current Quadro and cadastro writers remain usable after B',async()=>{
  const body={version:1,request_id:id(request++),colaborador_id:id(29),data:'2026-10-01',obra_id:id(100),tipo_alocacao:'obra',periodo:'dia_inteiro',expected_revision:0};
  const p=await call(a,12,'fn_quadro_operar_v1',['alocar',body,false,null]);
  const r=await call(a,12,'fn_quadro_operar_v1',['alocar',body,true,p.versao]);assert.equal(r.version,1);
  assert.deepEqual(await call(a,12,'fn_quadro_operar_v1',['alocar',body,true,p.versao]),r);
  const remove={...body,request_id:id(request++),expected_revision:1,ids:r.allocations.map(x=>x.id)};
  const rp=await call(a,12,'fn_quadro_operar_v1',['remover',remove,false,null]);
  await call(a,12,'fn_quadro_operar_v1',['remover',remove,true,rp.versao]);
  await as(a,12,"SELECT fn_criar_colaborador_com_alocacao('Novo sintético B','Pedreiro',current_date,NULL,'obra',$1) v",[id(100)]);
 });
`;

test('PostgreSQL real local: before/after + complete current Folha regression',{timeout:300000},async()=>{
 assert.ok(process.env.QUADRO_PG_BIN&&process.env.QUADRO_TEST_DEPS,'Local PostgreSQL must be configured; no silent skip');
 const url=new URL('./encarregado-fecho-final.test.mjs',import.meta.url);
 let source=(await readFile(url,'utf8')).replace('new URL(p,import.meta.url)',`new URL(p,${JSON.stringify(url.href)})`);
 const marker=" async function write(action,data,user=13,c=a)";
 assert.equal(source.split(marker).length,2);
 source=source.replace(marker,()=>extension+'\n'+marker);
 // Cadastro test adds an operational row; original invariant now checks originals + that row.
 source=source.replace("assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,227);","assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,228);");
 const end=" await assert.rejects(q(await read('../supabase/encarregado_fecho_final_rollback.sql'))";
 source=source.replace(end,String.raw`
 await t.test('rollback after current writers preserves every new labor fact',async()=>{
  const before=(await q('SELECT primeline_quadro_b_20261011.data_hashes() v')).rows[0].v;
  await q(await bRead('rollback'));
  assert.deepEqual((await q('SELECT primeline_quadro_b_20261011.data_hashes() v')).rows[0].v,before);
  assert.equal((await q('SELECT estado FROM primeline_quadro_rollout.controlo')).rows[0].estado,'a');
 });
`+end);
 const folder=await mkdtemp(join(tmpdir(),'primeline-phase-b-current-'));
 const filename=join(folder,'expanded.test.mjs');await writeFile(filename,source);
 const env={...process.env};delete env.NODE_TEST_CONTEXT;
 const r=spawnSync(process.execPath,['--test',filename],{encoding:'utf8',timeout:270000,windowsHide:true,env});
 const output=(r.stdout||'')+(r.stderr||'');await writeFile(join(folder,'result.log'),output);console.log(output);
 assert.equal(r.status,0,`Local matrix failed: ${folder}`);
 assert.match(output,/ENCARREGADO_BEHAVIOR_UNCHANGED = YES/);
 assert.match(output,/rollback after current writers/);
});
