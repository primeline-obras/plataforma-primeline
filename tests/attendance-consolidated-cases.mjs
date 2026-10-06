import assert from 'node:assert/strict';
export async function consolidatedCases(t,{q,a,as,aux,auxDo,id,read}) {
 let seq=950000;const data=x=>({version:2,request_id:id(seq++),expected_revision:0,...x});
 await t.test('separate role capabilities; Gestão task report/confirmation and tenant remain enforced',async()=>{
  for(const [actor,admin,adm,he,report] of [[10,true,true,false,false],[11,true,false,false,false],[12,true,true,true,true],[13,false,false,false,true],[14,false,false,true,false],[15,false,false,true,false],[16,false,false,false,false]]) {
   if(actor===16){await assert.rejects(as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');continue;}
   const c=await as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);
   assert.equal(c.permissions.admin,admin);assert.equal(c.permissions.adm,adm);assert.equal(c.permissions.he_review,he);assert.equal(c.permissions.task_report,report);
  }
  for(const action of ['payroll_validate','payroll_close','payroll_reopen','he_validate','he_process','configure_he_eligibility','absence_confirm','special_review'])
   for(const actor of [11,13,14,15,16]) await assert.rejects(aux(actor,action,data({})),e=>e.code==='42501');
  await q('INSERT INTO planeamento_itens(id,fase_id,estado) VALUES($1,$2,\'em_execucao\')',[id(33901),id(500)]);
  const d=data({task_id:id(33901),work_id:id(100)});const r=await auxDo(12,'task_report',d);assert.equal(r.committed,true);assert.deepEqual(await auxDo(12,'task_report',d),r);
  await q('UPDATE utilizadores SET funcao=\'gerencia\' WHERE id=$1',[id(12)]);
  await assert.rejects(aux(12,'task_report',d),e=>e.code==='42501');await q('UPDATE utilizadores SET funcao=\'gestao_plataforma\' WHERE id=$1',[id(12)]);
  // Model a completed task whose reporting record still awaits authorized confirmation.
  await q("SELECT set_config('test.actor',$1,false)",[id(11)]);
  await q('UPDATE planeamento_itens SET estado=\'concluido\' WHERE id=$1',[id(33901)]);
  assert.equal((await q('SELECT estado FROM folha_tarefas_reportes WHERE tarefa_id=$1',[id(33901)])).rows[0].estado,'reported');
  await auxDo(12,'task_confirm',data({task_id:id(33901),work_id:id(100),expected_revision:1}));
  await assert.rejects(aux(12,'payroll_save',data({person_id:id(49),month:'2026-09-01',manual:{km:0,allowance:0}})),e=>e.code==='42501');
 });
 await t.test('Gestão can reject HE; stale revision and reduced-role replay are denied',async()=>{
  const old=(await q('SELECT overtime_enabled FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0].overtime_enabled;
  await q('UPDATE folha_config_empresa SET overtime_enabled=true WHERE empresa_id=$1',[id(1)]);
  await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Sintético HE','Pedreiro','2020-01-01')",[id(33902),id(1)]);
  const call=async(action,d)=>{const p=await as(a,12,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',[action,d]);return as(a,12,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',[action,d,p.versao]);};
  await call('allocate',data({work_id:id(100),person_id:id(33902),date:'2026-09-08',period:'dia_inteiro',expected_allocation_revision:0}));
  await call('save',data({work_id:id(100),date:'2026-09-08',key:{work_id:id(100),person_id:id(33902),date:'2026-09-08',kind:'primeline'},intervals:[{start:'09:00',end:'18:00'}],reason:'Factos sintéticos HE'}));
  const h=(await q('SELECT h.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(33902)])).rows[0];assert.ok(h);
  await assert.rejects(aux(12,'he_reject',data({id:h.id,expected_revision:h.revision+1})),e=>e.code==='40001');
  const d=data({id:h.id,expected_revision:h.revision});const r=await auxDo(12,'he_reject',d);assert.deepEqual(await auxDo(12,'he_reject',d),r);
  await q("UPDATE utilizadores SET funcao='gerencia' WHERE id=$1",[id(12)]);await assert.rejects(aux(12,'he_reject',d),e=>e.code==='42501');await q("UPDATE utilizadores SET funcao='gestao_plataforma' WHERE id=$1",[id(12)]);
  assert.equal((await q('SELECT estado FROM folha_he WHERE id=$1',[h.id])).rows[0].estado,'rejected');
  await q('UPDATE folha_config_empresa SET overtime_enabled=$2 WHERE empresa_id=$1',[id(1),old]);
 });
 await t.test('Gestão configuration commit/replay; Gerência legitimate draft preserved separately',async()=>{
  const c=(await q('SELECT * FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0];
  const d=data({expected_revision:c.revision,office_expected_minutes:c.office_expected_minutes,correction_days:1,overtime_enabled:c.overtime_enabled,calendar_complete:c.calendar_complete,holiday_dates:c.holiday_dates,calendar_validated_years:c.calendar_validated_years,payroll_rules_ready:c.payroll_rules_ready,official_template_hash:c.official_template_hash});
  const result=await auxDo(12,'configure_company',d);assert.equal(result.committed,true);assert.deepEqual(await auxDo(12,'configure_company',d),result);
  const s=(await q('SELECT * FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0];
  assert.equal((await auxDo(12,'configure_schedule',data({work_id:id(100),expected_revision:s.revision,intervals:s.intervals,expected_minutes:s.expected_minutes}))).committed,true);
  await assert.rejects(aux(12,'configure_schedule',data({work_id:id(103),intervals:s.intervals,expected_minutes:s.expected_minutes})),e=>e.code==='42501');
  await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Sintético Gerência','Pedreiro','2020-01-01')",[id(33903),id(1)]);
  assert.equal((await auxDo(11,'payroll_save',data({person_id:id(33903),month:'2026-09-01',manual:{km:0,allowance:0}}))).committed,true);
  await assert.rejects(aux(11,'payroll_validate',data({person_id:id(33903),month:'2026-09-01',expected_revision:1})),e=>e.code==='42501');
 });
 await t.test('legacy cutover: immutable history, closed DML, V2 working, unsafe rollback refused',async()=>{
  await q('UPDATE primeline_pacote2_gate.aprovacao SET consumed_at=NULL,frontend_validated=false');
  const pre=await read('../supabase/folha_v2_legacy_cutover_precheck.sql');
  await assert.rejects(q(pre),/FRONTEND_V2_VALIDATION_REQUIRED|POST_HOTFIX_VALIDATION_REQUIRED/);await q('ROLLBACK');
  await q('UPDATE primeline_pacote2_gate.aprovacao SET frontend_validated=true');await q(pre);
  const before=(await q('SELECT * FROM ponto_pessoal_obra ORDER BY id')).rows;
  await q(await read('../supabase/folha_v2_legacy_cutover.sql'));await q(await read('../supabase/folha_v2_legacy_cutover_postcheck.sql'));
  for(const sql of ['INSERT INTO ponto_pessoal_obra DEFAULT VALUES','UPDATE ponto_pessoal_obra SET horas=horas','DELETE FROM ponto_pessoal_obra','TRUNCATE ponto_pessoal_obra']) await assert.rejects(q(sql),e=>e.code==='42501');
  assert.deepEqual((await q('SELECT * FROM ponto_pessoal_obra ORDER BY id')).rows,before);
  const historical=before.find(p=>p.empresa_id===id(1)&&p.obra_id===id(100));
  assert.ok(historical);
  const history=await as(a,12,'SELECT fn_folha_historico_v2($1) v',[{person_id:historical.colaborador_id,work_id:historical.obra_id,date:historical.data,kind:'primeline'}]);
  assert.ok(history.legacy.some(p=>p.id===historical.id));
  const d=data({person_id:id(33801),month:'2026-09-01',manual:{km:0,allowance:0}});
  await q('INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,\'Sintético cutover\',\'Pedreiro\',\'2020-01-01\')',[id(33801),id(1)]);
  assert.equal((await auxDo(12,'payroll_save',d)).committed,true);
  const allocation=data({work_id:id(100),person_id:id(33801),date:'2026-09-25',period:'dia_inteiro',expected_allocation_revision:0});
  const ap=await as(a,12,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['allocate',allocation]);
  await as(a,12,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['allocate',allocation,ap.versao]);
  const sheet=data({work_id:id(100),date:'2026-09-25',key:{work_id:id(100),person_id:id(33801),date:'2026-09-25',kind:'primeline'},intervals:[{start:'09:00',end:'17:00'}],reason:'Correção sintética pós-cutover'});
  const preview=await as(a,12,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['save',sheet]);
  assert.equal((await as(a,12,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['save',sheet,preview.versao])).committed,true);
  await assert.rejects(q(await read('../supabase/folha_v2_legacy_cutover_rollback.sql')),/ROLLBACK_V2_FACTS_PRESENT/);await q('ROLLBACK');
 });
}
