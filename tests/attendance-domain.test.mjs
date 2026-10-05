import test from 'node:test';
import assert from 'node:assert/strict';
import {analyseSheet,intervalFacts,exactAllocations,normalIntervals,correctionAllowed,vacationSelection,overtimeTransition,payrollFacts,payrollTransition,activePlanningTasks,activeOn,localClock,daySummary,normalDaySelection} from '../src/attendance-domain.js';
import {createSheetClient} from '../src/attendance-client.js';
const day='2026-10-05', full=[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}];
test('resumo deriva pendências/abertos, ausência válida e DIA COMPLETO sem fecho',()=>{
 const rows=[{sheet:{intervals:full},expected_minutes:480},{absence:{tipo:'ferias'}},{absence:{tipo:'ausencia'}}];
 assert.deepEqual(daySummary(rows),{people:3,registered:1,open:0,pending:0,complete:true});
 assert.equal(daySummary([...rows,{sheet:null}]).complete,false);
 assert.equal(daySummary([{sheet:{intervals:[{start:'09:00',end:null}]}}]).open,1);
 assert.equal(daySummary([{absence:{tipo:'ferias'},conflict:'LEGACY_CONFLICT'}]).pending,1);
});
test('HE compara carga configurada também em jornadas parciais',()=>{
 assert.equal(analyseSheet({sheet:{intervals:[{start:'09:00',end:'13:00'}]},expectedMinutes:240}).overtime,'none');
 assert.equal(analyseSheet({sheet:{intervals:[{start:'09:00',end:'14:00'}]},expectedMinutes:240}).overtime,'potential');
});
test('sem folha não inventa presença nem horas',()=>assert.equal(analyseSheet({}).state,'none'));
test('entrada sem saída fica em aberto; sem hora de saída inventada',()=>{const r=analyseSheet({sheet:{intervals:[{start:'08:00',end:null}]},expectedMinutes:480});assert.equal(r.state,'open');assert.equal(r.minutes,0);});
test('8h deslocadas são normais, não HE',()=>{const r=analyseSheet({sheet:{intervals:full},expectedMinutes:480});assert.equal(r.state,'registered');assert.equal(r.overtime,'none');});
test('horário normal pode ser configurado por obra e período',()=>{const s={intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}]};assert.deepEqual(normalIntervals(s),full);assert.equal(normalIntervals(s,'manha').length,1);assert.throws(()=>normalIntervals(null));});
test('saída futura, entrada futura e dia futuro são recusados',()=>{const options={date:day,now:{date:day,time:'10:00'}};assert.throws(()=>intervalFacts(full,options),/futura/);assert.throws(()=>intervalFacts([{start:'11:00',end:null}],options),/futura/);assert.throws(()=>intervalFacts([{start:'08:00',end:null}],{date:'2026-10-06',now:options.now}),/futura/);});
test('intervalos negativos, inválidos e sobrepostos são recusados',()=>{for(const a of [[{start:null,end:'09:00'}],[{start:'24:00',end:null}],[{start:'08:00',end:'07:00'}],[{start:'08:00',end:'12:00'},{start:'11:00',end:'13:00'}],[{start:'08:00',end:null},{start:'14:00',end:null}]])assert.throws(()=>intervalFacts(a));});
test('horas em falta, férias e ausência/trabalho não são corrigidos silenciosamente',()=>{assert.equal(analyseSheet({sheet:{intervals:[{start:'08:00',end:'12:00'}]},expectedMinutes:480}).state,'missing');const vacation=analyseSheet({absence:{tipo:'ferias'},expectedMinutes:480});assert.equal(vacation.expectedMinutes,0);assert.equal(vacation.overtime,'none');assert.equal(analyseSheet({absence:{tipo:'ferias'},sheet:{intervals:full}}).state,'regularization');assert.equal(analyseSheet({absence:{tipo:'ausencia'}}).state,'absence');});
test('sem horário esperado não inventa horas em falta nem folha válida',()=>assert.equal(analyseSheet({sheet:{intervals:full}}).state,'regularization'));
test('mais de 8h de obra são potencial HE; escritório e dia especial não têm regra automática',()=>{const sheet={intervals:[{start:'08:00',end:'18:00'}]};assert.equal(analyseSheet({sheet,expectedMinutes:480}).overtime,'potential');assert.equal(analyseSheet({sheet,workType:'escritorio'}).overtime,'none');assert.equal(analyseSheet({sheet,specialDay:true}).overtime,'pending_rule');});
test('correção é parametrizada; nenhum dia seguinte assumido',()=>{assert.equal(correctionAllowed({role:'encarregado',date:day,today:day}),true);assert.equal(correctionAllowed({role:'encarregado',date:day,today:'2026-10-06',days:1}),true);assert.equal(correctionAllowed({role:'encarregado',date:day,today:'2026-10-07',days:1}),false);assert.equal(correctionAllowed({role:'administrativo',date:day,today:'2026-10-07'}),true);});
test('alocação exata não herda dia anterior; histórico de inativo permanece datado',()=>{assert.deepEqual(exactAllocations([{colaborador_id:'p',data:'2026-10-04'}],'p',day),[]);assert.equal(activeOn({data_admissao:'2026-01-01',data_saida:'2026-09-30'},'2026-09-25'),true);assert.equal(activeOn({data_admissao:'2026-01-01',data_saida:'2026-09-30'},day),false);});
test('férias suportam seleção não contígua, intervalos e remoção, sem consumir dia especial por inferência',()=>{const r=vacationSelection({selected:['2026-10-05','2026-10-07'],from:'2026-10-09',to:'2026-10-11',remove:['2026-10-10']});assert.deepEqual(r.dates,['2026-10-05','2026-10-07','2026-10-09','2026-10-11']);assert.equal(r.pendingRule,true);assert.equal(r.consumedDays,null);assert.equal(vacationSelection({selected:[day],calendarVerified:true}).consumedDays,1);});
test('HE segue Diretor/Adjunto → Administrativo, sem pagamento implícito',()=>{for(const role of ['diretor_obra','adjunto'])assert.equal(overtimeTransition('potential','approve',role),'pending_validation');assert.equal(overtimeTransition('potential','reject','diretor_obra'),'rejected');assert.equal(overtimeTransition('pending_validation','validate','administrativo'),'validated_pending_rule');assert.throws(()=>overtimeTransition('potential','approve','encarregado'));});
test('vencimentos agregam factos e exigem regra/modelo para fechar e exportar',()=>{assert.equal(payrollFacts([{date:day,intervals:full}]).workedMinutes,480);assert.equal(payrollFacts().financialEffect,false);assert.equal(payrollTransition('draft','validate',{canAdmin:true}),'validated');assert.throws(()=>payrollTransition('validated','close',{canAdmin:true,unresolved:1}));assert.throws(()=>payrollTransition('closed','export',{canAdmin:true}));});
test('conclusão final vem do Planeamento, não de 100% isoladamente',()=>assert.deepEqual(activePlanningTasks([{id:'a',estado:'concluido'},{id:'b',estado:'em_execucao',percentual_executado:100},{id:'c',arquivado_em:day}]).map(x=>x.id),['b']));
test('relógio é Europe/Lisbon, incluindo DST',()=>assert.deepEqual(localClock(new Date('2026-10-05T08:00:00Z')),{date:day,time:'09:00'}));
test('cliente usa preview/confirmação com mesmo request_id e nenhum DML direto',async()=>{const calls=[];const client=createSheetClient({requestId:()=> 'request',confirm:async()=>true,supabase:async(path,o)=>{const body=JSON.parse(o.body);calls.push({path,body});return Response.json(body.p_confirmar?{version:2,committed:true,request_id:'request',changed_keys:[{kind:'primeline',person_id:'p',date:day,work_id:'own'}]}:{version:2,committed:false,versao:'hash',summary:'Alterar?'});}});assert.equal((await client.operate('save',{date:day,work_id:'own',expected_revision:0})).committed,true);assert.equal(calls.length,2);assert.equal(calls[0].body.p_dados.request_id,calls[1].body.p_dados.request_id);assert.ok(calls.every(x=>x.path==='rpc/fn_folha_operar_v2'));});
test('falha ambígua reutiliza request_id; stale exige recarregar e nova operação',async()=>{let fail=true,stale=false,ids=0;const seen=[];const client=createSheetClient({requestId:()=>String(++ids),confirm:async()=>true,supabase:async(_,o)=>{const b=JSON.parse(o.body);seen.push(b.p_dados.request_id);if(stale)return Response.json({code:'STALE_REVISION',message:'Recarregue'},{status:409});if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'v'});if(fail)throw new Error('Ligação interrompida');return Response.json({version:2,committed:true,request_id:b.p_dados.request_id,changed_keys:[{kind:'primeline',person_id:'p',date:day,work_id:'own'}]});}});await assert.rejects(()=>client.operate('save',{date:day,work_id:'own'}));fail=false;await client.operate('save',{date:day,work_id:'own'});assert.deepEqual(new Set(seen),new Set(['1']));stale=true;await assert.rejects(()=>client.operate('save',{date:day,work_id:'own'}),/Recarregue/);stale=false;await client.operate('save',{date:day,work_id:'own'});assert.equal(ids,3);});
test('RPC ausente/recusa/resposta incompleta não simula sucesso nem usa legado',async()=>{for(const status of [404,403,500]){const calls=[];const c=createSheetClient({confirm:async()=>true,supabase:async p=>{calls.push(p);return Response.json({message:'Recusado'},{status});}});await assert.rejects(()=>c.context(day));assert.equal(calls.length,1);assert.equal(calls[0],'rpc/fn_folha_contexto_v2');}const c=createSheetClient({confirm:async()=>true,supabase:async()=>Response.json({})});await assert.rejects(()=>c.context(day),/inválida/);});
test('contexto de outra obra/data é recusado',async()=>{const c=createSheetClient({supabase:async()=>Response.json({version:2,date:'2026-10-06',work_id:'other',works:[],rows:[],external_rows:[],permissions:{}})});await assert.rejects(()=>c.context(day,'own'),/inválida/);});
test('cliente aceita chave Escritório NULL e não confunde destino obra',async()=>{
 const key={kind:'primeline',person_id:'self',date:day,work_id:null};
 const c=createSheetClient({requestId:()=> 'r',confirm:async()=>true,supabase:async(_,o)=>{const b=JSON.parse(o.body);return Response.json(b.p_confirmar?{version:2,committed:true,request_id:'r',changed_keys:[key]}:{version:2,committed:false,versao:'v'});}});
 assert.equal((await c.operate('save',{date:day,work_id:null,key})).committed,true);
});

test('confirmação sem chaves válidas ou com pessoa/obra/data diferente não simula sucesso',async()=>{
  const valid={kind:'primeline',person_id:'p',date:day,work_id:'own'};
  for(const changed_keys of [[],[null],[{...valid,kind:'external'}],[{...valid,person_id:'other'}],[{...valid,work_id:'other'}],[{...valid,date:'2026-10-06'}]]) {
    const c=createSheetClient({requestId:()=> 'request',confirm:async()=>true,supabase:async(_,o)=>{
      const b=JSON.parse(o.body);return Response.json(b.p_confirmar?{version:2,committed:true,request_id:'request',changed_keys}:{version:2,committed:false,versao:'v'});
    }});
    await assert.rejects(()=>c.operate('save',{date:day,work_id:'own',key:valid,expected_revision:0}),/não confirmada/);
  }
});

test('dia normal exige fim da jornada completa, exclui ausências/conflitos/folhas e respeita retroativos',()=>{
 const schedule={intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}]};
 const rows=[{person_id:'ok',can_write:true,period:'manha'},{person_id:'v',can_write:true,absence:{}},{person_id:'c',can_write:true,conflict:'CONFLICT'},{person_id:'s',can_write:true,sheet:{}}];
 const choose=(time,extra={})=>normalDaySelection(rows,{schedule,date:day,now:{date:day,time},...extra});
 assert.equal(choose('17:59').eligible.length,0);const done=choose('18:00');assert.equal(done.eligible.length,1);assert.equal(done.excluded.length,3);assert.deepEqual(done.eligible[0].intervals,[{start:'09:00',end:'13:00'}]);
 assert.equal(choose('18:00',{date:'2026-10-04'}).eligible.length,0);assert.equal(choose('18:00',{date:'2026-10-04',correctionDays:1}).eligible.length,1);assert.equal(choose('18:00',{date:'2026-10-04',admin:true}).eligible.length,1);
});
