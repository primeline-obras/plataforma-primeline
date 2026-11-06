import {prepararLeitor, podeConsultarFornecedores} from './supplier-invoices-reader.js?v=c-consulta-1';

const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const technical={recebida:'Recebida',em_validacao:'Em validação técnica',pendente_documentacao:'Pendente de documentação',devolvida:'Devolvida para esclarecimento',aprovada_tecnicamente:'Aprovada tecnicamente',enviada_financeiro:'Enviada ao Financeiro'};
const settlement={por_pagar:'Por pagar',parcialmente_liquidada:'Parcialmente liquidada',liquidada:'Liquidada'};
const actions={receber:'Fatura recebida',corrigir:'Dados corrigidos',validar:'Validação iniciada',pendencia:'Pendência documental',devolver:'Devolução para esclarecimento',aprovar:'Aprovação técnica',encaminhar:'Encaminhamento ao Financeiro',anexar_documento:'Documento associado',pagar:'Pagamento registado'};
const missing=value=>value===null?'Não indicado':'Desconhecido';
const label=(value,labels)=>value==null?missing(value):labels[value]||String(value);
export function supplierMoney(value){
 if(value==null)return missing(value);
 if(typeof value!=='string'&&typeof value!=='number')return 'Desconhecido';
 const match=String(value).match(/^(-?)(\d+)(?:\.(\d{1,2}))?$/);
 if(!match)return 'Desconhecido';
 return `${match[1]}${BigInt(match[2]).toLocaleString('pt-PT')} ,${(match[3]||'').padEnd(2,'0')} €`.replace(' ,',',');
}
function civil(value){
 if(value==null)return missing(value);
 const match=String(value).match(/^(\d{4})-(\d{2})-(\d{2})$/);
 return match?`${match[3]}/${match[2]}/${match[1]}`:'Desconhecido';
}
function moment(value){
 if(!value)return missing(value);
 const date=new Date(value);
 return Number.isFinite(date.getTime())?new Intl.DateTimeFormat('pt-PT',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Lisbon'}).format(date):'Desconhecido';
}
const key=identity=>JSON.stringify([identity?.authUserId,identity?.userId,identity?.companyId,identity?.role]);
export function createSupplierInvoicesReadonly({root,api,getIdentity}){
 root.classList.add('supplier-invoices-readonly');
 const reader=prepararLeitor({api,getIdentity});
 let generation=0,context=null,boundIdentity=null,selected=null,filters={work:'',technical:'',settlement:'',search:''};
 const emptyFilters=()=>({work:'',technical:'',settlement:'',search:''});
 function reset(){generation++;reader.reset();context=null;boundIdentity=null;selected=null;filters=emptyFilters();root.replaceChildren();}
 const lookup=(rows,id,fallback)=>rows.find(row=>row.id===id)?.nome||fallback;
 const name=(type,id,fallback)=>id==null?'Não indicado':lookup(context[type],id,fallback);
 const options=(rows)=>rows.map(row=>`<option value="${esc(row.id)}">${esc(row.nome||'Não indicado')}</option>`).join('');
 function visible(){return context.invoices.filter(row=>(!filters.work||row.obra_id===filters.work)&&(!filters.technical||row.estado_tecnico===filters.technical)&&(!filters.settlement||row.estado_liquidacao===filters.settlement)&&(!filters.search||`${row.numero_doc} ${name('suppliers',row.fornecedor_id,'Fornecedor não disponível')}`.toLocaleLowerCase('pt-PT').includes(filters.search.toLocaleLowerCase('pt-PT'))));}
 function notice(text,kind='status'){
  root.innerHTML=`<header class="sic-heading"><div><h1>Faturas de fornecedores</h1><p>Consulta dos documentos, estados e histórico autorizados.</p></div></header><section class="sic-panel sic-empty"><p role="${kind}">${esc(text)}</p>${kind==='alert'?'<button type="button" data-sic-refresh>ATUALIZAR CONSULTA</button>':''}</section>`;
 }
 function detail(row){
  const payments=context.payments.filter(p=>p.recepcao_id===row.id);
  const history=context.history.filter(h=>h.recepcao_id===row.id).slice().sort((a,b)=>String(b.criado_em||'').localeCompare(String(a.criado_em||'')));
  return `<section class="sic-panel" data-sic-detail tabindex="-1" aria-labelledby="sic-detail-title"><div class="sic-panel-head"><h2 id="sic-detail-title">Consulta do documento</h2><span>Revisão ${esc(row.revision??'desconhecida')}</span></div><div class="sic-detail"><h3>${esc(row.numero_doc)}</h3><p class="sic-muted">${esc(name('suppliers',row.fornecedor_id,'Fornecedor não disponível'))}</p><dl class="sic-meta"><div><dt>OBRA</dt><dd>${esc(name('works',row.obra_id,'Obra não disponível'))}</dd></div><div><dt>DATA DA FATURA</dt><dd>${esc(civil(row.data_fatura))}</dd></div><div><dt>ESTADO TÉCNICO</dt><dd>${esc(label(row.estado_tecnico,technical))}</dd></div><div><dt>ESTADO DE LIQUIDAÇÃO</dt><dd>${esc(label(row.estado_liquidacao,settlement))}</dd></div><div><dt>VENCIMENTO</dt><dd>${esc(civil(row.data_vencimento))}</dd></div></dl><dl class="sic-amounts">${[['Líquido · sem IVA',row.liquido],['IVA fiscal',row.iva],['Total documental',row.total],['Valor pago',row.pago],['Saldo por liquidar',row.saldo]].map(([title,value])=>`<div><dt>${title}</dt><dd>${esc(supplierMoney(value))}</dd></div>`).join('')}</dl><h4>PAGAMENTOS REGISTADOS · CONSULTA</h4>${payments.length?`<ul class="sic-payments">${payments.map(p=>`<li><span>${esc(civil(p.data))} · ${esc(p.referencia??'Referência não indicada')}</span><strong>${esc(supplierMoney(p.valor))}</strong></li>`).join('')}</ul>`:'<p class="sic-muted">Sem parcelas registadas.</p>'}<p class="sic-muted">Aprovação técnica e liquidação são estados distintos.</p><h4>HISTÓRICO DO DOCUMENTO</h4>${history.length?`<ol class="sic-timeline">${history.map(h=>`<li><strong>${esc(label(h.acao,actions))}</strong><small>${esc(moment(h.criado_em))} · ${esc(name('people',h.autor_id,'Autor não disponível'))}</small><p>${esc(h.motivo??'Motivo não indicado')}</p><details><summary>Consultar antes e depois</summary><h5>Antes</h5><pre>${esc(h.antes===undefined?'Desconhecido':JSON.stringify(h.antes,null,2))}</pre><h5>Depois</h5><pre>${esc(h.depois===undefined?'Desconhecido':JSON.stringify(h.depois,null,2))}</pre></details></li>`).join('')}</ol>`:'<p class="sic-muted">Sem eventos devolvidos pelo leitor autorizado.</p>'}<p class="sic-muted">Origem: receção V1, parcelas e respetivo histórico autorizado.</p></div></section>`;
 }
 function render(){
  if(!context||boundIdentity!==key(getIdentity())){reset();notice('O contexto mudou. Atualize a consulta.','alert');return;}
  const rows=visible();if(!rows.some(r=>r.id===selected))selected=null;
  const row=rows.find(r=>r.id===selected);
  root.innerHTML=`<header class="sic-heading"><div><h1>Faturas de fornecedores</h1><p>Consulta dos documentos, estados e histórico autorizados.</p></div><span class="sic-mode">ESCRITA FECHADA · CONSULTA</span></header><p class="sic-scope">Âmbito: empresa atual e obras autorizadas.</p><section class="sic-filters" aria-label="Filtros de consulta"><label>OBRA<select data-sic-filter="work"><option value="">Todas as autorizadas</option>${options(context.works)}</select></label><label>ESTADO TÉCNICO<select data-sic-filter="technical"><option value="">Todos</option>${Object.entries(technical).map(([id,nome])=>`<option value="${id}">${nome}</option>`).join('')}</select></label><label>ESTADO DE LIQUIDAÇÃO<select data-sic-filter="settlement"><option value="">Todos</option>${Object.entries(settlement).map(([id,nome])=>`<option value="${id}">${nome}</option>`).join('')}</select></label><label class="sic-search">DOCUMENTO OU FORNECEDOR<input type="search" data-sic-filter="search" placeholder="Pesquisar" value="${esc(filters.search)}"></label><button type="button" data-sic-refresh>ATUALIZAR</button></section><div class="sic-workspace"><section class="sic-panel" aria-labelledby="sic-list-title"><div class="sic-panel-head"><h2 id="sic-list-title">Documentos autorizados</h2><span role="status">${rows.length} documento${rows.length===1?'':'s'}</span></div>${rows.length?`<table><caption class="sic-sr-only">Receções V1 autorizadas, com estado técnico e de liquidação separados</caption><thead><tr><th>DOCUMENTO / FORNECEDOR</th><th>OBRA</th><th>ESTADO TÉCNICO</th><th>LIQUIDAÇÃO</th></tr></thead><tbody>${rows.map(r=>`<tr class="${r.id===selected?'sic-selected':''}"><td data-label="Documento / fornecedor"><button type="button" data-sic-select="${esc(r.id)}" aria-pressed="${r.id===selected}">${esc(r.numero_doc)}</button><small>${esc(name('suppliers',r.fornecedor_id,'Fornecedor não disponível'))}</small></td><td data-label="Obra">${esc(name('works',r.obra_id,'Obra não disponível'))}</td><td data-label="Estado técnico"><span class="sic-status">${esc(label(r.estado_tecnico,technical))}</span></td><td data-label="Liquidação"><span class="sic-status sic-settlement">${esc(label(r.estado_liquidacao,settlement))}</span></td></tr>`).join('')}</tbody></table>`:`<div class="sic-empty"><h3>${context.invoices.length?'Sem documentos para estes filtros':'Ainda não existem receções V1 para consultar'}</h3><p>${context.invoices.length?'Altere os filtros de consulta.':'Após a primeira instalação, a lista vazia é o resultado esperado. A escrita permanece fechada.'}</p></div>`}<p class="sic-panel-note">As faturas legadas continuam no circuito existente, com os acessos históricos.</p></section>${row?detail(row):'<section class="sic-panel sic-empty"><p>Selecione um documento autorizado para consultar o detalhe e o histórico.</p></section>'}</div>`;
  for(const field of ['work','technical','settlement'])root.querySelector(`[data-sic-filter="${field}"]`).value=filters[field];
 }
 async function show({workId=''}={}){
  reset();const seq=generation;
  if(!podeConsultarFornecedores(getIdentity())){notice('Consulta indisponível ou perfil não autorizado.','alert');return;}
  filters.work=workId;notice('A consultar documentos autorizados…');
  try{
   const result=await reader.load();if(seq!==generation||!root.isConnected)return;
   if(workId&&!result.context.works.some(w=>w.id===workId))throw Error('Obra indisponível');
   context=result.context;boundIdentity=key(getIdentity());render();
  }catch{
   if(seq!==generation||!root.isConnected)return;
   context=null;selected=null;notice('Consulta indisponível ou perfil não autorizado. Nenhuma alteração foi efetuada.','alert');
  }
 }
 root.addEventListener('click',event=>{
  const target=event.target.closest('button');if(!target||!root.contains(target))return;
  if(target.hasAttribute('data-sic-refresh')){void show({workId:filters.work});return;}
  if(target.hasAttribute('data-sic-select')&&context){selected=target.dataset.sicSelect;render();const detail=root.querySelector('[data-sic-detail]');if(detail){detail.focus({preventScroll:true});if(innerWidth<1100)detail.scrollIntoView({block:'start'});}}
 });
 root.addEventListener('change',event=>{
  const field=event.target.dataset.sicFilter;
  if(field==='work'){void show({workId:event.target.value});return;}
  if(['technical','settlement'].includes(field)&&context){filters[field]=event.target.value;selected=null;render();}
 });
 root.addEventListener('input',event=>{
  if(event.target.dataset.sicFilter!=='search'||!context)return;
  const caret=event.target.selectionStart;filters.search=event.target.value;selected=null;render();const input=root.querySelector('[data-sic-filter="search"]');if(input){input.focus({preventScroll:true});input.setSelectionRange(caret,caret);}
 });
 return {show,reset};
}
