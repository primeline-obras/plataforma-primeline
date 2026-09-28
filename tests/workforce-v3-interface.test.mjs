import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {canManageGeneralWorkforce,canReadWorkforceHistory,workforceRequest} from '../src/workforce-policy.js';
const app=await readFile(new URL('../src/app.js',import.meta.url),'utf8');
test('capacidades do quadro não herdam privilégios de outros módulos',()=>{
 for(const role of ['gestao_plataforma','administrativo']) assert(canManageGeneralWorkforce(role));
 for(const role of ['encarregado','diretor_obra','adjunto','preparador','desenhador','gerencia','financeiro','']) assert(!canManageGeneralWorkforce(role));
 assert(canReadWorkforceHistory('encarregado')); assert(!canReadWorkforceHistory('diretor_obra'));
});
test('pedido de pré-visualização e confirmação usa a mesma RPC/versionamento',async()=>{
 const calls=[]; const api=async(path,options)=>{calls.push({path,...JSON.parse(options.body)});return new Response(JSON.stringify({versao:'abc'}),{status:200});};
 const p=await workforceRequest(api,'minha_obra',{data:'2026-09-28'});
 await workforceRequest(api,'minha_obra',{data:'2026-09-28'},true,p.versao);
 assert.equal(calls[0].p_confirmar,false);assert.equal(calls[1].p_versao,'abc'); assert.equal(calls[1].path,'rpc/fn_quadro_operar');
 await assert.rejects(()=>workforceRequest(async()=>new Response(JSON.stringify({message:'bloqueado'}),{status:403}),'adicionar',{}),/bloqueado/);
});
test('interface ligada: ação limitada, consulta separada, sem substituição automática',()=>{
 assert(app.includes('id="foreman-team"')); assert(app.includes('foremanTeam.show(context)'));
 assert(app.includes('canConsultWorkforce() ? supabase(`quadro_pessoal_alocacao?'));
 assert(!app.includes('allowsMultipleWorks')); assert(!app.includes('isWorkforceForeman'));
 const save=app.slice(app.indexOf('async function saveWorkforceAllocation'),app.indexOf('function openVacationDaysDialog'));
 assert(!save.includes('method: "DELETE"'));assert(!save.includes('method: "PATCH"'));
 assert(save.includes('selectedWorkforceSourceIds.length !== 1'));
 assert(app.includes('data-workforce-action')); assert(app.includes('HISTÓRICO DE MOVIMENTAÇÕES'));
});
