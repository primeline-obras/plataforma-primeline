import assert from 'node:assert/strict';
import {createSheetClient,createAttendanceManagementClient} from '../src/attendance-client.js';
import {analyseSheet,daySummary} from '../src/attendance-domain.js';

// Independent read/projection and replay checks. Runs only inside the existing local fixture.
export async function focusedReauditCases(t,{q,a,as,aux,id}) {
 const work=id(100),date='2026-09-25',forbidden=['payroll','live_facts','entitlements','vacations','vacation_revision','config','people'];
 const management=(user,w=work,p=null,m=null)=>as(a,user,'SELECT fn_folha_gestao_contexto_v2($1,$2,$3) v',[w,p,m]);
 const daily=(user,w=work,d=date)=>as(a,user,'SELECT fn_folha_contexto_v2($1,$2) v',[d,w]);
 await t.test('reauditoria P1: JSON bruto e domínios por perfil; administrativo preservado',async()=>{
  for(const user of [13,14,15]) {
   const c=await management(user);
   assert.deepEqual(Object.keys(c).sort(),['history','overtime','permissions','schedule','task_reports','tasks','version']);
   forbidden.forEach(k=>assert.equal(Object.hasOwn(c,k),false));
   assert.doesNotMatch(JSON.stringify(c),/SALARY_SENTINEL|premium|allowance|"km"|payroll_save|folha_vencimentos/);
   assert.ok(c.history.every(e=>['tarefas',...(user===13?[]:['he','horario'])].includes(e.dominio)));
   assert.ok(c.task_reports.every(e=>e.obra_id===work&&e.empresa_id===id(1)));
   if(user===13)assert.deepEqual(c.overtime,[]);
   else assert.ok(c.overtime.every(e=>e.obra_id===work&&!Object.hasOwn(e,'empresa_id')));
   const client=createAttendanceManagementClient({supabase:async()=>Response.json(c)});
   assert.deepEqual(await client.context({workId:work}),c);
  }
  for(const user of [10,11,12]){const c=await management(user,null,id(42),'2026-09-01');assert.equal(c.payroll[0].manuais.note,'SALARY_SENTINEL');forbidden.forEach(k=>assert.equal(Object.hasOwn(c,k),true));}
  await assert.rejects(management(16),e=>e.code==='42501');
  const office=await daily(16,null);assert.equal(office.rows.length,1);assert.equal(office.rows[0].person_id,id(62));
  assert.doesNotMatch(JSON.stringify(office),/SALARY_SENTINEL|premium|allowance|"km"|payroll_save/);
 });
 await t.test('reauditoria: matriz negativa dos quatro readers em obra e self-service',async()=>{
  const key={kind:'primeline',person_id:id(30),work_id:work,date};
  for(const user of [16,17,18,81,82,83]) {
   await assert.rejects(daily(user),e=>e.code==='42501');
   await assert.rejects(management(user),e=>e.code==='42501');
   await assert.rejects(as(a,user,'SELECT fn_folha_pessoas_v2($1,$2) v',[date,work]),e=>e.code==='42501');
   await assert.rejects(as(a,user,'SELECT fn_folha_historico_v2($1) v',[key]),e=>e.code==='42501');
  }
  for(const user of [14,15])await assert.rejects(as(a,user,'SELECT fn_folha_pessoas_v2($1,$2) v',[date,work]),e=>e.code==='42501');
  const people=await as(a,13,'SELECT fn_folha_pessoas_v2($1,$2) v',[date,work]);
  assert.ok(people.people.every(p=>!Object.hasOwn(p,'valor_hora')&&!Object.hasOwn(p,'nivel')&&!Object.hasOwn(p,'contacto')&&p.person_id!==id(49)));
  for(const user of [13,14,15])await assert.rejects(daily(user,id(103)),e=>e.code==='42501');
 });
 await t.test('reauditoria: Financeiro sem obra não recebe acesso nem dados RH',async()=>{
  // Keep the expectation explicit: empty access envelope is acceptable only without enabled write.
  const c=await daily(81,null);assert.deepEqual(c.works,[]);assert.deepEqual(c.rows,[]);assert.deepEqual(c.external_rows,[]);
  assert.equal(c.office_available,false);assert.equal(c.management,false);assert.ok(Object.values(c.permissions).every(v=>v===false));
  assert.deepEqual(c.providers,[]);assert.deepEqual(c.external_people,[]);
  await assert.rejects(management(81,null),e=>e.code==='42501');
 });
 await t.test('reauditoria: quatro domínios derivados e ações fechadas; evento administrativo com obra permanece privado',async()=>{
  const rows=(await q("SELECT action,dominio FROM folha_gestao_historico WHERE action IN('task_report','he_approve','configure_schedule','payroll_save')")).rows;
  for(const [action,domain] of [['task_report','tarefas'],['he_approve','he'],['configure_schedule','horario'],['payroll_save','administrativo']])assert.ok(rows.some(x=>x.action===action&&x.dominio===domain));
  const generated=(await q("SELECT attgenerated,pg_get_expr(d.adbin,d.adrelid) expression FROM pg_attribute a JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid='folha_gestao_historico'::regclass AND a.attname='dominio'")).rows[0];assert.equal(generated.attgenerated,'s');
  const salary=(await q("SELECT id FROM folha_gestao_historico WHERE action='payroll_save' AND obra_id=$1",[work])).rows;assert.ok(salary.length>0);
  for(const user of [13,14,15]){const c=await management(user);assert.ok(salary.every(s=>!c.history.some(x=>x.id===s.id)));}
 });
 for(const [name,user,action,role] of [['payroll',10,'payroll_save','administrativo'],['HE',14,'he_approve','diretor_obra'],['tarefa',13,'task_report','encarregado']]) {
  await t.test('reauditoria replay '+name+': redução de papel recusa; reposição preserva idempotência',async()=>{
   const op=(await q("SELECT payload,token,resultado FROM folha_privado.operacoes WHERE ator_id=$1 AND payload->>'action'=$2 ORDER BY criado_em LIMIT 1",[id(user),action])).rows[0];assert.ok(op);
   const before=(await q('SELECT count(*)::int n FROM folha_gestao_historico')).rows[0].n;
   await q("UPDATE utilizadores SET funcao='financeiro' WHERE id=$1",[id(user)]);
   try{await assert.rejects(aux(user,action,op.payload.data,true,op.token),e=>e.code==='42501');await assert.rejects(aux(user,action,op.payload.data,false,null),e=>e.code==='42501');}
   finally{await q('UPDATE utilizadores SET funcao=$2 WHERE id=$1',[id(user),role]);}
   assert.deepEqual(await aux(user,action,op.payload.data,true,op.token),op.resultado);
   assert.equal((await q('SELECT count(*)::int n FROM folha_gestao_historico')).rows[0].n,before);
  });
 }
 await t.test('reauditoria: remoção de responsabilidade recusa contexto/replays HE e tarefa',async()=>{
  for(const [user,action,role] of [[14,'he_approve','diretor_obra'],[13,'task_report','encarregado']]) {
   const op=(await q("SELECT payload,token,resultado FROM folha_privado.operacoes WHERE ator_id=$1 AND payload->>'action'=$2 ORDER BY criado_em LIMIT 1",[id(user),action])).rows[0];
   await q("UPDATE obra_responsaveis SET papel='preparador' WHERE utilizador_id=$1 AND obra_id=$2 AND papel=$3",[id(user),work,role]);
   try{await assert.rejects(management(user),e=>e.code==='42501');await assert.rejects(daily(user),e=>e.code==='42501');await assert.rejects(aux(user,action,op.payload.data,true,op.token),e=>e.code==='42501');}
   finally{await q('UPDATE obra_responsaveis SET papel=$3 WHERE utilizador_id=$1 AND obra_id=$2 AND papel=$4',[id(user),work,role,'preparador']);}
   assert.deepEqual(await aux(user,action,op.payload.data,true,op.token),op.resultado);
  }
 });
 await t.test('reauditoria P2: allowlist exata, campos futuros não passam, cliente preserva tudo',async()=>{
  await q('ALTER TABLE ponto_pessoal_obra ADD COLUMN audit_future_private text');
  try{
   await q("UPDATE ponto_pessoal_obra SET audit_future_private='FUTURE_PRIVATE_SENTINEL' WHERE colaborador_id=$1",[id(45)]);
   const key={kind:'primeline',person_id:id(45),work_id:work,date:'2026-09-24'};
   const h=await as(a,13,'SELECT fn_folha_historico_v2($1) v',[key]);assert.equal(h.events.length,0);assert.equal(h.legacy.length,1);
   const allowed=['id','data','obra_id','horas','entrada_manha','saida_manha','entrada_tarde','saida_tarde','periodos_alocados','estado','registado_por','atualizado_por','criado_em','atualizado_em'].sort();
   assert.deepEqual(Object.keys(h.legacy[0]).sort(),allowed);assert.doesNotMatch(JSON.stringify(h),/PRIVATE_SENTINEL|FUTURE_PRIVATE_SENTINEL|observacao|justificacao_estado|revision/);
   const client=createSheetClient({supabase:async()=>Response.json(h)});assert.deepEqual(await client.history(key),h);
   assert.equal(h.legacy[0].estado,'presente');assert.equal(h.legacy_interpretation,'original');
  }finally{await q('ALTER TABLE ponto_pessoal_obra DROP COLUMN audit_future_private');}
 });
 await t.test('P2 corrigido: histórico exclusivamente legado entra na lista diária sem escrita',async()=>{
  const key={kind:'primeline',person_id:id(45),work_id:work,date:'2026-09-24'};
  const h=await as(a,13,'SELECT fn_folha_historico_v2($1) v',[key]);
  assert.equal(h.legacy.length,1);
  const c=await daily(13,work,key.date);
  const row=c.rows.find(r=>r.person_id===key.person_id);
  assert.ok(row);assert.equal(row.legacy,true);assert.equal(row.sheet,null);assert.equal(row.conflict,null);
  assert.equal(row.can_write,false);assert.equal(row.can_remove,false);
  assert.equal(analyseSheet(row).state,'legacy');assert.equal(daySummary([row]).pending,0);
 });
 await t.test('P2 corrigido: justificação pendente preservada e contabilizada',async()=>{
  const c=await daily(13,work,'2026-01-03');
  const row=c.rows.find(r=>r.person_id===id(20));
  assert.equal(row.absence.estado,'ausente_pendente');
  assert.equal(analyseSheet({sheet:null,absence:row.absence,expectedMinutes:480}).state,'absence_pending');
  assert.equal(daySummary([{...row,sheet:null}]).pending,1);
  assert.equal(daySummary([{...row,sheet:null}]).complete,false);
 });
}
