const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const TRUST_STATES = {
  ativo: { label: "ATIVO", tone: "positive" },
  recomendado: { label: "RECOMENDADO", tone: "positive" },
  nao_avaliado: { label: "NÃO AVALIADO", tone: "neutral" },
  nao_recomendado: { label: "NÃO RECOMENDADO", tone: "negative" },
  bloqueado: { label: "BLOQUEADO", tone: "negative" },
  inativo: { label: "INATIVO", tone: "inactive" },
};

const SCORE_FIELDS = [
  ["qualidade", "QUALIDADE"],
  ["cumprimento_prazo", "PRAZO"],
  ["seguranca", "SEGURANÇA"],
  ["comunicacao", "COMUNICAÇÃO"],
];

const normalizeState = value => String(value || "nao_avaliado")
  .trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .replaceAll("-", "_").replaceAll(" ", "_");

const isoDate = value => value ? String(value).slice(0, 10) : "";

const average = values => {
  const valid = values
    .filter(value => value !== null && value !== undefined && value !== "")
    .map(Number).filter(Number.isFinite);
  return valid.length ? valid.reduce((sum, value) => sum + value, 0) / valid.length : null;
};

const formatScore = value => Number.isFinite(value) ? value.toFixed(1).replace(".", ",") : "—";

export function createSubcontractorsModule({
  supabase,
  isSupabaseConfigured,
  getWorks,
  getSuppliers,
  getSubcontracts,
  euro,
  toast,
}) {
  const state = {
    suppliers: [],
    allSuppliers: [],
    subcontracts: [],
    evaluations: [],
    priceRows: [],
    priceError: "",
    priceSearch: "",
    priceSupplier: "all",
    priceLoading: false,
    activeTab: "directory",
    search: "",
    trustFilter: "all",
    sort: "rating",
    selectedSupplierId: null,
    loaded: false,
  };
  let priceSearchTimer = null;
  const content = document.querySelector("#subcontractors-content");

  function supplierName(id) {
    return state.allSuppliers.find(item => item.id === id)?.nome
      || state.suppliers.find(item => item.id === id)?.nome
      || "Fornecedor não identificado";
  }

  function workName(id) {
    const work = getWorks().find(item => item.id === id);
    return work ? `OBRA ${work.numero || "—"} · ${work.nome || "Sem nome"}` : "OBRA NÃO IDENTIFICADA";
  }

  function supplierContacts(supplier) {
    const contactName = supplier.contacto || supplier.nome_contacto ||
      supplier.pessoa_contacto || supplier.responsavel || "";
    const phone = supplier.telefone || supplier.telemovel || supplier.telefone_contacto || "";
    const email = supplier.email || supplier.email_contacto || "";
    return [...new Set([contactName, phone, email].map(value => String(value || "").trim()).filter(Boolean))];
  }

  function supplierMetrics(supplier) {
    const history = state.subcontracts.filter(item => item.fornecedor_id === supplier.id);
    const evaluations = state.evaluations.filter(item => item.fornecedor_id === supplier.id);
    const workCount = new Set(history.map(item => item.obra_id).filter(Boolean)).size;
    const total = history.reduce((sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
    const criteria = Object.fromEntries(SCORE_FIELDS.map(([field]) => [
      field,
      average(evaluations.map(item => item[field])),
    ]));
    const rating = average(evaluations.flatMap(item =>
      SCORE_FIELDS.map(([field]) => item[field])));
    return { history, evaluations, workCount, total, criteria, rating };
  }

  function directoryRows() {
    const needle = state.search.trim().toLocaleLowerCase("pt-PT");
    return state.suppliers.map(supplier => ({
      supplier,
      trust: normalizeState(supplier.estado_confianca),
      metrics: supplierMetrics(supplier),
      contacts: supplierContacts(supplier),
    })).filter(row => {
      const matchesState = state.trustFilter === "all" || row.trust === state.trustFilter;
      const searchable = [row.supplier.nome, ...row.contacts].join(" ").toLocaleLowerCase("pt-PT");
      return matchesState && (!needle || searchable.includes(needle));
    }).sort((left, right) => {
      if (state.sort === "rating") {
        const ratingDifference = (right.metrics.rating ?? -1) - (left.metrics.rating ?? -1);
        if (ratingDifference) return ratingDifference;
      }
      if (state.sort === "works") {
        const workDifference = right.metrics.workCount - left.metrics.workCount;
        if (workDifference) return workDifference;
      }
      if (state.sort === "value") {
        const valueDifference = right.metrics.total - left.metrics.total;
        if (valueDifference) return valueDifference;
      }
      return String(left.supplier.nome || "").localeCompare(
        String(right.supplier.nome || ""), "pt-PT", { sensitivity: "base" });
    });
  }

  function trustBadge(value) {
    const normalized = normalizeState(value);
    const config = TRUST_STATES[normalized] || {
      label: String(value || "NÃO AVALIADO").replaceAll("_", " ").toUpperCase(),
      tone: "neutral",
    };
    return `<span class="supplier-trust ${config.tone}">${escapeHtml(config.label)}</span>`;
  }

  function renderRating(metrics, compact = false) {
    if (!metrics.evaluations.length) {
      return `<div class="supplier-rating empty"><strong>—</strong><span>SEM AVALIAÇÕES</span></div>`;
    }
    return `<div class="supplier-rating">
      <strong>${formatScore(metrics.rating)}<small>/5</small></strong>
      <span>${metrics.evaluations.length} AVALIA${metrics.evaluations.length === 1 ? "ÇÃO" : "ÇÕES"}</span>
      ${compact ? "" : `<div>${SCORE_FIELDS.map(([field, label]) =>
        `<em title="${label}">${label.slice(0, 3)} ${formatScore(metrics.criteria[field])}</em>`
      ).join("")}</div>`}
    </div>`;
  }

  function renderDirectoryCard(row) {
    const selected = state.selectedSupplierId === row.supplier.id;
    return `<button type="button" class="supplier-directory-row ${selected ? "selected" : ""}"
      data-supplier-detail="${row.supplier.id}" aria-expanded="${selected}">
      <div class="supplier-identity">
        <span class="supplier-avatar">${escapeHtml(String(row.supplier.nome || "?")
          .split(/\s+/).slice(0, 2).map(part => part[0]).join("").toUpperCase())}</span>
        <div><strong>${escapeHtml(row.supplier.nome || "Fornecedor sem nome")}</strong>
          ${trustBadge(row.supplier.estado_confianca)}
          <small>${row.contacts.length
            ? row.contacts.map(escapeHtml).join(" · ")
            : "CONTACTO NÃO INDICADO"}</small></div>
      </div>
      <div class="supplier-stat"><span>OBRAS</span><strong>${row.metrics.workCount}</strong></div>
      <div class="supplier-stat"><span>ADJUDICADO HISTÓRICO</span><strong>${euro.format(row.metrics.total)}</strong></div>
      ${renderRating(row.metrics)}
      <span class="supplier-open-arrow">${selected ? "↑" : "→"}</span>
    </button>`;
  }

  function renderSubcontractHistory(item) {
    return `<article class="supplier-history-row">
      <div><span>${escapeHtml(workName(item.obra_id))}</span>
        <strong>${escapeHtml(item.especialidade || "Especialidade não indicada")}</strong></div>
      <div><span>VALOR ADJUDICADO</span><strong>${euro.format(Number(item.valor_adjudicado || 0))}</strong></div>
      <div><span>DATAS PREVISTAS</span><strong>${isoDate(item.data_inicio_prevista) || "—"} → ${isoDate(item.data_fim_prevista) || "—"}</strong></div>
      <span class="supplier-work-state ${escapeHtml(item.estado || "")}">${escapeHtml(
        String(item.estado || "sem_estado").replaceAll("_", " ").toUpperCase())}</span>
    </article>`;
  }

  function renderEvaluation(item) {
    return `<article class="supplier-evaluation-card">
      <div class="supplier-evaluation-head"><div><span>${escapeHtml(workName(item.obra_id))}</span>
        <strong>${isoDate(item.criado_em) || "DATA NÃO INDICADA"}</strong></div>
        <b>${formatScore(average(SCORE_FIELDS.map(([field]) => item[field])))}<small>/5</small></b></div>
      <div class="supplier-score-grid">${SCORE_FIELDS.map(([field, label]) =>
        `<div><span>${label}</span><strong>${formatScore(average([item[field]]))}</strong></div>`
      ).join("")}</div>
      ${item.observacoes
        ? `<p>${escapeHtml(item.observacoes)}</p>`
        : `<p class="empty-note">SEM OBSERVAÇÕES</p>`}
    </article>`;
  }

  function renderDetail() {
    const supplier = state.suppliers.find(item => item.id === state.selectedSupplierId);
    if (!supplier) return "";
    const metrics = supplierMetrics(supplier);
    const history = metrics.history.slice().sort((a, b) =>
      String(b.data_inicio_prevista || b.criado_em || "").localeCompare(
        String(a.data_inicio_prevista || a.criado_em || "")));
    const evaluations = metrics.evaluations.slice().sort((a, b) =>
      String(b.criado_em || "").localeCompare(String(a.criado_em || "")));
    const contacts = supplierContacts(supplier);
    return `<section class="supplier-detail">
      <div class="supplier-detail-head">
        <div><p class="eyebrow">HISTÓRICO COMPLETO</p><h2>${escapeHtml(supplier.nome || "Subempreiteiro")}</h2>
          <div class="supplier-detail-meta">${trustBadge(supplier.estado_confianca)}
            <span>${contacts.length ? contacts.map(escapeHtml).join(" · ") : "CONTACTO NÃO INDICADO"}</span></div></div>
        <button type="button" data-close-supplier-detail>FECHAR ×</button>
      </div>
      <div class="supplier-detail-kpis">
        <div><span>OBRAS</span><strong>${metrics.workCount}</strong></div>
        <div><span>SUBEMPREITADAS</span><strong>${metrics.history.length}</strong></div>
        <div><span>ADJUDICADO HISTÓRICO</span><strong>${euro.format(metrics.total)}</strong></div>
        <div>${renderRating(metrics, true)}</div>
      </div>
      <div class="supplier-detail-columns">
        <section><div class="supplier-subsection-title"><div><p class="eyebrow">EXECUÇÃO</p>
          <h3>HISTÓRICO DE SUBEMPREITADAS</h3></div><span>${history.length}</span></div>
          <div class="supplier-history-list">${history.length
            ? history.map(renderSubcontractHistory).join("")
            : `<div class="subcontract-empty">SEM SUBEMPREITADAS REGISTADAS</div>`}</div>
        </section>
        <section><div class="supplier-subsection-title"><div><p class="eyebrow">QUALIDADE</p>
          <h3>AVALIAÇÕES RECEBIDAS</h3></div><span>${evaluations.length}</span></div>
          <div class="supplier-evaluation-list">${evaluations.length
            ? evaluations.map(renderEvaluation).join("")
            : `<div class="subcontract-empty">AINDA NÃO EXISTEM AVALIAÇÕES</div>`}</div>
        </section>
      </div>
    </section>`;
  }

  function renderModuleTabs() {
    return `<nav class="subcontractor-module-tabs">
      <button type="button" data-subcontractor-tab="directory" class="${state.activeTab === "directory" ? "active" : ""}">DIRETÓRIO GERAL</button>
      <button type="button" data-subcontractor-tab="prices" class="${state.activeTab === "prices" ? "active" : ""}">COMPARATIVO DE PREÇOS</button>
    </nav>`;
  }

  function filteredPriceRows() {
    return state.priceRows.filter(row => {
      const matchesSupplier = state.priceSupplier === "all" || row.fornecedor_id === state.priceSupplier;
      return matchesSupplier;
    }).sort((a, b) => supplierName(a.fornecedor_id).localeCompare(supplierName(b.fornecedor_id), "pt-PT")
      || String(b.data || "").localeCompare(String(a.data || "")));
  }

  function renderPriceRows(rows) {
    if (state.priceLoading) return `<tr><td colspan="6"><div class="subcontract-empty">A PESQUISAR PREÇOS…</div></td></tr>`;
    if (!state.priceSearch.trim()) return `<tr><td colspan="6"><div class="subcontract-empty">ESCREVA UMA PALAVRA-CHAVE PARA PESQUISAR</div></td></tr>`;
    if (!rows.length) return `<tr><td colspan="6"><div class="subcontract-empty">SEM PREÇOS PARA A PALAVRA PESQUISADA</div></td></tr>`;
    let previousSupplier = null;
    return rows.map(row => {
      const supplier = supplierName(row.fornecedor_id);
      const group = supplier !== previousSupplier
        ? `<tr class="price-supplier-group"><td colspan="6">${escapeHtml(supplier)}</td></tr>` : "";
      previousSupplier = supplier;
      return `${group}<tr>
        <td><strong>${escapeHtml(supplier)}</strong></td>
        <td>${escapeHtml(row.artigo || "Sem designação")}</td>
        <td>${escapeHtml(row.unidade || "—")}</td>
        <td><strong>${euro.format(Number(row.preco_unitario || 0))}</strong></td>
        <td>${escapeHtml(isoDate(row.data) || "—")}</td>
        <td><span class="price-origin ${row.origem === "Material" ? "material" : "estaleiro"}">${escapeHtml(row.origem)}</span></td>
      </tr>`;
    }).join("");
  }

  function renderPriceComparison() {
    const rows = filteredPriceRows();
    const supplierIds = [...new Set(state.priceRows.map(item => item.fornecedor_id).filter(Boolean))]
      .sort((a, b) => supplierName(a).localeCompare(supplierName(b), "pt-PT"));
    return `${renderModuleTabs()}
      <section class="price-comparison-panel">
        <div class="price-comparison-head"><div><p class="eyebrow">HISTÓRICO DE COMPRAS</p><h2>COMPARATIVO DE PREÇOS</h2>
          <span>Pesquisa parcial por designação em faturas de material e despesas de estaleiro, agrupada por fornecedor.</span></div>
          <strong>${rows.length} REGISTOS</strong></div>
        ${state.priceError ? `<div class="subcontract-price-warning">${escapeHtml(state.priceError)}</div>` : ""}
        <div class="price-comparison-filters">
          <label class="supplier-search"><span>⌕</span><input type="search" data-price-search value="${escapeHtml(state.priceSearch)}" placeholder="Pesquisar artigo ou designação…"></label>
          <label><span>FORNECEDOR</span><div class="select-wrap"><select data-price-supplier><option value="all">Todos os fornecedores</option>
            ${supplierIds.map(id => `<option value="${escapeHtml(id)}" ${state.priceSupplier === id ? "selected" : ""}>${escapeHtml(supplierName(id))}</option>`).join("")}
          </select><b>⌄</b></div></label>
        </div>
        <div class="price-comparison-table-wrap"><table class="price-comparison-table">
          <thead><tr><th>FORNECEDOR</th><th>ARTIGO</th><th>UNIDADE</th><th>PREÇO UNITÁRIO</th><th>DATA</th><th>ORIGEM</th></tr></thead>
          <tbody>${renderPriceRows(rows)}</tbody>
        </table></div>
      </section>`;
  }

  function render() {
    if (!state.loaded) {
      content.innerHTML = `<div class="empty-state"><strong>A CARREGAR DIRETÓRIO…</strong></div>`;
      return;
    }
    if (state.activeTab === "prices") {
      content.innerHTML = renderPriceComparison();
      return;
    }
    const rows = directoryRows();
    const allMetrics = state.suppliers.map(supplier => supplierMetrics(supplier));
    const evaluated = allMetrics.filter(item => item.evaluations.length).length;
    const recommended = state.suppliers.filter(item =>
      ["ativo", "recomendado"].includes(normalizeState(item.estado_confianca))).length;
    const supplierIds = new Set(state.suppliers.map(item => item.id));
    const totalAdjudicated = state.subcontracts.filter(
      item => supplierIds.has(item.fornecedor_id)).reduce(
      (sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
    const trustOptions = [...new Set(state.suppliers.map(item =>
      normalizeState(item.estado_confianca)))].sort();

    content.innerHTML = `${renderModuleTabs()}
      <section class="subcontractors-kpis">
        <article><span>SUBEMPREITEIROS</span><strong>${state.suppliers.length}</strong></article>
        <article><span>ATIVOS / RECOMENDADOS</span><strong>${recommended}</strong></article>
        <article><span>COM AVALIAÇÃO</span><strong>${evaluated}</strong></article>
        <article><span>ADJUDICADO HISTÓRICO</span><strong>${euro.format(totalAdjudicated)}</strong></article>
      </section>
      <section class="supplier-directory-panel">
        <div class="supplier-directory-toolbar">
          <label class="supplier-search"><span>⌕</span><input type="search" data-supplier-search
            value="${escapeHtml(state.search)}" placeholder="Pesquisar nome, contacto, telefone ou email…"></label>
          <label><span>ESTADO DE CONFIANÇA</span><div class="select-wrap"><select data-supplier-trust>
            <option value="all">Todos os estados</option>
            ${trustOptions.map(value => {
              const config = TRUST_STATES[value];
              return `<option value="${escapeHtml(value)}" ${state.trustFilter === value ? "selected" : ""}>${
                escapeHtml(config?.label || value.replaceAll("_", " ").toUpperCase())}</option>`;
            }).join("")}
          </select><b>⌄</b></div></label>
          <label><span>ORDENAR</span><div class="select-wrap"><select data-supplier-sort>
            <option value="rating" ${state.sort === "rating" ? "selected" : ""}>Melhor avaliação</option>
            <option value="name" ${state.sort === "name" ? "selected" : ""}>Nome A–Z</option>
            <option value="works" ${state.sort === "works" ? "selected" : ""}>Mais obras</option>
            <option value="value" ${state.sort === "value" ? "selected" : ""}>Maior valor adjudicado</option>
          </select><b>⌄</b></div></label>
        </div>
        <div class="supplier-directory-heading">
          <div><p class="eyebrow">BASE DE FORNECEDORES</p><h2>DIRETÓRIO GERAL</h2></div>
          <span>${rows.length} DE ${state.suppliers.length}</span>
        </div>
        <div class="supplier-directory-list">${rows.length
          ? rows.map(renderDirectoryCard).join("")
          : `<div class="subcontract-empty">NENHUM SUBEMPREITEIRO CORRESPONDE AOS FILTROS</div>`}</div>
      </section>
      ${renderDetail()}`;
  }

  async function query(path) {
    const response = await supabase(path);
    if (!response.ok) throw new Error(await response.text());
    return response.json();
  }

  async function loadPriceRows(searchTerm) {
    const term = String(searchTerm || "").trim();
    if (!term || !isSupabaseConfigured) {
      state.priceRows = [];
      state.priceError = "";
      state.priceLoading = false;
      render();
      return;
    }
    state.priceLoading = true;
    state.priceError = "";
    render();
    const pattern = encodeURIComponent(`*${term.replace(/[*,]/g, " ")}*`);
    const results = await Promise.allSettled([
      query("faturas?select=id,fornecedor_id,data_fatura,tipo_origem&tipo_origem=eq.material"),
      query(`faturas_itens?select=*&designacao=ilike.${pattern}`),
      query(`despesas_estaleiro?select=*&designacao=ilike.${pattern}`),
    ]);
    if (term !== state.priceSearch.trim()) return;
    const [invoiceResult, itemResult, expenseResult] = results;
    const materialInvoices = invoiceResult.status === "fulfilled" ? invoiceResult.value : [];
    const invoiceItems = itemResult.status === "fulfilled" ? itemResult.value : [];
    const expenses = expenseResult.status === "fulfilled" ? expenseResult.value : [];
    const invoiceById = new Map(materialInvoices.map(item => [item.id, item]));
    state.priceRows = invoiceItems.map(item => {
      const invoice = invoiceById.get(item.fatura_id) || {};
      return {
        fornecedor_id: invoice.fornecedor_id || item.fornecedor_id,
        artigo: item.designacao,
        unidade: item.unidade,
        preco_unitario: item.valor_unitario ?? item.preco_unitario,
        data: invoice.data_fatura || item.data || item.criado_em,
        origem: "Material",
      };
    }).filter(item => item.artigo && Number.isFinite(Number(item.preco_unitario)))
      .concat(expenses.map(item => ({
        fornecedor_id: item.fornecedor_id,
        artigo: item.designacao,
        unidade: item.unidade,
        preco_unitario: item.preco_unitario ?? item.valor_unitario ?? (
          Number(item.quantidade) ? Number(item.valor_total || item.valor) / Number(item.quantidade) : item.valor_total || item.valor
        ),
        data: item.data_pagamento || item.data || item.criado_em,
        origem: "Estaleiro",
      })).filter(item => item.artigo && Number.isFinite(Number(item.preco_unitario))));
    state.priceError = results.some(result => result.status === "rejected")
      ? "Algumas origens ainda não estão disponíveis para esta pesquisa."
      : "";
    state.priceLoading = false;
    render();
  }

  async function load() {
    state.loaded = false;
    state.priceLoading = false;
    render();
    if (!isSupabaseConfigured) {
      state.suppliers = getSuppliers().map(item => ({
        ...item,
        tipo_entidade: "subempreiteiro",
        estado_confianca: item.estado_confianca || "nao_avaliado",
      }));
      state.allSuppliers = getSuppliers();
      state.subcontracts = typeof getSubcontracts === "function" ? getSubcontracts() : [];
      state.evaluations = [];
      state.priceRows = [];
      state.loaded = true;
      render();
      return;
    }
    try {
      [state.suppliers, state.subcontracts, state.evaluations] = await Promise.all([
        query("fornecedores?select=*&tipo_entidade=eq.subempreiteiro&order=nome"),
        query("subempreitadas?select=*&order=criado_em.desc"),
        query("avaliacoes_subempreiteiro?select=*&order=criado_em.desc"),
      ]);
      state.allSuppliers = getSuppliers();
      state.priceRows = [];
      state.priceError = "";
    } catch (error) {
      state.suppliers = [];
      state.subcontracts = [];
      state.evaluations = [];
      state.priceRows = [];
      state.priceLoading = false;
      state.priceError = "Não foi possível carregar o comparativo de preços.";
      toast(`Não foi possível carregar o diretório: ${error.message}`, "error");
    }
    state.loaded = true;
    render();
  }

  content.addEventListener("input", event => {
    if (event.target.matches("[data-price-search]")) {
      state.priceSearch = event.target.value;
      state.priceRows = [];
      state.priceError = "";
      state.priceLoading = Boolean(state.priceSearch.trim());
      render();
      const search = content.querySelector("[data-price-search]");
      search?.focus();
      search?.setSelectionRange(state.priceSearch.length, state.priceSearch.length);
      clearTimeout(priceSearchTimer);
      priceSearchTimer = setTimeout(() => loadPriceRows(state.priceSearch), 350);
      return;
    }
    if (!event.target.matches("[data-supplier-search]")) return;
    state.search = event.target.value;
    state.selectedSupplierId = null;
    render();
    const search = content.querySelector("[data-supplier-search]");
    search?.focus();
    search?.setSelectionRange(state.search.length, state.search.length);
  });

  content.addEventListener("change", event => {
    if (event.target.matches("[data-price-supplier]")) {
      state.priceSupplier = event.target.value;
      render();
      return;
    }
    if (event.target.matches("[data-supplier-trust]")) {
      state.trustFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-supplier-sort]")) {
      state.sort = event.target.value;
      render();
    }
  });

  content.addEventListener("click", event => {
    const tab = event.target.closest("[data-subcontractor-tab]");
    if (tab) {
      state.activeTab = tab.dataset.subcontractorTab;
      state.selectedSupplierId = null;
      render();
      return;
    }
    const row = event.target.closest("[data-supplier-detail]");
    if (row) {
      state.selectedSupplierId = row.dataset.supplierDetail;
      render();
      content.querySelector(".supplier-detail")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    if (event.target.closest("[data-close-supplier-detail]")) {
      state.selectedSupplierId = null;
      render();
    }
  });

  return { show: load, refresh: load };
}
