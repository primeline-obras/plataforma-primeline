import { analyseSheet, SHEET_STATES, localClock, intervalFacts, normalIntervals, daySummary, normalDaySelection } from './attendance-domain.js?v=7';
import { createSheetClient } from './attendance-client.js?v=5';
import { platformConfirm } from './platform-dialogs.js?v=1';
import {createAttendanceManagementModule} from './attendance-management.js?v=6';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function createAttendanceModule({root,supabase,isConfigured,toast,now=()=>new Date(),confirm=message=>platformConfirm(message,{title:'Folha de Ponto',confirmLabel:'CONFIRMAR'}),navigatePlanning}) {
  const client=createSheetClient({supabase,confirm});
  const management=createAttendanceManagementModule({supabase,confirm,toast,navigatePlanning,onFactsChanged:refreshFacts});
  const state={date:localClock(now()).date,workId:null,context:null,loading:false,error:'',editor:null,candidates:null,busy:false,history:null};
  let epoch=0;
  function key(row,external=false) {return {kind:external?'external':'primeline',person_id:row.person_id,work_id:state.workId,date:state.date};}
  function facts(row){const f=analyseSheet({sheet:row.sheet,absence:row.absence,legacy:row.legacy,expectedMinutes:row.expected_minutes,workType:state.context.tipo_local||'obra',specialDay:row.special_day??state.context.special_day,specialReviewed:row.special_reviewed===true});return row.conflict&&!row.sheet?.state&&!row.sheet?.estado?{...f,state:'regularization'}:f;}
  function statusDetails(row,f) {
    const types={baixa_doenca:'Baixa por doença',baixa_maternidade:'Baixa de maternidade',baixa_parental:'Baixa parental',ferias:'Férias',falta_injustificada:'Falta injustificada',falta_justificada_sem_remuneracao:'Falta justificada sem remuneração',falta_justificada_com_remuneracao:'Falta justificada com remuneração'};
    const reasons={LEGACY_WRITER_BLOCKED:'Escrita V2 bloqueada por registo legado neste dia · regularização necessária',LEGACY_CONFLICT:'Legado e Folha V2 coexistem · regularização necessária',ALLOCATION_CONFLICT:'Conflito de alocações · regularização necessária'};
    return (row.absence?`<span>${esc(types[row.absence.tipo]||row.absence.tipo)}${row.absence.estado==='ausente_pendente'&&f.state!=='absence_pending'?' · JUSTIFICAÇÃO PENDENTE':''}${['justificada','confirmada'].includes(row.absence.estado)?' · '+(row.absence.estado==='justificada'?'Justificada':'Confirmada'):''}</span>`:'')+
      (row.legacy&&f.state!=='legacy'?'<span>REGISTO LEGADO · somente leitura</span>':'')+
      (row.conflict?`<span>${esc(reasons[row.conflict]||'Conflito · regularização necessária')}</span>`:'');
  }
  function rowHtml(row,external=false) {
    const f=facts(row), can=state.context.permissions.write===true && row.can_write===true && !row.legacy;
    if(row.overtime?.estado)f.overtime=row.overtime.estado;
    return `<article class="sheet-person"><div><strong>${esc(row.name)}</strong><span>${esc(external?row.provider_name:row.role)}</span><b>${SHEET_STATES[f.state]}</b>${statusDetails(row,f)}${row.special_day?'<em>DIA ESPECIAL · '+(row.special_reviewed===true?'REVISTO':'REQUER REVISÃO')+'</em>':''}${f.overtime!=='none'&&!(row.special_day&&f.overtime==='pending_rule')?'<em>'+({potential:'Potencial HE',pending_rule:'DIA ESPECIAL — REQUER REVISÃO',pending_validation:'HE · validação administrativa pendente',rejected:'HE rejeitada',validated_pending_rule:'HE validada · regra financeira pendente'}[f.overtime]||'Pendente')+'</em>':''}</div><div class="sheet-actions">${can?`<button data-sheet-edit="${esc(row.person_id)}" data-external="${external}">${row.sheet?'EDITAR':'REGISTAR'}</button>`:''}${!external&&state.workId&&row.can_remove===true&&!row.legacy&&!row.absence&&!row.conflict?`<button data-sheet-remove="${esc(row.person_id)}">RETIRAR DA EQUIPA DE HOJE</button>`:""}<button data-sheet-history="${esc(row.person_id)}" data-external="${external}">HISTÓRICO</button></div></article>`;
  }
  function render() {
    const c=state.context;
    const summary=c?daySummary([...c.rows,...c.external_rows],{specialDay:c.special_day,workType:c.tipo_local}):null;
    const normal=c&&state.workId?normalDaySelection(c.rows,{schedule:c.schedule,date:state.date,now:localClock(now()),admin:c.admin,correctionDays:c.correction_days,specialDay:c.special_day}):null;
    root.innerHTML=`<div class="sheet-v2"><div class="sheet-toolbar"><label>LOCAL<select data-sheet-work><option value="">${c?.office_available?"ESCRITÓRIO — PRÓPRIA FOLHA":"Selecionar obra"}</option>${(c?.works||[]).map(w=>`<option value="${esc(w.id)}" ${w.id===state.workId?'selected':''}>Obra ${esc(w.number)} · ${esc(w.name)}</option>`).join('')}</select></label><label>DATA<input data-sheet-date type="date" value="${state.date}"></label><button data-sheet-refresh>ATUALIZAR</button></div>
    <p role="status">${state.loading?'A carregar…':esc(state.error)}</p>
    ${c && (state.workId||c.office_available)?`<p class="sheet-summary" data-sheet-summary>${summary.people} pessoas · ${summary.registered} registadas · ${summary.open} em aberto · ${summary.pending} pendentes${summary.complete ? " · DIA COMPLETO ✓" : ""}</p>${c.overtime_generation==="disabled_pending_compatibility"?"<p>Geração automática de HE desativada até validar calendário e compatibilidade com lançamentos manuais.</p>":""}${c.special_day?"<p>DIA ESPECIAL — registe horários reais.</p>":""}<h3>PESSOAL PRIMELINE</h3>${c.permissions.write&&state.workId?`<div class="sheet-actions">${c.permissions.allocation_write===true?"<button data-sheet-add>+ ADICIONAR PESSOA À OBRA</button>":""}<button data-sheet-bulk="start" ${!c.schedule?'disabled':''}>MARCAR EQUIPA PRESENTE</button><button data-sheet-bulk="finish" ${!c.schedule?'disabled':''}>COMPLETAR EQUIPA</button><button data-sheet-bulk="normal" ${!normal?.eligible.length?'disabled':''}>REGISTAR EQUIPA — DIA NORMAL</button></div>`:''}<div class="sheet-list">${c.rows.map(r=>rowHtml(r)).join('')||'<p>Sem pessoas alocadas neste dia.</p>'}</div><h3>MÃO DE OBRA EXTERNA</h3><div class="sheet-list">${c.external_rows.map(r=>rowHtml(r,true)).join('')||'<p>Sem registos externos neste dia.</p>'}</div>${c.permissions.external_write?'<button data-sheet-add-external>+ REGISTAR TRABALHADOR EXTERNO</button>':''}`:''}
    <div data-sheet-detail></div><section data-sheet-management></section></div>`;
    if(c?.management&&!state.loading&&!state.busy)management.show(root.querySelector('[data-sheet-management]'),{workId:state.workId,date:state.date,schedule:c.schedule});else management.reset();
    root.querySelectorAll('button,input,select').forEach(e=>{if(state.busy)e.disabled=true;});
  }
  async function load() {
    const token=++epoch;state.loading=true;state.context=null;state.error='';state.editor=null;state.candidates=null;state.history=null;render();
    try {
      if(!isConfigured)throw new Error('A Folha de Ponto necessita de ligação segura.');
      let c=await client.context(state.date,state.workId);
      if(token!==epoch)return;
      if(!state.workId && !c.office_available && c.works.length===1){state.workId=c.works[0].id;c=await client.context(state.date,state.workId);}
      if(token!==epoch)return;
      if(state.workId && !c.works.some(w=>w.id===state.workId))throw new Error('Obra indisponível para esta sessão.');
      state.context=c;
    }catch(e){if(token===epoch)state.error=e.message;}finally{if(token===epoch){state.loading=false;render();}}
  }
  function find(id,external){return (external?state.context.external_rows:state.context.rows).find(r=>r.person_id===id);}
  async function refreshFacts(action){
    if(action?.startsWith('configure_'))return load();
    const token=epoch;if(!state.context)return;
    try{
      const c=await client.context(state.date,state.workId);if(token!==epoch||!root.isConnected)return;
      state.context=c;
      const lists=root.querySelectorAll('.sheet-list');
      if(lists[0])lists[0].innerHTML=c.rows.map(r=>rowHtml(r)).join('')||'<p>Sem pessoas alocadas neste dia.</p>';
      if(lists[1])lists[1].innerHTML=c.external_rows.map(r=>rowHtml(r,true)).join('')||'<p>Sem registos externos neste dia.</p>';
      const summary=daySummary([...c.rows,...c.external_rows],{specialDay:c.special_day,workType:c.tipo_local});
      const target=root.querySelector('[data-sheet-summary]');
      if(target)target.textContent=`${summary.people} pessoas · ${summary.registered} registadas · ${summary.open} em aberto · ${summary.pending} pendentes${summary.complete?' · DIA COMPLETO ✓':''}`;
      const normal=root.querySelector('[data-sheet-bulk="normal"]');
      if(normal)normal.disabled=!normalDaySelection(c.rows,{schedule:c.schedule,date:state.date,now:localClock(now()),admin:c.admin,correctionDays:c.correction_days,specialDay:c.special_day}).eligible.length;
    }catch(e){if(token===epoch)await load();throw e;}
  }
  function openEditor(row,external) {
    state.editor={row,external};
    const intervals=row.sheet?.intervals||[];
    const slots=Array.from({length:Math.max(2,intervals.length)},(_,i)=>intervals[i]||{});
    root.querySelector('[data-sheet-detail]').innerHTML=`<form data-sheet-form><h3>${esc(row.name)}</h3><p>Registe apenas as horas já realizadas. Deixe a saída vazia enquanto estiver a trabalhar.</p>${row.absence?'<p>Existe uma ausência neste dia. O trabalho registado será enviado para regularização.</p>':''}<div class="sheet-intervals">${slots.map((x,i)=>`<label>ENTRADA ${i+1}<input type="time" name="start${i}" value="${esc(x.start)}"></label><label>SAÍDA ${i+1}<input type="time" name="end${i}" value="${esc(x.end)}"></label>`).join('')}</div><label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000">${esc(row.sheet?.note||'')}</textarea></label>${state.date<new Date(Date.parse(localClock(now()).date+'T12:00:00Z')-86400000).toISOString().slice(0,10)?'<label>MOTIVO DA CORREÇÃO (OBRIGATÓRIO)<input name="reason" maxlength="1000" required></label>':row.sheet?'<label>MOTIVO DA CORREÇÃO (OPCIONAL)<input name="reason" maxlength="1000"></label>':''}<button type="submit">GUARDAR</button><p role="alert" data-sheet-error></p></form>`;
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
    if(e.target.matches('[name=external_id]')){const f=e.target.form,p=state.context.external_people?.find(x=>x.id===e.target.value);f.elements.name.value=p?.name||'';if(p)f.elements.provider_id.value=p.provider_id;f.elements.name.readOnly=!!p;}
    if(e.target.matches('[data-sheet-date]')){state.date=e.target.value;load();}
    if(e.target.matches('[data-sheet-work]')){state.workId=e.target.value||null;load();}
  });
  root.addEventListener('submit',e=>{
    if(e.target.matches('[data-sheet-external-form]')){
      e.preventDefault();const f=e.target;
      if(!state.context.permissions.external_write||!state.context.providers?.some(p=>p.id===f.elements.provider_id.value))return;
      return write('external_register',{external_id:f.elements.external_id.value||null,provider_id:f.elements.provider_id.value,name:f.elements.name.value.trim(),note:f.elements.note.value.trim()});
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
      if(b.dataset.sheetEdit){const row=find(b.dataset.sheetEdit,b.dataset.external==='true');if(!row?.can_write||row.legacy||!state.context.permissions.write)return;return openEditor(row,b.dataset.external==='true');}
      if(b.dataset.sheetRemove){const row=find(b.dataset.sheetRemove,false);if(!row||row.can_remove!==true)return;if(row.sheet||row.absence||row.conflict||row.legacy)throw new Error("Regularize a Folha, ausência, legado ou conflito antes de retirar esta pessoa.");return write("remove_from_day",{person_id:row.person_id,expected_allocation_revision:row.allocation_revision,ids:row.allocation_ids});}
      if(b.dataset.sheetHistory){const row=find(b.dataset.sheetHistory,b.dataset.external==='true'),token=epoch;const history=await client.history(key(row,b.dataset.external==='true'));if(token!==epoch)return;root.querySelector('[data-sheet-detail]').innerHTML=`<h3>HISTÓRICO FOLHA V2</h3>${history.events.map(x=>`<p>${esc(x.at)} · ${esc(x.action)} · ${esc(x.reason)} · autor ${esc(x.ator_id)}</p><details><summary>VER ALTERAÇÃO</summary><pre>Antes: ${esc(JSON.stringify(x.antes))}\nDepois: ${esc(JSON.stringify(x.depois))}</pre></details>`).join('')||'<p>Sem alterações registadas.</p>'}<h3>REGISTO LEGADO</h3><p>Registo original, somente leitura. Não convertido para Folha V2.</p>${history.legacy.map(x=>`<article data-sheet-legacy><p>${esc(x.data)} · Obra ${esc(x.obra_id)} · ${esc(x.estado)} · ${esc(x.horas)} horas · períodos ${esc((x.periodos_alocados||[]).join(" / "))}</p><p>${esc(x.entrada_manha)}–${esc(x.saida_manha)} / ${esc(x.entrada_tarde)}–${esc(x.saida_tarde)}</p><p>Registado: ${esc(x.criado_em)} · autor ${esc(x.registado_por)} · atualizado: ${esc(x.atualizado_em)} · autor ${esc(x.atualizado_por)}</p></article>`).join('')||'<p>Sem registo legado.</p>'}`;return;}
      if(b.dataset.sheetBulk){
        const action=b.dataset.sheetBulk,clock=localClock(now());if(action==='normal'&&state.context.admin&&Date.parse(clock.date)-Date.parse(state.date)>86400000)throw new Error('Para datas anteriores à janela, registe individualmente com motivo.');
        if(action==='normal'){const chosen=normalDaySelection(state.context.rows,{schedule:state.context.schedule,date:state.date,now:clock,admin:state.context.admin,correctionDays:state.context.correction_days,specialDay:state.context.special_day});if(!chosen.eligible.length)return toast('Nenhuma pessoa elegível para dia normal.');return write('bulk',{operation:'normal',items:chosen.eligible.map(({row,intervals})=>({key:key(row),expected_revision:row.revision,intervals}))});}
        if(state.date!==clock.date)throw new Error('Use a ação coletiva apenas no próprio dia; trate datas anteriores individualmente.');
        const rows=state.context.rows.filter(r=>r.can_write&&!r.absence&&!r.legacy&&!r.conflict&&(action==='start'?!r.sheet:facts(r).open));
        if(!rows.length)return toast('Não existem pessoas elegíveis para esta ação.');
        const items=rows.map(row=>{
          let intervals;
          if(action==='start')intervals=[{start:localClock(now()).time,end:null}];
          else intervals=(row.sheet.intervals||[]).map(x=>({...x,end:x.end||clock.time}));
          if(action==='start'&&state.date!==localClock(now()).date)throw new Error('Marque a chegada coletiva apenas no próprio dia.');
          intervalFacts(intervals,{date:state.date,now:localClock(now())});
          return {key:key(row),expected_revision:row.revision,intervals};
        });
        return write('bulk',{items,operation:action,effective_time:clock.time});
      }
      if(b.hasAttribute('data-sheet-add')){
        const token=epoch;const people=await client.candidates(state.date,state.workId);if(token!==epoch)return;state.candidates=people;
        const sorted=[...people].sort((a,b)=>Number(!!a.current_work)-Number(!!b.current_work)||String(a.name).localeCompare(String(b.name),'pt'));
        root.querySelector('[data-sheet-detail]').innerHTML=`<h3>ADICIONAR PESSOA</h3><label>PESQUISAR<input data-sheet-search type="search"></label><label>PERÍODO<select data-sheet-period><option value="dia_inteiro">Dia inteiro</option><option value="manha">Manhã</option><option value="tarde">Tarde</option></select></label><div>${sorted.map(p=>`<button class="sheet-candidate" data-sheet-candidate="${esc(p.person_id)}" data-search="${esc(p.name.toLocaleLowerCase('pt'))}">${esc(p.name)} · ${esc(p.current_work?.label||'Sem alocação')}${p.recent?' · Equipa recente':''}</button>`).join('')}</div>`;return;
      }
      if(b.dataset.sheetCandidate){const person=state.candidates.find(p=>p.person_id===b.dataset.sheetCandidate);if(person.current_work && (person.current_work.type!=='obra'||person.can_transfer!==true))throw new Error('Esta transferência necessita de intervenção do Administrativo.');if(!person.current_work && person.can_allocate!==true)throw new Error('Esta pessoa não está disponível para alocação.');return write(person.current_work?'transfer':'allocate',{person_id:person.person_id,period:root.querySelector('[data-sheet-period]').value,expected_allocation_revision:person.allocation_revision,source_work_id:person.current_work?.id||null});}
      if(b.hasAttribute('data-sheet-add-external')){
        if(!state.context.permissions.external_write)return;
        root.querySelector('[data-sheet-detail]').innerHTML=`<form data-sheet-external-form><h3>MÃO DE OBRA EXTERNA</h3><label>PESSOA<select name="external_id"><option value="">Novo trabalhador</option>${(state.context.external_people||[]).map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join("")}</select></label><label>FORNECEDOR<select name="provider_id" required><option value="">Selecionar fornecedor</option>${(state.context.providers||[]).map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></label><label>NOME DO TRABALHADOR<input name="name" required maxlength="160"></label><label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000"></textarea></label><p>Registo operacional separado do cadastro Primeline. Sem cálculo de pagamento.</p><button type="submit">REGISTAR EXTERNO</button><p role="alert" data-sheet-error></p></form>`;
      }
    }catch(error){toast(error.message,'error');}
  });
  root.addEventListener('input',e=>{if(e.target.matches('[data-sheet-search]'))root.querySelectorAll('[data-sheet-candidate]').forEach(b=>b.hidden=!b.dataset.search.includes(e.target.value.toLocaleLowerCase('pt')));});
  return {show:load,refresh:load};
}
