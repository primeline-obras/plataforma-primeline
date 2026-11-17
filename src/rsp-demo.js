// Standalone manual meeting data. No API, RPC, fetch, or official module writes.
export const DEMO_USER_ID = '0bc80854-3c75-4fc9-92c4-6a81201a261f';
export const DEMO_AUTH_USER_ID = 'b80cc786-1d10-47dd-bbf1-03dd2a7a6012';
export const DEMO_COMPANY_ID = '73fb13c8-d29f-4192-a506-4ca243343add';
export function canUseRspDemo(identity) {
  return Boolean(identity?.authUserId === DEMO_AUTH_USER_ID
    && identity.userId === DEMO_USER_ID && identity.companyId === DEMO_COMPANY_ID
    && identity.profileActive === true && identity.profileAuthUserId === identity.authUserId);
}
const moneyFields = {initialSale:'Venda contratual inicial',approvedTees:'Valor dos TEEs aprovados',advance:'Adiantamento',cost:'Custo Direto Total',estimatedRealCost:'Estimativa de Custo Real',billed:'Valor Recebido'};
// sale is retained verbatim for V3/V4 traceability; never treated as contractual sale or approved TEEs.
const fieldsLegacy = {sale:'Venda atualizada guardada na V3/V4'};
const dateFields = {start:'Data de início da obra',end:'Data prevista de conclusão da obra',meeting:'Data da reunião'};
const fields = {...moneyFields,...fieldsLegacy,...dateFields,planning:'Planeamento',tees:'TEEs'};
const escape = value => String(value ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const euro = new Intl.NumberFormat('pt-PT',{style:'currency',currency:'EUR'});
export function amount(value) {
  if (value === '' || value == null) return null;
  if (!/^\d+(?:\.\d{1,2})?$/.test(String(value))) return null;
  const n=Number(value);return Number.isFinite(n) && n<=1e12 ? n : null;
}
export function dateValue(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value??'')) return null;
  const n=Date.parse(value+'T00:00:00Z');
  return Number.isFinite(n) && new Date(n).toISOString().slice(0,10)===value ? n : null;
}
export function demoValues(data={}) {
  const initialSale=amount(data.initialSale),approvedTees=amount(data.approvedTees),cost=amount(data.cost),billed=amount(data.billed),estimatedRealCost=amount(data.estimatedRealCost);
  const sale=initialSale!==null&&approvedTees!==null?Math.round((initialSale+approvedTees)*100)/100:null;
  const difference=(a,b)=>a!==null&&b!==null?Math.round((a-b)*100)/100:null;
  const start=dateValue(data.start),end=dateValue(data.end),meeting=dateValue(data.meeting);
  return {sale,initialSale,approvedTees,cost,billed,estimatedRealCost,margin:difference(sale,cost),realMargin:difference(sale,estimatedRealCost),costDifference:difference(cost,estimatedRealCost),remaining:difference(sale,billed),
    billingPercent:sale!==null&&sale>0&&billed!==null?billed/sale*100:null,
    deadlinePercent:start!==null&&end!==null&&meeting!==null&&end>start?Math.min(100,Math.max(0,(meeting-start)/(end-start)*100)):null};
}
const format=n=>n===null?'—':euro.format(n);
const empty=()=>Object.fromEntries(Object.keys(fields).map(k=>[k,'']));
function sanitize(row) {
  if(!row || typeof row!=='object' || Array.isArray(row))throw Error('DEMO_STORAGE_FORMAT');
  const out=empty();for(const k of Object.keys(fields)){
    const v=row[k]??'';if(typeof v!=='string'||v.length>(['planning','tees'].includes(k)?15000:40))throw Error('DEMO_STORAGE_FORMAT');
    if((k in moneyFields || k in fieldsLegacy) && v!=='' && amount(v)===null)throw Error('DEMO_STORAGE_VALUES');
    if(k in dateFields && v!=='' && dateValue(v)===null)throw Error('DEMO_STORAGE_VALUES');out[k]=v;
  }return out;
}
const metadataFields={reference:'Número / referência',name:'Nome utilizado na reunião',client:'Cliente',director:'Diretor de Obra'};
const emptyMetadata=()=>Object.fromEntries(Object.keys(metadataFields).map(k=>[k,'']));
function cleanMetadata(row){
  const out=emptyMetadata();for(const k of Object.keys(metadataFields)){const v=row[k]??'';if(typeof v!=='string'||v.length>(k==='reference'?80:250))throw Error('DEMO_METADATA_FORMAT');out[k]=v.trim();}
  if(!out.name)throw Error('DEMO_WORK_NAME_REQUIRED');return out;
}
function cleanRecord(row){
  if(!row||typeof row!=='object'||!/^demo-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(row.id)||typeof row.hidden!=='boolean')throw Error('DEMO_MANUAL_RECORD_FORMAT');
  return{id:row.id,...cleanMetadata(row),hidden:row.hidden,data:sanitize(row.data)};
}
export function createRspDemo({root,getIdentity,storage,host=globalThis,createId=()=>globalThis.crypto.randomUUID(),confirm=async message=>host.confirm?.(message)??false}) {
  let records=[],current='',draft=empty(),metaDraft=emptyMetadata(),present=true,dirty=false,creating=false,storageError='',loadedFor='',baselineRaw=null;
  const authorized=()=>canUseRspDemo(getIdentity());
  const key=()=>`primeline:rsp-demo:v3:${getIdentity().companyId}:${getIdentity().userId}`;
  const getStorage=()=>storage??host.localStorage;
  const works=()=>records.filter(w=>!w.hidden);
  function load(){
    if(loadedFor===key())return;loadedFor=key();records=[];storageError='';
    try{const raw=getStorage().getItem(key());baselineRaw=raw;if(raw!==null){const parsed=JSON.parse(raw);if(parsed?.version!==3||!Array.isArray(parsed.works))throw Error('FORMAT');const next=parsed.works.map(cleanRecord);if(new Set(next.map(w=>w.id)).size!==next.length)throw Error('DUPLICATE_ID');records=next;}}
    catch{storageError='Não foi possível ler os dados locais V3. O conteúdo existente não será substituído; conserve este navegador e recupere uma cópia antes de continuar.';}
  }
  function commitRecords(next){
    if(!authorized()||storageError)return false;
    try{
      if(getStorage().getItem(key())!==baselineRaw){storageError='Os dados mudaram noutra aba. Esta versão não será sobrescrita; preserve o texto em edição e recarregue.';return false;}
      const checked=next.map(cleanRecord);if(new Set(checked.map(w=>w.id)).size!==checked.length)throw Error('DUPLICATE_ID');
      const raw=JSON.stringify({version:3,works:checked});getStorage().setItem(key(),raw);baselineRaw=raw;records=checked;return true;
    }catch{storageError='Não foi possível guardar no navegador. Os dados em edição foram preservados neste ecrã; não feche a página.';return false;}
  }
  const validDraft=()=>Object.keys(moneyFields).every(k=>draft[k]===''||amount(draft[k])!==null)&&Object.keys(dateFields).every(k=>draft[k]===''||dateValue(draft[k])!==null)&&(!(draft.start&&draft.end)||dateValue(draft.end)>dateValue(draft.start));
  function validMetadata(){try{cleanMetadata(metaDraft);return true;}catch{return false;}}
  function save(){
    if(!authorized()||!current||!validDraft()||!validMetadata())return false;
    const next=records.map(w=>w.id===current?{...w,...cleanMetadata(metaDraft),data:sanitize(draft)}:w);
    if(commitRecords(next)){dirty=false;return true;}return false;
  }
  function message(text){const el=root.querySelector('[data-demo-create-validation]')??root.querySelector('[data-demo-validation]');if(el)el.textContent=text;}
  function validateAndSave(){
    if(!validMetadata()){message('O nome utilizado na reunião é obrigatório. Verifique a identificação da obra.');return false;}
    if(!validDraft()){message('Verifique valores monetários, datas e conclusão posterior ao início.');return false;}
    if(dirty&&!save()){render();return false;}return true;
  }
  function progress(label,percent,detail='',deadline=false){return `<div data-demo-progress="${deadline?'deadline':'billing'}" class="meeting-progress${deadline?' deadline':''}"><span>${label} <b>${percent===null?'—':percent.toFixed(1)+'%'}</b></span>${percent===null?'':`<div><i style="width:${Math.max(0,Math.min(100,percent))}%"></i></div>`}${detail?`<small>${escape(detail)}</small>`:''}</div>`;}
  const financialLabels=[['VENDA TOTAL ATUALIZADA','sale'],['CUSTO DIRETO TOTAL','cost'],['MARGEM PREVISTA','margin'],['POR FATURAR','remaining']];
  const estimateLabels=[['Estimativa de Custo Real','estimatedRealCost'],['Margem Real Estimada','realMargin'],['Diferença CD − CR','costDifference']];
  function legacyNotice(data){return data.sale!==''&&data.sale!=null&&(data.initialSale===''||data.approvedTees==='')?`<p class="rsp-demo-legacy-note" role="status">Venda atualizada guardada na V3/V4: ${format(amount(data.sale))}. Valor preservado, não utilizado nas novas fórmulas. Preencha a venda contratual e os TEEs aprovados; indique 0 apenas se não existirem TEEs aprovados.</p>`:'';}
  function estimates(data,includeCost=true){const v=demoValues(data);return `<dl class="meeting-dl rsp-demo-estimates">${estimateLabels.filter(([,k])=>includeCost||k!=='estimatedRealCost').map(([label,k])=>`<div><dt>${label}</dt><dd data-demo-estimate="${k}">${format(v[k])}</dd></div>`).join('')}</dl>`;}
  const workLabel=w=>w.reference?`OBRA ${w.reference}`:'OBRA';
  const dateDetail=()=>`${draft.start||'—'} → ${draft.end||'—'} · reunião ${draft.meeting||'—'}`;
  function field(k,label,showLabel=true){return `<label class="rsp-demo-inline-field">${showLabel?escape(label):''}<input aria-label="${escape(label)}" data-field="${k}" name="${k}" type="${k in dateFields?'date':'number'}"${k in dateFields?'':' min="0" max="1000000000000" step="0.01"'} value="${escape(draft[k])}"></label>`;}
  function metadataEditor(){return `<div class="rsp-demo-metadata-fields">${Object.entries(metadataFields).map(([k,label])=>`<label class="rsp-demo-inline-field">${label}${k==='name'?' *':''}<input type="text" data-meta="${k}" name="work_${k}" value="${escape(metaDraft[k])}" maxlength="${k==='reference'?80:250}"${k==='name'?' required':''}></label>`).join('')}</div>`;}
  function noteEditor(k,label,data,caption='Notas manuais'){return `<label class="rsp-demo-inline-field">${escape(caption)}<textarea data-field="${k}" name="${k}" maxlength="15000" rows="6" aria-label="${label}">${escape(data[k])}</textarea></label>`;}
  function notes(data,editing=false){return [['planning','PLANEAMENTO'],['tees','TEEs']].map(([k,label])=>`<article class="panel meeting-card"><div class="meeting-title"><span>${label}</span></div>${editing?noteEditor(k,label,data):`<div data-demo-note="${k}" class="rsp-demo-notes">${escape(data[k]||'—')}</div>`}</article>`).join('');}
  function actions(){return `<div class="rsp-demo-actions">${!current&&!creating&&(!present||works().length===0)?`<button type="button" class="secondary-button" data-demo-new${storageError?' disabled':''}>+ NOVA OBRA</button>`:''}<button type="button" class="secondary-button" data-demo-mode>${present?'EDITAR':'APRESENTAR'}</button>${current&&!present?`<button type="button" class="secondary-button" data-demo-save${storageError?' disabled':''}>GUARDAR</button>`:''}</div>`;}
  function status(){return `${current?legacyNotice(draft):''}${storageError?`<div role="alert" class="overview-warning">${escape(storageError)}</div>`:''}${!present?`<p class="rsp-demo-status" role="status" data-demo-status>${escape(dirty?'Alterações por guardar':'Cadastro e valores exclusivos deste navegador')}</p><p data-demo-validation role="alert"></p>`:''}`;}
  function newForm(){return creating?`<form class="panel meeting-card" data-demo-create-form><div class="meeting-title"><span>NOVA OBRA DA RSP DEMO</span></div>
    <section class="rsp-demo-create-section" aria-label="Identificação"><div class="meeting-title"><span>IDENTIFICAÇÃO</span></div>${metadataEditor()}</section>
    <section class="rsp-demo-create-section" aria-label="Contrato"><div class="meeting-title"><span>CONTRATO</span></div><div class="rsp-demo-contract-fields">${Object.entries(moneyFields).filter(([k])=>k!=='billed').map(([k,label])=>field(k,label)).join('')}</div></section>
    <section class="rsp-demo-create-section" aria-label="Faturação"><div class="meeting-title"><span>FATURAÇÃO</span></div>${field('billed',moneyFields.billed)}<p class="rsp-demo-status">Por faturar = venda total atualizada − valor recebido.</p></section>
    <section class="rsp-demo-create-section" aria-label="Prazo"><div class="meeting-title"><span>PRAZO</span></div><div class="rsp-demo-date-fields">${Object.entries(dateFields).map(([k,label])=>field(k,label)).join('')}</div></section>
    <section class="rsp-demo-create-section" aria-label="Acompanhamento"><div class="meeting-title"><span>ACOMPANHAMENTO</span></div><div class="rsp-demo-note-fields">${noteEditor('planning','PLANEAMENTO',draft,'Planeamento')}${noteEditor('tees','TEEs',draft,'TEEs')}</div></section>
    <p class="form-error" data-demo-create-validation role="alert"></p><div class="rsp-demo-actions"><button type="submit" class="secondary-button" data-demo-create>GUARDAR OBRA</button><button type="button" class="secondary-button" data-demo-cancel>CANCELAR</button></div></form>`:'';}
  function hiddenManager(){const hidden=records.filter(w=>w.hidden);return !present&&hidden.length?`<details class="rsp-detail" data-demo-hidden><summary>RETIRADAS DA APRESENTAÇÃO (${hidden.length}) — DADOS PRESERVADOS</summary><div class="rsp-demo-hidden-list">${hidden.map(w=>`<div><span>${escape(workLabel(w))} · ${escape(w.name)}</span><button type="button" class="secondary-button" data-demo-restore="${w.id}"${storageError?' disabled':''}>REATIVAR</button></div>`).join('')}</div></details>`:'';}
  function renderList(){const active=works();return `<div class="page-heading rsp-heading"><div><p class="eyebrow">GESTÃO DE PRODUÇÃO · RSP DEMO</p><h1>REUNIÃO SEMANAL DE PRODUÇÃO</h1><span>Obras cadastradas manualmente · dados exclusivos da reunião.</span></div>${actions()}</div>${status()}${newForm()}
    <section class="rsp-list">${active.map((work,index)=>{const v=demoValues(work.data);return `<article class="rsp-work panel" data-demo-card="${work.id}">
      <header class="rsp-work-header"><div><p class="eyebrow">${escape(workLabel(work))}</p><h2>${escape(work.name)}</h2>${work.client?`<span>${escape(work.client)}</span>`:''}${work.director?`<small class="rsp-demo-director">Diretor de Obra: ${escape(work.director)}</small>`:''}</div><div class="rsp-demo-actions"><button type="button" class="secondary-button" data-demo-open="${work.id}">ABRIR DETALHE →</button>${!present?`<button type="button" class="secondary-button" data-demo-edit="${work.id}">EDITAR OBRA</button><button type="button" class="secondary-button" data-demo-up="${work.id}" aria-label="Subir ${escape(work.name)}"${index===0||storageError?' disabled':''}>↑</button><button type="button" class="secondary-button" data-demo-down="${work.id}" aria-label="Descer ${escape(work.name)}"${index===active.length-1||storageError?' disabled':''}>↓</button><button type="button" class="secondary-button" data-demo-hide="${work.id}"${storageError?' disabled':''}>RETIRAR DA APRESENTAÇÃO</button>`:''}</div></header>
      <div class="rsp-kpis">${financialLabels.map(([label,k])=>`<div><span>${label}</span><strong>${format(v[k])}</strong></div>`).join('')}</div>
      ${legacyNotice(work.data)}${estimates(work.data)}<div class="rsp-progress-grid">${progress('RECEBIDO',v.billingPercent)}${progress('PRAZO CONSUMIDO',v.deadlinePercent,'',true)}</div>
      ${[['planning','PLANEAMENTO'],['tees','TEEs']].map(([k,label])=>`<details class="rsp-detail"><summary>${label}</summary><div class="rsp-demo-notes">${escape(work.data[k]||'—')}</div></details>`).join('')}
    </article>`;}).join('')||`<div class="overview-empty panel">${records.length?'NÃO HÁ OBRAS NA APRESENTAÇÃO. USE EDITAR PARA REATIVAR AS OBRAS RETIRADAS.':'A RSP DEMO ESTÁ VAZIA. CADASTRE A PRIMEIRA OBRA EM + NOVA OBRA.'}</div>`}</section>${hiddenManager()}`;}
  function renderDetail(work){const v=demoValues(draft);return `
    <div class="meeting-heading"><button type="button" data-demo-back>← RSP DEMO</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · ${escape(workLabel(work))} · DEMO</p><h1>${escape(work.name)}</h1>${work.client?`<span>${escape(work.client)}</span>`:''}${work.director?`<small class="rsp-demo-director">Diretor de Obra: ${escape(work.director)}</small>`:''}</div><div class="rsp-demo-heading-end">${actions()}</div></div>
    ${status()}${!present?`<section class="panel meeting-card"><div class="meeting-title"><span>IDENTIFICAÇÃO DA OBRA</span></div>${metadataEditor()}</section>`:''}
    <section class="meeting-kpis">${financialLabels.map(([label,k])=>`<article><span>${label}</span><strong data-demo-kpi="${k}">${format(v[k])}</strong><small>${k==='remaining'?'venda total atualizada − valor recebido':k==='margin'?'venda total atualizada − custo direto total':k==='sale'?'venda contratual inicial + TEEs aprovados':'preenchimento manual'}</small></article>`).join('')}</section>
    <section class="meeting-two"><article class="panel meeting-card"><div class="meeting-title"><span>RESUMO CONTRATUAL</span></div><dl class="meeting-dl">${Object.entries(moneyFields).filter(([k])=>k!=='billed').map(([k,label])=>`<div><dt>${escape(label)}</dt><dd>${present?`<span data-demo-financial="${k}">${format(amount(draft[k]))}</span>`:field(k,label,false)}</dd></div>`).join('')}</dl>${estimates(draft,false)}</article>
    <article class="panel meeting-card"><div class="meeting-title"><span>FATURAÇÃO E PRAZO</span></div>${present?'':field('billed',moneyFields.billed)}${progress('RECEBIDO',v.billingPercent,`${format(v.billed)} recebidos · venda ${format(v.sale)}`)}${progress('PRAZO CONSUMIDO',v.deadlinePercent,dateDetail(),true)}${present?'':`<div class="rsp-demo-date-fields">${Object.entries(dateFields).map(([k,label])=>field(k,label)).join('')}</div>`}</article></section>
    <section class="meeting-two">${notes(draft,!present)}</section>`;}
  function refreshValues(){const v=demoValues(draft);for(const k of ['sale','cost','margin','remaining']){const el=root.querySelector(`[data-demo-kpi="${k}"]`);if(el)el.textContent=format(v[k]);}for(const el of root.querySelectorAll('[data-demo-estimate]'))el.textContent=format(v[el.dataset.demoEstimate]);const oldNotice=root.querySelector('.rsp-demo-legacy-note');if(oldNotice)oldNotice.outerHTML=legacyNotice(draft);const billing=root.querySelector('[data-demo-progress=billing]'),deadline=root.querySelector('[data-demo-progress=deadline]');if(billing)billing.outerHTML=progress('RECEBIDO',v.billingPercent,`${format(v.billed)} recebidos · venda ${format(v.sale)}`);if(deadline)deadline.outerHTML=progress('PRAZO CONSUMIDO',v.deadlinePercent,dateDetail(),true);}
  function render(){if(!authorized()){root.replaceChildren();return;}const work=records.find(x=>x.id===current);root.classList.toggle('rsp-view',!work);root.classList.toggle('meeting-view',Boolean(work));root.dataset.demoScreen=work?'detail':'list';root.innerHTML=work?renderDetail(work):renderList();}
  function createWork(){
    if(!authorized()||!creating||storageError)return;if(!validMetadata()){message('O nome utilizado na reunião é obrigatório.');return;}
    if(!validDraft()){message('Verifique valores monetários, datas e conclusão posterior ao início.');return;}
    let id;try{id='demo-'+createId();if(!/^demo-[a-f0-9-]{36}$/i.test(id)||records.some(w=>w.id===id))throw Error('ID');}catch{message('Não foi possível criar um identificador local único. Nenhum dado foi alterado.');return;}
    if(commitRecords([...records,{id,...cleanMetadata(metaDraft),hidden:false,data:sanitize(draft)}])){creating=false;dirty=false;metaDraft=emptyMetadata();draft=empty();render();}else render();
  }
  function reorder(id,direction){const active=works(),from=active.findIndex(w=>w.id===id),to=from+direction;if(from<0||to<0||to>=active.length)return;const next=[...records],a=next.findIndex(w=>w.id===id),b=next.findIndex(w=>w.id===active[to].id);[next[a],next[b]]=[next[b],next[a]];commitRecords(next);render();}
  root.addEventListener('input',event=>{if(!authorized())return;const k=event.target.dataset.field,m=event.target.dataset.meta;if(Object.hasOwn(fields,k??'')){draft[k]=event.target.value;refreshValues();}else if(Object.hasOwn(metadataFields,m??'')){metaDraft[m]=event.target.value;}else return;dirty=true;const status=root.querySelector('[data-demo-status]');if(status)status.textContent='Alterações por guardar';});
  root.addEventListener('submit',event=>{event.preventDefault();if(event.target.matches('[data-demo-create-form]'))createWork();});
  root.addEventListener('click',async event=>{
    if(!authorized())return;const button=event.target.closest('button');if(!button||button.disabled)return;
    if(button.matches('[data-demo-new]')){creating=true;present=false;dirty=false;metaDraft=emptyMetadata();draft=empty();render();return;}
    if(button.matches('[data-demo-cancel]')){const same=key();if(dirty&&!await confirm('Descartar apenas os dados da nova obra ainda não guardada?'))return;if(!authorized()||key()!==same)return;creating=false;dirty=false;metaDraft=emptyMetadata();draft=empty();render();return;}
    if(button.matches('[data-demo-open],[data-demo-edit]')){const edit=button.matches('[data-demo-edit]');const work=records.find(w=>w.id===(edit?button.dataset.demoEdit:button.dataset.demoOpen)&&!w.hidden);if(!work)return;if(creating&&dirty){message('Guarde ou cancele o cadastro antes de abrir outra obra.');return;}creating=false;if(edit)present=false;current=work.id;draft={...work.data};metaDraft=cleanMetadata(work);dirty=false;render();host.scrollTo?.(0,0);return;}
    if(button.matches('[data-demo-back]')){if(dirty&&!validateAndSave())return;current='';draft=empty();metaDraft=emptyMetadata();render();host.scrollTo?.(0,0);return;}
    if(button.matches('[data-demo-save]')){if(!validMetadata()||!validDraft()){validateAndSave();return;}save();render();return;}
    if(button.matches('[data-demo-up]')){reorder(button.dataset.demoUp,-1);return;}
    if(button.matches('[data-demo-down]')){reorder(button.dataset.demoDown,1);return;}
    if(button.matches('[data-demo-hide]')){commitRecords(records.map(w=>w.id===button.dataset.demoHide?{...w,hidden:true}:w));render();return;}
    if(button.matches('[data-demo-restore]')){commitRecords(records.map(w=>w.id===button.dataset.demoRestore?{...w,hidden:false}:w));render();return;}
    if(button.matches('[data-demo-mode]')){if(creating){message('Guarde ou cancele o cadastro antes de apresentar.');return;}if(!present&&current&&!validateAndSave())return;present=!present;render();}
  });
  host.addEventListener('beforeunload',event=>{if(dirty){event.preventDefault();event.returnValue='';}});
  host.addEventListener('storage',event=>{if(authorized()&&event.key===key()){storageError='Os dados foram alterados noutra aba. Preserve o rascunho e recarregue antes de continuar; nada será sobrescrito.';render();}});
  return {show(){if(!authorized()){root.replaceChildren();return;}load();if(current&&!records.some(w=>w.id===current)){current='';draft=empty();metaDraft=emptyMetadata();dirty=false;}render();},reset(){records=[];current='';draft=empty();metaDraft=emptyMetadata();present=true;dirty=false;creating=false;loadedFor='';baselineRaw=null;storageError='';root.replaceChildren();}};
}
