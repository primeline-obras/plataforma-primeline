import {readFile} from 'node:fs/promises';
const read=p=>readFile(new URL('../src/'+p,import.meta.url),'utf8').then(s=>s.replaceAll('\r',''));
const [map,costs,suppliers]=await Promise.all(['management-map.js','production-dashboard.js','subcontractors.js'].map(read));
const importBody=map.slice(map.indexOf('  async function confirmImport() {'),map.indexOf('  root.addEventListener("input"')).trim();
const costBody=costs.slice(costs.indexOf('  async function confirmSubcontractCost('),costs.indexOf('  async function openMeeting(')).trim();
const mergeStart=suppliers.indexOf('      const source = state.suppliers.find',suppliers.indexOf('if (event.target.closest("[data-confirm-supplier-merge]"))'));
const merge=suppliers.slice(mergeStart,suppliers.indexOf('      return;\n    }',mergeStart));
const deleteStart=suppliers.indexOf('      const supplier = state.suppliers.find',suppliers.indexOf('const deleteButton = event.target.closest'));
const deletion=suppliers.slice(deleteStart,suppliers.indexOf('\n    }\n  });',deleteStart));
export const definitions=[['import',importBody+';globalThis.invoke=confirmImport;'],['cost',costBody+';globalThis.invoke=()=>confirmSubcontractCost("item",button);'],['merge','globalThis.invoke=async()=>{'+merge+'};'],['delete','globalThis.invoke=async()=>{'+deletion+'};']];
export function confirmationContext(platformConfirm,write){
 const supplier={id:'source',nome:'Synthetic'};
 return {state:{preview:{criar:1,duplicados:0},importing:false,importReadyRows:[],suppliers:[supplier,{id:'target',nome:'Destination'}],allSuppliers:[supplier],supplierZones:[],supplierSpecialties:[],mergeSourceId:'source',mergeTargetId:'target',mergePreview:{pode_mesclar:true,total_referencias:0}},platformConfirm,render(){},toast(){},load:async()=>{},runImportBatches:async()=>{write();return {criados:1};},meetingState:{work:{id:'work'}},meetingReturnView:'overview',canAdjustWorkCosts:()=>true,button:{disabled:false},deleteButton:{dataset:{deleteSupplier:'source'},disabled:false},supabase:async()=>{write();return {ok:true};},query:async()=>{write();return {};},openMeeting:async()=>{},onSupplierMerged(){}};
}