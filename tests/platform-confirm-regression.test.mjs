import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const read = p => readFile(new URL('../src/'+p, import.meta.url),'utf8');
const supplier = await read('subcontractors.js');
const dashboard = await read('production-dashboard.js');
const management = await read('management-map.js');

// Execute the real confirmation prefixes. A pending/cancelled dialog must never
// reach the subsequent mutation; no backend or business data is involved.
const confirmations = [...supplier.matchAll(/const confirmed = await platformConfirm\([\s\S]*?if \(!confirmed\) return;/g)].map(m=>m[0]);
assert.equal(confirmations.length,2);
const costPrefix=dashboard.slice(dashboard.indexOf('async function confirmSubcontractCost(')).split('button.disabled = true;')[0].split('{').slice(1).join('{');
const importPrefix=management.slice(management.indexOf('async function confirmImport() {')+'async function confirmImport() {'.length).split('state.importing = true;')[0];
for (const [name,body] of [['mesclar fornecedor',confirmations[0]],['eliminar duplicado',confirmations[1]],['confirmar custo',costPrefix],['confirmar importação',importPrefix]]) {
  test(`${name}: confirmação aguardada; cancelar não escreve`,async()=>{
    let answer, calls=0, writes=0;
    const context={platformConfirm:()=>{calls++;return new Promise(r=>{answer=r;});},
      source:{nome:'Sintético'},target:{nome:'Destino'},supplier:{nome:'Sintético'},
      state:{mergePreview:{total_referencias:0},preview:{criar:1,duplicados:0},importing:false},
      meetingState:{},canAdjustWorkCosts:()=>true,write:()=>{writes++;}};
    const invoke=()=>runInNewContext(`(async()=>{${body};write();})()`,context);
    const pending=invoke();assert.equal(calls,1);assert.equal(writes,0);
    answer(false);await pending;assert.equal(writes,0);
    const allowed=invoke();assert.equal(writes,0);answer(true);await allowed;assert.equal(writes,1);
  });
}
