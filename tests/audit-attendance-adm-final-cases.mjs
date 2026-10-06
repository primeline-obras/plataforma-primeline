// Independent audit of the exact candidate. Synthetic PostgreSQL only; no product changes.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
export async function auditAdmFinalCases(t,{q,a,b,as,aux,auxDo,id,today}) {
 let sequence=970000;const request=()=>id(sequence++);
 const data=x=>({version:2,request_id:request(),expected_revision:0,...x});
 const raw=(connection,actor,action,d,commit=false,token=null)=>as(connection,actor,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',[action,d,commit,token]);
 const auxOn=(connection,actor,action,d,commit=false,token=null)=>as(connection,actor,'SELECT fn_folha_gestao_v2($1,$2,$3,$4) v',[action,d,commit,token]);
 const save=async(actor,d)=>{const p=await raw(a,actor,'save',d);return raw(a,actor,'save',d,true,p.versao);};
 const config=(await q('SELECT to_jsonb(x) c FROM folha_config_empresa x WHERE empresa_id=$1',[id(1)])).rows[0].c;
 await q('UPDATE folha_config_empresa SET calendar_complete=true,calendar_validated_years=ARRAY[2026],holiday_dates=ARRAY[\'2026-09-09\'::date] WHERE empresa_id=$1',[id(1)]);
 for(let n=26000;n<=26007;n++)await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Synthetic audit ADM','Cargo sem HE','2020-01-01')",[id(n),id(1)]);
 const allocate=(n,d)=>q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,date_trunc('week',$4::date)::date,$4,'dia_inteiro',$5)",[request(),id(n),id(100),d,id(10)]);
 const body=(n,d,revision=0)=>data({work_id:id(100),date:d,key:{kind:'primeline',person_id:id(n),work_id:id(100),date:d},expected_revision:revision,intervals:[{start:'01:00',end:'03:00'},{start:'04:00',end:'10:00'}],reason:'Synthetic audit correction'});
 const ago=n=>new Date(Date.parse(today+'T12:00:00Z')-n*86400000).toISOString().slice(0,10);
 await t.test('independent ADM: window A–H changes actual intervals and preserves complete history',async()=>{
  for(const [n,days] of [[26000,0],[26001,1],[26002,2]])await allocate(n,ago(days));
  for(const [n,days] of [[26000,0],[26001,1]]){
   const d={...body(n,ago(days)),intervals:[{start:'00:00',end:'00:01'}],reason:null};await save(13,d);
   await save(13,{...d,request_id:request(),expected_revision:1,intervals:[{start:'00:00',end:'00:02'}]});
  }
  await assert.rejects(raw(a,13,'save',body(26002,ago(2))),/CORRECTION_WINDOW_EXCEEDED/);
  await assert.rejects(raw(a,10,'save',{...body(26002,ago(2)),reason:null}),/CORRECTION_REASON_REQUIRED/);
  await save(10,body(26002,ago(2)));
  const corrected={...body(26002,ago(2),1),intervals:[{start:'02:00',end:'05:00'},{start:'06:00',end:'11:00'}]};await save(10,corrected);
  const history=(await q('SELECT * FROM folha_historico WHERE person_id=$1 ORDER BY revision',[id(26002)])).rows;
  assert.equal(history.length,2);const h=history[1];assert.equal(h.revision,2);assert.equal(h.ator_id,id(10));assert.equal(h.request_id,corrected.request_id);assert.ok(h.at);assert.equal(h.reason,corrected.reason);
  assert.deepEqual(h.antes.intervals,[{start:'01:00',end:'03:00'},{start:'04:00',end:'10:00'}]);assert.deepEqual(h.depois.intervals,corrected.intervals);
 });
 await t.test('independent ADM: missing factual hours stay pending in day summary and payroll, never absence',async()=>{
  const date='2026-09-03';await allocate(26003,date);await save(10,{...body(26003,date),intervals:[{start:'09:00',end:'12:00'}]});
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[date,id(100)]),r=c.rows.find(x=>x.person_id===id(26003));assert.equal(r.sheet.state,'missing');assert.ok(c.summary.pending>0);assert.equal(c.summary.complete,false);
  const p=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[id(26003),'2026-09-01']);assert.equal(p.live_facts.sheets.find(x=>x.date===date).state,'missing');
  assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(26003)])).rows[0].n,0);
 });
 await t.test('independent ADM: office demands real intervals; surplus never creates HE',async()=>{
  const date='2026-09-04',d={...body(26004,date),work_id:null,key:{kind:'primeline',person_id:id(26004),work_id:null,date},intervals:[{start:'01:15',end:'12:15'}]};
  await assert.rejects(raw(a,10,'save',{...d,intervals:undefined,hours:11}),/VALIDATION_ERROR|interval|INVALID/);
  await save(10,d);const f=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(26004)])).rows[0];assert.equal(f.minutes,660);assert.deepEqual(f.intervals,d.intervals);
  assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id=$1',[f.id])).rows[0].n,0);
 });
 await t.test('independent ADM: Mon–Fri five, weekends zero, known holiday zero, unknown calendar not claimed',async()=>{
  const d=data({person_id:id(26005),from:'2026-09-14',to:'2026-09-18'});const five=await auxDo(10,'vacation_set',d);assert.equal(five.result.consumed_days,5);
  const zero=await auxDo(10,'vacation_set',data({person_id:id(26006),dates:['2026-09-09','2026-09-12','2026-09-13']}));assert.equal(zero.result.consumed_days,0);
  assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(26006)])).rows[0].n,0);
  await assert.rejects(aux(10,'vacation_set',data({person_id:id(26006),dates:['2026-09-14'],hours:4})),/VACATION_FULL_DAYS_ONLY/);
  await q('UPDATE folha_config_empresa SET calendar_validated_years=ARRAY[]::integer[] WHERE empresa_id=$1',[id(1)]);
  try{const x=await auxDo(10,'vacation_set',data({person_id:id(26006),dates:['2026-09-14'],expected_revision:1}));assert.equal(x.result.consumed_days,null);assert.equal(x.result.calendar_pending,true);assert.equal(x.result.pending_rule,false);assert.equal((await q('SELECT folha_privado.prazo_he($1,$2) d',[id(1),'2026-09-01'])).rows[0].d,null);}finally{await q('UPDATE folha_config_empresa SET calendar_validated_years=ARRAY[2026] WHERE empresa_id=$1',[id(1)]);}
 });
 await t.test('independent ADM: all new privileged actions deny replay after current permission reduction',async()=>{
  for(const action of ['absence_confirm','special_review','configure_he_eligibility','he_validate','he_process','payroll_validate','payroll_close','payroll_reopen']){
   const op=(await q("SELECT payload,token FROM folha_privado.operacoes WHERE ator_id=$1 AND payload->>'action'=$2 ORDER BY criado_em DESC LIMIT 1",[id(10),action])).rows[0];assert.ok(op,action);
   await q("UPDATE utilizadores SET funcao='gestao_plataforma' WHERE id=$1",[id(10)]);
   try{await assert.rejects(aux(10,action,op.payload.data,true,op.token),e=>e.code==='42501');}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
  }
 });
 await t.test('independent ADM: permission reduction between preview and confirmation denies new action',async()=>{
  const revision=(await q('SELECT revision FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0].revision;
  const d=data({roles:['pedreiro','servente'],expected_revision:revision}),p=await aux(10,'configure_he_eligibility',d);
  await q("UPDATE utilizadores SET funcao='gestao_plataforma' WHERE id=$1",[id(10)]);
  try{await assert.rejects(aux(10,'configure_he_eligibility',d,true,p.versao),e=>e.code==='42501');assert.equal((await q('SELECT revision FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0].revision,revision);}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
 });
 await t.test('independent ADM: two corrections concurrent, one commit and one stale result',async()=>{
  const date=ago(2),d1=body(26002,date,2),d2={...body(26002,date,2),intervals:[{start:'02:30',end:'10:30'}]};
  const p1=await raw(a,10,'save',d1),p2=await raw(b,10,'save',d2);
  const results=await Promise.allSettled([raw(a,10,'save',d1,true,p1.versao),raw(b,10,'save',d2,true,p2.versao)]);
  assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.match(results.find(x=>x.status==='rejected').reason.message,/STALE_REVISION|STALE_PREVIEW/);
  assert.equal((await q('SELECT revision FROM folha_registos WHERE colaborador_id=$1',[id(26002)])).rows[0].revision,3);
  assert.equal((await q('SELECT count(*)::int n FROM folha_historico WHERE person_id=$1',[id(26002)])).rows[0].n,3);
 });
 await t.test('independent ADM: monthly close concurrent, one receipt/history, replay no duplication',async()=>{
  const date='2026-09-04';await allocate(26007,date);await save(10,body(26007,date));
  await auxDo(10,'payroll_save',data({person_id:id(26007),month:'2026-09-01',manual:{km:0,allowance:0,note:'Manual synthetic'}}));
  await auxDo(10,'payroll_validate',data({person_id:id(26007),month:'2026-09-01',expected_revision:1}));
  const d1=data({person_id:id(26007),month:'2026-09-01',expected_revision:2}),d2={...d1,request_id:request()};const p1=await auxOn(a,10,'payroll_close',d1),p2=await auxOn(b,10,'payroll_close',d2);
  const results=await Promise.allSettled([auxOn(a,10,'payroll_close',d1,true,p1.versao),auxOn(b,10,'payroll_close',d2,true,p2.versao)]);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);
  const v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(26007)])).rows[0];assert.equal(v.revision,3);assert.ok(v.recibos_recebidos_em);assert.equal(v.recibos_recebidos_por,id(10));
  assert.equal((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE entidade_id=$1 AND action='payroll_close'",[v.id])).rows[0].n,1);
  const index=results.findIndex(x=>x.status==='fulfilled');assert.deepEqual(await auxOn(a,10,'payroll_close',index===0?d1:d2,true,index===0?p1.versao:p2.versao),results[index].value);
 });
 await t.test('independent ADM: raw JSON excludes balances, payroll and documents from operational roles',async()=>{
  for(const actor of [13,14,15]){
   const c=await as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);
   for(const key of ['people','live_facts','config','entitlements','vacations','payroll','absences'])assert.equal(Object.hasOwn(c,key),false,actor+':'+key);
   await assert.rejects(as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,$2,$3) v',[id(100),id(26007),'2026-09-01']),e=>e.code==='42501');
   if(actor===13)assert.deepEqual(c.overtime,[]);
  }
 });
 await t.test('independent ADM REQUIRED: reviewed special day no longer claims a pending review',async()=>{
  const row=(await q('SELECT id,revision,data::text d FROM folha_registos WHERE colaborador_id=$1 AND special_day AND special_reviewed_at IS NOT NULL ORDER BY data LIMIT 1',[id(20007)])).rows[0];assert.ok(row);
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[row.d,id(100)]),r=c.rows.find(x=>x.person_id===id(20007));assert.equal(r.special_review_pending,false);
  assert.notEqual(r.overtime.estado,'pending_rule','reviewed fact still projected as pending_rule / requires review');
 });
 await t.test('independent ADM REQUIRED: reused document policy isolates metadata by company',async()=>{
  const snapshot=JSON.parse(await readFile(new URL('./fixtures/encarregado-catalogo-real-20261004.json',import.meta.url),'utf8'));
  const table=snapshot.catalog.tables.find(x=>x.name==='ausencias_anexos'),policy=table.policies.find(x=>x.name==='ausencias_anexos_rh');
  assert.equal(table.rls,true);assert.equal(policy.using,'fn_e_administrativo()');assert.equal(policy.check,'fn_e_administrativo()');
  // Replay only the preserved, documented SELECT policy on the existing synthetic table.
  await q('ALTER TABLE ausencias_anexos ENABLE ROW LEVEL SECURITY;GRANT SELECT ON ausencias_anexos TO authenticated;CREATE POLICY audit_preserved_document_select ON ausencias_anexos FOR SELECT TO authenticated USING(fn_e_administrativo())');
  let rows;
  try{rows=await as(a,17,'SELECT count(*)::int v FROM ausencias_anexos');}
  finally{await q('DROP POLICY audit_preserved_document_select ON ausencias_anexos;REVOKE SELECT ON ausencias_anexos FROM authenticated;ALTER TABLE ausencias_anexos DISABLE ROW LEVEL SECURITY');}
  assert.equal(rows,0,'company B Administrative can read company A document metadata under preserved policy');
 });
 await t.test('independent ADM: new absence confirmation refuses company B actor for company A source',async()=>{
  const row=(await q("SELECT * FROM ausencias WHERE colaborador_id=$1 AND tipo='baixa_doenca' LIMIT 1",[id(20006)])).rows[0];assert.ok(row);
  await assert.rejects(aux(17,'absence_confirm',data({id:row.id,expected_state:row.estado,expected_type:row.tipo,reason:'Synthetic audit'})),e=>e.code==='42501');
 });
 await t.test('independent ADM REQUIRED: Director/Adjunto raw HE excludes administrative processing fields',async()=>{
  const leaks=[];
  for(const actor of [14,15]){
   const c=await as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);assert.ok(c.overtime.some(x=>x.processado_em),'synthetic processed HE is visible for evidence');
   const leaked=c.overtime.flatMap(row=>['processado_em','processado_por','prazo_processamento'].filter(k=>Object.hasOwn(row,k)));
   if(leaked.length)leaks.push({actor,fields:[...new Set(leaked)]});
  }
  assert.deepEqual(leaks,[], 'administrative processing fields returned to operational roles');
 });
 await t.test('independent ADM REQUIRED: Director/Adjunto raw history excludes administrative processing snapshots',async()=>{
  const leaks=[];
  for(const actor of [14,15]){
   const c=await as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);
   if(c.history.some(x=>x.action==='he_process'))leaks.push({actor,kind:'he_process'});
   if(c.history.some(x=>x.antes && Object.hasOwn(x.antes,'processado_por')))leaks.push({actor,kind:'snapshot'});
  }
  assert.deepEqual(leaks,[],'administrative HE history returned to operational roles');
 });
 await q('UPDATE folha_config_empresa SET office_expected_minutes=$2,correction_days=1,overtime_enabled=$3,calendar_complete=$4,holiday_dates=$5,calendar_validated_years=$6,he_eligible_roles=$7 WHERE empresa_id=$1',[id(1),config.office_expected_minutes,config.overtime_enabled,config.calendar_complete,config.holiday_dates,config.calendar_validated_years,config.he_eligible_roles]);
}
