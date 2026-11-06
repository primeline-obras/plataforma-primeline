const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function createReceptionClient({rpc,identity,store}){
 const key=()=> 'primeline-c1-recepcao:'+identity();
 const pending=()=>{const raw=store.getItem(key());return raw?JSON.parse(raw):null};let busy=false;
 return {pending,async register(payload,retry=false){if(busy)throw Error('Operação em curso.');const bound=identity(),k=key();if(!bound)throw Error('Sessão indisponível.');let q=pending();if(q&&!retry)throw Error('Confirme o pedido pendente antes de criar outro.');if(!q){q={p_request:crypto.randomUUID(),p_payload:payload};store.setItem(k,JSON.stringify(q))}busy=true;try{const r=await rpc('fn_c1_recepcao_registar',q);if(identity()!==bound)throw Error('Sessão alterada; confirme o pedido na sessão original.');if(!r.ok){const e=await r.json().catch(()=>({}));if([400,422].includes(r.status))store.removeItem(k);throw Error(receptionError(e))}const result=await r.json();if(identity()!==bound)throw Error('Sessão alterada; confirme na sessão original.');if(!result?.receipt?.id)throw Error('Resposta inesperada. Resultado por confirmar; confirme o pedido original.');store.removeItem(k);return result;}finally{busy=false}}};
}
const fields=['obra_id','fornecedor_id','tipo','subempreitada_id','numero','data_fatura','bruto','liquido','excecao_duplicado'];
const emptyDraft=()=>Object.fromEntries(fields.map(k=>[k,'']));
function invalid(field,message){const e=Error(message);e.field=field;throw e;}
function money(value,field,optional=false){
 const text=String(value??'').trim();if(!text&&optional)return '';
 if(!/^\d+(?:[.,]\d{1,2})?$/.test(text))invalid(field,'Indique um valor não negativo, sem milhares, com até duas casas decimais.');
 let [whole,fraction='']=text.replace(',','.').split('.');whole=whole.replace(/^0+(?=\d)/,'');
 if(whole.length>16)invalid(field,'O valor excede o limite permitido (16 algarismos inteiros).');
 return whole+'.'+fraction.padEnd(2,'0');
}
export function validateReceptionPayload(raw,context){
 const p={};
 for(const [field,list,label] of [['obra_id',context.works,'obra'],['fornecedor_id',context.suppliers,'fornecedor']]){
  p[field]=String(raw[field]||'');if(!p[field]||!list.some(x=>x.id===p[field]))invalid(field,'Selecione explicitamente '+label+' válido.');
 }
 p.tipo=String(raw.tipo||'');if(!['material','estaleiro','subempreitada'].includes(p.tipo))invalid('tipo','Selecione o tipo de receção.');
 p.subempreitada_id=String(raw.subempreitada_id||'');
 if(p.tipo==='subempreitada'&&!p.subempreitada_id)invalid('subempreitada_id','Selecione a subempreitada para este tipo de receção.');
 if(p.subempreitada_id&&!context.subcontracts.some(s=>s.id===p.subempreitada_id&&s.obra_id===p.obra_id&&s.fornecedor_id===p.fornecedor_id))invalid('subempreitada_id','A subempreitada não corresponde à obra e ao fornecedor selecionados.');
 p.numero=String(raw.numero||'').trim();if(!p.numero.replace(/\s/g,'')||p.numero.length>120)invalid('numero','Indique o número do documento, até 120 caracteres.');
 p.data_fatura=String(raw.data_fatura||'').trim();const date=new Date(p.data_fatura+'T00:00:00Z');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(p.data_fatura)||p.data_fatura.startsWith('0000')||!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==p.data_fatura)invalid('data_fatura','Indique uma data válida.');
 p.bruto=money(raw.bruto,'bruto');p.liquido=money(raw.liquido,'liquido',true);
 const cents=v=>BigInt(v.replace('.',''));if(p.liquido&&cents(p.liquido)>cents(p.bruto))invalid('liquido','O líquido SEM IVA não pode exceder o total COM IVA.');
 p.excecao_duplicado=String(raw.excecao_duplicado||'').trim();if(p.excecao_duplicado.length>1000)invalid('excecao_duplicado','O motivo de exceção admite até 1000 caracteres.');
 return p;
}
export function receptionError(detail){
 const messages={C1R_DUPLICATE_REQUIRES_ADM_REASON:'Documento duplicado detetado pelo servidor. Reveja os dados; uma exceção exige motivo explícito do Administrativo e nova confirmação.',C1R_NUMBER_REQUIRED:'Indique um número de documento válido.',C1R_INVALID_AMOUNT:'Reveja os valores monetários: não negativos e até duas casas decimais.',C1R_SUBCONTRACT_REQUIRED:'Selecione a subempreitada.',C1R_SUBCONTRACT_MISMATCH:'A subempreitada não corresponde à obra e ao fornecedor.',C1R_WORK_FORBIDDEN:'Obra não autorizada. Atualize as opções antes de continuar.',C1R_SUPPLIER_FORBIDDEN:'Fornecedor não autorizado. Atualize as opções antes de continuar.',C1R_INVALID_TYPE:'Selecione um tipo de receção válido.',C1R_REASON_TOO_LONG:'O motivo de exceção admite até 1000 caracteres.',C1R_REQUEST_DIVERGENT:'Pedido pendente divergente. Não crie outro registo; confirme o estado com o responsável.',C1R_SESSION_UNAVAILABLE:'Sessão indisponível. Regresse à plataforma nesta aba.',C1R_ADM_REQUIRED:'Esta operação exige perfil Administrativo.', '22003':'Valor monetário fora do limite permitido.', '22007':'Data inválida.', '22008':'Data inválida.', '22P02':'Campo em formato inválido.', '23514':'Os dados não respeitam os limites do registo. Reveja os valores e campos obrigatórios.'};
 return messages[detail.message]||messages[detail.code]||'Não foi possível concluir o registo. Se houver pedido pendente, confirme o pedido original antes de tentar outro.';
}
export function createReceptionView({root,rpc,identity,store}){
 let scope='',state=null,busy=false,error='',generation=0,draft=emptyDraft(),review=null,success='';
 const client=createReceptionClient({rpc,identity:()=>identity()&&scope?JSON.stringify([identity(),scope]):'',store});
 const options=rows=>rows.map(r=>`<option value="${esc(r.id)}">${esc(r.numero?`${r.numero} · ${r.nome}`:r.nome)}</option>`).join('');
 const readDraft=f=>Object.fromEntries(fields.map(k=>[k,f.elements[k]?.value||'']));
 function summary(p){const work=state.works.find(x=>x.id===p.obra_id),supplier=state.suppliers.find(x=>x.id===p.fornecedor_id),sub=state.subcontracts.find(x=>x.id===p.subempreitada_id);return `<dl><dt>Obra</dt><dd>${esc(work?`${work.numero||''} ${work.nome}`:p.obra_id)}</dd><dt>Fornecedor</dt><dd>${esc(supplier?.nome||p.fornecedor_id)}</dd><dt>Tipo</dt><dd>${esc(p.tipo)}</dd><dt>Subempreitada</dt><dd>${esc(sub?.nome||p.subempreitada_id||'Sem vínculo')}</dd><dt>Documento / data</dt><dd>${esc(p.numero)} · ${esc(p.data_fatura)}</dd><dt>Total COM IVA</dt><dd>${esc(p.bruto)} €</dd><dt>Líquido SEM IVA</dt><dd>${p.liquido?esc(p.liquido)+' €':'Não informado'}</dd></dl>${p.bruto==='0.00'?'<p role="alert">O total é zero. Confirme que corresponde ao documento.</p>':''}${p.excecao_duplicado?`<p role="alert">Exceção de duplicado solicitada pelo ADM: ${esc(p.excecao_duplicado)}</p>`:''}`;}
 function filterSubcontracts(){const f=root.querySelector('form');if(!f)return;const sub=f.elements.subempreitada_id;sub.disabled=busy||!f.elements.obra_id.value||!f.elements.fornecedor_id.value||!f.elements.tipo.value;sub.required=f.elements.tipo.value==='subempreitada';for(const o of sub.options){if(!o.value)continue;o.hidden=o.dataset.work!==f.elements.obra_id.value||o.dataset.supplier!==f.elements.fornecedor_id.value;o.disabled=o.hidden;if(o.selected&&o.hidden)sub.value='';}if(!f.elements.obra_id.value||!f.elements.fornecedor_id.value||!f.elements.tipo.value)sub.value='';draft.subempreitada_id=sub.value;const hint=root.querySelector('[data-subcontract-hint]');hint.textContent=sub.required?'Obrigatória para este tipo; apenas vínculos da obra e fornecedor selecionados.':'Vínculo opcional; selecione primeiro obra, fornecedor e tipo.';}
 function render(){
  if(!state)return;const pending=client.pending();
  root.innerHTML=`${success?`<p role="status" data-success>${esc(success)}</p>`:''}${error?`<p role="alert" data-form-error>${esc(error)}</p>`:''}${!state.can_register?'<p role="status">Registo suspenso. As receções e os pedidos pendentes são conservados.</p>':''}${pending&&state.can_register?`<section><p role="alert">Resultado por confirmar. Não crie outro registo para a mesma receção.</p>${summary(pending.p_payload)}<button type="button" data-retry>REVER PEDIDO ORIGINAL</button></section>`:''}${state.can_register&&!pending?`<form><label>Obra<select name="obra_id" required><option value="">Selecione a obra…</option>${options(state.works)}</select></label><label>Fornecedor<select name="fornecedor_id" required><option value="">Selecione o fornecedor…</option>${options(state.suppliers)}</select></label><label>Tipo<select name="tipo" required><option value="">Selecione o tipo…</option><option value="material">Material</option><option value="estaleiro">Estaleiro</option><option value="subempreitada">Subempreitada</option></select></label><label>Subempreitada<select name="subempreitada_id"><option value="">Selecione um vínculo, se aplicável…</option>${state.subcontracts.map(s=>`<option value="${esc(s.id)}" data-work="${esc(s.obra_id)}" data-supplier="${esc(s.fornecedor_id)}">${esc(s.nome||'Subempreitada')}</option>`).join('')}</select><small data-subcontract-hint></small></label><label>Número do documento<input name="numero" maxlength="120" required></label><label>Data da fatura<input name="data_fatura" type="date" required></label><label>Total documental COM IVA<input name="bruto" inputmode="decimal" type="text" required></label><label>Líquido SEM IVA, se conhecido<input name="liquido" inputmode="decimal" type="text"></label><p>Valores sem separadores de milhares; vírgula ou ponto decimal, até duas casas. O líquido pode ficar em branco.</p><label>Motivo de exceção ADM, se houver duplicado<input name="excecao_duplicado" maxlength="1000"></label><p>Duplicados são verificados pelo servidor, incluindo o legado. A tabela abaixo não é uma lista completa.</p><button type="submit">REVER DADOS ANTES DE REGISTAR</button></form>`:''}${review?`<section data-review aria-label="Confirmação da receção"><h2>Confirme os dados antes de registar</h2>${summary(review.payload)}<p>Esta ação ${review.retry?'repete o mesmo pedido, sem criar outro':'cria uma receção administrativa'}. Não aprova faturas nem gera pagamentos ou custos.</p><button type="button" data-confirm>${review.retry?'CONFIRMAR PEDIDO ORIGINAL':'CONFIRMAR REGISTO DA RECEÇÃO'}</button><button type="button" data-cancel>VOLTAR SEM REGISTAR</button></section>`:''}<p>Estado: recebida, documento por confirmar. Esta entrega não disponibiliza anexos, correções, exclusão, aprovação ou encaminhamento.</p><div class="scroll"><table><caption>Últimas 200 receções da empresa</caption><thead><tr><th>Número</th><th>Obra</th><th>Fornecedor</th><th>Data</th><th>Total documental</th><th>Estado</th></tr></thead><tbody>${state.receipts.map(r=>`<tr><td>${esc(r.numero)}</td><td>${esc(state.works.find(w=>w.id===r.obra_id)?.nome||r.obra_id)}</td><td>${esc(state.suppliers.find(s=>s.id===r.fornecedor_id)?.nome||r.fornecedor_id)}</td><td>${esc(r.data_fatura)}</td><td>${esc(r.bruto)} €</td><td>Recebida · documento por confirmar</td></tr>`).join('')||'<tr><td colspan="6">Sem receções registadas.</td></tr>'}</tbody></table></div><button type="button" data-refresh>ATUALIZAR</button>`;
  const f=root.querySelector('form');if(f)for(const k of fields)f.elements[k].value=draft[k];root.querySelectorAll('input,select,button').forEach(e=>e.disabled=busy);filterSubcontracts();
 }
 function changed(){const f=root.querySelector('form');if(!f)return;filterSubcontracts();draft=readDraft(f);review=null;success='';root.querySelector('[data-success]')?.remove();root.querySelector('[data-review]')?.remove();root.querySelector('[data-form-error]')?.remove();}
 root.addEventListener('input',changed);root.addEventListener('change',changed);
 async function show(){const g=++generation,b=identity();review=null;state=null;root.textContent='A consultar receções…';try{const r=await rpc('fn_c1_recepcao_contexto',{});if(g!==generation||b!==identity())return;if(!r.ok)throw Error('Receção C1 indisponível neste perfil, sessão ou instalação.');const next=await r.json();if(g!==generation||b!==identity())return;if(next.scope!=='ADMINISTRATIVE_RECEPTION_ONLY'||!next.actor?.id||!next.actor?.empresa_id)throw Error('Contrato de receção inesperado.');state=next;scope=JSON.stringify([state.actor.id,state.actor.empresa_id]);render();}catch(e){if(g===generation)root.innerHTML=`<p role="alert">${esc(e.message)}</p>`;}}
 function prepare(payload,retry=false){review={payload:structuredClone(payload),retry,identity:identity(),scope,generation};error='';success='';render();root.querySelector('[data-review]')?.scrollIntoView?.({block:'nearest'});}
 function formError(e){error=e.message;review=null;render();const field=root.querySelector('form')?.elements[e.field];field?.setAttribute('aria-invalid','true');field?.focus();}
 root.addEventListener('submit',e=>{if(!e.target.matches('form'))return;e.preventDefault();if(busy||!state?.can_register||client.pending())return;draft=readDraft(e.target);try{prepare(validateReceptionPayload(draft,state));}catch(err){formError(err);}});
 async function confirm(){
  if(busy||!state?.can_register||!review)return;const choice=review;
  if(!choice.identity||choice.identity!==identity()||choice.scope!==scope||choice.generation!==generation){review=null;error='Sessão ou contexto alterado. Reveja os dados novamente.';render();return;}
  if(!choice.retry){try{const f=root.querySelector('form');if(!f)return;draft=readDraft(f);const p=validateReceptionPayload(draft,state);if(JSON.stringify(p)!==JSON.stringify(choice.payload)){review=null;error='Os dados mudaram. Reveja-os antes de confirmar.';render();return;}}catch(err){formError(err);return;}}
  busy=true;error='';review=null;render();const b=identity(),g=generation;
  try{await client.register(choice.payload,choice.retry);if(b!==identity()||g!==generation)return;draft=emptyDraft();success='Receção registada e confirmada pelo servidor. Não repita o registo do mesmo documento.';await show();}
  catch(e){if(b===identity()&&g===generation){error=e.message;render();}}
  finally{busy=false;if(b===identity()&&g===generation)render();else if(state&&b===identity())render();}
 }
 root.addEventListener('click',e=>{const button=e.target.closest('button');if(!button||busy)return;if(button.hasAttribute('data-confirm'))void confirm();if(button.hasAttribute('data-cancel')){review=null;render();}if(button.hasAttribute('data-retry')){const q=client.pending();if(q)prepare(q.p_payload,true);}if(button.hasAttribute('data-refresh'))void show();});
 return {show,reset(){generation++;state=null;scope='';busy=false;draft=emptyDraft();review=null;error='';success='';root.replaceChildren()}};
}

export async function boot(root){
 const cfg=window.PRIMELINE_CONFIG||{};let url;try{url=new URL(cfg.supabaseUrl);if(url.origin!=='https://znttyadndpkxuekhjamd.supabase.co'||url.pathname!=='/'||!cfg.supabaseAnonKey)throw Error();}catch{root.textContent='Configuração oficial indisponível. Nenhuma chamada efetuada.';return;}
 try {
  // Exact shared module URL used by the preserved production app.js.
  const auth=await import('../src/supabase-browser.js?v=hours-session-20261105');
  return startReception({root,auth,host:window});
 } catch {root.textContent='Não foi possível carregar a autenticação da plataforma. Recarregue esta página.';}
}

export function startReception({root,auth,host}){
 const missing='Sessão ausente ou encerrada. Abra a plataforma nesta mesma aba, inicie sessão e regresse à Recepção C1 nesta aba.';
 let stopped=false,checking=null,timer=null;
 const identity=()=>auth.getSession()?.user?.id||'';
 let view;
 function notice(message){view?.reset();root.replaceChildren();const p=root.ownerDocument.createElement('p');p.setAttribute('role','alert');p.textContent=message;const a=root.ownerDocument.createElement('a');a.href='/';a.target='_self';a.textContent='Abrir a plataforma nesta aba';root.append(p,a);}
 function session(){const s=auth.getSession();if(!s?.access_token||!s.user?.id)throw Error(missing);return s;}
 const rpc=async(name,payload)=>{
  session();
  const r=await auth.supabase('rpc/'+name,{method:'POST',body:JSON.stringify(payload),cache:'no-store',redirect:'error'});
  if(!r.ok){
   const detail=await r.clone().json().catch(()=>({}));
   if(detail.message==='C1R_SESSION_UNAVAILABLE'){notice('Sessão não autorizada ou expirada. Regresse à plataforma nesta aba.');throw Error('Sessão não autorizada.');}
   if(detail.message==='C1R_ADM_REQUIRED')throw Error('Sessão reconhecida. A Recepção C1 exige perfil Administrativo.');
   if(r.status===403&&detail.code==='42501')throw Error('Sessão reconhecida. A RPC da Recepção C1 não está ativada ou não tem autorização de execução.');
   if(r.status===401){notice(missing);throw Error(missing);}
   if(r.status===404)throw Error('Sessão reconhecida. Serviço de Recepção C1 indisponível nesta instalação.');
  }
  return r;
 };
 view=createReceptionView({root,rpc,identity,store:host.sessionStorage});
 function invalidate(){notice(missing);}
 auth.onSessionReset(invalidate);
 async function check(){
  if(stopped||host.document.visibilityState==='hidden')return;
  if(checking)return checking;
  checking=(async()=>{
   try{
    const s=session();
    if(Number(s.expires_at)>0&&Number(s.expires_at)*1000<=Date.now()){
     notice('Sessão expirada. A renovar pela autenticação da plataforma…');
     await auth.refreshSession();session();
    }
    if(!stopped&&host.document.visibilityState!=='hidden')await view.show();
   }catch{if(!stopped)notice(missing);}
  })();
  try{await checking;}finally{checking=null;}
 }
 function hide(){view.reset();root.replaceChildren();}
 function visibility(){if(host.document.visibilityState==='hidden')hide();else void check();}
 function tick(){
  if(stopped)return;
  try{const s=auth.getSession();if(!s?.access_token||!s.user?.id)invalidate();else if(Number(s.expires_at)>0&&Number(s.expires_at)*1000<=Date.now()){hide();void check();}}catch{invalidate();}
  timer=host.setTimeout(tick,1000);
 }
 host.addEventListener('pagehide',hide);
 host.addEventListener('pageshow',check);
 host.addEventListener('focus',check);
 host.document.addEventListener('visibilitychange',visibility);
 host.addEventListener('primeline:session-expired',invalidate);
 tick();
 const ready=check();
 return {ready,check,dispose(){stopped=true;host.clearTimeout(timer);host.removeEventListener('pagehide',hide);host.removeEventListener('pageshow',check);host.removeEventListener('focus',check);host.removeEventListener('primeline:session-expired',invalidate);host.document.removeEventListener('visibilitychange',visibility);view.reset();root.replaceChildren();}};
}
