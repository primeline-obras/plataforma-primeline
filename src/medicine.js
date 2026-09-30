const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const medicineToday = () => new Intl.DateTimeFormat('en-CA', {timeZone:'Europe/Lisbon',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export function medicineStatus(current, today = medicineToday()) {
  if (!current) return {state:'missing', label:'Sem consulta realizada'};
  if (!current.data_proxima_consulta) return {state:'missing', label:'Sem próxima consulta'};
  const days = Math.round((Date.parse(current.data_proxima_consulta) - Date.parse(today)) / 86400000);
  return days < 0 ? {state:'expired',label:'Vencida'} : days <= 30 ? {state:'warning',label:'A vencer'} : {state:'valid',label:'Válida'};
}
export function medicineOperation(action, personId, consultation, fields, requestId, today = medicineToday()) {
  if (!['registar','corrigir','anular'].includes(action)) throw new Error('Operação inválida.');
  const payload = {p_version:1};
  if (action === 'registar') payload.p_colaborador_id = personId;
  else {
    if (!consultation?.id || !Number.isInteger(consultation.revisao) || consultation.anulado_em) throw new Error('Recarregue a consulta antes de a alterar.');
    if (!fields.motivo?.trim()) throw new Error('Indique o motivo da correção/anulação.');
    Object.assign(payload, {p_consulta_id:consultation.id,p_revisao_esperada:consultation.revisao,p_motivo:fields.motivo.trim()});
  }
  if (action !== 'anular') {
    const date = fields.data_consulta;
    const next = fields.proxima_consulta || null;
    const validDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0,10) === value;
    if (!validDate(date) || date > today) throw new Error('Indique uma consulta realizada, sem data futura.');
    if (next && (!validDate(next) || next < date)) throw new Error('A próxima consulta não pode ser anterior à realizada.');
    Object.assign(payload, {p_data_consulta:date,p_resultado:fields.resultado?.trim() || null,p_proxima_consulta:next});
  }
  payload.p_request_id = requestId;
  return {name:`fn_medicina_${action === 'registar' ? 'registar' : action === 'corrigir' ? 'corrigir' : 'anular'}_consulta`,payload,personId};
}
export function createMedicineClient(api) {
  async function call(name, payload) {
    let response, data;
    try { response = await api(`rpc/${name}`, {method:'POST',body:JSON.stringify(payload)}); data = await response.json(); }
    catch { throw Object.assign(new Error('Não foi possível confirmar a operação. Repita o mesmo pedido ou recarregue para verificar.'), {uncertain:true}); }
    if (!response.ok) {
      const stale = data?.code === '40001' || /STALE_REVISION/.test(data?.message || '');
      const unavailable = response.status === 404 || data?.code === 'PGRST202';
      throw Object.assign(new Error(stale ? 'A consulta mudou entretanto. Dados recarregados; reveja antes de voltar a alterar.' : unavailable ? 'Medicina indisponível. A RPC necessária não está disponível.' : data?.message || 'Sem acesso à operação de Medicina.'), {stale,uncertain:response.status >= 500});
    }
    return data;
  }
  return {
    async consult(personId) {
      const data = await call('fn_medicina_consultar_colaborador', {p_version:1,p_colaborador_id:personId});
      if (data?.version !== 1 || typeof data.can_write !== 'boolean' || !Object.hasOwn(data,'atual') || (data.atual && data.atual.colaborador_id !== personId) || (data.can_write && (!Array.isArray(data.consultas) || !Array.isArray(data.historico)))) throw new Error('Resposta de Medicina inválida. Recarregue os dados.');
      return data;
    },
    async save(operation) {
      const data = await call(operation.name, operation.payload);
      const c = data?.consulta;
      if (data?.version !== 1 || data.committed !== true || !c?.id || c.colaborador_id !== operation.personId || (operation.payload.p_consulta_id && c.id !== operation.payload.p_consulta_id)) throw Object.assign(new Error('Gravação não confirmada. Repita o mesmo pedido ou recarregue para verificar.'), {uncertain:true});
      return data;
    },
    async list(people) {
      const rows = new Array(people.length); let next = 0;
      await Promise.all(Array.from({length:Math.min(4, people.length)}, async () => {
        while (next < people.length) {
          const index = next++, person = people[index];
          try { const data = await this.consult(person.id); rows[index] = {...data.atual,colaborador_id:person.id,current:data.atual,can_write:data.can_write}; }
          catch (error) { rows[index] = {colaborador_id:person.id,current:null,error:error.message}; }
        }
      }));
      return rows;
    }
  };
}

// The backend selects the current consultation. No frontend sorting can replace it.
export function mountMedicine({root,person,client,canManage,onChanged=async()=>{},documents=async()=>[],download=async()=>{}}) {
  let data = null, busy = false, unresolved = false, generation = 0, docs = [], documentError = '';
  const format = value => value ? value.split('-').reverse().join('/') : '—';
  const docButtons = items => items.map(doc => `<button type="button" class="outline-action" data-med-document="${esc(doc.id)}">${esc(doc.nome_arquivo || 'Documento')}</button>`).join('');
  const writable = () => canManage() && data?.can_write === true;
  function render(message = '') {
    const current = data.atual, status = medicineStatus(current);
    root.innerHTML = `<section class="medicine-card"><h3>MEDICINA DO TRABALHO</h3>${person.data_saida ? '<p class="medicine-notice">COLABORADOR INATIVO · histórico preservado</p>' : ''}
      <p data-med-message role="status">${esc(message)}</p><div class="medicine-summary">
      <div><span>ÚLTIMA CONSULTA ATUAL</span><strong>${format(current?.data_ultima_consulta)}</strong></div>
      <div><span>RESULTADO / APTIDÃO</span><strong>${esc(current?.resultado || 'Não indicado')}</strong></div>
      <div><span>PRÓXIMA CONSULTA</span><strong>${format(current?.data_proxima_consulta)}</strong></div>
      <strong class="medicine-state ${status.state}">${status.label}</strong></div>
      <div class="medicine-actions">${writable() ? '<button type="button" class="primary-button" data-med-new>REGISTAR NOVA CONSULTA</button>' : '<span>SOMENTE LEITURA</span>'}<button type="button" class="outline-action" data-med-reload>RECARREGAR</button></div>
      <div data-med-editor></div><h4>HISTÓRICO DE CONSULTAS</h4>
      <div class="medicine-history">${Array.isArray(data.consultas) ? data.consultas.length ? data.consultas.map(c => `<article data-med-consultation="${esc(c.id)}" class="${c.anulado_em ? 'medicine-cancelled' : ''}"><div><strong>${format(c.data_ultima_consulta)}${c.id === current?.id ? ' · ATUAL' : ''}${c.anulado_em ? ' · ANULADA' : ''}</strong><p>${esc(c.resultado || 'Resultado não indicado')}</p><span>Próxima: ${format(c.data_proxima_consulta)}</span></div>${writable() && !c.anulado_em ? `<div class="medicine-actions"><button type="button" class="outline-action" data-med-correct="${esc(c.id)}">CORRIGIR CONSULTA</button><button type="button" class="outline-action" data-med-cancel="${esc(c.id)}">ANULAR REGISTO</button></div>` : ''}</article>`).join('') : '<p>Sem consultas registadas.</p>' : '<p>O seu perfil permite consultar apenas a consulta atual.</p>'}</div>
      ${Array.isArray(data.historico) && data.historico.length ? `<details><summary>Histórico de operações</summary>${data.historico.map(h=>`<p>${esc(h.operacao)} · ${esc(h.criado_em)}${h.motivo ? ` · ${esc(h.motivo)}` : ''}</p>`).join('')}</details>` : ''}
      ${canManage() ? `<h4>FICHAS DE APTIDÃO</h4><div class="medicine-documents">${docButtons(docs.filter(d=>d.tipo_documento==='ficha_aptidao')) || '<p>Sem ficha de aptidão associada ao colaborador.</p>'}</div><details><summary>DOCUMENTOS DO COLABORADOR (${docs.length})</summary><div class="medicine-documents">${docButtons(docs) || '<p>Sem documentos associados.</p>'}</div></details><p role="status">${esc(documentError)}</p>` : ''}</section>`;
    root.querySelector('[data-med-new]')?.addEventListener('click',()=>edit('registar'));
    root.querySelector('[data-med-reload]').onclick=()=>load();
    root.querySelectorAll('[data-med-correct]').forEach(b=>b.onclick=()=>edit('corrigir',b.dataset.medCorrect));
    root.querySelectorAll('[data-med-cancel]').forEach(b=>b.onclick=()=>edit('anular',b.dataset.medCancel));
    root.querySelectorAll('[data-med-document]').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await download(docs.find(d=>d.id===b.dataset.medDocument));}catch(e){root.querySelector('[data-med-message]').textContent=e.message;}finally{b.disabled=false;}});
  }
  async function load(message = '') {
    unresolved = false;
    const ticket = ++generation;
    root.innerHTML = '<section class="medicine-card"><h3>MEDICINA DO TRABALHO</h3><p role="status">A carregar…</p></section>';
    try {
      const result = await client.consult(person.id);
      if (ticket !== generation || !root.isConnected) return;
      data = result;
      try { docs = canManage() ? await documents(person.id) : []; documentError = ''; }
      catch { docs=[]; documentError='Não foi possível carregar os documentos. Recarregue para tentar novamente.'; }
      if (ticket === generation && root.isConnected) render(message);
    } catch (e) {
      if (ticket !== generation || !root.isConnected) return;
      data=null;root.innerHTML=`<section class="medicine-card"><h3>MEDICINA DO TRABALHO</h3><p role="alert">${esc(e.message)}</p><button type="button" data-med-reload>RECARREGAR</button></section>`;
      root.querySelector('button').onclick=()=>load();
    }
  }
  function edit(action, id) {
    if (!writable() || busy) return;
    const consultation=data.consultas?.find(c=>c.id===id);
    const host=root.querySelector('[data-med-editor]');
    host.innerHTML=`<form class="medicine-form"><h4>${action==='registar'?'REGISTAR NOVA CONSULTA':action==='corrigir'?'CORRIGIR CONSULTA':'ANULAR REGISTO'}</h4>
      ${action!=='anular'?`<div class="medicine-summary"><label>Data da consulta<input type="date" name="data_consulta" required max="${medicineToday()}" value="${esc(consultation?.data_ultima_consulta || '')}"></label><label>Resultado / aptidão<input name="resultado" value="${esc(consultation?.resultado || '')}"></label><label>Próxima consulta<input type="date" name="proxima_consulta" value="${esc(consultation?.data_proxima_consulta || '')}"></label></div><p>Registe apenas o resultado ocupacional. Não introduza dados clínicos.</p>`:''}
      ${action!=='registar'?'<label>Motivo obrigatório<input name="motivo" required></label>':''}
      <p class="form-error" role="alert"></p><div class="medicine-actions"><button type="submit" class="primary-button">CONFIRMAR</button><button type="button" class="outline-action" data-med-close>FECHAR E RECARREGAR</button></div></form>`;
    const form=host.querySelector('form'); let pending=null;
    form.querySelector('[data-med-close]').onclick=()=>load();
    form.onsubmit=async event=>{
      event.preventDefault();event.stopPropagation();if(busy || !writable())return;
      const error=form.querySelector('.form-error');error.textContent='';
      try {
        pending ||= medicineOperation(action,person.id,consultation,Object.fromEntries(new FormData(form)),crypto.randomUUID());
        busy=true;root.querySelectorAll('button').forEach(b=>b.disabled=true);
        await client.save(pending);pending=null;
        await load('Operação confirmada. Histórico atualizado.');
        try {await onChanged();} catch {root.querySelector('[data-med-message]').textContent='Operação confirmada. O painel global não atualizou; recarregue-o.';}
      } catch(e) {
        if(e.stale){pending=null;await load(e.message);try{await onChanged();}catch{}}
        else {error.textContent=e.message;unresolved=!!e.uncertain;if(!e.uncertain)pending=null;form.querySelectorAll('input').forEach(input=>input.disabled=!!e.uncertain);}
      } finally {busy=false;root.querySelectorAll('button').forEach(b=>b.disabled=unresolved && !b.matches('[type="submit"],[data-med-close]'));}
    };
    form.querySelector('input')?.focus();
  }
  return {ready:load(),reload:load};
}
