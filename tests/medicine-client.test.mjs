import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createMedicineClient,medicineOperation,medicineStatus} from '../src/medicine.js';
const today='2026-09-30';
test('estado ocupacional: sem consulta, NULL, vencida, hoje, 30/31 dias',()=>{
  assert.equal(medicineStatus(null,today).label,'Sem consulta realizada');
  for(const [date,label] of [[null,'Sem próxima consulta'],['2026-09-29','Vencida'],['2026-09-30','A vencer'],['2026-10-30','A vencer'],['2026-10-31','Válida']]) assert.equal(medicineStatus({data_proxima_consulta:date},today).label,label);
});
test('registar não inclui identidade de consulta anterior; próxima NULL permitida',()=>{
  const op=medicineOperation('registar','p',null,{data_consulta:today,resultado:'Apto'},'req',today);
  assert.deepEqual(op.payload,{p_version:1,p_colaborador_id:'p',p_data_consulta:today,p_resultado:'Apto',p_proxima_consulta:null,p_request_id:'req'});
});
test('datas futuras, inexistentes e intervalo invertido são recusados',()=>{
  for(const fields of [{data_consulta:'2026-10-01'},{data_consulta:'2026-02-30'},{data_consulta:today,proxima_consulta:'2026-09-01'}]) assert.throws(()=>medicineOperation('registar','p',null,fields,'req',today));
});
test('correção/anulação exigem motivo e revisão; anulado não pode ser editado',()=>{
  const c={id:'c',revisao:3};
  for(const action of ['corrigir','anular']) {
    assert.throws(()=>medicineOperation(action,'p',c,{data_consulta:today},'req',today));
    const op=medicineOperation(action,'p',c,{data_consulta:today,motivo:' Erro administrativo '},'req',today);
    assert.equal(op.payload.p_revisao_esperada,3);assert.equal(op.payload.p_motivo,'Erro administrativo');assert.equal(op.payload.p_consulta_id,'c');
    assert.throws(()=>medicineOperation(action,'p',{...c,anulado_em:today},{motivo:'Motivo'},'req',today));
  }
});
test('RPC de consulta é a fonte atual, preserva histórico e inativos sem filtrar',async()=>{
  const data={version:1,can_write:true,atual:{id:'c1',colaborador_id:'inactive'},consultas:[{id:'future'},{id:'cancelled'}, {id:'c1'}],historico:[]};
  const client=createMedicineClient(async(path,options)=>{assert.equal(path,'rpc/fn_medicina_consultar_colaborador');assert.deepEqual(JSON.parse(options.body),{p_version:1,p_colaborador_id:'inactive'});return Response.json(data);});
  assert.deepEqual(await client.consult('inactive'),data);
});
test('replay repete payload/request, sem DML direto nem repetição automática',async()=>{
  const calls=[];const client=createMedicineClient(async(path,options)=>{calls.push([path,JSON.parse(options.body)]);return Response.json({version:1,committed:true,idempotent:calls.length>1,consulta:{id:'c',colaborador_id:'p'}});});
  const op=medicineOperation('registar','p',null,{data_consulta:today},'same-request',today);
  await client.save(op);const result=await client.save(op);assert.equal(result.idempotent,true);assert.deepEqual(calls[0],calls[1]);assert.equal(calls.length,2);
});
test('não simula sucesso: resposta incompleta, pessoa errada e committed false',async()=>{
  for(const response of [{},{version:1,committed:false},{version:1,committed:true,consulta:{id:'c',colaborador_id:'other'}}]) {
    const client=createMedicineClient(async()=>Response.json(response));
    await assert.rejects(client.save({name:'fn_medicina_registar_consulta',payload:{},personId:'p'}),e=>e.uncertain===true);
  }
});
test('stale, permissão e RPC ausente falham sem repetição',async()=>{
  for(const [status,code] of [[400,'40001'],[403,'42501'],[404,'PGRST202']]) {
    let count=0;const client=createMedicineClient(async()=>{count++;return Response.json({code},{status});});
    await assert.rejects(client.consult('p'),e=>code!=='40001'||e.stale===true);assert.equal(count,1);
  }
});
test('painel global usa a mesma RPC, inclui sem consulta e limita concorrência',async()=>{
  let active=0,peak=0;const client=createMedicineClient(async()=>{peak=Math.max(peak,++active);await new Promise(r=>setTimeout(r,1));active--;return Response.json({version:1,can_write:false,atual:null});});
  const rows=await client.list(Array.from({length:12},(_,id)=>({id:String(id)})));assert.equal(rows.length,12);assert.ok(peak<=4);assert.ok(rows.every(r=>r.current===null));
});
test('frontend não consulta nem escreve diretamente medicina_trabalho',()=>{
  const app=readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
  const module=readFileSync(new URL('../src/medicine.js',import.meta.url),'utf8');
  assert.doesNotMatch(app,/supabase\(["'`]medicina_trabalho/);
  assert.doesNotMatch(module,/medicina_trabalho\?|method:\s*['"](?:PATCH|DELETE)/);
  assert.match(app,/medicineClient\.list\(collaborators\)/);
  assert.match(app,/data-edit-collaborator="\$\{person.id\}">CONSULTAR FICHA/);
});
