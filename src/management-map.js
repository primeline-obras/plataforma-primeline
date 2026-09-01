const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const CATEGORY_LABELS = { materiais: "Materiais", estaleiro: "Despesas de Estaleiro", mao_obra: "Mão de Obra", subempreitadas: "Subempreitadas" };
const WRITABLE_CATEGORIES = Object.entries(CATEGORY_LABELS).filter(([value]) => value !== "subempreitadas");

export function createManagementMapModule({ root, supabase, isConfigured, getWorks, getAccessContext, euro, toast, confirmAction }) {
  const state = { loaded: false, loading: false, error: "", rows: [], suppliers: [], collaborators: [], editing: null };
  const role = () => String(getAccessContext?.()?.role || "");
  const canEdit = () => ["gestao_plataforma", "administrativo"].includes(role());
  const availableWorks = () => {
    const byId = new Map(getWorks().map(work => [work.id, work]));
    state.rows.forEach(row => { if (row.obra_id && !byId.has(row.obra_id)) byId.set(row.obra_id, { id: row.obra_id, numero: row.obra_numero, nome: row.obra_nome }); });
    return [...byId.values()].sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
  };

  async function request(path, options = {}, message = "Não foi possível concluir a operação.") {
    const response = await supabase(path, options);
    const payload = await response.json().catch(() => null);
    if (!response.ok) throw new Error(payload?.message || payload?.details || message);
    return payload;
  }

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) state.rows = [];
      else {
        const calls = [
          request("rpc/fn_mapa_gestao_obras", { method: "POST", body: "{}" }, "Não foi possível consultar o Mapa de Gestão de Obras."),
          request("gestao_obras_lancamentos?select=id,obra_id,categoria,data_lancamento,entidade_nome,descricao,documento,unidade_medida,quantidade,valor_unitario,data_pagamento,valor&order=data_lancamento.desc", {}, "Não foi possível carregar os lançamentos manuais."),
        ];
        if (canEdit()) calls.push(
          request("fornecedores?select=id,nome&order=nome", {}, "Não foi possível carregar fornecedores."),
          request("colaboradores?select=id,nome&data_saida=is.null&order=nome", {}, "Não foi possível carregar colaboradores."),
        );
        const [historicalRows, manualRows = [], suppliers = [], collaborators = []] = await Promise.all(calls);
        const workById = new Map(getWorks().map(work => [work.id, work]));
        state.rows = [...manualRows.map(row => ({ ...row, origem_id: row.id, obra_numero: workById.get(row.obra_id)?.numero || "—", obra_nome: workById.get(row.obra_id)?.nome || "Obra", editavel: true })), ...(historicalRows || [])];
        state.suppliers = suppliers; state.collaborators = collaborators;
      }
      state.loaded = true;
    } catch (error) { state.error = error.message; }
    finally { state.loading = false; render(); }
  }

  function filteredRows() {
    const form = root.querySelector("[data-management-map-filters]");
    if (!form) return state.rows;
    const filters = Object.fromEntries(new FormData(form));
    const needle = String(filters.entidade || "").trim().toLocaleLowerCase("pt-PT");
    return state.rows.filter(row =>
      (!filters.obra_id || row.obra_id === filters.obra_id)
      && (!filters.categoria || row.categoria === filters.categoria)
      && (!filters.data_inicio || row.data_lancamento >= filters.data_inicio)
      && (!filters.data_fim || row.data_lancamento <= filters.data_fim)
      && (!needle || `${row.entidade_nome || ""} ${row.descricao || ""} ${row.documento || ""}`.toLocaleLowerCase("pt-PT").includes(needle))
    );
  }

  function renderTable() {
    const rows = filteredRows();
    const total = rows.reduce((sum, row) => sum + Number(row.valor || 0), 0);
    return `<div class="management-map-result"><div class="management-map-summary"><span><small>LANÇAMENTOS VISÍVEIS</small><strong>${rows.length}</strong></span><span><small>VALOR TOTAL</small><strong>${euro.format(total)}</strong></span></div>
      <div class="management-map-scroll"><table><thead><tr><th>DATA</th><th>OBRA</th><th>CATEGORIA</th><th>FORNECEDOR / COLABORADOR</th><th>DESCRIÇÃO</th><th>DOCUMENTO</th><th>UN. MEDIDA</th><th>QUANTIDADE</th><th>VALOR UNITÁRIO</th><th>DATA DE PAGAMENTO</th><th>VALOR (TOTAL)</th>${canEdit() ? "<th>AÇÕES</th>" : ""}</tr></thead><tbody>
        ${rows.length ? rows.map(row => `<tr><td>${esc(row.data_lancamento || "—")}</td><td class="management-work"><strong>${esc(row.obra_numero || "—")}</strong><small>${esc(row.obra_nome || "")}</small></td><td><span class="management-category ${esc(row.categoria)}">${esc(CATEGORY_LABELS[row.categoria] || row.categoria)}</span></td><td class="management-wrap management-entity">${esc(row.entidade_nome || "—")}</td><td class="management-wrap management-description">${esc(row.descricao || "—")}</td><td>${esc(row.documento || "—")}</td><td>${esc(row.unidade_medida || "—")}</td><td class="management-number">${row.quantidade == null ? "—" : esc(row.quantidade)}</td><td class="management-value">${row.valor_unitario == null ? "—" : euro.format(Number(row.valor_unitario))}</td><td>${esc(row.data_pagamento || "—")}</td><td class="management-value">${euro.format(Number(row.valor || 0))}</td>${canEdit() ? `<td class="management-actions">${row.editavel ? `<button type="button" data-edit-management-entry="${row.origem_id}">EDITAR</button><button type="button" class="danger" data-delete-management-entry="${row.origem_id}">APAGAR</button>` : `<small>HISTÓRICO</small>`}</td>` : ""}</tr>`).join("") : `<tr><td colspan="${canEdit() ? 12 : 11}" class="management-map-empty">SEM LANÇAMENTOS NESTE FILTRO</td></tr>`}
      </tbody></table></div></div>`;
  }

  function editor() {
    if (!canEdit()) return "";
    const entry = state.editing || {};
    const workOptions = availableWorks();
    const entityNames = [...state.suppliers, ...state.collaborators].map(item => item.nome).filter(Boolean);
    return `<details class="management-entry-editor" ${state.editing ? "open" : ""}><summary>${state.editing ? "EDITAR LANÇAMENTO" : "+ NOVO LANÇAMENTO"}<small>Materiais, mão de obra ou despesa de estaleiro</small></summary>
      <form data-management-entry-form><input type="hidden" name="id" value="${esc(entry.origem_id || "")}">
        <label>OBRA<select name="obra_id" required><option value="">Selecionar obra</option>${workOptions.map(work => `<option value="${work.id}" ${work.id === entry.obra_id ? "selected" : ""}>Obra ${esc(work.numero)} — ${esc(work.nome)}</option>`).join("")}</select></label>
        <label>CATEGORIA<select name="categoria" required>${WRITABLE_CATEGORIES.map(([value, label]) => `<option value="${value}" ${value === entry.categoria ? "selected" : ""}>${label}</option>`).join("")}</select></label>
        <label>DATA<input type="date" name="data_lancamento" required value="${esc(entry.data_lancamento || new Date().toISOString().slice(0, 10))}"></label>
        <label>FORNECEDOR / COLABORADOR<input name="entidade_nome" list="management-entities" required maxlength="180" value="${esc(entry.entidade_nome || "")}"><datalist id="management-entities">${entityNames.map(name => `<option value="${esc(name)}"></option>`).join("")}</datalist></label>
        <label>DESCRIÇÃO<input name="descricao" required maxlength="240" value="${esc(entry.descricao || "")}"></label>
        <label>DOCUMENTO<input name="documento" maxlength="120" value="${esc(entry.documento || "")}"></label>
        <label>UN. MEDIDA<input name="unidade_medida" maxlength="30" placeholder="Ex.: un., kg, m²" value="${esc(entry.unidade_medida || "")}"></label>
        <label>QUANTIDADE<input name="quantidade" type="number" min="0" step="any" value="${entry.quantidade ?? ""}"></label>
        <label>VALOR UNITÁRIO (€)<input name="valor_unitario" type="number" min="0" step="0.01" value="${entry.valor_unitario ?? ""}"></label>
        <label>DATA DE PAGAMENTO<input type="date" name="data_pagamento" value="${esc(entry.data_pagamento || "")}"></label>
        <label>VALOR TOTAL (€)<input name="valor" type="number" min="0" step="0.01" required value="${entry.valor ?? ""}"></label>
        <div><button class="primary-button" type="submit">${state.editing ? "GUARDAR ALTERAÇÕES" : "CRIAR LANÇAMENTO"}</button>${state.editing ? '<button class="outline-action" type="button" data-cancel-management-edit>CANCELAR</button>' : ""}</div><p class="form-error"></p>
      </form></details>`;
  }

  function render() {
    const works = availableWorks();
    root.innerHTML = `<section class="panel management-map"><header><div><p class="eyebrow">CONSOLIDADO DA EMPRESA</p><h2>MAPA DE GESTÃO DE OBRAS</h2><p>Consulta comparativa de preços e lançamentos de todas as obras.</p></div><button type="button" class="outline-action" data-refresh-management-map>ATUALIZAR</button></header>
      ${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)} Confirme se executou o SQL deste módulo.</span></div>` : ""}
      ${editor()}
      <form class="management-map-filters" data-management-map-filters>
        <label>OBRA<select name="obra_id"><option value="">Todas as obras</option>${works.map(work => `<option value="${work.id}">Obra ${esc(work.numero)} — ${esc(work.nome)}</option>`).join("")}</select></label>
        <label>CATEGORIA<select name="categoria"><option value="">Todas as categorias</option>${Object.entries(CATEGORY_LABELS).map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select></label>
        <label>DE<input type="date" name="data_inicio"></label><label>ATÉ<input type="date" name="data_fim"></label>
        <label class="management-map-search">FORNECEDOR / COLABORADOR<input name="entidade" placeholder="Pesquisar nome, descrição ou documento"></label>
        <button type="reset" class="outline-action">LIMPAR FILTROS</button>
      </form>
      ${state.loading ? `<div class="fleet-loading">A CARREGAR LANÇAMENTOS…</div>` : renderTable()}
    </section>`;
  }

  async function save(form) {
    if (!canEdit()) return;
    const fields = Object.fromEntries(new FormData(form));
    const button = form.querySelector("[type=submit]"); const error = form.querySelector(".form-error");
    button.disabled = true; error.textContent = "";
    try {
      await request("rpc/fn_guardar_lancamento_gestao_obras", { method: "POST", body: JSON.stringify({
        p_id: fields.id || null, p_obra_id: fields.obra_id, p_categoria: fields.categoria,
        p_data_lancamento: fields.data_lancamento, p_entidade_nome: fields.entidade_nome.trim(),
        p_descricao: fields.descricao.trim(), p_documento: fields.documento.trim() || null,
        p_unidade_medida: fields.unidade_medida.trim() || null,
        p_quantidade: fields.quantidade === "" ? null : Number(fields.quantidade),
        p_valor_unitario: fields.valor_unitario === "" ? null : Number(fields.valor_unitario),
        p_data_pagamento: fields.data_pagamento || null, p_valor: Number(fields.valor),
      }) }, "Não foi possível guardar o lançamento.");
      state.editing = null; state.loaded = false; toast(fields.id ? "Lançamento atualizado." : "Lançamento criado."); await load(true);
    } catch (failure) { error.textContent = failure.message; button.disabled = false; }
  }

  root.addEventListener("input", event => { if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())); });
  root.addEventListener("change", event => { if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())); });
  root.addEventListener("reset", () => setTimeout(() => root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())), 0));
  root.addEventListener("submit", event => { const form = event.target.closest("[data-management-entry-form]"); if (form) { event.preventDefault(); save(form); } });
  root.addEventListener("click", async event => {
    if (event.target.closest("[data-refresh-management-map]")) return load(true).catch(error => toast(error.message, "error"));
    if (event.target.closest("[data-cancel-management-edit]")) { state.editing = null; return render(); }
    const edit = event.target.closest("[data-edit-management-entry]");
    if (edit) { state.editing = state.rows.find(row => row.origem_id === edit.dataset.editManagementEntry) || null; render(); return; }
    const remove = event.target.closest("[data-delete-management-entry]");
    if (remove) {
      const confirmed = confirmAction ? await confirmAction("Apagar este lançamento? A eliminação fica registada na auditoria.", { title: "Apagar lançamento", danger: true, confirmLabel: "APAGAR" }) : false;
      if (!confirmed) return;
      try { await request("rpc/fn_apagar_lancamento_gestao_obras", { method: "POST", body: JSON.stringify({ p_id: remove.dataset.deleteManagementEntry }) }); toast("Lançamento apagado."); state.loaded = false; await load(true); }
      catch (error) { toast(error.message, "error"); }
    }
  });

  function fragment(html) { const template = document.createElement("template"); template.innerHTML = html.trim(); return template.content.firstElementChild; }
  return { show: () => load(), refresh: () => load(true) };
}
