import test from 'node:test';
import assert from 'node:assert/strict';
import {saveVehicleAssignment} from '../src/vehicle-assignment.js';
const payload={p_version:1,p_viatura_id:'vehicle',p_novo_colaborador_id:null,p_revisao_esperada:4,p_request_id:'request',p_motivo:null};
test('assignment sends exact payload once and requires a confirmed matching result',async()=>{
 let calls=0;
 const response={version:1,committed:true,viatura_id:'vehicle'};
 assert.deepEqual(await saveVehicleAssignment(async(path,options)=>{calls++;assert.equal(path,'rpc/fn_alterar_responsavel_viatura');assert.equal(options.method,'POST');assert.deepEqual(JSON.parse(options.body),payload);return Response.json(response);},payload),response);
 assert.equal(calls,1);
 for(const bad of [{...response,version:2},{...response,committed:false},{...response,viatura_id:'other'},null])await assert.rejects(()=>saveVehicleAssignment(async()=>Response.json(bad),payload),/não confirmou/);
});
test('assignment reports stale SQLSTATE, permission, validation and network without retry',async()=>{
 for(const [status,result,pattern,stale] of [[400,{code:'40001',message:'STALE_REVISION: changed'},/outro utilizador/,true],[403,{code:'42501'},/permissão/,false],[400,{code:'22023'},/validar/,false]]){
 let calls=0;await assert.rejects(()=>saveVehicleAssignment(async()=>{calls++;return Response.json(result,{status});},payload),e=>{assert.match(e.message,pattern);assert.equal(e.stale,stale);return true;});assert.equal(calls,1);
 }
 let calls=0;await assert.rejects(()=>saveVehicleAssignment(async()=>{calls++;throw Error('network');},payload),/confirmar/);assert.equal(calls,1);
});
