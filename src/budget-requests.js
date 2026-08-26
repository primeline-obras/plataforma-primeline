const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);
const today = () => new Date().toISOString().slice(0, 10);
const STATES = {
  em_curso: "Em curso", enviado: "Enviado", aguarda_resposta: "Aguarda resposta",
  adjudicado: "Adjudicado", recusado: "Recusado", cancelado: "Cancelado",
  perdido: "Revisão necessária",
};
const CLOSED_STATES = new Set(["adjudicado", "recusado", "cancelado", "perdido"]);

export function createBudgetRequestsModule({ root, supabase, isConfigured, getProfile, euro, prettyDate, toast }) {
  const state = { loaded: false, loading: false, requests: [], versions: [], selectedId: "", error: "" };

  async function api(path, options) {
    const response = await supabase(path, options);
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.message || payload.details || "Não foi possível consultar os pedidos de orçamento.");
    }
    return response.status === 204 ? [] : response.json();
  }

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) { state.requests = []; state.versions = []; }
      else [state.requests, state.versions] = await Promise.all([
        api("pedidos_orcamento?select=*&order=criado_em.desc"),
        api("pedidos_orcamento_versoes?select=*&order=data_envio.desc,criado_em.desc"),
      ]);
      state.loaded = true;
      if (!state.selectedId || !state.requests.some(row => row.id === state.selectedId)) state.selectedId = state.requests[0]?.id || "";
    } catch (error) { state.error = `${error.message} Confirme se executou o SQL do Bloco 13.`; }
    finally { state.loading = false; render(); }
  }

  const selected = () => state.requests.find(row => row.id === state.selectedId) || null;
  const dateLabel = value => value ? prettyDate.format(new Date(`${value}T12:00:00`)) : "Sem data limite";
  const orderedRequests = rows => [...rows].sort((left, right) => {
    const priority = Number(Boolean(right.prioritario)) - Number(Boolean(left.prioritario));
    if (priority) return priority;
    if (!left.data_limite_entrega && !right.data_limite_entrega) return 0;
    if (!left.data_limite_entrega) return 1;
    if (!right.data_limite_entrega) return -1;
    return left.data_limite_entrega.localeCompare(right.data_limite_entrega);
  });

  function newRequestForm() {
    return `<details class="operations-form-card budget-new-form"><summary>＋ NOVO PEDIDO DE ORÇAMENTO</summary><form data-budget-request-form>
      <div class="operations-form-grid"><label>CLIENTE<input name="cliente_nome" required maxlength="200"></label><label>CONTACTO<input name="cliente_contacto" maxlength="200"></label></div>
      <label>INTERMEDIÁRIO (OPCIONAL)<input name="intermediario" maxlength="200"></label>
      <label>DESCRIÇÃO DO TRABALHO<textarea name="descricao_trabalho" rows="4" required></textarea></label>
      <div class="operations-form-grid"><label>DATA LIMITE DE ENTREGA<input name="data_limite_entrega" type="date"></label><label class="budget-priority-field"><input name="prioritario" type="checkbox"> PRIORITÁRIO</label></div>
      <button class="primary-button" type="submit">CRIAR PEDIDO <span>→</span></button><p class="form-error"></p>
    </form></details>`;
  }

  function board() {
    return `<section class="budget-board">${Object.entries(STATES).map(([stateName, label]) => {
      const rows = orderedRequests(state.requests.filter(row => row.estado === stateName));
      return `<article class="budget-column ${stateName}"><header><strong>${label}</strong><span>${rows.length}</span></header><div>${rows.length ? rows.map(row => `<button type="button" class="budget-card ${row.id === state.selectedId ? "active" : ""}" data-budget-id="${row.id}"><span class="budget-card-title"><strong>${esc(row.cliente_nome)}</strong>${row.prioritario ? `<em>PRIORITÁRIO</em>` : ""}</span><p>${esc(row.descricao_trabalho)}</p><small>LIMITE · ${esc(dateLabel(row.data_limite_entrega))}</small></button>`).join("") : `<p class="operations-empty">SEM PEDIDOS</p>`}</div></article>`;
    }).join("")}</section>`;
  }

  function versionForm(item) {
    return `<form class="budget-version-form" data-budget-version-form data-request-id="${item.id}"><div class="operations-form-grid"><label>DATA DE ENVIO<input name="data_envio" type="date" required value="${today()}"></label><label>VALOR (€)<input name="valor" type="number" min="0" step="0.01"></label></div><label>NOTAS<textarea name="notas" rows="2" placeholder="Ex. Retificação de quantidades"></textarea></label><button class="primary-button" type="submit">REGISTAR VERSÃO <span>→</span></button><p class="form-error"></p></form>`;
  }

  function detail() {
    const item = selected();
    if (!item) return `<section class="panel budget-detail"><div class="operations-empty">SELECIONE OU CRIE UM PEDIDO</div></section>`;
    const versions = state.versions.filter(row => row.pedido_id === item.id);
    return `<section class="panel budget-detail"><header><div><p class="eyebrow">PEDIDO DE ORÇAMENTO</p><h2>${esc(item.cliente_nome)}</h2><p>${esc(item.cliente_contacto || "Contacto não indicado")}${item.intermediario ? ` · Intermediário: ${esc(item.intermediario)}` : ""}</p></div><span>${versions.length} VERSÃO${versions.length === 1 ? "" : "ÕES"}</span></header>
      <p class="budget-description">${esc(item.descricao_trabalho)}</p>
      ${item.estado === "perdido" ? `<div class="work-warning"><strong>CLASSIFICAÇÃO PENDENTE</strong><span>Este pedido tinha o estado antigo “Perdido”. Confirme se foi recusado pelo cliente ou cancelado antes da decisão.</span></div>` : ""}
      <form class="budget-status-form" data-budget-status-form data-request-id="${item.id}"><label>ESTADO<select name="estado">${Object.entries(STATES).filter(([value]) => value !== "perdido" || item.estado === "perdido").map(([value, label]) => `<option value="${value}" ${value === item.estado ? "selected" : ""} ${value === "perdido" ? "disabled" : ""}>${label}</option>`).join("")}</select></label><label>SITUAÇÃO ATUAL<textarea name="situacao_atual" rows="3" placeholder="Próximo passo, bloqueio ou informação relevante">${esc(item.situacao_atual || "")}</textarea></label><label class="budget-priority-field"><input name="prioritario" type="checkbox" ${item.prioritario ? "checked" : ""}> PRIORITÁRIO</label><button type="submit">GUARDAR SITUAÇÃO</button>${item.estado !== "cancelado" ? `<button type="button" class="danger-action" data-cancel-budget-request="${item.id}">CANCELAR PEDIDO</button>` : ""}<p class="form-error"></p></form>
      <div class="budget-versions"><div><p class="eyebrow">HISTÓRICO</p><h3>ENVIOS E RETIFICAÇÕES</h3></div>${versionForm(item)}<div>${versions.length ? versions.map((row, index) => `<article><span>V${String(versions.length - index).padStart(2, "0")}</span><time>${dateLabel(row.data_envio)}</time><strong>${row.valor == null ? "Valor não indicado" : euro.format(Number(row.valor))}</strong><p>${esc(row.notas || "Sem notas")}</p><button type="button" class="danger-action" data-delete-budget-version="${row.id}">APAGAR</button></article>`).join("") : `<p class="operations-empty">AINDA SEM VERSÕES ENVIADAS</p>`}</div></div>
    </section>`;
  }

  function render() {
    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">ÁREA COMERCIAL</p><h1>PEDIDOS DE ORÇAMENTO</h1><p>Acompanhe prazos, situação atual e todas as versões enviadas ao cliente.</p></div><div class="heading-stat"><span>ATIVOS</span><strong>${String(state.requests.filter(row => !CLOSED_STATES.has(row.estado)).length).padStart(2, "0")}</strong></div></div>
      ${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)}</span></div>` : ""}
      ${state.loading ? `<div class="fleet-loading">A CARREGAR PEDIDOS…</div>` : `${newRequestForm()}${board()}${detail()}`}`;
  }

  root.addEventListener("click", event => {
    const button = event.target.closest("[data-budget-id]");
    if (button) { state.selectedId = button.dataset.budgetId; render(); }
    const cancel = event.target.closest("[data-cancel-budget-request]");
    if (cancel) {
      if (!window.confirm("Cancelar este pedido de orçamento? O histórico será mantido.")) return;
      cancel.disabled = true;
      api("rpc/fn_cancelar_pedido_orcamento", { method: "POST", body: JSON.stringify({ p_pedido_id: cancel.dataset.cancelBudgetRequest }) })
        .then(() => { const row = state.requests.find(item => item.id === cancel.dataset.cancelBudgetRequest); if (row) row.estado = "cancelado"; toast("Pedido cancelado, com histórico preservado."); render(); })
        .catch(error => { toast(error.message, "error"); cancel.disabled = false; });
      return;
    }
    const versionDelete = event.target.closest("[data-delete-budget-version]");
    if (versionDelete) {
      if (!window.confirm("Apagar esta versão do orçamento? A ação fica registada na auditoria.")) return;
      versionDelete.disabled = true;
      api("rpc/fn_apagar_versao_pedido_orcamento", { method: "POST", body: JSON.stringify({ p_versao_id: versionDelete.dataset.deleteBudgetVersion }) })
        .then(() => { state.versions = state.versions.filter(row => row.id !== versionDelete.dataset.deleteBudgetVersion); toast("Versão apagada."); render(); })
        .catch(error => { toast(error.message, "error"); versionDelete.disabled = false; });
    }
  });

  root.addEventListener("submit", async event => {
    const requestForm = event.target.closest("[data-budget-request-form]");
    const versionForm = event.target.closest("[data-budget-version-form]");
    const statusForm = event.target.closest("[data-budget-status-form]");
    if (!requestForm && !versionForm && !statusForm) return;
    event.preventDefault();
    const form = requestForm || versionForm || statusForm; const errorNode = form.querySelector(".form-error"); const button = form.querySelector('button[type="submit"]');
    button.disabled = true; errorNode.textContent = "";
    try {
      const fields = Object.fromEntries(new FormData(form));
      if (requestForm) {
        const payload = { empresa_id: getProfile()?.empresa_id, cliente_nome: fields.cliente_nome.trim(), cliente_contacto: fields.cliente_contacto.trim() || null, intermediario: fields.intermediario.trim() || null, descricao_trabalho: fields.descricao_trabalho.trim(), data_limite_entrega: fields.data_limite_entrega || null, prioritario: fields.prioritario === "on", estado: "em_curso", criado_por: getProfile()?.id || null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), situacao_atual: null, ...payload };
        if (isConfigured) [saved] = await api("pedidos_orcamento?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.requests.unshift(saved); state.selectedId = saved.id; toast("Pedido de orçamento criado.");
      } else if (versionForm) {
        const payload = { pedido_id: form.dataset.requestId, data_envio: fields.data_envio, valor: fields.valor ? Number(fields.valor) : null, notas: fields.notas.trim() || null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("pedidos_orcamento_versoes?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.versions.unshift(saved); toast("Versão registada no histórico.");
      } else {
        const payload = { estado: fields.estado, situacao_atual: fields.situacao_atual.trim() || null, prioritario: fields.prioritario === "on" };
        if (isConfigured) await api(`pedidos_orcamento?id=eq.${encodeURIComponent(form.dataset.requestId)}&select=*`, { method: "PATCH", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        Object.assign(state.requests.find(row => row.id === form.dataset.requestId), payload); toast("Situação atualizada.");
      }
      render();
    } catch (error) { errorNode.textContent = error.message || "Não foi possível guardar."; button.disabled = false; }
  });

  return { show: () => load(), refresh: () => load(true) };
}
