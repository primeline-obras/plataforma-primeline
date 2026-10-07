import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {confirmationContext} from './platform-confirm-handlers.mjs';
const read=p=>readFile(new URL('../src/'+p,import.meta.url),'utf8').then(s=>s.replaceAll('\r',''));
const [map,costs,suppliers]=await Promise.all(['management-map.js','production-dashboard.js','subcontractors.js'].map(read));
const importBody=map.slice(map.indexOf('  async function confirmImport() {'),map.indexOf('  root.addEventListener("input"')).trim();
const costBody=costs.slice(costs.indexOf('  async function confirmSubcontractCost('),costs.indexOf('  async function openMeeting(')).trim();
const mergeStart=suppliers.indexOf('      const source = state.suppliers.find',suppliers.indexOf('if (event.target.closest("[data-confirm-supplier-merge]"))'));
const merge=suppliers.slice(mergeStart,suppliers.indexOf('      return;\n    }',mergeStart));
const deleteStart=suppliers.indexOf('      const supplier = state.suppliers.find',suppliers.indexOf('const deleteButton = event.target.closest'));
const deletion=suppliers.slice(deleteStart,suppliers.indexOf('\n    }\n  });',deleteStart));
const definitions=[['import',importBody+';globalThis.invoke=confirmImport;'],['cost',costBody+';globalThis.invoke=()=>confirmSubcontractCost("item",button);'],['merge','globalThis.invoke=async()=>{'+merge+'};'],['delete','globalThis.invoke=async()=>{'+deletion+'};']];
for(const [name,code] of definitions) {
 test(name+': full real handler cancellation and confirmed mutation',async()=>{
  for(const answer of [false,true]) {
   let writes=0;const supplier={id:'source',nome:'Synthetic'};
   const state={preview:{criar:1,duplicados:0},importing:false,importReadyRows:[],suppliers:[supplier,{id:'target',nome:'Destination'}],allSuppliers:[supplier],supplierZones:[],supplierSpecialties:[],mergeSourceId:'source',mergeTargetId:'target',mergePreview:{pode_mesclar:true,total_referencias:0}};
   const context={state,platformConfirm:async()=>answer,render(){},toast(){},load:async()=>{},runImportBatches:async()=>{writes++;return {criados:1};},meetingState:{work:{id:'work'}},meetingReturnView:'overview',canAdjustWorkCosts:()=>true,button:{disabled:false},deleteButton:{dataset:{deleteSupplier:'source'},disabled:false},supabase:async()=>{writes++;return {ok:true};},query:async()=>{writes++;return {};},openMeeting:async()=>{},onSupplierMerged(){}};
   runInNewContext(code,context);await context.invoke();assert.equal(writes,answer?1:0);
  }
 });
}
test('import handler must coalesce simultaneous confirmation waits',async()=>{
 const answers=[];let writes=0;
 const context={state:{preview:{criar:1,duplicados:0},importing:false,importReadyRows:[]},platformConfirm:()=>new Promise(r=>answers.push(r)),render(){},toast(){},load:async()=>{},runImportBatches:async()=>{writes++;return {criados:1};}};
 runInNewContext(importBody+';globalThis.invoke=confirmImport;',context);
 const a=context.invoke(),b=context.invoke();for(const answer of answers)answer(true);await Promise.all([a,b]);
 assert.equal(writes,1,'Two pending handler activations produce duplicate confirmed import batches');
});
for(const [name,code] of definitions) {
 test(name+': concurrent confirmation, cancellation and failed adapter release the guard',async()=>{
  let answer,calls=0,writes=0;
  const context=confirmationContext(()=>{calls++;return new Promise(r=>answer=r);},()=>writes++);
  runInNewContext(code,context);
  const first=context.invoke(),duplicate=context.invoke();assert.equal(calls,1);
  answer(false);await Promise.all([first,duplicate]);assert.equal(writes,0);
  context.platformConfirm=async()=>{throw new Error('Synthetic adapter error');};
  await context.invoke().catch(()=>{});
  assert.equal(context.state.importing,false);assert.ok(!context.state.mergeLoading);
  assert.equal(context.button.disabled,false);assert.equal(context.deleteButton.disabled,false);
  context.platformConfirm=async()=>true;await context.invoke();assert.equal(writes,1);
 });
}
