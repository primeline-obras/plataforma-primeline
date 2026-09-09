const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[c]);
const num = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const nullableNumber = value => value === "" || value == null ? null : num(value);

export function calculateBestPrices(items, proposals, prices) {
  const winners = items.map(item => {
    const quoted = prices.filter(row => row.item_id === item.id && row.preco_total != null);
    if (!quoted.length) return { item_id: item.id, proposta_id: null, melhor_preco: null };
    const winner = quoted.reduce((best, row) => num(row.preco_total) < num(best.preco_total) ? row : best);
    return { item_id: item.id, proposta_id: winner.proposta_id, melhor_preco: num(winner.preco_total) };
  });
  return { winners, soma_dos_menores: winners.reduce((sum, row) => sum + num(row.melhor_preco), 0), itens_sem_cotacao: winners.filter(row => row.proposta_id == null).length };
}

export function calculateCosting({ melhor_preco, custo_estimado, valor_adjudicado, preco_venda }) {
  const negotiation = valor_adjudicado == null ? null : num(valor_adjudicado) - num(melhor_preco);
  const budgetDeviation = valor_adjudicado == null || custo_estimado == null ? null : num(valor_adjudicado) - num(custo_estimado);
  const budgetPct = budgetDeviation == null || !num(custo_estimado) ? null : budgetDeviation / num(custo_estimado) * 100;
  const margin = preco_venda == null || valor_adjudicado == null ? null : num(preco_venda) - num(valor_adjudicado);
  const marginPct = margin == null || !num(preco_venda) ? null : margin / num(preco_venda) * 100;
  return { negotiation, budgetDeviation, budgetPct, margin, marginPct };
}

export function createComparativeMapModule({ host, supabase, isConfigured, getSuppliers, getPhases, euro, toast, onAdjudicated }) {
  const state = { work: null, maps: [], proposals: [], items: [], prices: [], adjustments: [], canEdit: false, expanded: "", newOpen: false, loading: false, editingItemId: "", editingProposalId: "", pendingDelete: "" };
  const root = () => host.querySelector("[data-comparative-map-root]");
  const supplierName = id => getSuppliers().find(row => row.id === id)?.nome || "Fornecedor";
  const proposalsFor = id => state.proposals.filter(row => row.mapa_id === id);
  const itemsFor = id => state.items.filter(row => row.mapa_id === id).sort((a, b) => String(a.numero).localeCompare(String(b.numero), "pt", { numeric: true }));
  const pricesFor = itemId => state.prices.filter(row => row.item_id === itemId);
  const adjustmentsFor = id => state.adjustments.filter(row => row.mapa_id === id);
  const priceFor = (itemId, proposalId) => state.prices.find(row => row.item_id === itemId && row.proposta_id === proposalId);
  const bestFor = item => {
    const quoted = pricesFor(item.id).filter(row => row.preco_unitario != null);
    return quoted.length ? quoted.reduce((best, row) => num(row.preco_total) < num(best.preco_total) ? row : best) : null;
  };
  const bestSum = mapId => itemsFor(mapId).reduce((sum, item) => sum + num(bestFor(item)?.preco_total), 0);
  const money = value => value == null ? "—" : euro.format(num(value));
  const percent = value => value == null ? "—" : `${num(value).toFixed(1)}%`;

  async function api(path, options = {}, label = "Não foi possível concluir a operação") {
    const response = await supabase(path, options);
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw new Error(detail.message || detail.details || label);
    }
    return response.status === 204 ? null : response.json();
  }

  const supplierOptions = selected => getSuppliers().map(row => `<option value="${row.id}" ${row.id === selected ? "selected" : ""}>${esc(row.nome)}</option>`).join("");
  const phaseOptions = () => (getPhases() || []).map(row => `<option value="${row.id}">${esc(row.codigo || "")} · ${esc(row.descricao || "Fase")}</option>`).join("");

  function renderNewMap() {
    if (!state.canEdit) return "";
    return `<div class="comparison-new-wrap"><button class="outline-action" type="button" data-toggle-new-map>${state.newOpen ? "FECHAR" : "＋ NOVO MAPA COMPARATIVO"}</button>
      ${state.newOpen ? `<form class="comparison-new-form" data-new-map><label>ESPECIALIDADE<input name="especialidade" required></label><label>DESCRIÇÃO<input name="descricao"></label><label>CUSTO ESTIMADO (€)<input name="custo_estimado" type="number" min="0" step="0.01"></label><label>PREÇO DE VENDA (€)<input name="preco_venda" type="number" min="0" step="0.01"></label><button class="primary-button" type="submit">CRIAR MAPA</button><p class="form-error"></p></form>` : ""}</div>`;
  }

  function deleteActions(type, id) {
    const key = `${type}:${id}`;
    if (state.pendingDelete !== key) return `<button class="comparison-delete-button" type="button" data-request-delete-${type}="${id}">ELIMINAR</button>`;
    return `<span class="comparison-delete-confirm"><b>CONFIRMAR?</b><button type="button" data-cancel-delete>CANCELAR</button><button class="comparison-delete-button" type="button" data-confirm-delete-${type}="${id}">SIM, ELIMINAR</button></span>`;
  }

  function renderProposalInfo(map, proposal) {
    const editing = state.editingProposalId === proposal.id;
    if (!editing) return `<article class="comparison-commercial-card"><header><strong>${esc(supplierName(proposal.fornecedor_id))}</strong>${state.canEdit ? `<span class="comparison-row-actions"><button type="button" data-edit-proposal="${proposal.id}">EDITAR</button>${deleteActions("proposal", proposal.id)}</span>` : ""}</header><div class="comparison-proposal-summary"><span>PROPOSTA <strong>${esc(proposal.data_proposta || "—")}</strong></span><span>VALIDADE <strong>${esc(proposal.prazo_validade || "—")}</strong></span><span>CONTACTO <strong>${esc(proposal.contacto || proposal.telemovel || "—")}</strong></span><span>CONDIÇÕES <strong>${esc(proposal.condicoes_pagamento || "—")}</strong></span></div></article>`;
    return `<form class="comparison-commercial-card editing" data-proposal-info="${proposal.id}"><header><strong>EDITAR PROPOSTA · ${esc(supplierName(proposal.fornecedor_id))}</strong><button type="button" data-cancel-edit-proposal>CANCELAR</button></header><div class="comparison-commercial-grid">
      <label>FORNECEDOR<select name="fornecedor_id" required>${supplierOptions(proposal.fornecedor_id)}</select></label><label>DATA DA PROPOSTA<input type="date" name="data_proposta" value="${esc(proposal.data_proposta || "")}"></label><label>VALIDADE<input type="date" name="prazo_validade" value="${esc(proposal.prazo_validade || "")}"></label>
      <label>CONTACTO<input name="contacto" value="${esc(proposal.contacto || "")}"></label><label>TELEMÓVEL<input name="telemovel" value="${esc(proposal.telemovel || "")}"></label>
      <label>CONDIÇÕES DE PAGAMENTO<textarea name="condicoes_pagamento">${esc(proposal.condicoes_pagamento || "")}</textarea></label><label>EXCLUSÕES / ÂMBITO<textarea name="exclusoes_ambito">${esc(proposal.exclusoes_ambito || "")}</textarea></label>
      <label>OUTRAS INFORMAÇÕES<textarea name="outras_informacoes">${esc(proposal.outras_informacoes || "")}</textarea></label><label class="primeline-note">NOTA PRIMELINE<textarea name="nota_primeline">${esc(proposal.nota_primeline || "")}</textarea></label>
    </div><div class="comparison-edit-actions"><button type="button" data-cancel-edit-proposal>CANCELAR</button><button class="secondary-button" type="submit">GUARDAR ALTERAÇÕES</button></div><p class="form-error"></p></form>`;
  }

  function renderGrid(map) {
    const proposals = proposalsFor(map.id);
    const items = itemsFor(map.id);
    if (!proposals.length || !items.length) return `<div class="procurement-empty">ADICIONE ITENS E PROPOSTAS PARA COMEÇAR A COMPARAÇÃO.</div>`;
    return `<div class="comparison-table-wrap"><table class="comparison-table"><thead><tr><th>Nº</th><th>DESIGNAÇÃO / DESCRITIVO</th><th>UNID.</th><th>QUANT.</th>${proposals.map(p => `<th><span>${esc(supplierName(p.fornecedor_id))}</span><small>UNITÁRIO / TOTAL</small></th>`).join("")}<th>MELHOR PREÇO</th><th>AÇÕES</th></tr></thead><tbody>
      ${items.map(item => { const best = bestFor(item); const editing = state.editingItemId === item.id; return `<tr class="${editing ? "comparison-item-editing" : ""}"><td>${editing ? `<input data-item-field="numero" value="${esc(item.numero)}" required>` : esc(item.numero)}</td><td>${editing ? `<input data-item-field="designacao" value="${esc(item.designacao)}" required>` : `<strong>${esc(item.designacao)}</strong>`}</td><td>${editing ? `<input data-item-field="unidade" value="${esc(item.unidade)}" required>` : esc(item.unidade)}</td><td>${editing ? `<input data-item-field="quantidade" type="number" min="0.0001" step="0.0001" value="${num(item.quantidade)}" required>` : num(item.quantidade)}</td>${proposals.map(proposal => { const price = priceFor(item.id, proposal.id); return `<td><form data-save-price data-item="${item.id}" data-proposal="${proposal.id}"><input aria-label="Preço unitário ${esc(supplierName(proposal.fornecedor_id))}" name="preco_unitario" type="number" min="0" step="0.0001" value="${price?.preco_unitario ?? ""}" placeholder="Sem cotação" ${state.canEdit && !editing ? "" : "disabled"}><output>${price ? money(price.preco_total) : "—"}</output><input name="observacoes" value="${esc(price?.observacoes || "")}" placeholder="Inclui / exclui" ${state.canEdit && !editing ? "" : "disabled"}>${state.canEdit && !editing ? '<button type="submit">GUARDAR</button>' : ""}</form></td>`; }).join("")}<td class="comparison-best"><strong>${best ? esc(supplierName(proposals.find(p => p.id === best.proposta_id)?.fornecedor_id)) : "SEM COTAÇÃO"}</strong><span>${best ? money(best.preco_total) : "—"}</span></td><td class="comparison-item-actions">${state.canEdit ? editing ? `<button type="button" data-save-item="${item.id}">GUARDAR</button><button type="button" data-cancel-edit-item>CANCELAR</button>` : `<button type="button" data-edit-item="${item.id}">EDITAR</button>${deleteActions("item", item.id)}` : "—"}</td></tr>`; }).join("")}
      <tr class="comparison-total"><td colspan="4">TOTAL POR PROPOSTA</td>${proposals.map(p => `<td>${money(pricesForProposal(p.id).reduce((sum,row) => sum+num(row.preco_total),0))}</td>`).join("")}<td><small>SOMA DOS MENORES</small><strong>${money(bestSum(map.id))}</strong></td><td></td></tr>
    </tbody></table></div>`;
  }

  const pricesForProposal = id => state.prices.filter(row => row.proposta_id === id);

  function renderCosting(map) {
    const best = bestSum(map.id);
    const { negotiation, budgetDeviation, budgetPct, margin, marginPct } = calculateCosting({ melhor_preco: best, custo_estimado: map.custo_estimado_orcamento, valor_adjudicado: map.valor_adjudicado_real, preco_venda: map.preco_venda });
    return `<section class="comparison-costing"><header>CUSTEIO E MARGEM</header><form data-save-costing="${map.id}"><label>CUSTO ESTIMADO · ORÇAMENTO<input name="custo_estimado_orcamento" type="number" min="0" step="0.01" value="${map.custo_estimado_orcamento ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div><span>MELHOR PREÇO NO COMPARATIVO</span><strong>${money(best)}</strong></div><label>VALOR ADJUDICADO REAL<input name="valor_adjudicado_real" type="number" min="0" step="0.01" value="${map.valor_adjudicado_real ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div><span>DIFERENÇA DA NEGOCIAÇÃO</span><strong>${money(negotiation)}</strong></div><div><span>DESVIO FACE AO ORÇAMENTO</span><strong>${money(budgetDeviation)} · ${percent(budgetPct)}</strong></div><label>PREÇO DE VENDA<input name="preco_venda" type="number" min="0" step="0.01" value="${map.preco_venda ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div class="comparison-margin"><span>MARGEM REAL</span><strong>${money(margin)} · ${percent(marginPct)}</strong><small>Calculada exclusivamente sobre o Valor Adjudicado Real.</small></div>${state.canEdit ? '<button class="secondary-button" type="submit">GUARDAR CUSTEIO</button>' : ""}<p class="form-error"></p></form></section>`;
  }

  function renderAdjustments(map) {
    const proposals = proposalsFor(map.id);
    return `<section class="comparison-adjustments"><header><strong>AJUSTES DE ESCOPO / LEITURA TÉCNICA</strong><span>Registe diferenças de âmbito sem alterar os preços apresentados.</span></header>${adjustmentsFor(map.id).map(row => `<article><b>${esc(supplierName(proposals.find(p => p.id === row.proposta_id)?.fornecedor_id))}</b><span>${esc(row.justificacao)}</span><strong>${money(row.valor_ajustado)}</strong></article>`).join("") || '<p class="procurement-empty">SEM AJUSTES</p>'}${state.canEdit && proposals.length ? `<form data-add-adjustment="${map.id}"><select name="proposta_id" required>${proposals.map(p => `<option value="${p.id}">${esc(supplierName(p.fornecedor_id))}</option>`).join("")}</select><input name="valor_ajustado" type="number" step="0.01" required placeholder="Valor ajustado"><input name="justificacao" required placeholder="Justificação técnica"><button type="submit">ADICIONAR AJUSTE</button><p class="form-error"></p></form>` : ""}</section>`;
  }

  function renderMap(map) {
    const expanded = state.expanded === map.id;
    const proposals = proposalsFor(map.id);
    return `<article class="comparison-map ${expanded ? "expanded" : ""}"><button class="comparison-map-head" type="button" data-toggle-map="${map.id}"><span><small>${esc(state.work?.numero)} · ${esc(map.especialidade)}</small><strong>${esc(map.descricao || map.especialidade)}</strong></span><span>${itemsFor(map.id).length} ITENS</span><span>${proposals.length} PROPOSTAS</span><span>${money(bestSum(map.id))}</span><b>${expanded ? "−" : "+"}</b></button>${expanded ? `<div class="comparison-map-body">
      ${state.canEdit ? `<div class="comparison-map-actions"><span>GESTÃO DO MAPA</span>${deleteActions("map", map.id)}</div>` : ""}
      <div class="comparison-entry-forms">${state.canEdit ? `<form data-add-item="${map.id}"><strong>NOVO ITEM</strong><input name="numero" required placeholder="Nº"><input name="designacao" required placeholder="Designação"><input name="unidade" value="un" required><input name="quantidade" type="number" min="0.0001" step="0.0001" value="1" required><button type="submit">ADICIONAR</button><p class="form-error"></p></form><form data-add-proposal="${map.id}"><strong>NOVA PROPOSTA</strong><select name="fornecedor_id" required><option value="">Fornecedor</option>${supplierOptions()}</select><input name="data_proposta" type="date"><button type="submit">ADICIONAR</button><p class="form-error"></p></form>` : ""}</div>
      ${renderGrid(map)}${renderAdjustments(map)}${renderCosting(map)}
      <section class="comparison-commercial"><header>CONDIÇÕES / INFORMAÇÃO COMERCIAL</header>${proposals.map(p => renderProposalInfo(map,p)).join("") || '<p class="procurement-empty">SEM PROPOSTAS</p>'}</section>
      ${state.canEdit && proposals.length && map.valor_adjudicado_real != null ? `<form class="comparison-adjudicate" data-adjudicate-map="${map.id}"><strong>CRIAR SUBEMPREITADA</strong><select name="proposta_id" required>${proposals.map(p => `<option value="${p.id}">${esc(supplierName(p.fornecedor_id))}</option>`).join("")}</select><select name="fase_id" required>${phaseOptions()}</select><input name="data_inicio" type="date" required><input name="data_fim" type="date" required><select name="condicao_pagamento"><option value="">Sem condição definida</option><option value="imediato">Imediato</option><option value="15_dias">15 dias</option><option value="30_dias">30 dias</option></select><button type="submit">CRIAR COM ${money(map.valor_adjudicado_real)}</button><p class="form-error"></p></form>` : ""}
    </div>` : ""}</article>`;
  }

  function render() {
    const container = root(); if (!container) return;
    if (state.loading) return void (container.innerHTML='<div class="empty-state">A CARREGAR MAPAS COMPARATIVOS…</div>');
    container.innerHTML=`<section class="comparison-module"><header><div><p class="eyebrow">MODELO VALIDADO</p><h3>MAPA COMPARATIVO DE SUBEMPREITADAS E FORNECEDORES</h3><span>Propostas dinâmicas, melhor preço por item, ajustes, custeio e margem real.</span></div><b>${state.maps.length}</b></header>${renderNewMap()}<div>${state.maps.length ? state.maps.map(renderMap).join("") : '<div class="procurement-empty">NÃO EXISTEM MAPAS COMPARATIVOS NESTA OBRA.</div>'}</div></section>`;
  }

  async function load(work) {
    state.work=work; state.loading=true; render();
    try {
      if (!isConfigured) { state.canEdit=true; state.maps=[]; state.proposals=[]; state.items=[]; state.prices=[]; state.adjustments=[]; }
      else {
        const [maps,permission]=await Promise.all([api(`mapas_comparativos?select=*&obra_id=eq.${encodeURIComponent(work.id)}&order=criado_em.desc`),api("rpc/fn_pode_editar_obra",{method:"POST",body:JSON.stringify({p_obra_id:work.id})})]);
        state.maps=maps; state.canEdit=Boolean(permission); const ids=maps.map(row=>row.id);
        if (ids.length) {
          const encoded=ids.map(encodeURIComponent).join(",");
          [state.proposals,state.items,state.adjustments]=await Promise.all([api(`comparativo_propostas?select=*&mapa_id=in.(${encoded})&order=criado_em`),api(`comparativo_itens?select=*&mapa_id=in.(${encoded})&order=numero`),api(`comparativo_ajustes?select=*&mapa_id=in.(${encoded})&order=criado_em`)]);
          const itemIds=state.items.map(row=>row.id);
          state.prices=itemIds.length?await api(`comparativo_itens_precos?select=*&item_id=in.(${itemIds.map(encodeURIComponent).join(",")})`):[];
        } else { state.proposals=[];state.items=[];state.prices=[];state.adjustments=[]; }
      }
    } catch(error) { toast(error.message,"error"); }
    finally { state.loading=false;render(); }
  }

  async function submit(form, action) { const button=form.querySelector('button[type="submit"]'); if(button)button.disabled=true; try{await action();}catch(error){const p=form.querySelector('.form-error');if(p)p.textContent=error.message;else toast(error.message,"error");}finally{if(button)button.disabled=false;} }
  const post = (table,payload) => api(table,{method:"POST",headers:{Prefer:"return=representation"},body:JSON.stringify(payload)});
  const patch = (table,id,payload) => api(`${table}?id=eq.${encodeURIComponent(id)}`,{method:"PATCH",headers:{Prefer:"return=representation"},body:JSON.stringify(payload)});

  async function deleteItem(id) {
    const result = await api("rpc/fn_eliminar_item_comparativo", { method: "POST", body: JSON.stringify({ p_item_id: id }) });
    if (num(result?.precos_restantes) !== 0) throw new Error("A eliminação do item deixou preços relacionados na base.");
    state.pendingDelete = ""; state.editingItemId = ""; await load(state.work); toast(`Item eliminado com ${num(result?.precos_eliminados)} preço(s) relacionado(s).`);
  }

  async function deleteProposal(id) {
    const result = await api("rpc/fn_eliminar_proposta_comparativo", { method: "POST", body: JSON.stringify({ p_proposta_id: id }) });
    if (num(result?.precos_restantes) !== 0 || num(result?.ajustes_restantes) !== 0) throw new Error("A eliminação da proposta deixou registos relacionados na base.");
    state.pendingDelete = ""; state.editingProposalId = ""; await load(state.work); toast(`Proposta eliminada com ${num(result?.precos_eliminados)} preço(s) e ${num(result?.ajustes_eliminados)} ajuste(s).`);
  }

  async function deleteMap(id) {
    const result = await api("rpc/fn_eliminar_mapa_comparativo", { method: "POST", body: JSON.stringify({ p_mapa_id: id }) });
    const remaining = ["mapas_restantes", "itens_restantes", "propostas_restantes", "precos_restantes", "ajustes_restantes"];
    if (remaining.some(field => num(result?.[field]) !== 0)) throw new Error("A eliminação do mapa deixou registos relacionados na base.");
    state.pendingDelete = ""; state.expanded = ""; await load(state.work);
    toast(`Mapa eliminado com ${num(result?.itens_eliminados)} item(ns), ${num(result?.propostas_eliminadas)} proposta(s), ${num(result?.precos_eliminados)} preço(s) e ${num(result?.ajustes_eliminados)} ajuste(s).`);
  }

  host.addEventListener("click", event => {
    const toggleNew = event.target.closest("[data-toggle-new-map]");
    if (toggleNew) { state.newOpen = !state.newOpen; render(); return; }
    const editItem = event.target.closest("[data-edit-item]");
    if (editItem) { state.editingItemId = editItem.dataset.editItem; state.pendingDelete = ""; render(); return; }
    if (event.target.closest("[data-cancel-edit-item]")) { state.editingItemId = ""; render(); return; }
    const saveItem = event.target.closest("[data-save-item]");
    if (saveItem) {
      const row = saveItem.closest("tr");
      return void submit(row, async () => {
        const value = name => row.querySelector(`[data-item-field="${name}"]`)?.value.trim() || "";
        const quantity = num(value("quantidade"));
        if (!value("numero") || !value("designacao") || !value("unidade") || quantity <= 0) throw new Error("Preencha os dados válidos do item.");
        await patch("comparativo_itens", saveItem.dataset.saveItem, { numero: value("numero"), designacao: value("designacao"), unidade: value("unidade"), quantidade: quantity });
        state.editingItemId = ""; await load(state.work); toast("Item atualizado sem perder os preços existentes.");
      });
    }
    const editProposal = event.target.closest("[data-edit-proposal]");
    if (editProposal) { state.editingProposalId = editProposal.dataset.editProposal; state.pendingDelete = ""; render(); return; }
    if (event.target.closest("[data-cancel-edit-proposal]")) { state.editingProposalId = ""; render(); return; }
    if (event.target.closest("[data-cancel-delete]")) { state.pendingDelete = ""; render(); return; }
    for (const type of ["item", "proposal", "map"]) {
      const request = event.target.closest(`[data-request-delete-${type}]`);
      if (request) {
        const attribute = type === "item" ? "requestDeleteItem" : type === "proposal" ? "requestDeleteProposal" : "requestDeleteMap";
        state.pendingDelete = `${type}:${request.dataset[attribute]}`; render(); return;
      }
      const confirm = event.target.closest(`[data-confirm-delete-${type}]`);
      if (confirm) {
        const attribute = type === "item" ? "confirmDeleteItem" : type === "proposal" ? "confirmDeleteProposal" : "confirmDeleteMap";
        const id = confirm.dataset[attribute];
        const action = type === "item" ? deleteItem : type === "proposal" ? deleteProposal : deleteMap;
        return void action(id)
          .catch(error => toast(error.message || "Não foi possível eliminar o registo.", "error"));
      }
    }
    const toggle = event.target.closest("[data-toggle-map]");
    if (toggle) { state.expanded = state.expanded === toggle.dataset.toggleMap ? "" : toggle.dataset.toggleMap; render(); }
  });
  host.addEventListener("submit",event=>{const form=event.target;if(!form.closest('[data-comparative-map-root]'))return;event.preventDefault();
    if(form.matches('[data-new-map]'))return submit(form,async()=>{await post('mapas_comparativos',{obra_id:state.work.id,especialidade:form.elements.especialidade.value.trim(),descricao:form.elements.descricao.value.trim()||null,custo_estimado_orcamento:nullableNumber(form.elements.custo_estimado.value),preco_venda:nullableNumber(form.elements.preco_venda.value)});state.newOpen=false;await load(state.work);toast('Mapa comparativo criado.');});
    if(form.matches('[data-add-item]'))return submit(form,async()=>{await post('comparativo_itens',{mapa_id:form.dataset.addItem,numero:form.elements.numero.value.trim(),designacao:form.elements.designacao.value.trim(),unidade:form.elements.unidade.value.trim(),quantidade:num(form.elements.quantidade.value)});await load(state.work);toast('Item adicionado.');});
    if(form.matches('[data-add-proposal]'))return submit(form,async()=>{await post('comparativo_propostas',{mapa_id:form.dataset.addProposal,fornecedor_id:form.elements.fornecedor_id.value,data_proposta:form.elements.data_proposta.value||null});await load(state.work);toast('Proposta adicionada.');});
    if(form.matches('[data-save-price]'))return submit(form,async()=>{if(form.elements.preco_unitario.value==='')throw new Error('Indique um preço ou deixe o item sem cotação.');const payload={item_id:form.dataset.item,proposta_id:form.dataset.proposal,preco_unitario:num(form.elements.preco_unitario.value),observacoes:form.elements.observacoes.value.trim()||null};await api('comparativo_itens_precos?on_conflict=item_id,proposta_id',{method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=representation'},body:JSON.stringify(payload)});await load(state.work);toast('Preço guardado.');});
    if(form.matches('[data-proposal-info]'))return submit(form,async()=>{const payload={fornecedor_id:form.elements.fornecedor_id.value};['data_proposta','prazo_validade','contacto','telemovel','condicoes_pagamento','exclusoes_ambito','outras_informacoes','nota_primeline'].forEach(k=>payload[k]=form.elements[k].value.trim()||null);await patch('comparativo_propostas',form.dataset.proposalInfo,payload);state.editingProposalId="";await load(state.work);toast('Proposta atualizada sem perder preços ou ajustes.');});
    if(form.matches('[data-add-adjustment]'))return submit(form,async()=>{await post('comparativo_ajustes',{mapa_id:form.dataset.addAdjustment,proposta_id:form.elements.proposta_id.value,valor_ajustado:num(form.elements.valor_ajustado.value),justificacao:form.elements.justificacao.value.trim()});await load(state.work);toast('Ajuste registado.');});
    if(form.matches('[data-save-costing]'))return submit(form,async()=>{await patch('mapas_comparativos',form.dataset.saveCosting,{custo_estimado_orcamento:nullableNumber(form.elements.custo_estimado_orcamento.value),valor_adjudicado_real:nullableNumber(form.elements.valor_adjudicado_real.value),preco_venda:nullableNumber(form.elements.preco_venda.value)});await load(state.work);toast('Custeio guardado.');});
    if(form.matches('[data-adjudicate-map]'))return submit(form,async()=>{const result=await api('rpc/fn_criar_subempreitada_do_comparativo',{method:'POST',body:JSON.stringify({p_mapa_id:form.dataset.adjudicateMap,p_proposta_id:form.elements.proposta_id.value,p_fase_id:form.elements.fase_id.value,p_data_inicio_prevista:form.elements.data_inicio.value,p_data_fim_prevista:form.elements.data_fim.value,p_condicao_pagamento:form.elements.condicao_pagamento.value||null})});await onAdjudicated?.(Array.isArray(result)?result[0]:result);toast('Subempreitada criada com o Valor Adjudicado Real.');});
  });
  return {show:work=>load(work),reload:()=>state.work&&load(state.work)};
}
