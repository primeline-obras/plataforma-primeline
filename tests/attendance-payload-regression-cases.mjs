import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createSheetClient} from '../src/attendance-client.js';

export async function payloadRegressionCases(t,{q,a,as,call,aux,auxDo,id}) {
 let seq=800000;
 const data=extra=>({version:2,request_id:id(seq++),expected_revision:0,...extra});
 await t.test('P1: payroll com obra recusado antes de escrita; administrativo legítimo preservado',async()=>{
  const before=(await q('SELECT count(*)::int n FROM folha_gestao_historico')).rows[0].n;
  await assert.rejects(aux(10,'payroll_save',data({work_id:id(100),person_id:id(42),month:'2026-09-01',manual:{km:456,allowance:789,note:'SALARY_SENTINEL'}})),e=>e.code==='22023');
  assert.equal((await q('SELECT count(*)::int n FROM folha_gestao_historico')).rows[0].n,before);
  const payrollRequest=data({person_id:id(42),month:'2026-09-01',manual:{km:456,allowance:789,note:'SALARY_SENTINEL'}});
  const replay=await auxDo(10,'payroll_save',payrollRequest);
  await q("UPDATE utilizadores SET funcao='encarregado' WHERE id=$1",[id(10)]);
  try{await assert.rejects(aux(10,'payroll_save',payrollRequest,true,'unused'),e=>e.code==='42501');}
  finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
  assert.deepEqual(await auxDo(10,'payroll_save',payrollRequest),replay);
  const c=await as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[id(42),'2026-09-01']);
  for(const user of [11,12]){const admin=await as(a,user,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[id(42),'2026-09-01']);assert.equal(admin.payroll[0].manuais.note,'SALARY_SENTINEL');}
  assert.equal(c.payroll[0].manuais.note,'SALARY_SENTINEL');assert.ok(c.history.some(x=>x.dominio==='administrativo'));
 });
 await t.test('P1: JSON operacional não contém blocos administrativos, inclusive histórico antigo com obra',async()=>{
  // Only the local synthetic owner can create this deliberately mis-scoped historical row.
  await q("INSERT INTO folha_gestao_historico(empresa_id,obra_id,action,entidade_id,depois,ator_id,request_id) VALUES($1,$2,'payroll_save',$3,$4,$5,$6)",[id(1),id(100),id(42),{km:456,allowance:789,note:'SALARY_SENTINEL'},id(10),id(seq++)]);
  for(const user of [13,14,15]) {
   const c=await as(a,user,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);
   for(const field of ['payroll','live_facts','entitlements','vacations','vacation_revision','people','config'])assert.equal(Object.hasOwn(c,field),false,field);
   assert.doesNotMatch(JSON.stringify(c),/SALARY_SENTINEL|premium|allowance|"km"|payroll_save/);
   assert.ok(c.history.every(e=>['tarefas',...(user===13?[]:['he','horario'])].includes(e.dominio)));
   if(user===13)assert.deepEqual(c.overtime,[]);
  }
  await assert.rejects(as(a,16,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');
  const office=await as(a,16,'SELECT fn_folha_contexto_v2($1,NULL) v',['2026-09-25']);assert.equal(office.rows.length,1);assert.equal(office.rows[0].person_id,id(62));assert.doesNotMatch(JSON.stringify(office),/SALARY_SENTINEL|premium|allowance/);
  await assert.rejects(as(a,81,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');
  await assert.rejects(as(a,18,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');
  await assert.rejects(as(a,17,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');
  await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(13)]);
  try{await assert.rejects(as(a,13,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]),e=>e.code==='42501');}finally{await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(13)]);}
 });
 await t.test('projeção legado: precheck somente leitura recusa coluna ausente',async()=>{
  const source=await readFile(new URL('../supabase/folha_ponto_v2_precheck.sql',import.meta.url),'utf8');
  const guard=source.match(/DO \$legacy_projection\$[\s\S]*?END \$legacy_projection\$;/)[0];
  await q('BEGIN READ ONLY');await q(guard);await q('ROLLBACK');
  await q('BEGIN');await q('ALTER TABLE ponto_pessoal_obra DROP COLUMN horas');
  try{await assert.rejects(q(guard),/LEGACY_PROJECTION_COLUMNS_MISSING/);}finally{await q('ROLLBACK');}
 });
 await t.test('domínio estrutural fechado; ausência e catálogos mínimos no contexto diário',async()=>{
  await assert.rejects(q("INSERT INTO folha_gestao_historico(empresa_id,action,entidade_id,ator_id,request_id) VALUES($1,'unknown',$2,$3,$4)",[id(1),id(42),id(10),id(seq++)]),e=>e.code==='23514');
  await assert.rejects(q("INSERT INTO folha_gestao_historico(empresa_id,action,dominio,entidade_id,ator_id,request_id) VALUES($1,'payroll_save','tarefas',$2,$3,$4)",[id(1),id(42),id(10),id(seq++)]),e=>e.code==='428C9');
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-29',id(100)]);
  const absence=c.rows.find(x=>x.person_id===id(21)).absence;assert.deepEqual(Object.keys(absence).sort(),['data','estado','id','tipo']);
  for(const user of [14,15]){const reader=await as(a,user,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-29',id(100)]);assert.deepEqual(reader.providers,[]);assert.deepEqual(reader.external_people,[]);}
 });
 await t.test('P2: nenhum, só legado, só V2, ambos; projeção explícita e cliente preserva origem',async()=>{
  for(const [n,v2,legacy] of [[44,false,false],[45,false,true],[46,true,false],[47,true,true]]) {
   const day='2026-09-24',key={kind:'primeline',person_id:id(n),work_id:id(100),date:day};
   if(legacy)await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
   if(legacy)await q("INSERT INTO ponto_pessoal_obra(empresa_id,obra_id,colaborador_id,data,horas,estado,observacao,registado_por) VALUES($1,$2,$3,$4,8,'presente','PRIVATE_SENTINEL',$5)",[id(1),id(100),id(n),day,id(10)]);
   if(v2)await q("INSERT INTO folha_historico(empresa_id,obra_id,person_id,data,kind,action,revision,ator_id,request_id) VALUES($1,$2,$3,$4,'primeline','save',1,$5,$6)",[id(1),id(100),id(n),day,id(10),id(seq++)]);
   const h=await as(a,v2||legacy?13:10,'SELECT fn_folha_historico_v2($1) v',[key]);assert.equal(h.events.length,Number(v2));assert.equal(h.legacy.length,Number(legacy));assert.equal(h.legacy_interpretation,'original');
   assert.doesNotMatch(JSON.stringify(h),/PRIVATE_SENTINEL|observacao|justificacao_estado/);
   if(legacy){assert.equal(h.legacy[0].horas,8);assert.equal(Object.hasOwn(h.legacy[0],'revision'),false);}
   const client=createSheetClient({supabase:async()=>Response.json(h)});assert.deepEqual(await client.history(key),h);
   await assert.rejects(as(a,18,'SELECT fn_folha_historico_v2($1) v',[key]),e=>e.code==='42501');
  }
 });
}
