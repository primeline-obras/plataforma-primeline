import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {daySummary,dayStatus,workedTime,delegationLabel} from '../src/attendance-domain.js';
import {createSheetClient} from '../src/attendance-client.js';
import {loadForemanVacationMap} from '../src/foreman-scope.js';
test('dia vazio não completo; faltas parciais são em preenchimento',()=>{
 assert.equal(dayStatus(daySummary([])),'SEM EQUIPA');assert.equal(daySummary([]).complete,false);
 assert.equal(dayStatus(daySummary([{sheet:null}])),'NÃO INICIADO');
 assert.equal(dayStatus(daySummary([{sheet:{state:'missing',intervals:[{start:'08:00',end:'10:00'}]}}])),'EM PREENCHIMENTO');
 assert.equal(dayStatus(daySummary([{sheet:{state:'registered',intervals:[{start:'08:00',end:'10:00'}]}}])),'DIA COMPLETO ✓');
});
test('delegação explícita, distinta e por configurar, sem inferência',()=>{
 assert.equal(delegationLabel(null,'lisboa'),'DELEGAÇÃO POR CONFIGURAR');assert.equal(delegationLabel('algarve','lisboa'),'ALGARVE');
 assert.equal(delegationLabel('lisboa','lisboa'),'');assert.equal(delegationLabel('lisboa',null),'LISBOA');assert.throws(()=>delegationLabel('outra','lisboa'));
});
test('totais factuais, intervalos múltiplos e entrada aberta',()=>{
 assert.equal(workedTime([{start:'10:00',end:'16:00'}]),'6h');assert.equal(workedTime([{start:'08:00',end:'12:00'},{start:'13:00',end:'16:00'}]),'7h');
 assert.equal(workedTime([{start:'08:00',end:null}]),'0h · Em aberto');
});
test('equipa em lote chama um preview e uma confirmação, mesmo request, sem DML',async()=>{
 const calls=[],data={date:'2026-10-09',work_id:'w',people:[{person_id:'p',expected_revision:0},{person_id:'q',expected_revision:0}]};
 const client=createSheetClient({requestId:()=> 'req',confirm:async()=>true,supabase:async(url,opts)=>{const b=JSON.parse(opts.body);calls.push({url,b});return Response.json(b.p_confirmar?{version:2,committed:true,request_id:'req',changed_keys:data.people.map(p=>({kind:'primeline',person_id:p.person_id,date:data.date,work_id:'w'}))}:{version:2,committed:false,versao:'token'});}});
 await client.operate('team_add',data);assert.equal(calls.length,2);assert.ok(calls.every(x=>x.url==='rpc/fn_equipa_operar_v2'));assert.deepEqual(calls[0].b.p_dados,calls[1].b.p_dados);
});
test('férias usa projeção mínima global, sem escrita nem raw RH',async()=>{
 const calls=[],response=await loadForemanVacationMap(async(url,opts)=>{calls.push({url,opts});return Response.json({version:2,people:[{id:'director',nome:'Sintético',funcao:'Diretor'}],vacations:[]});},'2026-10-01','2026-10-31');
 assert.equal((await response.json()).people[0].id,'director');assert.equal(calls[0].url,'rpc/fn_folha_ferias_mapa_v2');assert.deepEqual(JSON.parse(calls[0].opts.body),{p_inicio:'2026-10-01',p_fim:'2026-10-31'});
});
test('Folha não tem renderização/ação de tarefas; Plano usa somente reporte',()=>{
 const management=readFileSync(new URL('../src/attendance-management.js',import.meta.url),'utf8'),plan=readFileSync(new URL('../src/action-plan.js',import.meta.url),'utf8');
 assert.doesNotMatch(management,/data-management-task=|TAREFAS ATIVAS|REPORTES DE CONCLUSÃO|\['tasks','TAREFAS'\]/);
 assert.match(plan,/client.execute\('task_report'/);assert.match(plan,/AGUARDA CONFIRMAÇÃO DO DIRETOR/);assert.doesNotMatch(plan,/method:\s*['"]PATCH|fn_atualizar_tarefa_encarregado/);
});
