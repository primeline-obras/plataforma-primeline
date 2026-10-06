import assert from 'node:assert/strict';
import {analyseSheet,daySummary,normalDaySelection} from '../src/attendance-domain.js';
export async function visibleStateCases(t,{q,a,as,call,id}) {
 const work=id(100),date='2026-09-24';
 const context=(user=13,w=work,d=date)=>as(a,user,'SELECT fn_folha_contexto_v2($1,$2) v',[d,w]);
 await t.test('legado: reader mínimo para Encarregado, Diretor/Adjunto e Administrativo',async()=>{
  for(const user of [13,14,15,10]){
   const c=await context(user),r=c.rows.find(x=>x.person_id===id(45));
   assert.equal(r.legacy,true);assert.equal(r.sheet,null);assert.equal(r.conflict,null);
   assert.equal(r.can_write,false);assert.equal(r.can_remove,false);
   assert.equal(Object.hasOwn(r,'legacy_details'),false);assert.doesNotMatch(JSON.stringify(r),/PRIVATE_SENTINEL|observacao|entrada_manha/);
   const key={kind:'primeline',person_id:r.person_id,work_id:work,date};
   const h=await as(a,user,'SELECT fn_folha_historico_v2($1) v',[key]);assert.equal(h.legacy.length,1);assert.equal(h.events.length,0);
  }
 });
 await t.test('legado: só outra obra/empresa não entram; nenhum anterior herdado',async()=>{
  assert.equal((await context(10,id(101))).rows.some(r=>r.person_id===id(45)),false);
  assert.equal((await context(10,work,'2026-09-23')).rows.some(r=>r.person_id===id(45)),false);
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await q("INSERT INTO ponto_pessoal_obra(id,empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES($1,$2,$3,$4,$5,'presente',$6)",[id(92001),id(2),work,id(49),date,id(17)]);
  try{assert.equal((await context()).rows.some(r=>r.person_id===id(49)),false);}
  finally{await q('DELETE FROM ponto_pessoal_obra WHERE id=$1',[id(92001)]);}
 });
 await t.test('legado: tentativa direta V2 recusada sem alocação, bulk e retirada recusados',async()=>{
  const key={kind:'primeline',person_id:id(45),work_id:work,date};
  const d={version:2,request_id:id(92002),date,work_id:work,key,expected_revision:0,intervals:[{start:'09:00',end:'13:00'}]};
  await assert.rejects(call(a,10,'save',d),/LEGACY_CONFLICT/);
  await assert.rejects(call(a,10,'bulk',{...d,request_id:id(92003),operation:'normal',items:[{key,expected_revision:0,intervals:d.intervals}]}),/LEGACY_CONFLICT|NORMAL_DAY_CONFLICT/);
  await assert.rejects(call(a,10,'remove_from_day',{version:2,request_id:id(92004),date,work_id:work,person_id:id(45),expected_allocation_revision:0,ids:[]}),/REGULARIZATION_REQUIRED/);
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(45),date])).rows[0].n,0);
 });
 await t.test('legado noutro local não habilita escrita que o writer já recusa',async()=>{
  await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,periodo,semana_inicio,tipo_alocacao) VALUES($1,$2,$3,$4,'dia_inteiro','2026-09-21','obra')",[id(92011),id(45),id(101),date]);
  try{
   const r=(await context(10,id(101))).rows.find(r=>r.person_id===id(45));
   assert.equal(r.legacy,false);assert.equal(r.conflict,'LEGACY_WRITER_BLOCKED');assert.equal(r.can_write,false);assert.equal(r.can_remove,false);
   assert.equal(r.sheet,null);assert.equal(Object.hasOwn(r,'legacy_details'),false);
  }finally{await q('DELETE FROM quadro_pessoal_alocacao WHERE id=$1',[id(92011)]);}
 });
 await t.test('legado + V2 mesma chave: conflito real; só V2 sem alocação continua visível',async()=>{
  // Owner seeds a pre-existing incoherence in the local fixture; no RPC creates it.
  for(const [row,person,request] of [[92005,45,92006],[92007,46,92008]])
   await q("INSERT INTO folha_registos(id,empresa_id,obra_id,tipo_local,data,colaborador_id,intervals,minutes,estado,special_day,revision,criado_por,atualizado_por,request_id) VALUES($1,$2,$3,'obra',$4,$5,$8::jsonb,0,'open',false,1,$6,$6,$7)",[id(row),id(1),work,date,id(person),id(10),id(request),JSON.stringify([{start:'09:00',end:null}])]);
  try{
   const c=await context(),both=c.rows.find(r=>r.person_id===id(45)),v2=c.rows.find(r=>r.person_id===id(46));
   assert.equal(both.conflict,'LEGACY_CONFLICT');assert.equal(both.can_write,false);assert.equal(daySummary([both]).pending,1);
   assert.equal(v2.legacy,false);assert.equal(v2.conflict,null);assert.ok(v2.sheet);
  }finally{await q('DELETE FROM folha_registos WHERE id=ANY($1::uuid[])',[[id(92005),id(92007)]]);}
 });
 await t.test('ausência pendente: resumo backend/cliente, bulk e retirada bloqueados',async()=>{
  const c=await context(13,work,'2026-01-03'),r=c.rows.find(r=>r.person_id===id(20));
  assert.equal(r.absence.estado,'ausente_pendente');assert.equal(c.summary.pending,1);assert.equal(c.summary.complete,false);
  assert.equal(daySummary([r]).pending,1);assert.equal(r.can_remove,false);
  const key={kind:'primeline',person_id:r.person_id,work_id:work,date:'2026-01-03'},d={version:2,date:key.date,work_id:work,request_id:id(92009)};
  await assert.rejects(call(a,10,'bulk',{...d,operation:'normal',items:[{key,expected_revision:r.revision,intervals:[{start:'09:00',end:'13:00'}]}]}),/ABSENCE_CONFLICT/);
  await assert.rejects(call(a,10,'remove_from_day',{...d,request_id:id(92010),person_id:r.person_id,expected_allocation_revision:r.allocation_revision,ids:r.allocation_ids}),/REGULARIZATION_REQUIRED/);
  assert.equal(normalDaySelection([r],{schedule:null,date:key.date,now:{date:key.date,time:'18:00'},admin:true}).eligible.length,0);
  assert.equal(analyseSheet({absence:r.absence,sheet:{intervals:[{start:'09:00',end:'13:00'}]}}).state,'regularization');
 });
 await t.test('ausências resolvidas, férias e legado: zero pendências fictícias no domínio',()=>{
  for(const estado of ['confirmada','justificada'])assert.equal(daySummary([{absence:{tipo:'falta_justificada',estado}}]).complete,true);
  assert.equal(analyseSheet({absence:{tipo:'ferias',estado:'confirmada'}}).state,'vacation');
  assert.equal(daySummary([{legacy:true,sheet:null}]).complete,true);
  const normal=normalDaySelection([{person_id:'legacy',legacy:true,can_write:true}],{schedule:null,date,now:{date,time:'18:00'},admin:true});
  assert.equal(normal.eligible.length,0);assert.equal(normal.excluded[0].reason,'Registo legado');
 });
}
