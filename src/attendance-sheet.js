import { analyseSheet, SHEET_STATES, localClock, intervalFacts, normalIntervals, daySummary, normalDaySelection, dayStatus, workedTime, delegationLabel } from './attendance-domain.js?v=8';
import { createSheetClient } from './attendance-client.js?v=7';
import { platformConfirm } from './platform-dialogs.js?v=1';
import {createAttendanceManagementModule} from './attendance-management.js?v=7';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function createAttendanceModule({root,supabase,isConfigured,toast,now=()=>new Date(),confirm=message=>platformConfirm(message,{title:'Folha de Ponto',confirmLabel:message.startsWith('REGISTAR ENTRADA')?'CONFIRMAR ENTRADAS':message.startsWith('CONFIRMAR SAÍDAS')?'CONFIRMAR SAÍDAS':message.includes('deixará a equipa')?'CONFIRMAR RETIRADA':'CONFIRMAR',danger:message.includes('deixará a equipa')}),navigatePlanning}) {
  const client=createSheetClient({supabase,confirm});
  const management=createAttendanceManagementModule({supabase,confirm,toast,navigatePlanning,onFactsChanged:refreshFacts});
  const state={date:localClock(now()).date,workId:null,context:null,loading:false,error:'',editor:null,candidates:null,busy:false,history:null,panelToken:0,notice:null,historyRequest:0};
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
    return `<article class="sheet-person" data-person="${esc(row.person_id)}" data-kind="${external?'external':'primeline'}" tabindex="-1"><div><strong>${esc(row.name)}</strong><span>${esc(external?(row.role||'FUNÇÃO POR REGISTAR')+' · '+row.provider_name:row.role)}</span><b>${SHEET_STATES[f.state]}</b><span>${esc((row.sheet?.intervals||[]).map(x=>`${x.start}–${x.end||'Em aberto'}`).join(' / ')||'Sem horário registado')}</span><strong>TOTAL: ${esc(workedTime(row.sheet?.intervals||[]))}</strong>${!external?`<span>${esc(delegationLabel(row.delegation,state.context.delegation))}</span>`:''}${statusDetails(row,f)}${row.special_day?'<em>DIA ESPECIAL · '+(row.special_reviewed===true?'REVISTO':'REQUER REVISÃO')+'</em>':''}${f.overtime!=='none'&&!(row.special_day&&f.overtime==='pending_rule')?'<em>'+({potential:'Potencial HE',pending_rule:'DIA ESPECIAL — REQUER REVISÃO',pending_validation:'HE · validação administrativa pendente',rejected:'HE rejeitada',validated_pending_rule:'HE validada · regra financeira pendente'}[f.overtime]||'Pendente')+'</em>':''}</div><div class="sheet-actions">${can?`<button class="sheet-primary" data-sheet-edit="${esc(row.person_id)}" data-external="${external}">${row.sheet?'EDITAR':'REGISTAR'}</button>`:''}${!external&&state.workId&&row.can_remove===true&&!row.legacy&&!row.absence&&!row.conflict?`<button class="sheet-remove" data-sheet-remove="${esc(row.person_id)}">RETIRAR DA EQUIPA</button>`:""}</div>${state.notice?.id===row.person_id?`<p class="sheet-feedback" role="status">${esc(state.notice.message)}</p>`:''}</article>`;
  }
  function emptyTeam(){return `<div class="sheet-empty"><p>Esta obra ainda não tem equipa configurada para esta data. Adicione os Pedreiros e Serventes que pertencem à obra. Eles continuarão na equipa até serem retirados ou transferidos.</p>${state.context?.permissions.allocation_write&&state.workId?'<button data-sheet-add>ADICIONAR PESSOAS À EQUIPA</button>':''}</div>`;}
  function card(id){return [...root.querySelectorAll('[data-person]')].find(e=>e.dataset.person===id);}
  function closePanel(){state.panelToken++;state.editor=null;state.candidates=null;root.querySelector('[data-sheet-detail]')?.remove();root.querySelectorAll('[aria-expanded]').forEach(e=>e.setAttribute('aria-expanded','false'));}
  function panel(host,title,button){closePanel();const el=document.createElement('section');el.dataset.sheetDetail='';el.className='sheet-panel';el.innerHTML=`<header class="sheet-panel-heading"><h3>${esc(title)}</h3><button type="button" data-sheet-cancel>CANCELAR</button></header><div data-sheet-panel-body></div>`;host.append(el);if(button){button.setAttribute('aria-expanded','true');el._origin=button;}return el.querySelector('[data-sheet-panel-body]');}
  function workLabel(){const w=state.context.works.find(x=>x.id===state.workId);return w?`Obra ${w.number} · ${w.name}`:'Escritório';}
  function scopeLabel(){return `${workLabel()} · ${state.date.split('-').reverse().join('/')}`;}
  function bulkMessage(operation,items){const names=items.map(x=>find(x.key.person_id,false)?.name||'Pessoa');const times=items.map(x=>x.intervals.map(i=>`${i.start}–${i.end||'Em aberto'}`).join(' / '));return `${operation==='start'?'REGISTAR ENTRADA AGORA?':operation==='finish'?'CONFIRMAR SAÍDAS DA EQUIPA?':'REGISTAR EQUIPA — DIA NORMAL?'}\n${scopeLabel()}\n${items.length} pessoas\n${names.map((n,i)=>`${n} · ${times[i]}`).join('\n')}\n${operation==='start'?'Isto irá abrir o ponto destas pessoas com a hora de entrada indicada.':operation==='finish'?'Isto irá completar os pontos abertos com a hora de saída indicada.':'Este horário será registado para as pessoas indicadas.'}`;}
  function render() {
    const c=state.context;
    const summary=c?daySummary([...c.rows,...c.external_rows],{specialDay:c.special_day,workType:c.tipo_local}):null;
    const normal=c&&state.workId?normalDaySelection(c.rows,{schedule:c.schedule,date:state.date,now:localClock(now()),admin:c.admin,correctionDays:c.correction_days,specialDay:c.special_day}):null;
    root.innerHTML=`<div class="sheet-v2"><div class="sheet-toolbar"><label>LOCAL<select data-sheet-work><option value="">${c?.office_available?"ESCRITÓRIO — PRÓPRIA FOLHA":"Selecionar obra"}</option>${(c?.works||[]).map(w=>`<option value="${esc(w.id)}" ${w.id===state.workId?'selected':''}>Obra ${esc(w.number)} · ${esc(w.name)}</option>`).join('')}</select></label><label>DATA<input data-sheet-date type="date" value="${state.date}"></label><button data-sheet-day="-1" aria-label="Dia anterior">DIA ANTERIOR</button><button data-sheet-day="1" aria-label="Dia seguinte">DIA SEGUINTE</button><button data-sheet-refresh>ATUALIZAR</button>${c&&(state.workId||c.office_available)?'<button data-sheet-work-history>HISTÓRICO DA OBRA</button>':''}</div>
    <p role="status">${state.loading?'A carregar…':esc(state.error)}</p>
    ${c && (state.workId||c.office_available)?`<p class="sheet-summary" data-sheet-summary>${summary.people} pessoas · ${summary.registered} registadas · ${summary.open} em aberto · ${summary.pending} pendentes${" · "+dayStatus(summary)}</p>${c.admin&&c.overtime_generation==="disabled_pending_compatibility"?"<p>Geração automática de HE desativada até validar calendário e compatibilidade com lançamentos manuais.</p>":""}${c.special_day?"<p>DIA ESPECIAL — registe horários reais.</p>":""}<h3>PESSOAL PRIMELINE</h3>${c.permissions.write&&state.workId?`<div class="sheet-actions">${c.permissions.allocation_write===true?"<button data-sheet-add>+ ADICIONAR PESSOA À OBRA</button>":""}<button data-sheet-bulk="start" ${state.date!==localClock(now()).date||!c.rows.some(r=>r.can_write&&!r.sheet&&!r.absence&&!r.legacy&&!r.conflict)?'disabled':''}>MARCAR EQUIPA PRESENTE</button><button data-sheet-bulk="finish" ${state.date!==localClock(now()).date||!c.rows.some(r=>r.can_write&&r.sheet&&facts(r).open&&!r.absence&&!r.legacy&&!r.conflict)?'disabled':''}>COMPLETAR EQUIPA</button><button data-sheet-bulk="normal" ${!c.calendar_verified||!normal?.eligible.length?'disabled':''}>REGISTAR EQUIPA — DIA NORMAL</button></div>`:''}<div data-sheet-work-history-panel></div><div data-sheet-team-panel></div><div class="sheet-list">${c.rows.map(r=>rowHtml(r)).join('')||emptyTeam()}</div><h3>MÃO DE OBRA EXTERNA</h3><div class="sheet-list">${c.external_rows.map(r=>rowHtml(r,true)).join('')||'<p>Sem registos externos neste dia.</p>'}</div>${c.permissions.external_write?'<button data-sheet-add-external>+ REGISTAR TRABALHADOR EXTERNO</button>':''}`:''}
    <div data-sheet-external-panel></div><section data-sheet-management></section></div>`;
    if(c?.management&&!state.loading&&!state.busy)management.show(root.querySelector('[data-sheet-management]'),{workId:state.workId,date:state.date,schedule:c.schedule});else management.reset();
    root.querySelectorAll('button,input,select').forEach(e=>{if(state.busy){e.dataset.sheetDisabled=String(e.disabled);e.disabled=true;}});
  }
  async function load() {
    const token=++epoch;state.loading=true;state.context=null;state.error='';state.editor=null;state.candidates=null;state.history=null;state.panelToken++;render();
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
      if(target)target.textContent=`${summary.people} pessoas · ${summary.registered} registadas · ${summary.open} em aberto · ${summary.pending} pendentes${" · "+dayStatus(summary)}`;
      const normal=root.querySelector('[data-sheet-bulk="normal"]');
      if(normal)normal.disabled=!c.calendar_verified||!normalDaySelection(c.rows,{schedule:c.schedule,date:state.date,now:localClock(now()),admin:c.admin,correctionDays:c.correction_days,specialDay:c.special_day}).eligible.length;
    }catch(e){if(token===epoch)await load();throw e;}
  }
  function openEditor(row,external) {
    const target=panel(card(row.person_id),`${row.sheet?'EDITAR HORÁRIO':'REGISTAR HORÁRIO'} — ${row.name}`,root.querySelector(`[data-sheet-edit="${row.person_id}"]`));state.editor={row,external};
    const intervals=row.sheet?.intervals||[];
    const slots=Array.from({length:Math.max(2,intervals.length)},(_,i)=>intervals[i]||{});
    target.innerHTML=`<form data-sheet-form><p>${esc(scopeLabel())}</p><p>Registe apenas as horas já realizadas. Deixe a saída vazia enquanto estiver a trabalhar.</p>${row.absence?'<p>Existe uma ausência neste dia. O trabalho registado será enviado para regularização.</p>':''}<div class="sheet-intervals">${slots.map((x,i)=>`<label>ENTRADA ${i+1}<input type="time" name="start${i}" value="${esc(x.start)}"></label><label>SAÍDA ${i+1}<input type="time" name="end${i}" value="${esc(x.end)}"></label>`).join('')}</div><label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000">${esc(row.sheet?.note||'')}</textarea></label>${state.date<new Date(Date.parse(localClock(now()).date+'T12:00:00Z')-86400000).toISOString().slice(0,10)?'<label>MOTIVO DA CORREÇÃO (OBRIGATÓRIO)<input name="reason" maxlength="1000" required></label>':row.sheet?'<label>MOTIVO DA CORREÇÃO (OPCIONAL)<input name="reason" maxlength="1000"></label>':''}<output data-sheet-total>TOTAL: ${esc(workedTime(intervals))}</output><button type="button" data-sheet-add-interval>+ ADICIONAR INTERVALO</button><button class="sheet-primary" type="submit">GUARDAR</button><p role="alert" data-sheet-error></p></form>`;
  }
  async function loadWorkHistory(form){const request=state.panelToken,historyRequest=++state.historyRequest,from=form.elements.from.value,to=form.elements.to.value,token=epoch,workId=state.workId,results=root.querySelector('[data-sheet-work-history-results]');results.innerHTML='<p role="status">A carregar horas da obra…</p>';const button=form.querySelector('button');button.disabled=true;try{const entries=await client.workHistory(from,to,workId);if(token!==epoch||request!==state.panelToken||historyRequest!==state.historyRequest)return;results.innerHTML=`<p>Horas registadas nesta obra · ${esc(from)} a ${esc(to)}. Os registos legados e V2 são apresentados separadamente.</p>${entries.map(x=>`<article class="sheet-history-event" data-sheet-work-record ${x.source==='legacy'?'data-sheet-legacy':''}><strong>${esc(x.name)}</strong><p>${esc(x.role)}${x.kind==='external'?' · MÃO DE OBRA EXTERNA':''} · ${esc(x.date.split('-').reverse().join('/'))}</p><p>${esc(x.intervals.map(i=>`${i.start}–${i.end||'Em aberto'}`).join(' / ')||'Sem intervalos históricos')}</p><strong>TOTAL: ${esc(x.source==='legacy'?String(x.hours??'Por confirmar')+'h':workedTime(x.intervals))}</strong><p>${esc(x.source==='legacy'?'REGISTO LEGADO · somente leitura':SHEET_STATES[x.state]||'Registo factual')}${x.conflict?' · CONFLITO — REQUER REGULARIZAÇÃO':''}</p></article>`).join('')||'<p>Sem horas registadas nesta obra no período selecionado.</p>'}`;}catch(error){if(request===state.panelToken&&historyRequest===state.historyRequest)results.textContent=error.message;}finally{if(button.isConnected)button.disabled=false;}}
  async function write(action,data,message=null) {
    if(state.busy)return;
    const token=epoch,position=window.scrollY,personId=data.key?.person_id||data.people?.[0]?.person_id;state.busy=true;const feedback=document.createElement('p');feedback.className='sheet-feedback';feedback.setAttribute('role','status');feedback.textContent='A preparar confirmação…';const host=root.querySelector('[data-sheet-detail]');if(host)host.append(feedback);else root.querySelector('.sheet-summary').insertAdjacentElement('afterend',feedback);
    const controls=[...root.querySelectorAll('button,input,select')].map(e=>[e,e.disabled]);
    controls.forEach(([e])=>e.disabled=true);
    try {
      const result=await client.operate(action,{date:state.date,work_id:state.workId,...data},message);
      if(token!==epoch)return;
      if(result){toast('Registo confirmado.');const affected=personId||result.changed_keys[0]?.person_id;state.notice={id:affected,message:'Registo confirmado.'};await load();window.scrollTo(0,position);const target=card(affected);target?.scrollIntoView({block:'nearest'});target?.focus({preventScroll:true});}
    }catch(e){if(token===epoch){toast(e.message,'error');if(['STALE_REVISION','40001'].includes(e.code))await load();else {const el=root.querySelector('[data-sheet-error]');if(el)el.textContent=e.message;else {const status=root.querySelector('[role=status]');if(status)status.textContent=e.message;}}}}
    finally{feedback.remove();state.busy=false;root.querySelectorAll('[data-sheet-disabled]').forEach(e=>{e.disabled=e.dataset.sheetDisabled==='true';delete e.dataset.sheetDisabled;});controls.forEach(([e,disabled])=>{if(e.isConnected)e.disabled=disabled;});}
  }
  root.addEventListener('change',e=>{
    if(e.target.matches('[data-sheet-candidate]')){const count=root.querySelectorAll('[data-sheet-candidate]:checked').length;const button=root.querySelector('[data-sheet-add-selected]');button.disabled=count===0;button.textContent=count?'CONFIRMAR '+count+' PESSOA'+(count>1?'S':''):'ADICIONAR SELECIONADOS';}
    if(e.target.matches('[name=external_id]')){const f=e.target.form,p=state.context.external_people?.find(x=>x.id===e.target.value);f.elements.name.value=p?.name||'';if(p)f.elements.provider_id.value=p.provider_id;f.elements.name.readOnly=!!p;}
    if(e.target.matches('[data-sheet-date]')){state.notice=null;state.date=e.target.value;load();}
    if(e.target.matches('[data-sheet-work]')){state.notice=null;state.workId=e.target.value||null;load();}
  });
  root.addEventListener('submit',e=>{
    if(e.target.matches('[data-sheet-history-range]')){e.preventDefault();return loadWorkHistory(e.target);}
    if(e.target.matches('[data-sheet-external-form]')){
      e.preventDefault();const f=e.target;
      if(!state.context.permissions.external_write||!state.context.providers?.some(p=>p.id===f.elements.provider_id.value))return;
      const intervals=[...f.querySelectorAll('input[name^=start]')].map((x,i)=>({start:x.value||null,end:f.elements['end'+i].value||null})).filter(x=>x.start||x.end);
      try{if(!intervals.length)throw new Error('Registe pelo menos uma entrada.');intervalFacts(intervals,{date:state.date,now:localClock(now())});}catch(error){f.querySelector('[data-sheet-error]').textContent=error.message;return;}
      return write('external_register',{external_id:f.elements.external_id.value||null,provider_id:f.elements.provider_id.value,name:f.elements.name.value.trim(),role:f.elements.role.value,intervals,note:f.elements.note.value.trim(),reason:f.elements.reason?.value.trim()||null},`REGISTAR TRABALHADOR EXTERNO?\n${f.elements.name.value.trim()} · ${f.elements.role.value}\n${scopeLabel()}\n${intervals.map(i=>`${i.start}–${i.end||'Em aberto'}`).join(' / ')}\nTOTAL: ${workedTime(intervals)}`);
    }
    if(!e.target.matches('[data-sheet-form]'))return;e.preventDefault();
    const {row,external}=state.editor, form=e.target;
    const intervals=[...form.querySelectorAll('input[name^=start]')].map((x,i)=>({start:x.value||null,end:form.elements[`end${i}`].value||null})).filter(x=>x.start||x.end);
    try{if(!intervals.length)throw new Error('Registe pelo menos uma entrada.');intervalFacts(intervals,{date:state.date,now:localClock(now())});}
    catch(error){form.querySelector('[data-sheet-error]').textContent=error.message;return;}
    write('save',{key:key(row,external),expected_revision:row.revision,intervals,note:form.elements.note.value.trim(),reason:form.elements.reason?.value.trim()||null},`CONFIRMAR HORÁRIO — ${row.name}?\n${scopeLabel()}\n${intervals.map(i=>`${i.start}–${i.end||'Em aberto'}`).join(' / ')}\nTOTAL: ${workedTime(intervals)}`);
  });
  root.addEventListener('click',async e=>{
    const b=e.target.closest('button');if(!b||state.busy||state.loading)return;
    try {
      if(b.hasAttribute('data-sheet-cancel')){const origin=b.closest('[data-sheet-detail]')._origin;closePanel();origin?.focus({preventScroll:true});return;}
      if(b.hasAttribute('data-sheet-day')){const d=new Date(state.date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+Number(b.dataset.sheetDay));state.date=d.toISOString().slice(0,10);state.notice=null;return load();}
      if(b.hasAttribute('data-sheet-refresh'))return load();
      if(b.dataset.sheetEdit){const row=find(b.dataset.sheetEdit,b.dataset.external==='true');if(!row?.can_write||row.legacy||!state.context.permissions.write)return;return openEditor(row,b.dataset.external==='true');}
      if(b.dataset.sheetRemove){const row=find(b.dataset.sheetRemove,false);if(!row||row.can_remove!==true)return;if(row.sheet||row.absence||row.conflict||row.legacy)throw new Error("Regularize a Folha, ausência, legado ou conflito antes de retirar esta pessoa.");return write('team_remove',{people:[{person_id:row.person_id,expected_revision:row.team_revision}]},`${row.name} deixará a equipa de ${scopeLabel()}.\nO histórico anterior será preservado. Isto não regista uma falta ou ausência.`);}
      if(b.hasAttribute('data-sheet-work-history')){const body=panel(root.querySelector('[data-sheet-work-history-panel]'),`HISTÓRICO — ${workLabel()}`,b);body.innerHTML=`<p>Escolha um período até 31 dias.</p><form data-sheet-history-range><div class="sheet-intervals"><label>DE<input type="date" name="from" value="${state.date}" required></label><label>ATÉ<input type="date" name="to" value="${state.date}" required></label></div><button type="submit">CONSULTAR HORAS</button></form><div data-sheet-work-history-results></div>`;return loadWorkHistory(body.querySelector('form'));}
      if(b.dataset.sheetBulk){
        const action=b.dataset.sheetBulk,clock=localClock(now());if(action==='normal'&&state.context.admin&&Date.parse(clock.date)-Date.parse(state.date)>86400000)throw new Error('Para datas anteriores à janela, registe individualmente com motivo.');
        if(action==='normal'){const chosen=normalDaySelection(state.context.rows,{schedule:state.context.schedule,date:state.date,now:clock,admin:state.context.admin,correctionDays:state.context.correction_days,specialDay:state.context.special_day});if(!chosen.eligible.length)return toast('Nenhuma pessoa elegível para dia normal.');const items=chosen.eligible.map(({row,intervals})=>({key:key(row),expected_revision:row.revision,intervals}));return write('bulk',{operation:'normal',items},bulkMessage('normal',items));}
        if(state.date!==clock.date)throw new Error('Use a ação coletiva apenas no próprio dia; trate datas anteriores individualmente.');
        const rows=state.context.rows.filter(r=>r.can_write&&!r.absence&&!r.legacy&&!r.conflict&&(action==='start'?!r.sheet:facts(r).open));
        if(!rows.length)return toast('Não existem pessoas elegíveis para esta ação.');
        const items=rows.map(row=>{
          let intervals;
          if(action==='start')intervals=[{start:clock.time,end:null}];
          else intervals=(row.sheet.intervals||[]).map(x=>({...x,end:x.end||clock.time}));
          if(action==='start'&&state.date!==localClock(now()).date)throw new Error('Marque a chegada coletiva apenas no próprio dia.');
          intervalFacts(intervals,{date:state.date,now:localClock(now())});
          return {key:key(row),expected_revision:row.revision,intervals};
        });
        return write('bulk',{items,operation:action,effective_time:clock.time},bulkMessage(action,items));
      }
      if(b.hasAttribute('data-sheet-add')){
        const target=panel(root.querySelector('[data-sheet-team-panel]'),'ADICIONAR PESSOAS À EQUIPA',b),request=state.panelToken;target.innerHTML='<p role="status">A carregar pessoas disponíveis…</p>';const token=epoch;const people=await client.candidates(state.date,state.workId);if(token!==epoch||request!==state.panelToken)return;state.candidates=people;
        const sorted=[...people].sort((a,b)=>Number(!!a.current_work)-Number(!!b.current_work)||String(a.name).localeCompare(String(b.name),'pt'));
        target.innerHTML=`<p>${esc(scopeLabel())}</p><p>Estas pessoas ficam na equipa desta obra a partir desta data, até serem retiradas ou transferidas.</p><label>PESQUISAR<input data-sheet-search type="search"></label><div>${sorted.map(p=>`<label class="sheet-candidate" data-search="${esc(p.name.toLocaleLowerCase('pt'))}"><input type="checkbox" data-sheet-candidate="${esc(p.person_id)}" ${!p.can_allocate&&!p.can_transfer?'disabled':''}><span>${esc(p.name)} · ${esc(p.role)} · ${esc(p.current_work?.label||'Sem alocação')} · ${esc(delegationLabel(p.delegation,state.context.delegation))}</span></label>`).join('')||'<p>Não existem pessoas elegíveis para adicionar a esta equipa.</p>'}</div><button data-sheet-add-selected disabled>ADICIONAR SELECIONADOS</button>`;return;
      }
      if(b.hasAttribute('data-sheet-add-selected')){const ids=[...root.querySelectorAll('[data-sheet-candidate]:checked')].map(e=>e.dataset.sheetCandidate);if(!ids.length)return;const selected=ids.map(id=>state.candidates.find(p=>p.person_id===id));if(selected.some(p=>p.current_work&&!p.can_allocate)){if(selected.length!==1||!selected[0].can_transfer)throw new Error('Selecione uma só pessoa para confirmar a transferência autorizada.');return write('team_transfer',{people:[{person_id:selected[0].person_id,expected_revision:selected[0].team_revision,source_work_id:selected[0].current_work.id}]},`CONFIRMAR TRANSFERÊNCIA — ${selected[0].name}?\nDe ${selected[0].current_work.label} para ${scopeLabel()}.\nA pessoa permanecerá nesta equipa até ser retirada ou transferida. O histórico será preservado.`);}return write('team_add',{people:selected.map(p=>({person_id:p.person_id,expected_revision:p.team_revision}))},`ADICIONAR ${selected.length} PESSOAS À EQUIPA?\n${scopeLabel()}\n${selected.map(p=>p.name).join('\n')}\nEstas pessoas ficam na equipa até serem retiradas ou transferidas.`);}
      if(b.hasAttribute('data-sheet-add-interval')){const f=b.form,n=f.querySelectorAll('input[name^=start]').length;f.querySelector('.sheet-intervals').insertAdjacentHTML('beforeend',`<label>ENTRADA ${n+1}<input type="time" name="start${n}"></label><label>SAÍDA ${n+1}<input type="time" name="end${n}"></label>`);return;}
      if(b.hasAttribute('data-sheet-add-external')){
        if(!state.context.permissions.external_write)return;
        panel(root.querySelector('[data-sheet-external-panel]'),'REGISTAR TRABALHADOR EXTERNO',b).innerHTML=`<form data-sheet-external-form><p>${esc(scopeLabel())}</p><label>PESSOA<select name="external_id"><option value="">Novo trabalhador</option>${(state.context.external_people||[]).map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join("")}</select></label><label>FORNECEDOR<select name="provider_id" required><option value="">Selecionar fornecedor</option>${(state.context.providers||[]).map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></label><label>NOME DO TRABALHADOR<input name="name" required maxlength="160"></label><label>FUNÇÃO<select name="role" required><option value="">Selecionar</option><option value="pedreiro">PEDREIRO</option><option value="servente">SERVENTE</option></select></label><div class="sheet-intervals">${[0,1].map(i=>`<label>ENTRADA ${i+1}<input type="time" name="start${i}"></label><label>SAÍDA ${i+1}<input type="time" name="end${i}"></label>`).join('')}</div><output data-sheet-total>TOTAL: 0h</output><button type="button" data-sheet-add-interval>+ ADICIONAR INTERVALO</button>${state.date<localClock(now()).date?'<label>MOTIVO DA CORREÇÃO<input name="reason" required maxlength="1000"></label>':''}<label>OBSERVAÇÃO OPERACIONAL<textarea name="note" maxlength="1000"></textarea></label><p>Registo operacional separado do cadastro Primeline. Sem cálculo de pagamento.</p><button class="sheet-primary" type="submit">REGISTAR EXTERNO</button><p role="alert" data-sheet-error></p></form>`;
      }
    }catch(error){toast(error.message,'error');const el=root.querySelector('[data-sheet-panel-body]');if(el){const p=document.createElement('p');p.setAttribute('role','alert');p.textContent=error.message;el.append(p);}}
  });
  root.addEventListener('input',e=>{if(e.target.matches('input[type=time]')){const f=e.target.form,output=f?.querySelector('[data-sheet-total]');if(output){try{const xs=[...f.querySelectorAll('input[name^=start]')].map((x,i)=>({start:x.value||null,end:f.elements['end'+i].value||null})).filter(x=>x.start||x.end);output.textContent='TOTAL: '+workedTime(xs);}catch(error){output.textContent=error.message;}}}if(e.target.matches('[data-sheet-search]'))root.querySelectorAll('.sheet-candidate').forEach(b=>b.hidden=!b.dataset.search.includes(e.target.value.toLocaleLowerCase('pt')));});
  return {show:load,refresh:load};
}
