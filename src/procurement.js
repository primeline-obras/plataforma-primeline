const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const number = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const isoToday = () => new Date().toISOString().slice(0, 10);

export function createProcurementModule({
  host,
  supabase,
  isConfigured,
  getPhases,
  getSuppliers,
  getSubcontracts,
  euro,
  toast,
  onImportExcel,
  onAdjudicated,
  onConsultationsChanged,
}) {
  const state = {
    work: null,
    loadedWorkId: "",
    loading: false,
    canEdit: false,
    consultations: [],
    budgetItems: [],
    consultationItems: [],
    candidates: [],
    candidateItems: [],
    expandedId: "",
    newFormOpen: false,
  };

  const root = () => host.querySelector("[data-procurement-root]");
  const phases = () => getPhases() || [];
  const supplierName = id => getSuppliers().find(item => item.id === id)?.nome || "Fornecedor";
  const phaseFor = id => phases().find(item => item.id === id);
  const itemQuantity = item => {
    const raw = item.quantidade ?? item.quantidade_prevista ?? item.qtd;
    return raw == null || raw === "" ? null : number(raw);
  };
  const itemUnit = item => item.unidade || item.unidade_medida || "un.";
  const itemLabel = item => item.numero_artigo ? `${item.numero_artigo} · ${item.descricao}` : item.descricao || "Artigo";
  const linkedItemIds = consultationId => new Set(state.consultationItems.filter(row => row.consulta_subempreitada_id === consultationId).map(row => row.item_orcamento_id));
  const itemsFor = consultationId => {
    const ids = linkedItemIds(consultationId);
    return state.budgetItems.filter(item => ids.has(item.id));
  };
  const candidatesFor = consultationId => state.candidates.filter(item => item.consulta_subempreitada_id === consultationId);
  const priceFor = (candidateId, itemId) => state.candidateItems.find(item => item.candidato_id === candidateId && item.item_orcamento_id === itemId);

  function renderNewConsultation() {
    if (!state.canEdit) return "";
    const specialties = [...new Set([
      ...state.consultations.map(item => item.trabalho),
      ...getSubcontracts().filter(item => item.obra_id === state.work.id).map(item => item.especialidade),
    ].filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt"));
    const selectedPhase = phases()[0]?.id || "";
    return `<div class="procurement-new-wrap">
      <button type="button" class="outline-action" data-toggle-new-consultation>${state.newFormOpen ? "FECHAR" : "＋ NOVA CONSULTA"}</button>
      ${state.newFormOpen ? `<form class="procurement-new-form" data-new-consultation>
        <div class="procurement-form-row">
          <label>ESPECIALIDADE<input name="trabalho" list="procurement-specialties" maxlength="160" required placeholder="Ex.: Caixilharia"><datalist id="procurement-specialties">${specialties.map(value => `<option value="${escapeHtml(value)}">`).join("")}</datalist></label>
          <label>FASE<select name="fase_id" required>${phases().map(phase => `<option value="${phase.id}" ${phase.id === selectedPhase ? "selected" : ""}>${escapeHtml(phase.codigo || "")} · ${escapeHtml(phase.descricao || "Fase")}</option>`).join("")}</select></label>
        </div>
        <div class="procurement-budget-head"><div><strong>ITENS DO ORÇAMENTO</strong><span>Selecione os artigos que vão ser pedidos aos fornecedores.</span></div><input data-budget-search placeholder="Pesquisar artigo…"></div>
        <div class="procurement-budget-items" data-budget-items></div>
        <p class="form-error"></p><button class="primary-button" type="submit">CRIAR CONSULTA <span>→</span></button>
      </form>` : ""}
    </div>`;
  }

  function renderBudgetItems(form) {
    if (!form) return;
    const phaseId = form.elements.fase_id.value;
    const needle = form.querySelector("[data-budget-search]").value.trim().toLocaleLowerCase("pt");
    const items = state.budgetItems.filter(item => item.fase_id === phaseId && (!needle || itemLabel(item).toLocaleLowerCase("pt").includes(needle)));
    form.querySelector("[data-budget-items]").innerHTML = items.length ? items.map(item => {
      const quantity = itemQuantity(item);
      return `<label class="procurement-budget-item ${quantity == null || quantity <= 0 ? "incomplete" : ""}"><input type="checkbox" name="item_id" value="${item.id}" ${quantity == null || quantity <= 0 ? "disabled" : ""}><span><strong>${escapeHtml(itemLabel(item))}</strong><small>${quantity == null || quantity <= 0 ? "QUANTIDADE POR PREENCHER NO ORÇAMENTO" : `${escapeHtml(itemUnit(item))} · Quantidade ${quantity}`}</small></span><b>${euro.format(number(item.venda_prevista))}</b></label>`;
    }).join("") : `<div class="procurement-empty">SEM ITENS DO ORÇAMENTO NESTA FASE</div>`;
  }

  function renderCandidateForm(consultation) {
    if (!state.canEdit) return "";
    return `<form class="procurement-candidate-form" data-add-candidate="${consultation.id}">
      <div><label>PESQUISAR FORNECEDOR<input data-supplier-search placeholder="Nome do fornecedor"></label><label>FORNECEDOR EXISTENTE<select name="fornecedor_id" required><option value="">Selecionar fornecedor</option>${getSuppliers().map(item => `<option value="${item.id}">${escapeHtml(item.nome)}</option>`).join("")}</select></label></div>
      <label>CONTACTO DESTA CONSULTA<input name="contacto" maxlength="160"></label><label>TELEFONE<input name="telefone" maxlength="50"></label>
      <button type="submit">＋ ADICIONAR</button><p class="supplier-not-found" data-supplier-message></p><p class="form-error"></p>
    </form>`;
  }

  function rowStats(candidates, item) {
    const values = candidates.map(candidate => priceFor(candidate.id, item.id)?.preco_unitario).filter(value => value != null).map(Number);
    if (!values.length) return { min: "—", average: "—", max: "—" };
    return { min: euro.format(Math.min(...values)), average: euro.format(values.reduce((a, b) => a + b, 0) / values.length), max: euro.format(Math.max(...values)) };
  }

  function renderComparison(consultation) {
    const items = itemsFor(consultation.id);
    const candidates = candidatesFor(consultation.id);
    if (!candidates.length) return `<div class="procurement-empty">ADICIONE PELO MENOS UM FORNECEDOR PARA COMEÇAR A COMPARAÇÃO.</div>`;
    return `<div class="procurement-sheet-wrap"><table class="procurement-sheet"><thead><tr><th>ARTIGO</th><th>QTD.</th>${candidates.map(candidate => `<th><span>${escapeHtml(supplierName(candidate.fornecedor_id))}</span><small>${candidate.escolhido ? "ESCOLHIDO" : "PREÇO UNITÁRIO"}</small></th>`).join("")}<th>MÍN.</th><th>MÉDIO</th><th>MÁX.</th></tr></thead><tbody>
      ${items.map(item => {
        const stats = rowStats(candidates, item);
        const quantity = itemQuantity(item);
        return `<tr><td><strong>${escapeHtml(itemLabel(item))}</strong><small>${escapeHtml(itemUnit(item))}</small></td><td>${quantity ?? "—"}</td>${candidates.map(candidate => {
          const price = priceFor(candidate.id, item.id);
          return `<td><input type="number" min="0" step="0.0001" value="${price?.preco_unitario ?? ""}" data-candidate-price="${candidate.id}" data-budget-item="${item.id}" data-quantity="${quantity ?? ""}" ${state.canEdit && !candidate.escolhido && quantity > 0 ? "" : "disabled"} title="${quantity > 0 ? "Preço unitário" : "Preencha primeiro a quantidade no orçamento"}"><output>${price ? euro.format(number(price.preco_total)) : "—"}</output></td>`;
        }).join("")}<td data-row-stat="min">${stats.min}</td><td data-row-stat="average">${stats.average}</td><td data-row-stat="max">${stats.max}</td></tr>`;
      }).join("")}
      <tr class="procurement-totals"><td colspan="2">TOTAL POR CANDIDATO</td>${candidates.map(candidate => `<td data-candidate-total="${candidate.id}">${euro.format(number(candidate.valor_total))}</td>`).join("")}<td colspan="3"></td></tr></tbody></table></div>
      <div class="procurement-candidate-actions">${candidates.map(candidate => `<div class="procurement-candidate-action"><strong>${escapeHtml(supplierName(candidate.fornecedor_id))}</strong>${state.canEdit && !candidate.escolhido ? `<button type="button" data-save-candidate="${candidate.id}">GUARDAR PREÇOS</button><form data-adjudicate="${candidate.id}"><label>INÍCIO<input type="date" name="data_inicio" value="${isoToday()}" required></label><label>FIM<input type="date" name="data_fim" required></label><label>PAGAMENTO<select name="condicao_pagamento" required><option value="imediato">Imediato</option><option value="15_dias">15 dias</option><option value="30_dias">30 dias</option></select></label><button type="submit">ADJUDICAR</button><p class="form-error"></p></form>` : `<span class="chosen-candidate">${candidate.escolhido ? "ADJUDICADO" : "CONSULTA EM LEITURA"}</span>`}</div>`).join("")}</div>`;
  }

  function renderConsultation(consultation) {
    const expanded = state.expandedId === consultation.id;
    const itemCount = itemsFor(consultation.id).length;
    const candidateCount = candidatesFor(consultation.id).length;
    const phase = phaseFor(consultation.fase_id);
    return `<article class="procurement-consultation ${expanded ? "expanded" : ""}"><button type="button" class="procurement-consultation-head" data-toggle-consultation="${consultation.id}"><span><small>${escapeHtml(phase?.codigo || "SEM FASE")}</small><strong>${escapeHtml(consultation.trabalho || "Consulta")}</strong></span><span><b>${itemCount}</b> ITENS</span><span><b>${candidateCount}</b> FORNECEDORES</span><em>${expanded ? "−" : "+"}</em></button>${expanded ? `<div class="procurement-consultation-body">${renderCandidateForm(consultation)}${renderComparison(consultation)}</div>` : ""}</article>`;
  }

  function render() {
    const container = root();
    if (!container) return;
    if (state.loading) return void (container.innerHTML = `<div class="empty-state">A CARREGAR MAPAS COMPARATIVOS…</div>`);
    const open = state.consultations.filter(item => item.estado === "em_consulta" || !item.estado);
    container.innerHTML = `<section class="procurement-entry"><header><div><p class="eyebrow">MAPA COMPARATIVO</p><h3>EM CONSULTA</h3><span>Crie consultas, recolha propostas e compare preços por artigo.</span></div><div class="procurement-header-actions">${state.canEdit ? '<button type="button" class="outline-action" data-import-subcontracts>IMPORTAR EXCEL</button>' : ""}<b>${open.length}</b></div></header>${renderNewConsultation()}<div class="procurement-consultations">${open.length ? open.map(renderConsultation).join("") : `<div class="procurement-empty">NÃO EXISTEM CONSULTAS ABERTAS NESTA OBRA.</div>`}</div></section>`;
    renderBudgetItems(container.querySelector("[data-new-consultation]"));
  }

  async function api(path, options = {}, label = "Não foi possível concluir a operação") {
    const response = await supabase(path, options);
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw new Error(detail.message || detail.details || label);
    }
    if (response.status === 204) return null;
    return response.json();
  }

  async function load(work, force = false) {
    state.work = work;
    if (!force && state.loadedWorkId === work.id) return render();
    if (state.loading) return;
    state.loading = true; render();
    try {
      if (!isConfigured) {
        state.canEdit = true;
        state.consultations = [{ id: "demo-consulta", obra_id: work.id, fase_id: phases()[0]?.id, trabalho: "Caixilharia", estado: "em_consulta" }];
        state.budgetItems = [{ id: "demo-item-1", fase_id: phases()[0]?.id, numero_artigo: "1.1", descricao: "Fornecimento e montagem", quantidade: 8, unidade: "un.", venda_prevista: 8000 }];
        state.consultationItems = [{ consulta_subempreitada_id: "demo-consulta", item_orcamento_id: "demo-item-1" }];
        state.candidates = [];
        state.candidateItems = [];
      } else {
        const phaseIds = phases().map(item => item.id);
        const [consultations, budgetItems, permission] = await Promise.all([
          api(`consultas_subempreitada?select=*&obra_id=eq.${encodeURIComponent(work.id)}&order=criado_em.desc`),
          phaseIds.length ? api(`itens_orcamento?select=*&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})&order=numero_artigo`) : [],
          api("rpc/fn_pode_editar_obra", { method: "POST", body: JSON.stringify({ p_obra_id: work.id }) }),
        ]);
        state.consultations = consultations;
        state.budgetItems = budgetItems;
        state.canEdit = Boolean(permission);
        const consultationIds = consultations.map(item => item.id);
        if (consultationIds.length) {
          const encoded = consultationIds.map(encodeURIComponent).join(",");
          [state.consultationItems, state.candidates] = await Promise.all([
            api(`consultas_subempreitada_itens?select=*&consulta_subempreitada_id=in.(${encoded})`),
            api(`consultas_subempreitada_candidatos?select=*&consulta_subempreitada_id=in.(${encoded})&order=criado_em`),
          ]);
          const candidateIds = state.candidates.map(item => item.id);
          state.candidateItems = candidateIds.length ? await api(`consultas_subempreitada_candidatos_itens?select=*&candidato_id=in.(${candidateIds.map(encodeURIComponent).join(",")})`) : [];
        } else {
          state.consultationItems = []; state.candidates = []; state.candidateItems = [];
        }
      }
      state.loadedWorkId = work.id;
      onConsultationsChanged?.(state.consultations);
    } catch (error) { toast(error.message, "error"); }
    finally { state.loading = false; render(); }
  }

  async function withButton(button, callback) {
    button.disabled = true;
    try { await callback(); } catch (error) { toast(error.message, "error"); } finally { button.disabled = false; }
  }

  function updateDraft() {
    const container = root();
    container?.querySelectorAll("[data-candidate-price]").forEach(input => {
      const value = input.value === "" ? null : number(input.value);
      input.nextElementSibling.textContent = value == null ? "—" : euro.format(value * number(input.dataset.quantity));
    });
    container?.querySelectorAll(".procurement-sheet tbody tr:not(.procurement-totals)").forEach(row => {
      const values = [...row.querySelectorAll("[data-candidate-price]")].map(input => input.value === "" ? null : number(input.value)).filter(value => value != null);
      const stats = values.length ? { min: Math.min(...values), average: values.reduce((a, b) => a + b, 0) / values.length, max: Math.max(...values) } : null;
      ["min", "average", "max"].forEach(key => { const cell = row.querySelector(`[data-row-stat="${key}"]`); if (cell) cell.textContent = stats ? euro.format(stats[key]) : "—"; });
    });
    const candidateIds = [...new Set([...container?.querySelectorAll("[data-candidate-price]") || []].map(input => input.dataset.candidatePrice))];
    candidateIds.forEach(id => {
      const total = [...container.querySelectorAll(`[data-candidate-price="${id}"]`)].reduce((sum, input) => sum + (input.value === "" ? 0 : number(input.value) * number(input.dataset.quantity)), 0);
      const target = container.querySelector(`[data-candidate-total="${id}"]`); if (target) target.textContent = euro.format(total);
    });
  }

  async function saveCandidate(candidateId) {
    const inputs = [...root().querySelectorAll(`[data-candidate-price="${candidateId}"]:not(:disabled)`)];
    const drafts = inputs.map(input => ({ item_orcamento_id: input.dataset.budgetItem, preco_unitario: input.value === "" ? null : number(input.value) }));
    const rows = drafts.filter(item => item.preco_unitario != null).map(item => {
      const input = inputs.find(field => field.dataset.budgetItem === item.item_orcamento_id);
      return { candidato_id: candidateId, ...item, preco_total: item.preco_unitario * number(input.dataset.quantity) };
    });
    if (!rows.length) throw new Error("Preencha pelo menos um preço para este fornecedor.");
    if (isConfigured) {
      await api("rpc/fn_guardar_precos_candidato_subempreitada", { method: "POST", body: JSON.stringify({ p_candidato_id: candidateId, p_precos: drafts }) }, "Não foi possível guardar os preços");
    }
    state.candidateItems = state.candidateItems.filter(item => item.candidato_id !== candidateId);
    rows.forEach(row => {
      state.candidateItems.push(row);
    });
    const candidate = state.candidates.find(item => item.id === candidateId);
    candidate.valor_total = rows.reduce((sum, item) => sum + item.preco_total, 0);
    toast("Preços guardados.");
  }

  host.addEventListener("click", event => {
    if (event.target.closest("[data-import-subcontracts]")) {
      onImportExcel?.({ work: state.work, phases: phases(), suppliers: getSuppliers(), consultations: state.consultations, subcontracts: getSubcontracts().filter(item => item.obra_id === state.work.id), onComplete: () => load(state.work, true) });
      return;
    }
    const newButton = event.target.closest("[data-toggle-new-consultation]");
    if (newButton) { state.newFormOpen = !state.newFormOpen; return render(); }
    const consultationButton = event.target.closest("[data-toggle-consultation]");
    if (consultationButton) { state.expandedId = state.expandedId === consultationButton.dataset.toggleConsultation ? "" : consultationButton.dataset.toggleConsultation; return render(); }
    const saveButton = event.target.closest("[data-save-candidate]");
    if (saveButton) return withButton(saveButton, () => saveCandidate(saveButton.dataset.saveCandidate));
  });

  host.addEventListener("input", event => {
    if (event.target.matches("[data-budget-search]")) return renderBudgetItems(event.target.closest("form"));
    if (event.target.matches("[data-candidate-price]")) return updateDraft();
    if (event.target.matches("[data-supplier-search]")) {
      const form = event.target.closest("form");
      const needle = event.target.value.trim().toLocaleLowerCase("pt");
      const matches = getSuppliers().filter(item => !needle || item.nome.toLocaleLowerCase("pt").includes(needle));
      form.elements.fornecedor_id.innerHTML = `<option value="">Selecionar fornecedor</option>${matches.map(item => `<option value="${item.id}">${escapeHtml(item.nome)}</option>`).join("")}`;
      form.querySelector("[data-supplier-message]").textContent = matches.length ? "" : "Fornecedor não encontrado. Contacte o administrativo ou a gerência para o criarem primeiro.";
    }
  });

  host.addEventListener("change", event => {
    if (event.target.matches("[data-new-consultation] [name=fase_id]")) renderBudgetItems(event.target.closest("form"));
  });

  host.addEventListener("submit", event => {
    const form = event.target;
    if (!form.closest("[data-procurement-root]")) return;
    event.preventDefault();
    const button = form.querySelector("button[type=submit]");
    if (form.matches("[data-new-consultation]")) return withButton(button, async () => {
      const itemIds = [...form.querySelectorAll('[name="item_id"]:checked')].map(input => input.value);
      if (!itemIds.length) throw new Error("Selecione pelo menos um item do orçamento.");
      if (isConfigured) {
        await api("rpc/fn_criar_consulta_subempreitada", { method: "POST", body: JSON.stringify({ p_obra_id: state.work.id, p_fase_id: form.elements.fase_id.value, p_trabalho: form.elements.trabalho.value.trim(), p_item_ids: itemIds }) }, "Não foi possível criar a consulta");
        state.newFormOpen = false; await load(state.work, true);
      } else {
        const consultation = { id: crypto.randomUUID(), obra_id: state.work.id, fase_id: form.elements.fase_id.value, trabalho: form.elements.trabalho.value.trim(), estado: "em_consulta" };
        state.consultations.unshift(consultation);
        state.consultationItems.push(...itemIds.map(itemId => ({ consulta_subempreitada_id: consultation.id, item_orcamento_id: itemId })));
        state.expandedId = consultation.id;
        state.newFormOpen = false;
        onConsultationsChanged?.(state.consultations);
        render();
      }
      toast("Consulta criada com os itens selecionados.");
    });
    if (form.matches("[data-add-candidate]")) return withButton(button, async () => {
      if (!form.elements.fornecedor_id.value) throw new Error("Escolha um fornecedor existente.");
      if (candidatesFor(form.dataset.addCandidate).some(item => item.fornecedor_id === form.elements.fornecedor_id.value)) throw new Error("Este fornecedor já foi adicionado à consulta.");
      const payload = { consulta_subempreitada_id: form.dataset.addCandidate, fornecedor_id: form.elements.fornecedor_id.value, contacto: form.elements.contacto.value.trim() || null, telefone: form.elements.telefone.value.trim() || null, escolhido: false };
      if (isConfigured) {
        await api("consultas_subempreitada_candidatos", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) }, "Não foi possível adicionar o fornecedor");
        await load(state.work, true);
      } else {
        payload.id = crypto.randomUUID();
        state.candidates.push(payload);
        render();
      }
      toast("Fornecedor adicionado à consulta.");
    });
    if (form.matches("[data-adjudicate]")) return withButton(button, async () => {
      const candidateId = form.dataset.adjudicate;
      await saveCandidate(candidateId);
      let result = null;
      if (isConfigured) result = await api("rpc/fn_adjudicar_candidato_subempreitada", { method: "POST", body: JSON.stringify({ p_candidato_id: candidateId, p_data_inicio_prevista: form.elements.data_inicio.value, p_data_fim_prevista: form.elements.data_fim.value, p_condicao_pagamento: form.elements.condicao_pagamento.value }) }, "Não foi possível adjudicar o candidato");
      if (isConfigured) {
        await onAdjudicated(result); await load(state.work, true);
      } else {
        const candidate = state.candidates.find(item => item.id === candidateId);
        if (candidate) candidate.escolhido = true;
        render();
      }
      toast("Candidato adjudicado e planeamento sincronizado.");
    });
  });

  return { show: work => load(work), reload: () => state.work && load(state.work, true) };
}
