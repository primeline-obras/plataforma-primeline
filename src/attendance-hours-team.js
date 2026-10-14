import {createHoursWorkerCard}from './attendance-hours-editor.js';
import {referenceSuggestions}from './attendance-hours-domain.js';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
// Prepared team view; mounting awaits the corresponding visual approval.
export function createHoursOperationalTeam({root,client,date,workId}){
 let generation=0,busy=false,context=null,error='',cards=[];
 function eligible(){return (context?.people||[]).filter(p=>p.can_write&&!p.has_absence&&!p.records.length&&!p.references.length&&!p.hidden_record_count).map(p=>({person_id:p.person_id,kind:p.kind,expected_daily_revision:p.expected_daily_revision,intervals:referenceSuggestions({date:p.date,reference:p.reference,external:p.kind==='external',mode:'dia_inteiro',specialDay:context.base.special_day})})).filter(p=>p.intervals?.length);}
 function render(){cards.forEach(c=>c.destroy());cards=[];root.innerHTML=`<section class="hours-v3-team"><header><label>DATA<input type="date" data-hours-team-date value="${esc(date)}" ${busy?'disabled':''}></label><button type="button" data-hours-team-refresh ${busy?'disabled':''}>ATUALIZAR</button><button type="button" class="sheet-primary" data-hours-team-normal ${busy||!eligible().length?'disabled':''}>DIA NORMAL DA EQUIPA · ${eligible().length}</button></header><p role="status">${busy?'A carregar…':esc(error)}</p><div data-hours-team-cards></div></section>`;
  if(context&&!busy){const host=root.querySelector('[data-hours-team-cards]');for(const day of context.people){const el=document.createElement('div');host.append(el);cards.push(createHoursWorkerCard({host:el,day,works:context.works,client,onSaved:load}));}}}
 async function load(){const token=++generation;busy=true;error='';context=null;render();try{const result=await client.team(date,workId);if(token===generation)context=result;}catch(e){if(token===generation)error=e.message;}finally{if(token===generation){busy=false;render();}}}
 async function click(e){if(e.target.closest('[data-hours-team-refresh]'))return load();if(!e.target.closest('[data-hours-team-normal]')||busy)return;const people=eligible();if(!people.length)return;busy=true;render();try{await client.executeNormalBatch({workId,date,people});}catch(e){error=e.message;}finally{busy=false;}if(!error)await load();else render();}
 function change(e){if(e.target.matches('[data-hours-team-date]')&&!busy){date=e.target.value;client.reset();load();}}
 root.addEventListener('click',click);root.addEventListener('change',change);return {load,destroy:()=>{generation++;client.reset();cards.forEach(c=>c.destroy());root.removeEventListener('click',click);root.removeEventListener('change',change);root.innerHTML='';}};
}
