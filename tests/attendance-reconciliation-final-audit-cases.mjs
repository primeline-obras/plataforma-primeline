import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {analyseSheet,daySummary} from '../src/attendance-domain.js';

export async function reconciliationFinalAudit(t,{q,a,as,call,auxDo,id}){
 const p=id(29),w=id(100),dates=['2026-09-14','2026-09-15','2026-09-16'];let seq=97000;
 const req=()=>id(seq++),evidence=[];
 const full=[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}];
 const read=async d=>(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[p,d])).rows[0];
 const parity=async(d,state,label)=>{
  const stored=await read(d),c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[d,w]),r=c.rows.find(r=>r.person_id===p);
  const monthly=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[p,'2026-09-01']);
  assert.equal(stored.estado,state);assert.equal(r.sheet.state,state);assert.equal(monthly.live_facts.sheets.find(s=>s.id===stored.id).state,state);
  const facts=analyseSheet({sheet:r.sheet,absence:r.absence,legacy:r.legacy,expectedMinutes:r.expected_minutes});
  assert.equal(facts.state,state);assert.equal(daySummary([r]).complete,state==='registered');
  assert.equal(c.rows.length,1);assert.equal(c.summary.pending,state==='registered'?0:1);assert.equal(c.summary.complete,state==='registered');
  const v=monthly.payroll.find(v=>v.competencia==='2026-09-01');if(v)assert.equal(v.factos.sheets.find(s=>s.id===stored.id).state,state);
  evidence.push({label,state,context:c});return stored;
 };
 const vacation=async(action,days,extra={})=>{
  const revision=(await q('SELECT coalesce((SELECT revision FROM folha_ferias_revisoes WHERE colaborador_id=$1),0) r',[p])).rows[0].r;
  const data={version:2,request_id:req(),person_id:p,dates:days,expected_revision:revision,admin_override:true,...extra};
  await auxDo(10,action,data);return data;
 };
 await t.test('auditoria independente: preparar folhas distintas sem dados ou referências reais',async()=>{
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1',[p])).rows[0].n,0);
  for(const [i,d] of dates.entries()){
   const allocation={version:2,request_id:req(),work_id:w,date:d,person_id:p,period:'dia_inteiro',expected_allocation_revision:0};
   let preview=await call(a,10,'allocate',allocation);await call(a,10,'allocate',allocation,true,preview.versao);
   const data={version:2,request_id:req(),work_id:w,date:d,key:{person_id:p,work_id:w,date:d,kind:'primeline'},expected_revision:0,intervals:i===0?full:i===1?[{start:'09:00',end:'16:00'}]:[{start:'09:00',end:null}]};
   preview=await call(a,10,'save',data);await call(a,10,'save',data,true,preview.versao);
   assert.equal((await read(d)).expected_minutes,480);
  }
  await auxDo(10,'payroll_save',{version:2,request_id:req(),person_id:p,month:'2026-09-01',expected_revision:0,manual:{premium:0,km:0,allowance:0,note:'Independent synthetic audit'}});
 });
 await t.test('auditoria independente P2/inverso: registered → férias → regularization → registered em todas as camadas',async()=>{
  const d=dates[0],before=await parity(d,'registered','initial');await vacation('vacation_set',[d]);
  const blocked=await parity(d,'regularization','vacation added');assert.equal(blocked.revision,before.revision+1);
  const operation=await vacation('vacation_remove',[d]);const restored=await parity(d,'registered','vacation removed');
  assert.equal(restored.revision,before.revision+2);assert.deepEqual(restored.intervals,before.intervals);assert.equal(restored.minutes,before.minutes);
  const event=(await q('SELECT * FROM folha_historico WHERE request_id=$1',[operation.request_id])).rows;
  assert.equal(event.length,1);assert.equal(event[0].ator_id,id(10));assert.equal(event[0].revision,restored.revision);assert.ok(event[0].at);
  assert.equal(event[0].origem,'vacation_reconciliation');assert.equal(event[0].antes.estado,'regularization');assert.equal(event[0].depois.estado,'registered');
  assert.ok((await q("SELECT 1 FROM folha_gestao_historico WHERE request_id=$1 AND action='vacation_remove'",[operation.request_id])).rowCount);
  assert.ok((await q("SELECT 1 FROM folha_gestao_historico WHERE request_id=$1 AND action='payroll_reconcile'",[operation.request_id])).rowCount);
 });
 await t.test('auditoria independente A–C/E: replace multidata mantém full/missing/open distintos',async()=>{
  await vacation('vacation_replace',dates,{scope_dates:dates});for(const d of dates)await parity(d,'regularization','multidate vacation');
  await vacation('vacation_replace',[],{scope_dates:dates});
  for(const [i,d] of dates.entries())await parity(d,['registered','missing','open'][i],['full restored','short restored','open restored'][i]);
 });
 await t.test('auditoria independente G–I: ausência pendente, justificação e remoção não inventam presença',async()=>{
  const d=dates[1],absence=req();await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'falta_injustificada','ausente_pendente')",[absence,p,d]);await parity(d,'regularization','pending absence with work');
  await q("UPDATE ausencias SET estado='justificada' WHERE id=$1",[absence]);await parity(d,'regularization','justified absence with work');
  assert.equal((await q('SELECT tipo FROM ausencias WHERE id=$1',[absence])).rows[0].tipo,'falta_injustificada');
  await q('DELETE FROM ausencias WHERE id=$1',[absence]);await parity(d,'missing','absence removed short work');
 });
 await t.test('auditoria independente: referências históricas e ACL permanecem factuais',async()=>{
  for(const d of dates)assert.equal((await read(d)).expected_minutes,480);
  const c=(await q("SELECT count(*)::int n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' AND (p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog'] OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'))")).rows[0].n;assert.equal(c,0);
  const folder=path.join(tmpdir(),'primeline-reconciliation-final-audit');await mkdir(folder,{recursive:true});
  await writeFile(path.join(folder,'synthetic-contexts.json'),JSON.stringify(evidence,null,2),'utf8');
 });
}
