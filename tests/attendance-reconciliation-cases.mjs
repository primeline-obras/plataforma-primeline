import assert from 'node:assert/strict';
import {analyseSheet,daySummary} from '../src/attendance-domain.js';

export async function reconciliationCases(t,{q,a,b,as,call,aux,auxDo,id}) {
 let seq=95000;
 const request=()=>id(seq++),work=id(100),full=[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}];
 const read=async(p,d)=>(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(p),d])).rows[0];
 const vacationRevision=async p=>(await q('SELECT coalesce((SELECT revision FROM folha_ferias_revisoes WHERE colaborador_id=$1),0) r',[id(p)])).rows[0].r;
 const vacation=async(p,action,dates,extra={})=>{
  const data={version:2,request_id:request(),person_id:id(p),dates,expected_revision:await vacationRevision(p),admin_override:true,...extra};
  return {data,result:await auxDo(10,action,data)};
 };
 const save=async(p,d,intervals=full,w=work)=>{
  const current=await read(p,d);
  if(w && !current && !(await q('SELECT 1 FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2 AND obra_id=$3',[id(p),d,w])).rowCount){const data={version:2,request_id:request(),work_id:w,date:d,person_id:id(p),period:'dia_inteiro',expected_allocation_revision:0};const preview=await call(a,10,'allocate',data);await call(a,10,'allocate',data,true,preview.versao);}
  const data={version:2,request_id:request(),work_id:w,date:d,key:{kind:'primeline',person_id:id(p),work_id:w,date:d},expected_revision:current?.revision||0,intervals};
  const preview=await call(a,10,'save',data);await call(a,10,'save',data,true,preview.versao);return read(p,d);
 };
 const parity=async(p,d,state)=>{
  const stored=await read(p,d),context=await as(a,10,'SELECT fn_folha_contexto_v2($1,$2) v',[d,stored.obra_id]);
  const row=context.rows.find(x=>x.person_id===id(p));assert.equal(stored.estado,state);assert.equal(row.sheet.state,state);
  assert.equal(analyseSheet({sheet:row.sheet,absence:row.absence,legacy:row.legacy,expectedMinutes:row.expected_minutes}).state,state);
  const monthly=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[id(p),d.slice(0,7)+'-01']);
  assert.equal(monthly.live_facts.sheets.find(x=>x.id===stored.id).state,state);
  assert.equal(daySummary([row]).complete,state==='registered'&&!row.special_review_pending);return stored;
 };

 await t.test('reconciliação: cenário exato da auditoria, remover férias restaura 8h e paridade',async()=>{
  const p=34,d='2026-09-25',before=await read(p,d);assert.equal(before.estado,'regularization');
  const {data}=await vacation(p,'vacation_remove',[d]);const after=await parity(p,d,'registered');
  assert.equal(after.revision,before.revision+1);assert.deepEqual(after.intervals,before.intervals);
  const history=(await q("SELECT * FROM folha_historico WHERE person_id=$1 AND data=$2 AND action='reconcile' ORDER BY revision DESC",[id(p),d])).rows[0];
  assert.equal(history.request_id,data.request_id);assert.equal(history.origem,'vacation_reconciliation');assert.equal(history.ator_id,id(10));
  assert.equal(history.antes.estado,'regularization');assert.equal(history.depois.estado,'registered');assert.ok(history.at);
 });
 for(const [p,intervals,end] of [[32,full,'registered'],[33,[{start:'09:00',end:'13:00'},{start:'14:00',end:'17:00'}],'missing'],[37,[{start:'09:00',end:null}],'open']]){
  await t.test(`reconciliação A/B: ${end} → férias → regularização → ${end}`,async()=>{
   const d='2026-09-22',before=await save(p,d,intervals);assert.equal(before.estado,end);
   const {data}=await vacation(p,'vacation_set',[d]);const conflict=await parity(p,d,'regularization');assert.equal(conflict.revision,before.revision+1);
   const count=(await q('SELECT count(*)::int n FROM folha_historico WHERE request_id=$1',[data.request_id])).rows[0].n;
   await auxDo(10,'vacation_set',data);assert.equal((await read(p,d)).revision,conflict.revision);
   assert.equal((await q('SELECT count(*)::int n FROM folha_historico WHERE request_id=$1',[data.request_id])).rows[0].n,count);
   await vacation(p,'vacation_remove',[d]);const after=await parity(p,d,end);assert.equal(after.revision,before.revision+2);
  });
 }
 await t.test('reconciliação B: remover férias não elimina conflito de alocações remanescente',async()=>{
  // Existing synthetic historical overlap; no allocation guard is bypassed.
  const p=21,d='2026-09-29',original=(await q('SELECT to_jsonb(a) v FROM ausencias a WHERE colaborador_id=$1 AND data=$2',[id(p),d])).rows[0].v;
  await q("INSERT INTO folha_registos(empresa_id,obra_id,tipo_local,data,colaborador_id,intervals,minutes,estado,special_day,expected_minutes,revision,criado_por,atualizado_por,request_id) VALUES($1,$2,'obra',$3,$4,$5,480,'regularization',false,480,1,$6,$6,$7)",[id(1),work,d,id(p),JSON.stringify(full),id(10),request()]);
  try{await vacation(p,'vacation_remove',[d]);await parity(p,d,'regularization');}
  finally{await q("SELECT set_config('test.actor',$1,false)",[id(10)]);await q('INSERT INTO ausencias SELECT * FROM jsonb_populate_record(NULL::public.ausencias,$1::jsonb)',[JSON.stringify(original)]);}
 });
 await t.test('reconciliação C: seleção multidata e replace reconciliam dias exatos',async()=>{
  const p=39,days=['2026-09-22','2026-09-23'];for(const d of days)await save(p,d);
  await vacation(p,'vacation_set',days);for(const d of days)await parity(p,d,'regularization');
  await vacation(p,'vacation_replace',[days[1]],{scope_dates:days});await parity(p,days[0],'registered');await parity(p,days[1],'regularization');
  await vacation(p,'vacation_remove',[days[1]]);await parity(p,days[1],'registered');
 });
 await t.test('reconciliação C: falha na segunda data reverte ausência, folhas, HE e históricos integralmente',async()=>{
  const p=44,days=['2026-09-22','2026-09-23'];for(const d of days)await save(p,d);
  const snapshot=async()=> (await q("SELECT jsonb_build_object('s', (SELECT jsonb_agg(to_jsonb(f) ORDER BY id) FROM folha_registos f),'h',(SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM folha_historico h),'a',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM ausencias a),'he',(SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM folha_he h),'m',(SELECT jsonb_agg(to_jsonb(h) ORDER BY id) FROM folha_gestao_historico h)) v")).rows[0].v;
  const before=await snapshot();
  // Synthetic fault injection proves rollback after the first day has already reconciled.
  await q(`CREATE FUNCTION public.test_reconciliation_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.colaborador_id='${id(p)}' AND NEW.data='2026-09-23' THEN RAISE EXCEPTION 'SYNTHETIC_SECOND_DAY_FAILURE'; END IF; RETURN NEW; END $$; CREATE TRIGGER zz_test_reconciliation_fault BEFORE INSERT ON ausencias FOR EACH ROW EXECUTE FUNCTION test_reconciliation_fault()`);
  try{await assert.rejects(vacation(p,'vacation_set',days),/SYNTHETIC_SECOND_DAY_FAILURE/);assert.deepEqual(await snapshot(),before);}
  finally{await q('DROP TRIGGER zz_test_reconciliation_fault ON ausencias; DROP FUNCTION test_reconciliation_fault()');}
 });
 await t.test('reconciliação D: writers legados INSERT/UPDATE/DELETE e justificação sem conversão automática',async()=>{
  const p=42,d='2026-09-22';await save(p,d);await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  const absence=request();await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'falta_injustificada','ausente_pendente')",[absence,id(p),d]);
  const before=await parity(p,d,'regularization');
  await q("UPDATE ausencias SET tipo='falta_justificada_sem_remuneracao',estado='justificada' WHERE id=$1",[absence]);
  const justified=await parity(p,d,'regularization');assert.equal(justified.revision,before.revision);
  await q('DELETE FROM ausencias WHERE id=$1',[absence]);await parity(p,d,'registered');
  assert.ok((await q("SELECT 1 FROM folha_historico WHERE person_id=$1 AND data=$2 AND origem='absence_reconciliation'",[id(p),d])).rowCount);
 });
 await t.test('reconciliação D: mudar a data da ausência reconcilia origem e destino',async()=>{
  const p=39,first='2026-09-22',next='2026-09-23',absence=request();await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'falta_injustificada','ausente_pendente')",[absence,id(p),first]);await parity(p,first,'regularization');
  await q('UPDATE ausencias SET data=$2 WHERE id=$1',[absence,next]);await parity(p,first,'registered');await parity(p,next,'regularization');
  await q('DELETE FROM ausencias WHERE id=$1',[absence]);await parity(p,next,'registered');
 });
 await t.test('reconciliação E: HE superseded com férias e regenerada apenas na revisão corrente, sem replay duplicado',async()=>{
  const p=40,d='2026-09-22';await save(p,d,[{start:'09:00',end:'18:00'}]);
  const before=await read(p,d);assert.equal((await q("SELECT count(*)::int n FROM folha_he WHERE folha_id=$1 AND estado='potential'",[before.id])).rows[0].n,1);
  await vacation(p,'vacation_set',[d]);assert.equal((await q("SELECT count(*)::int n FROM folha_he WHERE folha_id=$1 AND estado<>'superseded'",[before.id])).rows[0].n,0);
  const {data}=await vacation(p,'vacation_remove',[d]);await auxDo(10,'vacation_remove',data);
  const after=await parity(p,d,'registered'),he=(await q('SELECT * FROM folha_he WHERE folha_id=$1 ORDER BY folha_revision',[before.id])).rows;
  assert.equal(he.length,2);assert.equal(he[0].estado,'superseded');assert.equal(he[1].estado,'potential');assert.equal(he[1].folha_revision,after.revision);
 });
 await t.test('reconciliação E: Escritório nunca gera HE e mantém carga snapshot',async()=>{
  const p=60,d='2026-09-22',before=await save(p,d,[{start:'09:00',end:'18:00'}],null);
  await vacation(p,'vacation_set',[d]);await vacation(p,'vacation_remove',[d]);const after=await parity(p,d,'registered');assert.equal(after.expected_minutes,before.expected_minutes);
  assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id=$1',[before.id])).rows[0].n,0);
 });
 await t.test('reconciliação E: geração desligada, calendário incompleto, feriado e HE manual continuam bloqueados',async()=>{
  const original=(await q('SELECT * FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0];
  for(const [p,enabled,complete,holiday,manual] of [[46,false,true,false,false],[47,true,false,false,false],[48,true,true,true,false],[45,true,true,false,true]]){
   const d='2026-09-23';await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
   await q("UPDATE folha_config_empresa SET overtime_enabled=$1,calendar_complete=$2,holiday_dates=$3 WHERE empresa_id=$4",[enabled,complete,holiday?[d]:[],id(1)]);
   try{
    if(manual)await q('INSERT INTO horas_extraordinarias(colaborador_id,data) VALUES($1,$2)',[id(p),d]);
    const f=await save(p,d,[{start:'09:00',end:'18:00'}]);await vacation(p,'vacation_set',[d]);await vacation(p,'vacation_remove',[d]);await parity(p,d,'registered');
    assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id=$1',[f.id])).rows[0].n,0);
   }finally{await q('UPDATE folha_config_empresa SET overtime_enabled=$1,calendar_complete=$2,holiday_dates=$3 WHERE empresa_id=$4',[original.overtime_enabled,original.calendar_complete,original.holiday_dates,id(1)]);}
  }
 });
 await t.test('reconciliação F: Vencimentos guardado invalida validação e conserva factos/manuais',async()=>{
  const p=32,d='2026-09-22',month='2026-09-01';let data={version:2,request_id:request(),person_id:id(p),month,expected_revision:0,manual:{km:2,allowance:0,note:'Synthetic'}};
  await save(p,'2026-09-25'); // Resolve the allocation seeded by the transfer regression before validating this month.
  await q('UPDATE folha_config_empresa SET calendar_complete=true,calendar_validated_years=ARRAY[2026] WHERE empresa_id=$1',[id(1)]);
  await auxDo(10,'payroll_save',data);await auxDo(10,'payroll_validate',{...data,request_id:request(),expected_revision:1});
  await vacation(p,'vacation_set',[d]);let v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(p)])).rows[0];
  assert.equal(v.estado,'draft');assert.equal(v.factos.sheets.find(s=>s.date===d).state,'regularization');assert.equal(v.manuais.km,2);
  await vacation(p,'vacation_remove',[d]);v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(p)])).rows[0];assert.equal(v.factos.sheets.find(s=>s.date===d).state,'registered');
  assert.ok((await q("SELECT 1 FROM folha_gestao_historico WHERE entidade_id=$1 AND action='payroll_reconcile'",[v.id])).rowCount);
 });
 await t.test('reconciliação F: alocação e legado sincronizam fotografia mensal sem pendência fictícia duplicada',async()=>{
  const p=47,d='2026-09-21',allocation=request(),legacy=request();await auxDo(10,'payroll_save',{version:2,request_id:request(),person_id:id(p),month:'2026-09-01',expected_revision:0,manual:{km:0,allowance:0,note:'Synthetic'}});
  const facts=async()=> (await q('SELECT factos FROM folha_vencimentos WHERE colaborador_id=$1',[id(p)])).rows[0].factos;
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,periodo,semana_inicio,tipo_alocacao) VALUES($1,$2,$3,$4,'dia_inteiro','2026-09-21','obra')",[allocation,id(p),work,d]);assert.ok((await facts()).pending_days.includes(d));
  await q("INSERT INTO ponto_pessoal_obra(id,empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES($1,$2,$3,$4,$5,'presente',$6)",[legacy,id(1),work,id(p),d,id(10)]);assert.ok((await facts()).legacy_days.includes(d));assert.equal((await facts()).pending_days.includes(d),false);
  await q('DELETE FROM ponto_pessoal_obra WHERE id=$1',[legacy]);assert.equal((await facts()).legacy_days.includes(d),false);assert.ok((await facts()).pending_days.includes(d));
  await q('DELETE FROM quadro_pessoal_alocacao WHERE id=$1',[allocation]);assert.equal((await facts()).pending_days.includes(d),false);
 });
 await t.test('reconciliação G: horário/calendário não reclassificam silenciosamente folhas históricas',async()=>{
  const p=33,d='2026-09-22',before=await read(p,d),configuration=(await q('SELECT * FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0];
  await q('UPDATE folha_horarios SET expected_minutes=420 WHERE obra_id=$1',[work]);await q("UPDATE folha_config_empresa SET office_expected_minutes=420,holiday_dates=ARRAY['2026-09-22'::date] WHERE empresa_id=$1",[id(1)]);
  try{
   await vacation(p,'vacation_set',[d]);await vacation(p,'vacation_remove',[d]);const after=await parity(p,d,'missing');assert.equal(after.expected_minutes,480);assert.equal(after.special_day,before.special_day);
   const context=await as(a,10,'SELECT fn_folha_contexto_v2($1,$2) v',[d,work]);assert.equal(context.rows.find(r=>r.person_id===id(p)).expected_minutes,480);
  }finally{await q('UPDATE folha_horarios SET expected_minutes=480 WHERE obra_id=$1',[work]);await q('UPDATE folha_config_empresa SET office_expected_minutes=$1,holiday_dates=$2 WHERE empresa_id=$3',[configuration.office_expected_minutes,configuration.holiday_dates,id(1)]);}
 });
 await t.test('reconciliação: concorrência, preview antigo torna-se stale após férias',async()=>{
  const p=43,d='2026-09-22',f=await save(p,d);
  const data={version:2,request_id:request(),work_id:work,date:d,key:{kind:'primeline',person_id:id(p),work_id:work,date:d},expected_revision:f.revision,intervals:full};
  const preview=await call(b,10,'save',data);await vacation(p,'vacation_set',[d]);
  await assert.rejects(call(b,10,'save',data,true,preview.versao),e=>e.code==='40001');await parity(p,d,'regularization');
  await vacation(p,'vacation_remove',[d]);await parity(p,d,'registered');
 });
 await t.test('reconciliação: isolamento antigo recusado antes de qualquer escrita',async()=>{
  await a.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
  try{await a.query("SELECT set_config('test.actor',$1,false)",[id(10)]);await assert.rejects(a.query("DELETE FROM ausencias WHERE colaborador_id=$1 AND data='2026-09-22'",[id(32)]),e=>e.code==='40001');}
  finally{await a.query('ROLLBACK');}
 });
 await t.test('reconciliação: transações concorrentes reais ausência ↔ gravação coordenam ambos os sentidos',async()=>{
  const p=43,d='2026-09-23';await save(p,d);
  for(const direction of ['sheet_first','absence_first']){
   const before=await read(p,d),absence=request();
   if(direction==='sheet_first'){
    const data={version:2,request_id:request(),work_id:work,date:d,key:{kind:'primeline',person_id:id(p),work_id:work,date:d},expected_revision:before.revision,intervals:full};
    const preview=await call(a,10,'save',data);await a.query('BEGIN');await call(a,10,'save',data,true,preview.versao);
    await b.query("SELECT set_config('test.actor',$1,false)",[id(10)]);let completed=false;
    const pending=b.query("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'ferias','confirmada')",[absence,id(p),d]).then(v=>{completed=true;return v;});
    await new Promise(r=>setTimeout(r,80));assert.equal(completed,false);await a.query('COMMIT');await pending;
    await parity(p,d,'regularization');
   }else{
    const data={version:2,request_id:request(),work_id:work,date:d,key:{kind:'primeline',person_id:id(p),work_id:work,date:d},expected_revision:before.revision,intervals:full};
    const preview=await call(b,10,'save',data);await a.query('BEGIN');await a.query("SELECT set_config('test.actor',$1,false)",[id(10)]);
    await a.query("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,'ferias','confirmada')",[absence,id(p),d]);let completed=false;
    const pending=call(b,10,'save',data,true,preview.versao).then(value=>{completed=true;return {value};},error=>{completed=true;return {error};});
    await new Promise(r=>setTimeout(r,80));assert.equal(completed,false);await a.query('COMMIT');const outcome=await pending;assert.equal(outcome.error?.code,'40001');await parity(p,d,'regularization');
   }
   await q("SELECT set_config('test.actor',$1,false)",[id(10)]);await q('DELETE FROM ausencias WHERE id=$1',[absence]);await parity(p,d,'registered');
  }
 });
 await t.test('reconciliação: helpers privados sem EXECUTE externo',async()=>{
  for(const user of [10,13,17])await assert.rejects(as(a,user,'SELECT folha_privado.reconciliar_dia($1,$2,$3,$4) v',[id(32),'2026-09-22',request(),'absence_reconciliation']),e=>e.code==='42501');
 });
}
