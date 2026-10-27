const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));

export async function saveVehicleAssignment(api, payload) {
  let response;
  try { response = await api('rpc/fn_alterar_responsavel_viatura', {method:'POST', body:JSON.stringify(payload)}); }
  catch { throw new Error('Não foi possível confirmar a gravação. Pode repetir o mesmo pedido.'); }
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    const stale = result?.code === '40001' && String(result?.message).includes('STALE_REVISION');
    const error = new Error(stale ? 'A atribuição desta viatura foi alterada por outro utilizador. Reveja antes de confirmar novamente.'
      : [401,403].includes(response.status) || result?.code === '42501' ? 'Não tem permissão para alterar o responsável.'
      : result?.code === '22023' ? 'Não foi possível validar a alteração. Reveja o responsável e o motivo.'
      : 'Não foi possível guardar a atribuição.');
    error.stale = stale;
    throw error;
  }
  if (result?.version !== 1 || result.committed !== true || result.viatura_id !== payload.p_viatura_id) throw new Error('O serviço não confirmou a alteração. Pode repetir o mesmo pedido.');
  return result;
}

export function createVehicleAssignment({api, supabase, canManage, refreshVehicle, render, toast}) {
  const people = new Map();
  const histories = new Map();
  let generation = 0;
  const name = (id, historical = false) => id == null ? 'Sem atribuição' : people.get(id)?.nome || (historical ? 'Colaborador indisponível' : 'Responsável indisponível');
  const current = item => `${name(item.colaborador_atribuido_id)}${people.get(item.colaborador_atribuido_id)?.data_saida ? ' · INATIVO' : ''}`;
  async function names(ids) {
    const unique = [...new Set(ids.filter(Boolean))];
    unique.forEach(id => people.delete(id));
    if (!unique.length) return;
    const rows = await api(`colaboradores?select=id,nome,empresa_id,data_saida&id=in.(${unique.map(encodeURIComponent).join(',')})`, {includeInactiveCollaborators:true});
    rows.forEach(row => people.set(row.id,row));
  }
  async function loadCurrent(vehicles) {
    await names(vehicles.map(v => v.colaborador_atribuido_id)).catch(() => {});
  }
  async function loadHistory(item) {
    if (!item || !canManage()) return;
    const token = ++generation;
    histories.set(item.id,{loading:true});
    try {
      const rows = await api(`viaturas_atribuicoes_historico?select=*,autor:utilizadores!alterado_por(nome)&viatura_id=eq.${encodeURIComponent(item.id)}&order=alterado_em.desc,id.desc`);
      await names([item.colaborador_atribuido_id,...rows.flatMap(r => [r.colaborador_anterior_id,r.colaborador_novo_id])]).catch(() => {});
      if (token === generation) histories.set(item.id,{rows});
      return true;
    } catch { if (token === generation) histories.set(item.id,{error:true}); return false; }
  }
  function history(item) {
    if (!canManage()) return '';
    const data = histories.get(item.id);
    const date = value => new Intl.DateTimeFormat('pt-PT',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}).format(new Date(value));
    return `<section class="fleet-section fleet-assignment-history"><header><h3>HISTÓRICO DE ATRIBUIÇÕES</h3></header><div class="fleet-timeline">${!data || data.loading ? '<p>A carregar histórico…</p>' : data.error ? '<p role="alert">Não foi possível carregar o histórico de atribuições.</p>' : !data.rows.length ? '<p>Sem alterações de responsável registadas.</p>' : data.rows.map(row => `<article><time>${esc(date(row.alterado_em))}</time><i></i><div><strong>${esc(name(row.colaborador_anterior_id,true))} → ${esc(name(row.colaborador_novo_id,true))}</strong><p>Por: ${esc(row.autor?.nome || 'Utilizador indisponível')}</p>${row.motivo ? `<p>Motivo: ${esc(row.motivo)}</p>` : ''}</div></article>`).join('')}</div></section>`;
  }
  async function open(item) {
    if (!item || !canManage()) return;
    let snapshot = {...item}, candidates = [], ready = false, busy = false, intent = null, confirmed = false;
    const dialog = document.createElement('dialog');
    dialog.className = 'fleet-validity-dialog fleet-assignment-dialog';
    dialog.setAttribute('aria-label','Alterar responsável');
    dialog.innerHTML = `<header class="panel-title"><span>ALTERAR RESPONSÁVEL</span><button type="button" data-close aria-label="Fechar">×</button></header><form><p>Responsável atual: <strong data-current></strong></p><label>NOVO RESPONSÁVEL<select name="responsavel" disabled><option value="">Sem atribuição</option></select></label><label>MOTIVO (OPCIONAL)<textarea name="motivo" rows="3"></textarea></label><p class="form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="outline-action" data-close>CANCELAR</button><button class="primary-button" type="submit" disabled>CONFIRMAR</button></div></form>`;
    document.body.append(dialog);
    const form = dialog.querySelector('form'), select = form.elements.responsavel, error = form.querySelector('.form-error'), submit = form.querySelector('[type=submit]');
    const showCurrent = () => { dialog.querySelector('[data-current]').textContent = current(snapshot); };
    const controls = () => { dialog.querySelectorAll('button,input,select,textarea').forEach(c => {c.disabled=busy;}); select.disabled=busy||!ready||confirmed; submit.disabled=busy||!ready; submit.textContent=busy?'A guardar…':confirmed?'RECARREGAR FICHA':'CONFIRMAR'; };
    const close = () => {if(!busy){dialog.close();dialog.remove();}};
    dialog.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',close));
    dialog.addEventListener('cancel',e=>{e.preventDefault();close();});
    form.addEventListener('input',()=>{intent=null;});
    select.addEventListener('change',()=>{intent=null;});
    async function reload() {
      snapshot = {...await refreshVehicle(snapshot.id)};
      await loadCurrent([snapshot]);
      const historyLoaded = await loadHistory(snapshot);
      showCurrent(); render();
      if (!historyLoaded) throw new Error('Histórico indisponível.');
    }
    form.addEventListener('submit',async event=>{
      event.preventDefault(); if(busy||!ready||!canManage())return;
      error.textContent='';
      try {
        if(!confirmed){
          const target=select.value||null, motivo=form.elements.motivo.value.trim()||null;
          if(target===snapshot.colaborador_atribuido_id)throw new Error('Escolha um responsável diferente do atual.');
          if(target && !candidates.some(c=>c.id===target&&c.empresa_id===snapshot.empresa_id&&c.data_saida===null))throw new Error('Escolha um colaborador ativo da empresa da viatura.');
          if(!Number.isInteger(snapshot.atribuicao_revisao)||snapshot.atribuicao_revisao<0)throw new Error('Revisão indisponível. Reabra a ficha antes de confirmar.');
          if(!intent)intent={p_version:1,p_viatura_id:snapshot.id,p_novo_colaborador_id:target,p_revisao_esperada:snapshot.atribuicao_revisao,p_request_id:crypto.randomUUID(),p_motivo:motivo};
          busy=true;controls(); await saveVehicleAssignment(supabase,intent); confirmed=true;
        }
        busy=true;controls(); await reload(); busy=false;close();toast('Responsável atualizado.');
      } catch(e){
        error.textContent=e.message;
        if(e.stale){ready=false;intent=null;try{await reload();ready=true;}catch{error.textContent+=' Não foi possível recarregar a viatura. Reabra a ficha.';}}
        else if(confirmed)error.textContent='Alteração guardada; não foi possível recarregar a ficha. Use RECARREGAR FICHA.';
      } finally {busy=false;controls();}
    });
    showCurrent();dialog.showModal();
    try {
      snapshot={...await refreshVehicle(item.id)};
      if(!snapshot.empresa_id)throw new Error('Empresa da viatura indisponível.');
      const [rows]=await Promise.all([api(`colaboradores?select=id,nome,empresa_id,data_saida&empresa_id=eq.${encodeURIComponent(snapshot.empresa_id)}&data_saida=is.null&order=nome`),loadCurrent([snapshot])]);
      candidates=rows.filter(c=>c.empresa_id===snapshot.empresa_id&&c.data_saida===null);
      select.innerHTML='<option value="">Sem atribuição</option>'+candidates.map(c=>`<option value="${esc(c.id)}">${esc(c.nome)}</option>`).join('');
      select.value=candidates.some(c=>c.id===snapshot.colaborador_atribuido_id)?snapshot.colaborador_atribuido_id:'';
      ready=true;showCurrent();render();
    }catch{error.textContent='Não foi possível carregar os responsáveis disponíveis. Feche e tente novamente.';}
    controls();
  }
  return {current,loadCurrent,loadHistory,history,open};
}
