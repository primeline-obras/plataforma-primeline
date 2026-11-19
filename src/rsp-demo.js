import {INVESTMENT_MODEL,CONTRACT_MODEL,modelOf,blankInvestment,cleanInvestment,investmentForm,investmentCard,investmentDetail} from './rsp-demo-investment.js?v=903ed2fa1bad';
// Manual meeting payload V5. Dedicated server repository; no writes to official business modules.
export const DEMO_USER_ID = '0bc80854-3c75-4fc9-92c4-6a81201a261f';
export const DEMO_AUTH_USER_ID = 'b80cc786-1d10-47dd-bbf1-03dd2a7a6012';
export const DEMO_COMPANY_ID = '73fb13c8-d29f-4192-a506-4ca243343add';
export function canUseRspDemo(identity) {
  return Boolean(identity?.authUserId === DEMO_AUTH_USER_ID
    && identity.userId === DEMO_USER_ID && identity.companyId === DEMO_COMPANY_ID
    && identity.profileActive === true && identity.profileAuthUserId === identity.authUserId);
}
const moneyFields = {initialSale:'Venda contratual inicial',approvedTees:'Valor dos TEEs aprovados',advance:'Adiantamento',cost:'Custo Direto Total · sem IVA',estimatedRealCost:'Estimativa de Custo Real · sem IVA',billed:'Valor Recebido'};
// sale is retained verbatim for V3/V4 traceability; never treated as contractual sale or approved TEEs.
const fieldsLegacy = {sale:'Venda atualizada guardada na V3/V4'};
const dateFields = {start:'Data de início da obra',end:'Data prevista de conclusão da obra',meeting:'Data da reunião'};
const optionalMoneyFields={expensesYtd:'Total Despesas YTD · sem IVA'};
const fields = {...moneyFields,...optionalMoneyFields,...fieldsLegacy,...dateFields,planning:'Planeamento',tees:'TEEs'};
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
function sanitize(row,model=CONTRACT_MODEL) {
  if(!row || typeof row!=='object' || Array.isArray(row))throw Error('DEMO_STORAGE_FORMAT');
  const out=empty();for(const k of Object.keys(fields)){
    const v=row[k]??'';if(typeof v!=='string'||v.length>(['planning','tees'].includes(k)?15000:40))throw Error('DEMO_STORAGE_FORMAT');
    if((k in moneyFields || k in optionalMoneyFields || k in fieldsLegacy) && v!=='' && amount(v)===null)throw Error('DEMO_STORAGE_VALUES');
    if(k in dateFields && v!=='' && dateValue(v)===null)throw Error('DEMO_STORAGE_VALUES');out[k]=v;
  }if(!Object.hasOwn(row,'expensesYtd')||model===INVESTMENT_MODEL)delete out.expensesYtd;if(model===INVESTMENT_MODEL){if(row.expensesYtd!=null&&row.expensesYtd!=='')throw Error('DEMO_DUPLICATE_YTD');out.investment=cleanInvestment(row.investment);}return out;
}
const metadataFields={reference:'Número / referência',name:'Nome utilizado na reunião',client:'Cliente',director:'Diretor de Obra'};
const emptyMetadata=()=>Object.fromEntries(Object.keys(metadataFields).map(k=>[k,'']));
function cleanMetadata(row){
  const out=emptyMetadata();for(const k of Object.keys(metadataFields)){const v=row[k]??'';if(typeof v!=='string'||v.length>(k==='reference'?80:250))throw Error('DEMO_METADATA_FORMAT');out[k]=v.trim();}
  if(!out.name)throw Error('DEMO_WORK_NAME_REQUIRED');return out;
}
function cleanRecord(row){
  if(!row||typeof row!=='object'||!/^demo-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(row.id)||typeof row.hidden!=='boolean')throw Error('DEMO_MANUAL_RECORD_FORMAT');
  const model=modelOf(row);if(![CONTRACT_MODEL,INVESTMENT_MODEL].includes(model))throw Error('DEMO_MODEL_INVALID');
  if(model===CONTRACT_MODEL&&Object.hasOwn(row.data??{},'investment'))throw Error('DEMO_MODEL_DATA_MISMATCH');
  return{id:row.id,...cleanMetadata(row),hidden:row.hidden,data:sanitize(row.data,model),...(Object.hasOwn(row,'presentationModel')?{presentationModel:model}:{})};
}
export function createRspDemo({root,getIdentity,repository,storage,host=globalThis,createId=()=>globalThis.crypto.randomUUID(),confirm=async message=>host.confirm?.(message)??false}) {
  let records=[],current='',draft=empty(),metaDraft=emptyMetadata(),present=true,dirty=false,creating=false,storageError='',loadedFor='',baselineRaw=null,revision=0,busy=false,syncMessage="",generation=0,pendingCreateId="",modelDraft=CONTRACT_MODEL;
  const authorized=()=>canUseRspDemo(getIdentity());
  const key=()=>`primeline:rsp-demo:v3:${getIdentity().companyId}:${getIdentity().userId}`;
  const getStorage=()=>storage??host.localStorage;
  const works=()=>records.filter(w=>!w.hidden);
  async function load(){
    if(busy||dirty)return;
    const scope=key(),epoch=generation;busy=true;syncMessage='A carregar do servidor…';render();
    try{const result=await repository.load();if(epoch!==generation||!authorized()||key()!==scope)return;
      const checked=result.document.works.map(cleanRecord);if(new Set(checked.map(w=>w.id)).size!==checked.length)throw Error('FORMAT');
      records=checked;revision=result.revision;loadedFor=scope;probeBackup();storageError='';syncMessage='Dados carregados do servidor · revisão '+revision;
    }catch{if(epoch===generation){syncMessage='Leitura não confirmada';storageError='Não foi possível carregar do servidor. Nenhum dado local ou central foi substituído. Recarregue para consultar; não grave enquanto este erro persistir.';}}
    finally{if(epoch===generation){busy=false;render();}}
  }
  async function commitRecords(next,kind=current||creating?'form':'document'){
    if(!authorized()||storageError||backupError||busy||loadedFor!==key())return false;
    const checked=next.map(cleanRecord);if(new Set(checked.map(w=>w.id)).size!==checked.length)throw Error('DUPLICATE_ID');
    const document={version:3,works:checked},epoch=generation,scope=key();busy=true;
    if(!protectDraft(document,kind)){busy=false;render();return false;}
    syncMessage='A guardar no servidor…';message(syncMessage);
    for(const el of root.querySelectorAll('button,input,textarea,select'))el.disabled=true;
    try{const result=await repository.save(document,revision);if(epoch!==generation||!authorized()||key()!==scope)return false;
      records=checked;revision=result.revision;const saved=memoryDrafts.get(draftSlot);if(saved){saved.status='confirmed';try{getStorage().setItem(draftSlot,JSON.stringify({format:'RSP_DEMO_DRAFT_V2',scope,status:'confirmed'}));}catch{backupError='O servidor confirmou a gravação, mas a atualização da cópia local falhou.';}}draftSlot='';syncMessage='Guardado no servidor · revisão '+revision;return true;
    }catch(error){if(epoch===generation){syncMessage='Não sincronizado';storageError=error.code==='RSP_REVISION_CONFLICT'?'Outra sessão alterou os dados. O rascunho foi preservado; exporte-o antes de recarregar e reconciliar. Nada foi sobrescrito.':'Gravação não confirmada. O rascunho foi preservado; não repita a gravação. Exporte-o e consulte o servidor antes de reconciliar.';}return false;}
    finally{if(epoch===generation){busy=false;for(const el of root.querySelectorAll('button,input,textarea,select'))el.disabled=false;}}
  }
  function exportDraft(){
    const document=recoveryDocument??proposedDocument();
    const blob=new host.Blob([JSON.stringify(document,null,2)],{type:'application/json'}),url=host.URL.createObjectURL(blob),a=host.document.createElement('a');a.href=url;a.download='rsp-demo-rascunho.json';a.click();host.URL.revokeObjectURL(url);
  }
  async function importDocument(document){
    if(storageError||busy||dirty)return message('Guarde ou exporte o rascunho antes de importar.');
    try{if(document?.version!==3||!Array.isArray(document.works))throw Error('FORMAT');
      const incoming=document.works.map(cleanRecord),ids=new Set();for(const w of incoming){if(ids.has(w.id))throw Error('DUPLICATE_ID');ids.add(w.id);const existing=records.find(r=>r.id===w.id);if(existing&&JSON.stringify(existing)!==JSON.stringify(w))throw Error('CONFLICT');}
      const additions=incoming.filter(w=>!records.some(r=>r.id===w.id));if(!additions.length)return message('Não existem obras novas para transferir.');
      const scope=key(),epoch=generation;
      if(!await confirm('Transferir '+additions.length+' obras para o servidor?\n'+additions.map(w=>(w.reference?w.reference+' · ':'')+w.name+(w.hidden?' [retirada]':'')).join('\n')+'\nOs dados locais serão preservados.'))return;
      if(epoch!==generation||!authorized()||key()!==scope)return;
      await commitRecords([...records,...additions],'document');render();
    }catch{message('Transferência bloqueada: formato inválido ou identificadores com dados divergentes. Nenhuma obra foi substituída.');}
  }
  const memoryDrafts=new Map();let draftSlot='',backupError='',recoveryDocument=null;
  const canonical=value=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
  function proposedData(){const data=structuredClone(draft);if(modelDraft===INVESTMENT_MODEL)delete data.expensesYtd;return data;}
  function proposedDocument(){
    if(creating&&!pendingCreateId)pendingCreateId='demo-'+createId();
    return creating?{version:3,works:[...records,{id:pendingCreateId,...metaDraft,presentationModel:modelDraft,hidden:false,data:proposedData()}]}:{version:3,works:records.map(w=>w.id===current?{...w,...metaDraft,data:proposedData()}:w)};
  }
  function protectDraft(document=proposedDocument(),kind='form'){
    if(!authorized())return false;
    if(!draftSlot)draftSlot=key()+':draft:v2:'+createId();
    const envelope={format:'RSP_DEMO_DRAFT_V2',scope:key(),status:'pending',kind,revision,document,context:{current,creating,pendingCreateId,present,modelDraft,draft:{...draft},metaDraft:{...metaDraft}}};
    memoryDrafts.set(draftSlot,envelope);
    try{const raw=JSON.stringify(envelope);getStorage().setItem(draftSlot,raw);if(getStorage().getItem(draftSlot)!==raw)throw Error('WRITE_NOT_VERIFIED');backupError='';return true;}
    catch{backupError='SALVAGUARDA LOCAL INDISPONÍVEL. Gravação e edição bloqueadas. Exporte o rascunho agora. A cópia em memória só pode ser recuperada nesta página após login da mesma conta; fechar/recarregar pode perdê-la.';return false;}
  }
  function probeBackup(){
    if(!authorized())return;const probe=key()+':probe:'+createId();
    try{getStorage().setItem(probe,'1');if(getStorage().getItem(probe)!=='1')throw Error('READ_BACK');getStorage().removeItem(probe);backupError='';}
    catch{backupError='SALVAGUARDA LOCAL INDISPONÍVEL. Edição e gravação bloqueadas; dados do servidor continuam disponíveis. Não feche esta página com rascunhos por exportar.';}
  }
  function pendingDrafts(){
    if(!authorized())return [];const prefix=key(),found=new Map();
    try{const store=getStorage();for(let i=0;i<store.length;i++){const k=store.key(i);if(!k||!(k.startsWith(prefix+':draft:v2:')||k.startsWith(prefix+':pending:')))continue;try{const value=JSON.parse(store.getItem(k));if(value?.format==='RSP_DEMO_DRAFT_V2'&&value.scope===prefix&&value.status==='pending')found.set(k,value);else if(value?.version===3&&Array.isArray(value.works))found.set(k,{format:'LEGACY',scope:prefix,document:value});}catch{}}}catch{}
    for(const [k,v] of memoryDrafts)if(v.scope===prefix&&v.status==='pending')found.set(k,v);
    return [...found.entries()];
  }
  function recoveryControls(){const entries=pendingDrafts();return `<div role="alert">${escape(backupError)}</div>${entries.length?`<details><summary>RASCUNHOS PENDENTES (${entries.length}) — RECUPERAÇÃO EXPLÍCITA</summary>${entries.map(([k,v],i)=>`<button type="button" class="secondary-button" data-demo-recover="${escape(k)}">REVER RASCUNHO ${i+1}${v.format==='LEGACY'?' · versão anterior':''}</button>`).join('')}</details>`:''}`;}
  async function recoverDraft(slot){
    if(!authorized()||busy||dirty)return message('Exporte ou conclua o rascunho atual antes de recuperar outro.');
    const entry=pendingDrafts().find(([k])=>k===slot)?.[1];if(!entry)return;
    const scope=key(),epoch=generation;if(!await confirm('Recuperar este rascunho? Nada será gravado automaticamente no servidor.'))return;
    if(epoch!==generation||!authorized()||key()!==scope)return;
    if(canonical(entry.document)===canonical({version:3,works:records})){syncMessage='Este documento já corresponde ao servidor; nenhuma gravação foi repetida.';render();return;}
    if(entry.format!=='RSP_DEMO_DRAFT_V2'||entry.revision!==revision||entry.kind!=='form'){
      recoveryDocument=entry.document;storageError='Rascunho disponível para exportação. A revisão ou o tipo exige reconciliação manual; o servidor não será substituído.';render();return;
    }
    const c=entry.context;if(!c||typeof c.draft!=='object'||typeof c.metaDraft!=='object'||(!c.creating&&!records.some(w=>w.id===c.current))){storageError='Rascunho incompatível; conserve a cópia local.';render();return;}
    draftSlot=slot;current=c.current;creating=c.creating===true;pendingCreateId=c.pendingCreateId||'';present=false;modelDraft=c.modelDraft??modelOf(records.find(w=>w.id===c.current));draft={...c.draft};metaDraft={...c.metaDraft};dirty=true;recoveryDocument=null;syncMessage='Rascunho recuperado; ainda não guardado no servidor.';render();
  }
  const investmentValid=()=>{if(modelDraft!==INVESTMENT_MODEL)return true;try{cleanInvestment(draft.investment);return true;}catch{return false;}};
  const validDraft=()=>investmentValid()&&[...Object.keys(moneyFields),...Object.keys(optionalMoneyFields)].every(k=>draft[k]==null||draft[k]===''||amount(draft[k])!==null)&&Object.keys(dateFields).every(k=>draft[k]===''||dateValue(draft[k])!==null)&&(!(draft.start&&draft.end)||dateValue(draft.end)>dateValue(draft.start));
  function validMetadata(){try{cleanMetadata(metaDraft);return true;}catch{return false;}}
  async function save(){
    if(!authorized()||!current||!validDraft()||!validMetadata())return false;
    const next=records.map(w=>w.id===current?{...w,...cleanMetadata(metaDraft),data:sanitize(draft,modelOf(w))}:w);
    if(await commitRecords(next)){dirty=false;return true;}return false;
  }
  function message(text){const el=root.querySelector('[data-demo-create-validation]')??root.querySelector('[data-demo-validation]');if(el)el.textContent=text;}
  async function validateAndSave(){
    if(!validMetadata()){message('O nome utilizado na reunião é obrigatório. Verifique a identificação da obra.');return false;}
    if(!validDraft()){message('Verifique valores monetários, datas e conclusão posterior ao início.');return false;}
    if(dirty&&!await save()){render();return false;}return true;
  }
  function progress(label,percent,detail='',deadline=false){return `<div data-demo-progress="${deadline?'deadline':'billing'}" class="meeting-progress${deadline?' deadline':''}"><span>${label} <b>${percent===null?'—':percent.toFixed(1)+'%'}</b></span>${percent===null?'':`<div><i style="width:${Math.max(0,Math.min(100,percent))}%"></i></div>`}${detail?`<small>${escape(detail)}</small>`:''}</div>`;}
  const financialLabels=[['VENDA TOTAL ATUALIZADA','sale'],['CUSTO DIRETO TOTAL · SEM IVA','cost'],['MARGEM PREVISTA','margin'],['POR FATURAR','remaining']];
  const estimateLabels=[['Estimativa de Custo Real · sem IVA','estimatedRealCost'],['Margem Real Estimada','realMargin'],['Diferença CD − CR','costDifference']];
  function legacyNotice(data){return data.sale!==''&&data.sale!=null&&(data.initialSale===''||data.approvedTees==='')?`<p class="rsp-demo-legacy-note" role="status">Venda atualizada guardada na V3/V4: ${format(amount(data.sale))}. Valor preservado, não utilizado nas novas fórmulas. Preencha a venda contratual e os TEEs aprovados; indique 0 apenas se não existirem TEEs aprovados.</p>`:'';}
  function estimates(data,includeCost=true){const v=demoValues(data);return `<dl class="meeting-dl rsp-demo-estimates">${estimateLabels.filter(([,k])=>includeCost||k!=='estimatedRealCost').map(([label,k])=>`<div><dt>${label}</dt><dd data-demo-estimate="${k}">${format(v[k])}</dd></div>`).join('')}<div data-demo-ytd-row><dt>Total Despesas YTD · sem IVA<small class="rsp-demo-director">Todos os custos acumulados desde o início da obra; não apenas o ano corrente.</small></dt><dd>${!present&&current?field('expensesYtd',optionalMoneyFields.expensesYtd,false):`<span data-demo-ytd>${format(amount(data.expensesYtd))}</span>`}</dd></div></dl>`;}
  const workLabel=w=>w.reference?`OBRA ${w.reference}`:'OBRA';
  const dateDetail=()=>`${draft.start||'—'} → ${draft.end||'—'} · reunião ${draft.meeting||'—'}`;
  function field(k,label,showLabel=true){return `<label class="rsp-demo-inline-field">${showLabel?escape(label):''}<input aria-label="${escape(label)}" data-field="${k}" name="${k}" type="${k in dateFields?'date':'number'}"${k in dateFields?'':' min="0" max="1000000000000" step="0.01"'} value="${escape(draft[k])}"></label>`;}
  function metadataEditor(){return `<div class="rsp-demo-metadata-fields">${Object.entries(metadataFields).map(([k,label])=>`<label class="rsp-demo-inline-field">${label}${k==='name'?' *':''}<input type="text" data-meta="${k}" name="work_${k}" value="${escape(metaDraft[k])}" maxlength="${k==='reference'?80:250}"${k==='name'?' required':''}></label>`).join('')}</div>`;}
  function noteEditor(k,label,data,caption='Notas manuais'){return `<label class="rsp-demo-inline-field">${escape(caption)}<textarea data-field="${k}" name="${k}" maxlength="15000" rows="6" aria-label="${label}">${escape(data[k])}</textarea></label>`;}
  function notes(data,editing=false){return [['planning','PLANEAMENTO'],['tees','TEEs']].map(([k,label])=>`<article class="panel meeting-card"><div class="meeting-title"><span>${label}</span></div>${editing?noteEditor(k,label,data):`<div data-demo-note="${k}" class="rsp-demo-notes">${escape(data[k]||'—')}</div>`}</article>`).join('');}
  function actions(){return `<div class="rsp-demo-actions">${!current&&!creating&&(!present||works().length===0)?`<button type="button" class="secondary-button" data-demo-new${storageError?' disabled':''}>+ NOVA OBRA</button>`:''}<button type="button" class="secondary-button" data-demo-mode>${present?'EDITAR':'APRESENTAR'}</button>${current&&!present?`<button type="button" class="secondary-button" data-demo-save${storageError?' disabled':''}>GUARDAR</button>`:''}</div>`;}
  function status(){return `${recoveryControls()}${current&&modelDraft!==INVESTMENT_MODEL?legacyNotice(draft):''}${storageError?`<div role="alert" class="overview-warning">${escape(storageError)}</div>`:''}<p role="status">${escape(syncMessage)}</p><div class="rsp-demo-actions"><button type="button" class="secondary-button" data-demo-export>EXPORTAR RASCUNHO</button>${!present?`<button type="button" class="secondary-button" data-demo-import-local>TRANSFERIR DADOS DESTE NAVEGADOR</button><button type="button" class="secondary-button" data-demo-import-file>IMPORTAR CÓPIA LOCAL</button><input type="file" hidden data-demo-file accept="application/json,.json">`:``}</div>${!present?`<p class="rsp-demo-status" role="status" data-demo-status>${escape(dirty?'Alterações por guardar':syncMessage||'Dados centralizados')}</p><p data-demo-validation role="alert"></p>`:''}`;}
  function modelSelector(){return `<label class="rsp-demo-inline-field rsp-demo-model-selector">MODALIDADE DA OBRA<select data-demo-model name="presentationModel"><option value="empreitada" ${modelDraft===CONTRACT_MODEL?'selected':''}>Empreitada para cliente</option><option value="investimento_proprio" ${modelDraft===INVESTMENT_MODEL?'selected':''}>Investimento próprio</option></select></label>`;}
  function newForm(){return creating?`<form class="panel meeting-card" data-demo-create-form><div class="meeting-title"><span>NOVA OBRA DA RSP DEMO</span></div>
    <section class="rsp-demo-create-section" aria-label="Identificação"><div class="meeting-title"><span>IDENTIFICAÇÃO</span></div>${metadataEditor()}${modelSelector()}</section>
    ${modelDraft===INVESTMENT_MODEL?investmentForm(draft,{field,dateFields,noteEditor}):`<section class="rsp-demo-create-section" aria-label="Contrato"><div class="meeting-title"><span>CONTRATO</span></div><div class="rsp-demo-contract-fields">${Object.entries(moneyFields).filter(([k])=>k!=='billed').map(([k,label])=>field(k,label)).join('')}${field('expensesYtd',optionalMoneyFields.expensesYtd)}</div><p class="rsp-demo-status">Total Despesas YTD: todos os custos acumulados desde o início da obra, sem IVA. Não se soma novamente à estimativa de custo real.</p></section>
    <section class="rsp-demo-create-section" aria-label="Faturação"><div class="meeting-title"><span>FATURAÇÃO</span></div>${field('billed',moneyFields.billed)}<p class="rsp-demo-status">Por faturar = venda total atualizada − valor recebido.</p></section>
    <section class="rsp-demo-create-section" aria-label="Prazo"><div class="meeting-title"><span>PRAZO</span></div><div class="rsp-demo-date-fields">${Object.entries(dateFields).map(([k,label])=>field(k,label)).join('')}</div></section>
    <section class="rsp-demo-create-section" aria-label="Acompanhamento"><div class="meeting-title"><span>ACOMPANHAMENTO</span></div><div class="rsp-demo-note-fields">${noteEditor('planning','PLANEAMENTO',draft,'Planeamento')}${noteEditor('tees','TEEs',draft,'TEEs')}</div></section>`}
    <p class="form-error" data-demo-create-validation role="alert"></p><div class="rsp-demo-actions"><button type="submit" class="secondary-button" data-demo-create>GUARDAR OBRA</button><button type="button" class="secondary-button" data-demo-cancel>CANCELAR</button></div></form>`:'';}
  function hiddenManager(){const hidden=records.filter(w=>w.hidden);return !present&&hidden.length?`<details class="rsp-detail" data-demo-hidden><summary>RETIRADAS DA APRESENTAÇÃO (${hidden.length}) — DADOS PRESERVADOS</summary><div class="rsp-demo-hidden-list">${hidden.map(w=>`<div><span>${escape(workLabel(w))} · ${escape(w.name)}</span><button type="button" class="secondary-button" data-demo-restore="${w.id}"${storageError?' disabled':''}>REATIVAR</button></div>`).join('')}</div></details>`:'';}
  function renderList(){const active=works();return `<div class="page-heading rsp-heading"><div><p class="eyebrow">GESTÃO DE PRODUÇÃO · RSP DEMO</p><h1>REUNIÃO SEMANAL DE PRODUÇÃO</h1><span>Obras cadastradas manualmente · dados exclusivos da reunião.</span></div>${actions()}</div>${status()}${newForm()}
    <section class="rsp-list">${active.map((work,index)=>{const v=demoValues(work.data);return `<article class="rsp-work panel" data-demo-card="${work.id}">
      <header class="rsp-work-header"><div><p class="eyebrow">${escape(workLabel(work))}</p><h2>${escape(work.name)}</h2>${work.client?`<span>${escape(work.client)}</span>`:''}${work.director?`<small class="rsp-demo-director">Diretor de Obra: ${escape(work.director)}</small>`:''}</div><div class="rsp-demo-actions"><button type="button" class="secondary-button" data-demo-open="${work.id}">ABRIR DETALHE →</button>${!present?`<button type="button" class="secondary-button" data-demo-edit="${work.id}">EDITAR OBRA</button><button type="button" class="secondary-button" data-demo-up="${work.id}" aria-label="Subir ${escape(work.name)}"${index===0||storageError?' disabled':''}>↑</button><button type="button" class="secondary-button" data-demo-down="${work.id}" aria-label="Descer ${escape(work.name)}"${index===active.length-1||storageError?' disabled':''}>↓</button><button type="button" class="secondary-button" data-demo-hide="${work.id}"${storageError?' disabled':''}>RETIRAR DA APRESENTAÇÃO</button>`:''}</div></header>
      ${modelOf(work)===INVESTMENT_MODEL?investmentCard(work.data,{progress,deadlinePercent:v.deadlinePercent}):`<div class="rsp-kpis">${financialLabels.map(([label,k])=>`<div><span>${label}</span><strong>${format(v[k])}</strong></div>`).join('')}</div>
      ${legacyNotice(work.data)}${estimates(work.data)}<div class="rsp-progress-grid">${progress('RECEBIDO',v.billingPercent)}${progress('PRAZO CONSUMIDO',v.deadlinePercent,'',true)}</div>
      ${[['planning','PLANEAMENTO'],['tees','TEEs']].map(([k,label])=>`<details class="rsp-detail"><summary>${label}</summary><div class="rsp-demo-notes">${escape(work.data[k]||'—')}</div></details>`).join('')}`}
    </article>`;}).join('')||`<div class="overview-empty panel">${storageError?'DADOS DO SERVIDOR INDISPONÍVEIS — NENHUM ESTADO VAZIO FOI GRAVADO':busy?'A CARREGAR DADOS DO SERVIDOR…':records.length?'NÃO HÁ OBRAS NA APRESENTAÇÃO. USE EDITAR PARA REATIVAR AS OBRAS RETIRADAS.':'A RSP DEMO ESTÁ VAZIA. CADASTRE A PRIMEIRA OBRA EM + NOVA OBRA.'}</div>`}</section>${hiddenManager()}`;}
  function renderDetail(work){const v=demoValues(draft);
    if(modelOf(work)===INVESTMENT_MODEL)return `<div class="meeting-heading"><button type="button" data-demo-back>← RSP DEMO</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · ${escape(workLabel(work))} · INVESTIMENTO PRÓPRIO</p><h1>${escape(work.name)}</h1>${work.director?`<small class="rsp-demo-director">Diretor de Obra: ${escape(work.director)}</small>`:''}</div><div class="rsp-demo-heading-end">${actions()}</div></div>${status()}${!present?`<section class="panel meeting-card"><div class="meeting-title"><span>IDENTIFICAÇÃO DA OBRA · INVESTIMENTO PRÓPRIO</span></div>${metadataEditor()}<p class="rsp-demo-status">Modalidade preservada. Não se convertem empreitadas existentes automaticamente.</p></section>`:''}${investmentDetail(draft,{editing:!present,field,dateFields,noteEditor,progress,deadlinePercent:v.deadlinePercent,dateDetail:dateDetail()})}`;
    return `
    <div class="meeting-heading"><button type="button" data-demo-back>← RSP DEMO</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · ${escape(workLabel(work))} · DEMO</p><h1>${escape(work.name)}</h1>${work.client?`<span>${escape(work.client)}</span>`:''}${work.director?`<small class="rsp-demo-director">Diretor de Obra: ${escape(work.director)}</small>`:''}</div><div class="rsp-demo-heading-end">${actions()}</div></div>
    ${status()}${!present?`<section class="panel meeting-card"><div class="meeting-title"><span>IDENTIFICAÇÃO DA OBRA</span></div>${metadataEditor()}</section>`:''}
    <section class="meeting-kpis">${financialLabels.map(([label,k])=>`<article><span>${label}</span><strong data-demo-kpi="${k}">${format(v[k])}</strong><small>${k==='remaining'?'venda total atualizada − valor recebido':k==='margin'?'venda total atualizada − custo direto total':k==='sale'?'venda contratual inicial + TEEs aprovados':'preenchimento manual'}</small></article>`).join('')}</section>
    <section class="meeting-two"><article class="panel meeting-card"><div class="meeting-title"><span>RESUMO CONTRATUAL</span></div><dl class="meeting-dl">${Object.entries(moneyFields).filter(([k])=>k!=='billed').map(([k,label])=>`<div><dt>${escape(label)}</dt><dd>${present?`<span data-demo-financial="${k}">${format(amount(draft[k]))}</span>`:field(k,label,false)}</dd></div>`).join('')}</dl>${estimates(draft,false)}</article>
    <article class="panel meeting-card"><div class="meeting-title"><span>FATURAÇÃO E PRAZO</span></div>${present?'':field('billed',moneyFields.billed)}${progress('RECEBIDO',v.billingPercent,`${format(v.billed)} recebidos · venda ${format(v.sale)}`)}${progress('PRAZO CONSUMIDO',v.deadlinePercent,dateDetail(),true)}${present?'':`<div class="rsp-demo-date-fields">${Object.entries(dateFields).map(([k,label])=>field(k,label)).join('')}</div>`}</article></section>
    <section class="meeting-two">${notes(draft,!present)}</section>`;}
  function refreshValues(){if(modelDraft===INVESTMENT_MODEL){const budget=root.querySelector('[data-investment-budget]');if(budget)budget.textContent=format(amount(draft.investment?.initialBudget));return;}const v=demoValues(draft);for(const k of ['sale','cost','margin','remaining']){const el=root.querySelector(`[data-demo-kpi="${k}"]`);if(el)el.textContent=format(v[k]);}for(const el of root.querySelectorAll('[data-demo-estimate]'))el.textContent=format(v[el.dataset.demoEstimate]);const oldNotice=root.querySelector('.rsp-demo-legacy-note');if(oldNotice)oldNotice.outerHTML=legacyNotice(draft);const billing=root.querySelector('[data-demo-progress=billing]'),deadline=root.querySelector('[data-demo-progress=deadline]');if(billing)billing.outerHTML=progress('RECEBIDO',v.billingPercent,`${format(v.billed)} recebidos · venda ${format(v.sale)}`);if(deadline)deadline.outerHTML=progress('PRAZO CONSUMIDO',v.deadlinePercent,dateDetail(),true);}
  function render(){if(!authorized()){root.replaceChildren();return;}const work=records.find(x=>x.id===current);root.classList.toggle('rsp-view',!work);root.classList.toggle('meeting-view',Boolean(work));root.dataset.demoScreen=work?'detail':'list';root.innerHTML=work?renderDetail(work):renderList();if(busy||!loadedFor||backupError){for(const el of root.querySelectorAll('button,input,textarea,select'))if(!el.matches('[data-demo-export],[data-demo-recover]'))el.disabled=true;}}
  async function createWork(){
    if(!authorized()||!creating||storageError)return;if(!validMetadata()){message('O nome utilizado na reunião é obrigatório.');return;}
    if(!validDraft()){message('Verifique valores monetários, datas e conclusão posterior ao início.');return;}
    let id;try{id=pendingCreateId||'demo-'+createId();pendingCreateId=id;if(!/^demo-[a-f0-9-]{36}$/i.test(id)||records.some(w=>w.id===id))throw Error('ID');}catch{message('Não foi possível criar um identificador local único. Nenhum dado foi alterado.');return;}
    if(await commitRecords([...records,{id,...cleanMetadata(metaDraft),hidden:false,presentationModel:modelDraft,data:sanitize(draft,modelDraft)}])){creating=false;pendingCreateId='';dirty=false;metaDraft=emptyMetadata();draft=empty();render();}else render();
  }
  async function reorder(id,direction){const active=works(),from=active.findIndex(w=>w.id===id),to=from+direction;if(from<0||to<0||to>=active.length)return;const next=[...records],a=next.findIndex(w=>w.id===id),b=next.findIndex(w=>w.id===active[to].id);[next[a],next[b]]=[next[b],next[a]];await commitRecords(next);render();}
  root.addEventListener('input',event=>{if(!authorized())return;
    const ik=event.target.dataset.investmentField,vk=event.target.dataset.investmentVat;
    if(ik||vk){if(modelDraft!==INVESTMENT_MODEL)return;draft.investment??=blankInvestment();if(ik&&Object.hasOwn(draft.investment,ik)&&ik!=='vatBasis')draft.investment[ik]=event.target.value;else if(vk&&Object.hasOwn(draft.investment.vatBasis,vk))draft.investment.vatBasis[vk]=event.target.value;else return;refreshValues();dirty=true;protectDraft();if(backupError)render();const status=root.querySelector('[data-demo-status]');if(status)status.textContent='Alterações por guardar';return;}
    const k=event.target.dataset.field,m=event.target.dataset.meta;if(Object.hasOwn(fields,k??'')){draft[k]=event.target.value;refreshValues();}else if(Object.hasOwn(metadataFields,m??'')){metaDraft[m]=event.target.value;}else return;dirty=true;protectDraft();if(backupError){render();return;}const status=root.querySelector('[data-demo-status]');if(status)status.textContent='Alterações por guardar';});
  root.addEventListener('submit',async event=>{event.preventDefault();if(event.target.matches('[data-demo-create-form]'))await createWork();});
  root.addEventListener('click',async event=>{
    if(!authorized()||busy)return;const button=event.target.closest('button');if(!button||button.disabled)return;
    if(button.matches('[data-demo-recover]')){await recoverDraft(button.dataset.demoRecover);return;}
    if(button.matches('[data-demo-export]')){exportDraft();return;}
    if(button.matches('[data-demo-import-local]')){try{await importDocument(JSON.parse(getStorage().getItem(key())));}catch{message('Não há documento local válido nesta conta e origem.');}return;}
    if(button.matches('[data-demo-import-file]')){root.querySelector('[data-demo-file]').click();return;}
    if(button.matches('[data-demo-new]')){modelDraft=CONTRACT_MODEL;creating=true;pendingCreateId='';present=false;dirty=false;metaDraft=emptyMetadata();draft=empty();render();return;}
    if(button.matches('[data-demo-cancel]')){const same=key();if(dirty&&!await confirm('Descartar apenas os dados da nova obra ainda não guardada?'))return;if(!authorized()||key()!==same)return;creating=false;pendingCreateId='';dirty=false;metaDraft=emptyMetadata();draft=empty();render();return;}
    if(button.matches('[data-demo-open],[data-demo-edit]')){const edit=button.matches('[data-demo-edit]');const work=records.find(w=>w.id===(edit?button.dataset.demoEdit:button.dataset.demoOpen)&&!w.hidden);if(!work)return;if(creating&&dirty){message('Guarde ou cancele o cadastro antes de abrir outra obra.');return;}creating=false;if(edit)present=false;current=work.id;modelDraft=modelOf(work);draft=structuredClone(work.data);metaDraft=cleanMetadata(work);dirty=false;render();host.scrollTo?.(0,0);return;}
    if(button.matches('[data-demo-back]')){if(dirty&&!await validateAndSave())return;current='';draft=empty();metaDraft=emptyMetadata();render();host.scrollTo?.(0,0);return;}
    if(button.matches('[data-demo-save]')){if(!validMetadata()||!validDraft()){await validateAndSave();return;}await save();render();return;}
    if(button.matches('[data-demo-up]')){await reorder(button.dataset.demoUp,-1);return;}
    if(button.matches('[data-demo-down]')){await reorder(button.dataset.demoDown,1);return;}
    if(button.matches('[data-demo-hide]')){await commitRecords(records.map(w=>w.id===button.dataset.demoHide?{...w,hidden:true}:w));render();return;}
    if(button.matches('[data-demo-restore]')){await commitRecords(records.map(w=>w.id===button.dataset.demoRestore?{...w,hidden:false}:w));render();return;}
    if(button.matches('[data-demo-mode]')){if(creating){message('Guarde ou cancele o cadastro antes de apresentar.');return;}if(!present&&current&&!await validateAndSave())return;present=!present;render();}
  });
  host.addEventListener('beforeunload',event=>{if(dirty||busy){event.preventDefault();event.returnValue='';}});
  root.addEventListener('change',async event=>{if(event.target.matches('[data-demo-model]')&&authorized()&&creating&&!busy){const model=event.target.value;if(![CONTRACT_MODEL,INVESTMENT_MODEL].includes(model))return;modelDraft=model;if(model===INVESTMENT_MODEL)draft.investment??=blankInvestment();dirty=true;protectDraft();render();return;}if(!event.target.matches('[data-demo-file]')||!authorized())return;const file=event.target.files?.[0];if(!file)return;if(file.size>2000000){message('O ficheiro excede 2 MB.');return;}try{await importDocument(JSON.parse(await file.text()));}catch{message('Ficheiro inválido; nada foi alterado.');}});
  return {async show(){if(!authorized()){root.replaceChildren();return;}await load();if(current&&!records.some(w=>w.id===current)){current='';draft=empty();metaDraft=emptyMetadata();dirty=false;}const fresh=records.find(w=>w.id===current);if(fresh&&!dirty){modelDraft=modelOf(fresh);draft=structuredClone(fresh.data);metaDraft=cleanMetadata(fresh);}render();},reset(){modelDraft=CONTRACT_MODEL;draftSlot='';backupError='';recoveryDocument=null;generation++;pendingCreateId="";records=[];current='';draft=empty();metaDraft=emptyMetadata();present=true;dirty=false;creating=false;loadedFor='';baselineRaw=null;revision=0;busy=false;syncMessage='';storageError='';root.replaceChildren();}};
}
