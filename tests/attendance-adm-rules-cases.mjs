import assert from 'node:assert/strict';
export async function admRulesCases(t,{q,a,as,aux,auxDo,id,today}) {
 let seq=880000;const request=()=>id(seq++),data=x=>({version:2,request_id:request(),expected_revision:0,...x});
 const raw=(actor,action,d,confirmed=false,token=null)=>as(a,actor,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',[action,d,confirmed,token]);
 const save=async(actor,d)=>{const p=await raw(actor,'save',d);return raw(actor,'save',d,true,p.versao);};
 const old=(await q('SELECT to_jsonb(c) v FROM folha_config_empresa c WHERE empresa_id=$1',[id(1)])).rows[0].v;
 for(let n=20000;n<20010;n++)await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Sintético ADM','Pedreiro','2020-01-01')",[id(n),id(1)]);
 const allocate=async(p,d)=>q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,date_trunc('week',$4::date)::date,$4,'dia_inteiro',$5)",[request(),id(p),id(100),d,id(10)]);
 const sheet=(p,d,hours=8,revision=0,reason=null)=>data({work_id:id(100),date:d,key:{kind:'primeline',person_id:id(p),work_id:id(100),date:d},intervals:[{start:'00:00',end:hours===8?'08:00':hours===9?'09:00':'00:01'}],expected_revision:revision,reason});
 const dateAgo=n=>new Date(Date.parse(today+'T12:00:00Z')-n*86400000).toISOString().slice(0,10);
 await t.test('ADM: dia próprio/dia seguinte permitidos; +2 exige Administrativo/Gestão e motivo',async()=>{
  for(const [n,ago] of [[20000,0],[20001,1],[20002,2]])await allocate(n,dateAgo(ago));
  await save(13,sheet(20000,today,1));await save(13,sheet(20001,dateAgo(1),1));
  await assert.rejects(raw(13,'save',sheet(20002,dateAgo(2),1)),/CORRECTION_WINDOW_EXCEEDED/);
  await assert.rejects(raw(10,'save',sheet(20002,dateAgo(2),1)),/CORRECTION_REASON_REQUIRED/);
  const d=sheet(20002,dateAgo(2),1,0,'Correção administrativa sintética');await save(10,d);
  await save(10,{...d,request_id:request(),expected_revision:1,intervals:[{start:'00:00',end:'02:00'}]});
  const h=(await q('SELECT antes,depois,reason,ator_id,request_id FROM folha_historico WHERE person_id=$1 ORDER BY revision',[id(20002)])).rows;
  assert.equal(h.length,2);assert.equal(h[1].antes.minutes,1);assert.equal(h[1].depois.minutes,120);assert.equal(h[1].reason,d.reason);
 });
 await q('UPDATE folha_config_empresa SET calendar_complete=true,calendar_validated_years=ARRAY[2026],holiday_dates=ARRAY[\'2026-09-09\'::date,\'2026-10-05\'::date] WHERE empresa_id=$1',[id(1)]);
 await t.test('ADM: férias só úteis completos, feriado excluído, consumo e revisão atómicos',async()=>{
  const r=await auxDo(10,'vacation_set',data({person_id:id(20003),from:'2026-09-07',to:'2026-09-13'}));assert.equal(r.result.consumed_days,4);assert.equal(r.result.calendar_pending,false);
  assert.deepEqual((await q('SELECT data::text d FROM ausencias WHERE colaborador_id=$1 ORDER BY data',[id(20003)])).rows.map(x=>x.d),['2026-09-07','2026-09-08','2026-09-10','2026-09-11']);
  await assert.rejects(aux(10,'vacation_set',data({person_id:id(20003),dates:['2026-09-14'],fraction:0.5,expected_revision:1})),/VACATION_FULL_DAYS_ONLY/);
  const r2=await auxDo(10,'vacation_set',data({person_id:id(20004),dates:['2026-09-18','2026-09-19','2026-09-20','2026-09-21']}));assert.equal(r2.result.consumed_days,2);
  await q('UPDATE folha_config_empresa SET calendar_complete=false WHERE empresa_id=$1',[id(1)]);
  const r3=await auxDo(10,'vacation_set',data({person_id:id(20005),dates:['2026-09-14']}));assert.equal(r3.result.consumed_days,null);assert.equal(r3.result.calendar_pending,true);assert.equal(r3.result.pending_rule,false);
  await q('UPDATE folha_config_empresa SET calendar_complete=true WHERE empresa_id=$1',[id(1)]);
 });
 await t.test('ADM: direito informado, transitado até 30/04 e adicionais autorizados auditados',async()=>{
  await assert.rejects(aux(10,'vacation_entitlement',data({person_id:id(20003),year:2027,days:22,carry:3,additional:2,source:'Fonte sintética'})),/ENTITLEMENT_ADJUSTMENT_INVALID/);
  const r=await auxDo(10,'vacation_entitlement',data({person_id:id(20003),year:2027,days:17,carry:3,additional:2,source:'Fonte sintética',authorization:'Autorização sintética'}));assert.equal(r.result.days,17);
  const row=(await q('SELECT * FROM folha_direitos_ferias WHERE colaborador_id=$1',[id(20003)])).rows[0];assert.equal(row.saldo_transitado,3);assert.equal(row.dias_adicionais,2);assert.equal(row.validade_transitado,'2027-04-30');
  assert.equal((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE entidade_id=$1 AND action='vacation_entitlement'",[id(20003)])).rows[0].n,1);
 });
 await t.test('ADM: maternidade/parental; pendente só confirmado por Administrativo; doença exige anexo',async()=>{
  for(const [i,type] of ['baixa_doenca','baixa_maternidade','baixa_parental'].entries()) {
   const aid=request();await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado) VALUES($1,$2,$3,$4,'ausente_pendente')",[aid,id(20006),'2026-08-'+String(10+i).padStart(2,'0'),type]);
   const d=data({id:aid,expected_state:'ausente_pendente',expected_type:type,reason:'Validação documental sintética'});
   await assert.rejects(aux(13,'absence_confirm',d),e=>e.code==='42501');
   if(type==='baixa_doenca') {
    await assert.rejects(aux(10,'absence_confirm',d),/DOCUMENTO_PENDENTE/);
    await assert.rejects(as(a,13,"UPDATE ausencias SET estado='confirmada' WHERE id=$1 RETURNING id v",[aid]),/permission denied|42501|PERMISSION_DENIED/);
    await q("INSERT INTO ausencias_anexos(ausencia_id,arquivo_url,nome_arquivo) VALUES($1,'https://synthetic.invalid/document','documento-sintetico')",[aid]);
   }
   await auxDo(10,'absence_confirm',d);assert.equal((await q('SELECT estado FROM ausencias WHERE id=$1',[aid])).rows[0].estado,'confirmada');
   if(type==='baixa_doenca')await assert.rejects(q('DELETE FROM ausencias_anexos WHERE ausencia_id=$1',[aid]),/DOCUMENTO_OBRIGATORIO/);
  }
 });
 await t.test('ADM: sábado/domingo/feriado factuais especiais, nunca dia normal; revisão e sem dinheiro',async()=>{
  for(const d of ['2026-09-12','2026-09-13','2026-09-09']) {
   await allocate(20007,d);await save(10,sheet(20007,d,8,0,'Horas reais sintéticas'));
   const f=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(20007),d])).rows[0];assert.equal(f.special_day,true);
   assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id=$1',[f.id])).rows[0].n,0);
   await assert.rejects(raw(10,'bulk',data({work_id:id(100),date:d,operation:'normal',items:[sheet(20007,d,8,1,'Teste normal negado')]})),/NORMAL_DAY_CONFLICT|SPECIAL_DAY_NO_NORMAL_FILL/);
   const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[d,id(100)]);assert.equal(c.rows.find(x=>x.person_id===id(20007)).special_review_pending,true);
   await auxDo(10,'special_review',data({id:f.id,expected_revision:f.revision}));
   assert.equal((await q('SELECT special_reviewed_at IS NOT NULL ok FROM folha_registos WHERE id=$1',[f.id])).rows[0].ok,true);
  }
 });
 await t.test('ADM: elegibilidade por cargo RH, Pedreiro/Servente; motorista bloqueado por default',async()=>{
  await q('UPDATE folha_config_empresa SET overtime_enabled=true WHERE empresa_id=$1',[id(1)]);
  for(const [n,role] of [[20008,'Servente'],[20009,'Motorista']]){await q('UPDATE colaboradores SET funcao=$2 WHERE id=$1',[id(n),role]);await allocate(n,'2026-09-08');await save(10,sheet(n,'2026-09-08',9,0,'Horas reais'));}
  assert.equal((await q('SELECT count(*)::int n FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(20008)])).rows[0].n,1);
  assert.equal((await q('SELECT count(*)::int n FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(20009)])).rows[0].n,0);
  const revision=(await q('SELECT revision FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0].revision;
  await assert.rejects(aux(11,'configure_he_eligibility',data({roles:['motorista'],expected_revision:revision})),e=>e.code==='42501');
  await auxDo(10,'configure_he_eligibility',data({roles:['Pedreiro','Servente'],expected_revision:revision}));
  assert.equal((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE action='configure_he_eligibility'")).rows[0].n,1);
 });
 await t.test('ADM: HE Diretor/Adjunto → Administrativo; terceiro útil, processamento, replay e sem payroll',async()=>{
  let h=(await q('SELECT h.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(20008)])).rows[0];
  await auxDo(14,'he_approve',data({id:h.id,expected_revision:h.revision}));
  await assert.rejects(aux(11,'he_validate',data({id:h.id,expected_revision:2})),e=>e.code==='42501');
  await auxDo(10,'he_validate',data({id:h.id,expected_revision:2}));h=(await q('SELECT * FROM folha_he WHERE id=$1',[h.id])).rows[0];assert.equal(h.prazo_processamento,'2026-10-06');assert.equal(h.processado_em,null);
  assert.equal((await q("SELECT count(*)::int n FROM alertas WHERE entidade_id=$1 AND tipo='folha_he_processamento'",[h.id])).rows[0].n,1);
  const d=data({id:h.id,expected_revision:3});const r=await auxDo(10,'he_process',d);assert.deepEqual(await auxDo(10,'he_process',d),r);
  assert.equal((await q('SELECT processado_em IS NOT NULL ok FROM folha_he WHERE id=$1',[h.id])).rows[0].ok,true);
  const facts=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[id(20008),'2026-09-01']);assert.doesNotMatch(JSON.stringify(facts.live_facts),/overtime|premium|value|rate/);
  await q('UPDATE folha_config_empresa SET calendar_complete=false WHERE empresa_id=$1',[id(1)]);assert.equal((await q('SELECT folha_privado.prazo_he($1,$2) d',[id(1),'2026-09-01'])).rows[0].d,null);await q('UPDATE folha_config_empresa SET calendar_complete=true WHERE empresa_id=$1',[id(1)]);
 });
 await t.test('ADM: mapa sem prémio/HE, km explícito; validação, recibos, fecho/reabertura só Administrativo',async()=>{
  await assert.rejects(aux(10,'payroll_save',data({person_id:id(20008),month:'2026-09-01',manual:{premium:0}})),/MANUAL_FIELDS_INVALID/);
  await auxDo(10,'payroll_save',data({person_id:id(20008),month:'2026-09-01',manual:{km:12.5,allowance:0,note:'Observação manual'}}));
  const d=data({person_id:id(20008),month:'2026-09-01',expected_revision:1});await assert.rejects(aux(11,'payroll_validate',d),e=>e.code==='42501');await auxDo(10,'payroll_validate',d);
  await auxDo(10,'payroll_close',data({person_id:id(20008),month:'2026-09-01',expected_revision:2}));let v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(20008)])).rows[0];assert.equal(v.estado,'closed');assert.ok(v.recibos_recebidos_em);assert.equal(v.recibos_recebidos_por,id(10));
  await auxDo(10,'payroll_reopen',data({person_id:id(20008),month:'2026-09-01',expected_revision:3}));v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(20008)])).rows[0];assert.equal(v.estado,'draft');assert.equal(v.recibos_recebidos_em,null);assert.deepEqual(v.manuais,{km:12.5,allowance:0,note:'Observação manual'});
  await assert.rejects(aux(10,'payroll_export',data({person_id:id(20008),month:'2026-09-01',expected_revision:4})),/OFFICIAL_EXPORTER_REQUIRED/);
 });
 // Restore only test configuration, preserving its monotonic revision.
 await q('UPDATE folha_config_empresa SET office_expected_minutes=$2,correction_days=1,overtime_enabled=$3,calendar_complete=$4,holiday_dates=$5,calendar_validated_years=$6,he_eligible_roles=$7 WHERE empresa_id=$1',[id(1),old.office_expected_minutes,old.overtime_enabled,old.calendar_complete,old.holiday_dates,old.calendar_validated_years,old.he_eligible_roles]);
}
