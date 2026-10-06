import assert from 'node:assert/strict';
import {setTimeout as delay} from 'node:timers/promises';
import {readFile} from 'node:fs/promises';
export async function securityVisibilityCases(t,{q,a,b,as,aux,auxDo,id}) {
 let seq=920000;const data=x=>({version:2,request_id:id(seq++),expected_revision:0,...x});
 const context=actor=>as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);
 const forbidden=/processado_em|processado_por|prazo_processamento|he_process|he_validate|configure_he_eligibility/;
 await t.test('HE: exact operational projection, administrative projection and history, no raw processing leak',async()=>{
  const stored=(await q('SELECT * FROM folha_he WHERE processado_em IS NOT NULL')).rows;assert.ok(stored.length);
  for(const actor of [14,15]) {
   const c=await context(actor);assert.ok(c.overtime.length);assert.doesNotMatch(JSON.stringify(c),forbidden);
   for(const h of c.overtime)assert.deepEqual(Object.keys(h).sort(),['id','obra_id','folha_id','folha_revision','minutes','estado','revision','sheet','person_name'].sort());
   assert.ok(c.history.some(x=>x.action==='he_approve'));for(const e of c.history.filter(x=>x.dominio==='he'))assert.doesNotMatch(JSON.stringify([e.antes,e.depois]),forbidden);
  }
  for(const actor of [10,11,12]){const c=await context(actor);assert.ok(c.overtime.some(x=>x.processado_em));assert.ok(c.history.some(x=>x.action==='he_process'&&x.dominio==='administrativo'));}
  assert.deepEqual((await context(13)).overtime,[]);assert.doesNotMatch(JSON.stringify((await context(13)).history),forbidden);
 });
 await t.test('HE: raw day/history and operational preview, response, replay contain no administrative fields',async()=>{
  const f=(await q('SELECT f.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE h.processado_em IS NOT NULL LIMIT 1')).rows[0];
  for(const actor of [14,15,13]){const c=await as(a,actor,'SELECT fn_folha_contexto_v2($1,$2) v',[f.data,id(100)]);assert.doesNotMatch(JSON.stringify(c),forbidden);const h=await as(a,actor,'SELECT fn_folha_historico_v2($1) v',[{kind:'primeline',person_id:f.colaborador_id,work_id:id(100),date:f.data}]);assert.doesNotMatch(JSON.stringify(h),forbidden);}
  await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'HE sintética','Pedreiro','2020-01-01')",[id(21001),id(1)]);
  await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,'2026-09-14','2026-09-18','dia_inteiro',$4)",[id(seq++),id(21001),id(100),id(10)]);
  const sd=data({work_id:id(100),date:'2026-09-18',key:{kind:'primeline',person_id:id(21001),work_id:id(100),date:'2026-09-18'},intervals:[{start:'08:00',end:'17:00'}],reason:'Horas reais sintéticas'});
  const sp=await as(a,10,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['save',sd]);await as(a,10,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['save',sd,sp.versao]);
  const h=(await q("SELECT h.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1 AND h.estado='potential'",[id(21001)])).rows[0];assert.ok(h);
  const d=data({id:h.id,expected_revision:h.revision});const p=await aux(15,'he_reject',d);assert.doesNotMatch(JSON.stringify(p),forbidden);
  const r=await aux(15,'he_reject',d,true,p.versao);assert.doesNotMatch(JSON.stringify(r),forbidden);assert.deepEqual(await aux(15,'he_reject',d,true,p.versao),r);
 });
 await t.test('HE: administrative replay denied after role/active permission loss; processing alerts have private recipient and no obra/email',async()=>{
  for(const action of ['he_validate','he_process']){
   const event=(await q('SELECT * FROM folha_gestao_historico WHERE action=$1 AND ator_id=$2 ORDER BY at LIMIT 1',[action,id(10)])).rows[0];assert.ok(event);
   const d={version:2,request_id:event.request_id,id:event.entidade_id,expected_revision:event.antes.revision};
   for(const role of ['diretor_obra','adjunto','encarregado']){await q('UPDATE utilizadores SET funcao=$2 WHERE id=$1',[id(10),role]);try{await assert.rejects(aux(10,action,d,true,'unused'),e=>e.code==='42501');}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}}
   await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(10)]);try{await assert.rejects(aux(10,action,d,true,'unused'),e=>e.code==='42501');}finally{await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(10)]);}
  }
  const alerts=(await q("SELECT a.obra_id,a.enviar_email,u.funcao,u.empresa_id=a.empresa_id same FROM alertas a JOIN utilizadores u ON u.id=a.destinatario_utilizador_id WHERE a.tipo='folha_he_processamento'")).rows;
  assert.ok(alerts.length);assert.ok(alerts.every(x=>x.obra_id===null&&!x.enviar_email&&x.funcao==='administrativo'&&x.same));
  const catalog=JSON.parse(await readFile(new URL('./fixtures/encarregado-catalogo-real-20261004.json',import.meta.url),'utf8'));
  const helpers=['fn_e_financeiro()','fn_pode_ver_obra(uuid)'];const previous=new Map();
  for(const sig of helpers)previous.set(sig,(await q('SELECT CASE WHEN to_regprocedure($1) IS NULL THEN NULL ELSE pg_get_functiondef(to_regprocedure($1)) END d',[sig])).rows[0].d);
  const oldRls=(await q("SELECT relrowsecurity FROM pg_class WHERE oid='public.alertas'::regclass")).rows[0].relrowsecurity;
  // Commit local DDL before querying from the other connection; an open DDL transaction would block its SELECT.
  try{
   await q(catalog.details.definitions['fn_e_financeiro()']);await q(catalog.details.definitions['fn_pode_ver_obra(uuid)']);await q('ALTER TABLE public.alertas ENABLE ROW LEVEL SECURITY');
   for(const p of catalog.catalog.tables.find(x=>x.name==='alertas').policies){const cmd={'*':'ALL',r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE'}[p.cmd];await q(`CREATE POLICY "${p.name}" ON alertas FOR ${cmd} TO authenticated${p.using?' USING('+p.using+')':''}${p.check?' WITH CHECK('+p.check+')':''}`);}
   for(const actor of [13,14,15])assert.equal(await as(a,actor,"SELECT count(*)::int v FROM alertas WHERE tipo='folha_he_processamento'"),0);
   assert.ok(await as(a,10,"SELECT count(*)::int v FROM alertas WHERE tipo='folha_he_processamento'")>0);
  }finally{
   for(const p of catalog.catalog.tables.find(x=>x.name==='alertas').policies)await q(`DROP POLICY IF EXISTS "${p.name}" ON alertas`);
   if(!oldRls)await q('ALTER TABLE public.alertas DISABLE ROW LEVEL SECURITY');
   for(const sig of helpers){if(previous.get(sig))await q(previous.get(sig));else await q('DROP FUNCTION '+sig);}
  }
 });
 const date='2026-09-19',person=id(21000);await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Review sintético','Pedreiro','2020-01-01')",[person,id(1)]);
 await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,'2026-09-14',$4,'dia_inteiro',$5)",[id(seq++),person,id(100),date,id(10)]);
 const saveData=revision=>data({work_id:id(100),date,key:{kind:'primeline',person_id:person,work_id:id(100),date},expected_revision:revision,intervals:[{start:'09:00',end:'17:00'}],reason:'Correção sintética de factos'});
 const raw=(client,d,confirmed=false,token=null)=>as(client,10,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',['save',d,confirmed,token]);
 async function save(d){const p=await raw(a,d);return raw(a,d,true,p.versao);}
 const row=async()=>(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0];
 const daily=async()=>{const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[date,id(100)]);return {c,r:c.rows.find(x=>x.person_id===person)};};
 const payroll=()=>as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[person,'2026-09-01']);
 let pendingBeforeReview;await save(saveData(0));
 await t.test('special day: unreviewed factual state, pending counter and payroll parity; unauthorized review denied',async()=>{
  const {c,r}=await daily();assert.equal(r.special_day,true);assert.equal(r.special_reviewed,false);assert.equal(r.special_review_pending,true);assert.equal(r.overtime.estado,'pending_rule');assert.equal(c.summary.complete,false);assert.ok(c.summary.pending>=1);
  pendingBeforeReview=c.summary.pending;
  assert.equal((await payroll()).live_facts.sheets[0].special_reviewed,false);
  const f=await row();for(const actor of [11,12,13,14,15,16])await assert.rejects(aux(actor,'special_review',data({id:f.id,expected_revision:f.revision})),e=>e.code==='42501');
 });
 await t.test('special day: review succeeds with truthful before/after metadata, idempotence, actor/date/request/revision',async()=>{
  const f=await row(),d=data({id:f.id,expected_revision:f.revision});const res=await auxDo(10,'special_review',d);assert.deepEqual(await auxDo(10,'special_review',d),res);
  const {c,r}=await daily();assert.equal(r.special_reviewed,true);assert.equal(r.special_review_pending,false);assert.equal(r.overtime.estado,'none');assert.equal(c.summary.pending,pendingBeforeReview-1);assert.equal(c.summary.complete,c.summary.pending===0);assert.equal((await payroll()).live_facts.sheets[0].special_reviewed,true);
  const e=(await q("SELECT * FROM folha_gestao_historico WHERE request_id=$1 AND action='special_review'",[d.request_id])).rows;assert.equal(e.length,1);assert.equal(e[0].antes.special_reviewed_at,null);assert.ok(e[0].depois.special_reviewed_at);assert.equal(e[0].depois.special_reviewed_by,id(10));assert.equal(e[0].depois.revision,f.revision+1);assert.equal(e[0].ator_id,id(10));assert.ok(e[0].at);assert.equal(e[0].dominio,'administrativo');
 });
 await t.test('special day: factual edit invalidates review and keeps previous evidence/history; payroll becomes pending',async()=>{
  const f=await row(),d={...saveData(f.revision),intervals:[{start:'08:00',end:'16:00'}]};await save(d);
  const {r}=await daily();assert.equal(r.special_reviewed,false);assert.equal(r.special_review_pending,true);assert.equal(r.overtime.estado,'pending_rule');assert.equal((await payroll()).live_facts.sheets[0].special_reviewed,false);
  const e=(await q("SELECT * FROM folha_historico WHERE request_id=$1 AND action='save'",[d.request_id])).rows[0];assert.ok(e.antes.special_reviewed_at);assert.equal(e.depois.special_reviewed_at,null);
  assert.ok((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE entidade_id=$1 AND action='special_review'",[f.id])).rows[0].n>=1);
 });
 await t.test('special day: review versus concurrent edit serializes; stale review refused',async()=>{
  let f=await row();const edit=saveData(f.revision),preview=await raw(b,edit);
  await a.query('BEGIN');await auxDo(10,'special_review',data({id:f.id,expected_revision:f.revision}));
  const waiting=raw(b,edit,true,preview.versao).then(value=>({value}),error=>({error}));await delay(50);await a.query('COMMIT');assert.equal((await waiting).error?.code,'40001');
  f=await row();const review=data({id:f.id,expected_revision:f.revision});await aux(10,'special_review',review);
  const edit2={...saveData(f.revision),intervals:[{start:'07:00',end:'15:00'}]},p=await raw(b,edit2);await b.query('BEGIN');await raw(b,edit2,true,p.versao);
  const waiting2=aux(10,'special_review',review).then(value=>({value}),error=>({error}));await delay(50);await b.query('COMMIT');assert.equal((await waiting2).error?.code,'40001');assert.equal((await daily()).r.special_reviewed,false);
 });
 await t.test('special day: absence reconciliation also invalidates review, with preserved before/after',async()=>{
  const f=await row();await auxDo(10,'special_review',data({id:f.id,expected_revision:f.revision}));
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'baixa_parental','confirmada')",[id(seq++),person,date]);
  const {r}=await daily();assert.equal(r.sheet.state,'regularization');assert.equal(r.special_reviewed,false);assert.equal(r.special_review_pending,true);assert.equal((await payroll()).live_facts.sheets[0].special_reviewed,false);
  const e=(await q("SELECT * FROM folha_historico WHERE person_id=$1 AND action='reconcile' ORDER BY revision DESC LIMIT 1",[person])).rows[0];assert.ok(e.antes.special_reviewed_at);assert.equal(e.depois.special_reviewed_at,null);
 });
}
