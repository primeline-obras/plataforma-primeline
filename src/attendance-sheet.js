import { analyseSheet, SHEET_STATES, localClock, intervalFacts, normalIntervals } from './attendance-domain.js?v=1';
import { createSheetClient } from './attendance-client.js?v=1';
import { platformConfirm } from './platform-dialogs.js?v=1';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function createAttendanceModule({root,supabase,isConfigured,toast,now=()=>new Date(),confirm=message=>platformConfirm(message,{title:'Folha de Ponto',confirmLabel:'CONFIRMAR'})}) {
  const client=createSheetClient({supabase,confirm});
  const state={date:localClock(now()).date,workId:null,context:null,loading:false,error:'',editor:null,candidates:null,busy:false,history:null};
  let epoch=0;
  function key(row,external=false) {return {kind:external?'external':'primeline',person_id:row.person_id,work_id:state.workId,date:state.date};}
  function facts(row){return analyseSheet({sheet:row.sheet,absence:row.absence,expectedMinutes:row.expected_minutes,workType:'obra',specialDay:state.context.special_day});}
  function rowHtml(row,external=false) {
    const f=facts(row), can=state.context.permissions.write===true && row.can_write===true;
    return `<article class="sheet-person"><div><strong>${esc(row.name)}</strong><span>${esc(external?row.provider_name:row.role)}</span><b>${SHEET_STATES[f.state]}</b>${f.overtime!=='none'?'<em>'+({potential:'Potencial HE',pending_rule:'Dia especial · regra pendente',pending_validation:'Regularização pendente'}[f.overtime]||'Pendente')+'</em>':''}</div><div class="sheet-actions">${can?`<button data-sheet-edit="${esc(row.person_id)}" data-external="${external}">${row.sheet?'EDITAR':'REGISTAR'}</button>`:''}<button data-sheet-history="${esc(row.person_id)}" data-external="${external}">HISTÓRICO</button></div></article>`;
  }
  function render() {
    const c=state.context;
    root.innerHTML=`<div class="sheet-v2"><div class="sheet-toolbar"><label>OBRA<select data-sheet-work><option value="">Selecionar obra</option>${(c?.works||[]).map(w=>`<option value="${esc(w.id)}" ${w.id===state.workId?'selected':''}>Obra ${esc(w.number)} · ${esc(w.name)}</option>`).join('')}</select></label><label>DATA<input data-sheet-date type="date" value="${state.date}"></label><button data-sheet-refresh>ATUALIZAR</button></div>
    <p role="status">${state.loading?'A carregar…':esc(state.error)}</p>
    ${c && state.workId?`<h3>PESSOAL PRIMELINE</h3>${c.permissions.write?`<div class="sheet-actions"><button data-sheet-add>+ ADICIONAR PESSOA À OBRA</button><button data-sheet-bulk="start" ${!c.schedule?'disabled':''}>MARCAR EQUIPA PRESENTE</button><button data-sheet-bulk="finish" ${!c.schedule?'disabled':''}>COMPLETAR EQUIPA</button></div>`:''}<div class="sheet-list">${c.rows.map(r=>rowHtml(r)).join('')||'<p>Sem pessoas alocadas neste dia.</p>'}</div><h3>MÃO DE OBRA EXTERNA</h3><div class="sheet-list">${c.external_rows.map(r=>rowHtml(r,true)).join('')||'<p>Sem registos externos neste dia.</p>'}</div>${c.permissions.external_write?'<button data-sheet-add-external>+ REGISTAR TRABALHADOR EXTERNO</button>':''}`:''}
    <div data-sheet-detail></div></div>`;
    root.querySelectorAll('button,input,select').forEach(e=>{if(state.busy)e.disabled=true;});
  }
  async function load() {
    const token=++epoch;state.loading=true;state.context=null;state.error='';state.editor=null;state.candidates=null;state.history=null;render();
    try {
      if(!isConfigured)throw new Error('A Folha de Ponto necessita de ligação segura.');
      let c=await client.context(state.date,state.workId);
      if(token!==epoch)return;
      if(!state.workId && c.works.length===1){state.workId=c.works[0].id;c=await client.context(state.date,state.workId);}
      if(token!==epoch)return;
      if(state.workId && !c.works.some(w=>w.id===state.workId))throw new Error('Obra indisponível para esta sessão.');
      state.context=c;
    }catch(e){if(token===epoch)state.error=e.message;}finally{if(token===epoch){state.loading=false;render();}}
  }
  function find(id,external){return (external?state.context.external_rows:state.context.rows).find(r=>r.person_id===id);}
  function openEditor(row,external) {
    state.editor={row,external};
    const intervals=row.sheet?.intervals||[];
    const slots=Array.from({length:Math.max(2,intervals.length)},(_,i)=>intervals[i]||{});
    root.querySelector('[data-sheet-detail]').innerHTML=`<form data-sheet-form><h3>${esc(row.name)}</h3><p>Registe apenas as horas já realizadas. Deixe a saída vazia enquanto estiver a trabalhar.</p>${row.absence?'<p>Existe uma ausência neste dia. O trabalho registado será enviado para regularização.</p>':''}<div class="sheet-intervals">${slots.map((x,i)=>`<label>ENTRADA ${i+1}<input type="time" name="start${i}" value="${esc(x.start)}"></label><label>SAÍDA ${i+1}<input type="time" name="end${i}" value="${esc(x.end)}"></label>`).join('')}</div><label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000">${esc(row.sheet?.note||'')}</textarea></label>${row.sheet?'<label>MOTIVO DA CORREÇÃO<input name="reason" required maxlength="1000"></label>':''}<button type="submit">GUARDAR</button><p role="alert" data-sheet-error></p></form>`;
  }
  async function write(action,data) {
    if(state.busy)return;
    const token=epoch;state.busy=true;
    const controls=[...root.querySelectorAll('button,input,select')].map(e=>[e,e.disabled]);
    controls.forEach(([e])=>e.disabled=true);
    try {
      const result=await client.operate(action,{date:state.date,work_id:state.workId,...data});
      if(token!==epoch)return;
      if(result){toast('Registo confirmado.');await load();}
    }catch(e){if(token===epoch){toast(e.message,'error');if(['STALE_REVISION','40001'].includes(e.code))await load();else {const el=root.querySelector('[data-sheet-error]');if(el)el.textContent=e.message;}}}
    finally{state.busy=false;controls.forEach(([e,disabled])=>{if(e.isConnected)e.disabled=disabled;});if(!state.editor&&!state.loading)render();}
  }
  root.addEventListener('change',e=>{
    if(e.target.matches('[data-sheet-date]')){state.date=e.target.value;load();}
    if(e.target.matches('[data-sheet-work]')){state.workId=e.target.value||null;load();}
  });
  root.addEventListener('submit',e=>{
    if(e.target.matches('[data-sheet-external-form]')){
      e.preventDefault();const f=e.target;
      if(!state.context.permissions.external_write||!state.context.providers?.some(p=>p.id===f.elements.provider_id.value))return;
      return write('external_register',{provider_id:f.elements.provider_id.value,name:f.elements.name.value.trim(),note:f.elements.note.value.trim()});
    }
    if(!e.target.matches('[data-sheet-form]'))return;e.preventDefault();
    const {row,external}=state.editor, form=e.target;
    const intervals=[...form.querySelectorAll('input[name^=start]')].map((x,i)=>({start:x.value||null,end:form.elements[`end${i}`].value||null})).filter(x=>x.start||x.end);
    try{if(!intervals.length)throw new Error('Registe pelo menos uma entrada.');intervalFacts(intervals,{date:state.date,now:localClock(now())});}
    catch(error){form.querySelector('[data-sheet-error]').textContent=error.message;return;}
    write('save',{key:key(row,external),expected_revision:row.revision,intervals,note:form.elements.note.value.trim(),reason:form.elements.reason?.value.trim()||null});
  });
  root.addEventListener('click',async e=>{
    const b=e.target.closest('button');if(!b||state.busy)return;
    try {
      if(b.hasAttribute('data-sheet-refresh'))return load();
      if(b.dataset.sheetEdit){const row=find(b.dataset.sheetEdit,b.dataset.external==='true');if(!row?.can_write||!state.context.permissions.write)return;return openEditor(row,b.dataset.external==='true');}
      if(b.dataset.sheetHistory){const row=find(b.dataset.sheetHistory,b.dataset.external==='true'),token=epoch;const events=await client.history(key(row,b.dataset.external==='true'));if(token!==epoch)return;root.querySelector('[data-sheet-detail]').innerHTML=`<h3>HISTÓRICO</h3>${events.map(x=>`<p>${esc(x.at)} · ${esc(x.action)} · ${esc(x.reason)}</p>`).join('')||'<p>Sem alterações registadas.</p>'}`;return;}
      if(b.dataset.sheetBulk){
        const action=b.dataset.sheetBulk;
        const rows=state.context.rows.filter(r=>r.can_write&&!r.absence&&(action==='start'?!r.sheet:facts(r).open));
        if(!rows.length)return toast('Não existem pessoas elegíveis para esta ação.');
        const items=rows.map(row=>{
          let intervals;
          if(action==='start')intervals=[{start:localClock(now()).time,end:null}];
          else{const normal=normalIntervals(state.context.schedule,row.period||'dia_inteiro');intervals=(row.sheet.intervals||[]).map(x=>{if(x.end)return {...x};const slot=normal.find(s=>x.start>=s.start&&x.start<s.end);if(!slot)throw new Error('Complete individualmente as entradas fora do horário normal.');return {...x,end:slot.end};});}
          if(action==='start'&&state.date!==localClock(now()).date)throw new Error('Marque a chegada coletiva apenas no próprio dia.');
          intervalFacts(intervals,{date:state.date,now:localClock(now())});
          return {key:key(row),expected_revision:row.revision,intervals};
        });
        return write('bulk',{items});
      }
      if(b.hasAttribute('data-sheet-add')){
        const token=epoch;const people=await client.candidates(state.date,state.workId);if(token!==epoch)return;state.candidates=people;
        const sorted=[...people].sort((a,b)=>Number(!!a.current_work)-Number(!!b.current_work)||String(a.name).localeCompare(String(b.name),'pt'));
        root.querySelector('[data-sheet-detail]').innerHTML=`<h3>ADICIONAR PESSOA</h3><label>PESQUISAR<input data-sheet-search type="search"></label><label>PERÍODO<select data-sheet-period><option value="dia_inteiro">Dia inteiro</option><option value="manha">Manhã</option><option value="tarde">Tarde</option></select></label><div>${sorted.map(p=>`<button class="sheet-candidate" data-sheet-candidate="${esc(p.person_id)}" data-search="${esc(p.name.toLocaleLowerCase('pt'))}">${esc(p.name)} · ${esc(p.current_work?.label||'Sem alocação')}${p.recent?' · Equipa recente':''}</button>`).join('')}</div>`;return;
      }
      if(b.dataset.sheetCandidate){const person=state.candidates.find(p=>p.person_id===b.dataset.sheetCandidate);if(person.current_work && (person.current_work.type!=='obra'||person.can_transfer!==true))throw new Error('Esta transferência necessita de intervenção do Administrativo.');if(!person.current_work && person.can_allocate!==true)throw new Error('Esta pessoa não está disponível para alocação.');return write(person.current_work?'transfer':'allocate',{person_id:person.person_id,period:root.querySelector('[data-sheet-period]').value,expected_allocation_revision:person.allocation_revision,source_work_id:person.current_work?.id||null});}
      if(b.hasAttribute('data-sheet-add-external')){
        if(!state.context.permissions.external_write)return;
        root.querySelector('[data-sheet-detail]').innerHTML=`<form data-sheet-external-form><h3>MÃO DE OBRA EXTERNA</h3><label>FORNECEDOR<select name="provider_id" required><option value="">Selecionar fornecedor</option>${(state.context.providers||[]).map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></label><label>NOME DO TRABALHADOR<input name="name" required maxlength="160"></label><label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000"></textarea></label><p>Registo operacional separado do cadastro Primeline. Sem cálculo de pagamento.</p><button type="submit">REGISTAR EXTERNO</button><p role="alert" data-sheet-error></p></form>`;
      }
    }catch(error){toast(error.message,'error');}
  });
  root.addEventListener('input',e=>{if(e.target.matches('[data-sheet-search]'))root.querySelectorAll('[data-sheet-candidate]').forEach(b=>b.hidden=!b.dataset.search.includes(e.target.value.toLocaleLowerCase('pt')));});
  return {show:load,refresh:load};
}
