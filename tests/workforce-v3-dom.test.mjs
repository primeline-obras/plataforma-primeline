import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
import {workforceRequest} from '../src/workforce-policy.js';
const {JSDOM}=await import(process.env.QUADRO_JSDOM ? pathToFileURL(process.env.QUADRO_JSDOM).href : './quadro-runtime/node_modules/jsdom/lib/api.js');
const app=await readFile(new URL('../src/app.js',import.meta.url),'utf8');
const code=app.slice(app.indexOf('async function openWorkforceMyWork()'),app.indexOf('function openVacationDaysDialog'));
const tick=async()=>{for(let i=0;i<4;i++) await new Promise(resolve=>setImmediate(resolve));};
async function screen(role='encarregado',failure=false) {
 const dom=new JSDOM('<div id="workflow-dialog" hidden><h2 id="workflow-dialog-title"></h2><div id="workflow-dialog-content"></div></div>');
 const $=s=>dom.window.document.querySelector(s),calls=[],messages=[];
 const api=async(path,options)=>{
   const p=JSON.parse(options.body);calls.push({path,...p});
   if(path==='rpc/fn_quadro_obras_destino') return new Response(JSON.stringify([{id:'work-120',numero:'120',nome:'Obra autorizada'}]));
   if(failure) return new Response(JSON.stringify({message:'Várias origens: peça a resolução ao ADM/Gestão.'}),{status:400});
   return new Response(JSON.stringify({versao:'v1',colaborador:'Pessoa',data:p.p_dados.data,periodo:p.p_dados.periodo,acao:'mover',obra_origem_id:'work-118'}));
 };
 const context=vm.createContext({$,effectiveRole:()=>role,supabase:api,workforceRequest,
 safeText:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),
 collaborators:[{id:'person',nome:'Pessoa'}],selectedTeamWeek:'2026-09-28',works:[{id:'work-118',numero:'118'}],
 FormData:dom.window.FormData,friendlyApiError:async()=>'',toast:(m)=>messages.push(m),loadTeamData:async()=>{},console});
 vm.runInContext(code,context);await context.openWorkforceMyWork();
 return {dom,$,calls,messages,submit:async()=>{$('#workforce-my-form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await tick();}};
}
test('formulário exige pré-visualização, fixa destinos autorizados e confirma numa RPC',async()=>{
 const s=await screen();assert.equal(s.$('[name=obra_id]').options.length,1);assert.equal(s.$('[name=obra_id]').value,'work-120');
 await s.submit();assert(s.$('[data-move-preview]').textContent.includes('118'));assert.equal(s.calls.at(-1).p_confirmar,false);
 assert.equal(s.$('[type=submit]').textContent,'CONFIRMAR MOVIMENTAÇÃO');
 await s.submit();assert.equal(s.calls.at(-1).p_confirmar,true);assert.equal(s.calls.at(-1).p_versao,'v1');
 assert.equal(s.$('#workflow-dialog').hidden,true);s.dom.window.close();
});
test('alterar a data invalida a pré-visualização e não grava',async()=>{
 const s=await screen();await s.submit();s.$('[name=data]').value='2026-09-29';
 s.$('[name=data]').dispatchEvent(new s.dom.window.Event('change',{bubbles:true}));
 assert.equal(s.$('[data-move-preview]').textContent,'');await s.submit();assert.equal(s.calls.at(-1).p_confirmar,false);s.dom.window.close();
});
test('conflito visível no formulário, sem confirmação ou remoção',async()=>{
 const s=await screen('encarregado',true);await s.submit();assert(s.$('.form-error').textContent.includes('ADM/Gestão'));
 assert.equal(s.$('[type=submit]').disabled,false);assert(!s.calls.some(c=>c.p_confirmar));s.dom.window.close();
});
test('Diretor não consegue abrir a ação limitada',async()=>{
 const s=await screen('diretor_obra');assert.equal(s.calls.length,0);assert.equal(s.$('#workforce-my-form'),null);s.dom.window.close();
});
