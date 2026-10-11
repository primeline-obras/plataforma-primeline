// Financeiro only. No shared session, permissions or operational module is changed.
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const norm=value=>String(value??'').trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
export const EXPENSE_MONTHS=['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'];
const categories=new Map([['remuneracoes e encargos (sede)','remuneracoes_sede'],['remuneracoes e encargos sede','remuneracoes_sede'],['despesas sede','despesas_sede'],['despesas armazem','despesas_armazem']]);
const categoryLabels={remuneracoes_sede:'Remunerações e Encargos (Sede)',despesas_sede:'Despesas Sede',despesas_armazem:'Despesas Armazém'};
const statusLabels={valid:'VÁLIDA',invalid:'INVÁLIDA',duplicate:'DUPLICADA'};
const euro=value=>Number(value).toLocaleString('pt-PT',{style:'currency',currency:'EUR'});
export function expenseAmount(value){
 if(value==null||String(value).trim()==='')return null;
 if(typeof value==='number'){if(Number.isFinite(value))return value;throw Error('Valor não finito.');}
 let text=String(value).trim();
 if(!/^[+-]?(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d{1,2})?$/.test(text)&&!/^[+-]?\d+(?:\.\d{1,2})?$/.test(text))throw Error('Valor inválido: use números, sem texto ou fórmulas.');
 if(text.includes(','))text=text.replaceAll('.','').replace(',','.');
 const result=Number(text);if(!Number.isFinite(result))throw Error('Valor inválido.');return result;
}
export function parseExpenseGrid(grid,works=[]){
 const header=grid.findIndex(row=>norm(row[0]).startsWith('obra')&&EXPENSE_MONTHS.every((m,i)=>norm(row[i+1]).slice(0,3)===m));
 if(header<0)throw Error('Cabeçalho obrigatório: Obra seguido de JAN a DEZ, nessa ordem.');
 const rows=[],errors=[];
 grid.slice(header+1).forEach((row,i)=>{
  if(row.every(v=>String(v??'').trim()===''))return;
  const line=header+i+2,label=String(row[0]??'').trim(),category=categories.get(norm(label));
  const matches=works.filter(w=>String(w.numero)===label);
  if(!category&&matches.length!==1){errors.push({linha:line,label,erro:'Obra não identificada unicamente ou categoria desconhecida.'});return;}
  try{
   if(row.slice(13).some(v=>String(v??'').trim()))throw Error('Há dados fora das 12 colunas mensais.');
   const meses=EXPENSE_MONTHS.map((_,m)=>expenseAmount(row[m+1]));
   if(meses.every(v=>v===null))throw Error('A linha precisa de pelo menos um valor mensal.');
   rows.push({tipo:category?'despesa_fixa':'obra',...(category?{categoria:category}:{obra_id:matches[0].id}),meses,linha:line});
  }catch(error){errors.push({linha:line,label,erro:error.message});}
 });
 if(!rows.length&&!errors.length)throw Error('O ficheiro não contém linhas para importar.');
 return {rows,errors};
}
export function createFinancialExpensesImport({supabase,getProfile,isConfigured,onComplete}){
 let state,overlay,generation=0,sessionWatch;
 const session=()=>`${getProfile()?.id??''}:${getProfile()?.empresa_id??''}:${getProfile()?.funcao??''}`;
 const permitted=()=>['gestao_plataforma','gerencia','financeiro'].includes(getProfile()?.funcao);
 function close(){generation++;clearInterval(sessionWatch);sessionWatch=null;state=null;overlay?.remove();overlay=null;}
 async function api(name,data){
  if(!isConfigured)throw Error('Ligação à base de dados indisponível.');
  const captured=state,epoch=generation;
  if(!captured||session()!==captured.session||!permitted()){close();throw Error('Sessão alterada. Abra novamente o importador.');}
  const response=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(data)});
  const body=await response.json();
  if(epoch!==generation||state!==captured||session()!==captured.session){close();throw Error('Sessão alterada; resposta anterior descartada.');}
  if(!response.ok){const error=Error(body.message||'Não foi possível concluir.');error.code=body.code;throw error;}
  return body;
 }
 function params(confirm=false){return {p_ano:state.year,p_linhas:state.rows,p_nome_ficheiro:state.file,p_request_id:state.request,p_confirmar:confirm,p_preview_token:state.preview?.preview_token??null,p_substituir:state.replace};}
 async function preview(){state.request=crypto.randomUUID();state.preview=null;state.ask=false;state.result=null;state.preview=await api('fn_despesas_gerais_importar_v1',params());}
 async function busy(action){
  if(!state||state.busy)return;const captured=state;captured.busy=true;captured.error='';render();
  try{await action();}catch(error){if(state===captured){captured.error=error.message;if(error.code==='40001'){captured.preview=null;captured.ask=false;captured.error+=' Os dados mudaram. Refaça a pré-visualização.';}}}
  finally{if(state===captured){captured.busy=false;render();}}
 }
 function render(){
  if(!state||!overlay)return;
  const p=state.preview,r=state.result;
  overlay.querySelector('[data-content]').innerHTML=`<p>Ano <strong>${state.year}</strong> · ${esc(state.file||'Selecione um ficheiro')}</p><p>Nenhum pagamento, fatura ou débito bancário será criado. A importação grava valores mensais no Mapa Financeiro.</p>${state.error?`<p role="alert" style="color:#9d2929">${esc(state.error)}</p>`:''}${!r?`<label>${state.file?'Substituir ficheiro Excel (.xlsx)':'Ficheiro Excel (.xlsx)'}<input data-file type="file" accept=".xlsx" ${state.busy?'disabled':''}></label>`:''}${state.errors.length?`<h3>Corrija o ficheiro antes de confirmar</h3><ul>${state.errors.map(e=>`<li>Linha ${e.linha}: ${esc(e.label)} — ${esc(e.erro)}</li>`).join('')}</ul>`:''}${p?`<section data-summary style="display:flex;gap:32px;padding:20px 0"><div>VÁLIDAS<br><strong>${p.validas}</strong></div><div>INVÁLIDAS<br><strong>${p.invalidas}</strong></div><div>DUPLICADAS<br><strong>${p.duplicadas}</strong></div></section><div style="overflow:auto;max-height:360px"><table style="width:100%;text-align:left;border-collapse:collapse"><thead><tr><th>Linha</th><th>Destino</th><th>Valores mensais</th><th>Estado</th><th>Validação</th></tr></thead><tbody>${p.linhas.map((line,i)=>`<tr><td style="padding:12px">${state.rows[i]?.linha??i+1}</td><td>${esc(categoryLabels[state.rows[i]?.categoria]??('Obra '+(state.works.find(w=>w.id===state.rows[i]?.obra_id)?.numero??'')))}</td><td>${(state.rows[i]?.meses??[]).map((v,m)=>v===null?'':esc(EXPENSE_MONTHS[m].toUpperCase()+': '+euro(v))).filter(Boolean).join('<br>')}</td><td>${esc(statusLabels[line.estado]??line.estado)}</td><td>${(line.erros??[]).map(esc).join(' · ')||'Sem erros'}</td></tr>`).join('')}</tbody></table></div>`:''}${!r&&state.rows.length&&!state.errors.length?`<label style="display:block;margin:20px 0"><input data-replace type="checkbox" ${state.replace?'checked':''} ${state.busy?'disabled':''}> Autorizar substituição de valores mensais já existentes. Exige nova pré-visualização.</label>${!p?'<button data-preview>VALIDAR / PRÉ-VISUALIZAR</button>':''}${p&&!p.invalidas?state.ask?`<section data-confirm style="border:2px solid #a47739;padding:20px;margin:20px 0"><h3>Confirmar importação de ${p.validas} linhas?</h3><p>${p.duplicadas} duplicadas serão preservadas. Ano ${state.year}. ${state.replace?'Substituições explicitamente autorizadas.':'Sem substituir valores existentes.'}</p><button data-back ${state.busy?'disabled':''}>VOLTAR</button> <button data-commit ${state.busy?'disabled':''}>CONFIRMAR E GRAVAR</button></section>`:`<button data-ask ${state.busy?'disabled':''}>REVER CONFIRMAÇÃO</button>`:''}`:''}${r?`<section data-result style="padding:20px;background:#eef5ef"><h3>IMPORTAÇÃO CONCLUÍDA</h3><p>${r.validas} válidas · ${r.duplicadas} duplicadas · ${r.invalidas} inválidas.</p><p>Referência: ${esc(r.request_id)}${r.replay?' · Resultado recuperado sem repetir a escrita.':''}</p><label>Motivo para reverter somente esta importação<input data-reason type="text" minlength="5" maxlength="1000" style="display:block;width:100%;box-sizing:border-box"></label><button data-reverse-preview ${state.busy?'disabled':''}>PRÉ-VISUALIZAR REVERSÃO</button>${state.reversePreview?`<p>Reverter ${state.reversePreview.objetos??state.reversePreview.alteracoes??'os'} objetos desta importação. Auditoria preservada.</p><button data-reverse-commit ${state.busy?'disabled':''}>CONFIRMAR REVERSÃO</button>`:''}${state.reversed?'<p data-reversed>Importação revertida; trilho preservado.</p>':''}</section>`:''}<footer style="display:flex;justify-content:flex-end;margin-top:24px"><button data-close ${state.busy?'disabled':''}>${r?'FECHAR':'CANCELAR — SEM GRAVAR'}</button></footer>`;
 }
 function open({year,works}){
  close();if(!permitted())throw Error('Perfil sem permissão para importar despesas.');
  state={year,works,session:session(),rows:[],errors:[],file:'',request:null,preview:null,result:null,replace:false,ask:false,busy:false,error:'',reversePreview:null,reversed:false};
  overlay=document.createElement('div');overlay.dataset.financialExpenses='';
  overlay.style.cssText='position:fixed;inset:0;z-index:2000;background:#0008;display:flex;align-items:center;justify-content:center;padding:24px;box-sizing:border-box';
  overlay.innerHTML='<section role="dialog" aria-modal="true" aria-labelledby="financial-import-title" style="background:var(--surface,#fffdf8);color:var(--text,#27332d);border-radius:12px;padding:28px;max-width:960px;width:100%;max-height:90vh;overflow:auto;box-sizing:border-box"><h2 id="financial-import-title">IMPORTAR MAPA FINANCEIRO</h2><div data-content></div></section>';
  document.body.append(overlay);render();
  sessionWatch=setInterval(()=>{if(state&&session()!==state.session)close();},100);
  overlay.addEventListener('change',event=>{
   if(event.target.matches('[data-file]'))busy(async()=>{
    const file=event.target.files?.[0];if(!file)return;
    state.preview=null;state.result=null;state.rows=[];state.errors=[];state.ask=false;
    if(!/\.xlsx$/i.test(file.name)||file.size>5000000)throw Error('Escolha um .xlsx até 5 MB.');
    if(!globalThis.XLSX)throw Error('Leitor Excel indisponível.');
    const current=state,epoch=generation,buffer=await file.arrayBuffer();
    if(state!==current||generation!==epoch||session()!==current.session)return close();
    const wb=globalThis.XLSX.read(buffer,{type:'array',cellFormula:true});
    const candidates=wb.SheetNames.filter(n=>/mapa.*financeiro/i.test(n));
    if(candidates.length!==1)throw Error('O ficheiro deve conter exatamente uma folha “Mapa Financeiro”.');
    const sheet=wb.Sheets[candidates[0]];
    if(Object.values(sheet).some(c=>c&&typeof c==='object'&&c.f))throw Error('Use valores fixos; fórmulas não são aceites.');
    const parsed=parseExpenseGrid(globalThis.XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:''}),state.works);
    state.file=file.name;state.rows=parsed.rows;state.errors=parsed.errors;if(!state.errors.length)await preview();
   });
   if(event.target.matches('[data-replace]'))busy(async()=>{state.replace=event.target.checked;await preview();});
  });
  overlay.addEventListener('click',event=>{
   if(event.target.closest('[data-close]')&&!state.busy)return close();
   if(event.target.closest('[data-ask]')){state.ask=true;render();}
   if(event.target.closest('[data-back]')){state.ask=false;render();}
   if(event.target.closest('[data-preview]'))busy(preview);
   if(event.target.closest('[data-commit]'))busy(async()=>{const result=await api('fn_despesas_gerais_importar_v1',params(true));if(!result.committed)throw Error('Importação não confirmada.');state.result=result;state.ask=false;await onComplete?.();});
   if(event.target.closest('[data-reverse-preview]')){
    const reason=overlay.querySelector('[data-reason]').value.trim();
    busy(async()=>{state.reverseReason=reason;if(state.reverseReason.length<5)throw Error('Indique um motivo com pelo menos 5 caracteres.');state.reverseRequest=crypto.randomUUID();state.reversePreview=await api('fn_despesas_gerais_reverter_v1',{p_import_request_id:state.result.request_id,p_request_id:state.reverseRequest,p_motivo:state.reverseReason,p_confirmar:false,p_preview_token:null});});
   }
   if(event.target.closest('[data-reverse-commit]'))busy(async()=>{await api('fn_despesas_gerais_reverter_v1',{p_import_request_id:state.result.request_id,p_request_id:state.reverseRequest,p_motivo:state.reverseReason,p_confirmar:true,p_preview_token:state.reversePreview.preview_token});state.reversePreview=null;state.reversed=true;await onComplete?.();});
  });
 }
 return {open,close};
}
