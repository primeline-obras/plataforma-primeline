import assert from 'node:assert/strict';
import {analyseSheet,daySummary} from '../src/attendance-domain.js';
export async function finalStateAuditCases(t,{q,a,as,auxDo,id}) {
 await t.test('auditoria independente legado-only: origem real, alcance e capacidades',async()=>{
  const person=id(45),date='2026-09-24',work=id(100);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].n,0);
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].n,0);
  const before=(await q('SELECT md5(string_agg(to_jsonb(x)::text,\'|\' ORDER BY id)) h FROM ponto_pessoal_obra x WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].h;
  for(const user of [13,14,15,10]){
   const c=await as(a,user,'SELECT fn_folha_contexto_v2($1,$2) v',[date,work]),r=c.rows.find(x=>x.person_id===person);
   assert.ok(r);assert.equal(r.legacy,true);assert.equal(r.conflict,null);assert.equal(r.sheet,null);
   assert.equal(r.can_write,false);assert.equal(r.can_remove,false);assert.equal(daySummary([r]).complete,true);
   const h=await as(a,user,'SELECT fn_folha_historico_v2($1) v',[{kind:'primeline',person_id:person,date,work_id:work}]);
   assert.equal(h.legacy.length,1);assert.equal(h.events.length,0);assert.equal(h.legacy_interpretation,'original');
   assert.equal(Object.hasOwn(h.legacy[0],'revision'),false);
  }
  const after=(await q('SELECT md5(string_agg(to_jsonb(x)::text,\'|\' ORDER BY id)) h FROM ponto_pessoal_obra x WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].h;
  assert.equal(after,before);
 });
 await t.test('auditoria independente ausência pendente: tipo original e contadores conservados',async()=>{
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-01-03',id(100)]),r=c.rows.find(x=>x.person_id===id(20));
  assert.equal(r.absence.tipo,'falta_injustificada');assert.equal(r.absence.estado,'ausente_pendente');
  assert.equal(r.can_remove,false);assert.equal(c.summary.pending,1);assert.equal(c.summary.complete,false);
  assert.equal(daySummary([r]).pending,1);
  assert.equal((await q('SELECT tipo,estado FROM ausencias WHERE id=$1',[r.absence.id])).rows[0].estado,'ausente_pendente');
 });
 await t.test('auditoria independente: regularização persistida após remoção legítima de férias',async()=>{
  const person=id(34),date='2026-09-25';
  const original=(await q('SELECT to_jsonb(x) v FROM ausencias x WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].v;
  const rev=(await q('SELECT coalesce((SELECT revision FROM folha_ferias_revisoes WHERE colaborador_id=$1),0) r',[person])).rows[0].r;
  assert.equal((await q('SELECT estado FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0].estado,'regularization');
  const before=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[date,id(100)]);
  try{
   await auxDo(10,'vacation_remove',{version:2,request_id:id(94001),person_id:person,dates:[date],expected_revision:rev});
   const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[date,id(100)]);
   const r=c.rows.find(x=>x.person_id===person);
   assert.equal(r.absence,null);assert.equal(r.sheet.state,'regularization');assert.equal(r.conflict,null);
   const clientFacts=analyseSheet({sheet:r.sheet,absence:r.absence,legacy:r.legacy,expectedMinutes:r.expected_minutes});
   // Evidence assertion: current candidate flattens this persistent state.
   assert.equal(clientFacts.state,'registered');assert.equal(daySummary([r]).complete,true);
   assert.equal(c.summary.pending,before.summary.pending-1);assert.equal(c.summary.registered,before.summary.registered+1);
   const management=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[person,'2026-09-01']);
   assert.equal(management.live_facts.sheets.find(s=>s.date===date).state,'regularization');
  }finally{
   await q('INSERT INTO ausencias SELECT * FROM jsonb_populate_record(NULL::public.ausencias,$1::jsonb)',[JSON.stringify(original)]);
  }
 });
}
