const number = value => Number(value || 0);
const sum = (rows, field) => rows.reduce((total, row) => total + number(row[field]), 0);
const clampPercent = value => Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
const monthKey = value => value ? String(value).slice(0, 7) : "";
const monthLabel = key => new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit" }).format(new Date(`${key}-01T12:00:00`)).toUpperCase();
const safeDate = value => value ? new Date(`${String(value).slice(0, 10)}T12:00:00`) : null;
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);

export function createProductionDashboard(options) {
  const {
    supabase, isSupabaseConfigured, getSession, getWorks, getPendingInvoices,
    getFinanceInvoices, getSuppliers, euro, prettyDate, toast, showView,
  } = options;
  const emptyOverviewState = () => ({
    alerts: [], profile: null, responsibilities: [], phases: [], planning: [], budget: [],
    contracts: [], tees: [], measurements: [], subcontracts: [], consultations: [], warnings: [],
  });
  let overviewState = emptyOverviewState();
  let meetingState = null;

  async function query(path, warningLabel) {
    if (!isSupabaseConfigured) return [];
    const response = await supabase(path);
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      overviewState.warnings.push(`${warningLabel}: ${detail.message || "sem acesso"}`);
      return [];
    }
    return response.json();
  }

  function workExecution(workId, phases = overviewState.phases, planning = overviewState.planning, budget = overviewState.budget) {
    const workPhaseIds = new Set(phases.filter(phase => phase.obra_id === workId).map(phase => phase.id));
    const items = budget.filter(item => workPhaseIds.has(item.fase_id));
    const totalSale = sum(items, "venda_prevista");
    if (!totalSale) return 0;
    const progressByPhase = new Map(planning.map(row => [row.fase_id, number(row.percentual_executado)]));
    return clampPercent(items.reduce((total, item) => {
      const weight = number(item.venda_prevista) / totalSale;
      return total + weight * (progressByPhase.get(item.fase_id) || 0);
    }, 0));
  }

  function deadlinePercent(work) {
    const start = safeDate(work.data_inicio)?.getTime();
    const end = safeDate(work.data_fim_prevista)?.getTime();
    if (!start || !end || end <= start) return 0;
    return clampPercent(((Date.now() - start) / (end - start)) * 100);
  }

  function workFinancialSummary(workId) {
    const contract = overviewState.contracts.find(row => row.obra_id === workId) || {};
    const approvedTees = overviewState.tees.filter(row => row.obra_id === workId && row.estado_aprovacao_cliente === "aprovado");
    const pendingTees = overviewState.tees.filter(row => row.obra_id === workId && row.estado_aprovacao_cliente === "pendente");
    const sale = number(contract.venda_efetiva || contract.venda_inicial);
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const phaseIds = new Set(overviewState.phases.filter(phase => phase.obra_id === workId).map(phase => phase.id));
    const budgetCost = overviewState.budget.filter(item => phaseIds.has(item.fase_id))
      .reduce((total, item) => total + number(item.custo_direto || item.custo_previsto || item.compra_prevista), 0);
    const directCost = number(contract.custo_direto || contract.custo_direto_contratual) || budgetCost;
    const billed = overviewState.measurements.filter(row => row.obra_id === workId)
      .reduce((total, row) => total + number(row.valor_a_faturar), 0);
    const totalSale = sale + approvedTeeSale;
    return {
      sale, directCost, margin: totalSale - directCost - approvedTeeCost,
      billed, unbilled: totalSale - billed, approvedTees, pendingTees,
      subcontracts: overviewState.subcontracts.filter(row => row.obra_id === workId),
      consultations: overviewState.consultations.filter(row => row.obra_id === workId && row.estado === "em_consulta"),
    };
  }

  function overviewWorkSection(work, pendingInvoices, readOnly) {
    const summary = workFinancialSummary(work.id);
    const workInvoices = pendingInvoices.filter(invoice => invoice.obra_id === work.id);
    const progress = workExecution(work.id);
    const deadline = deadlinePercent(work);
    const subcontractStates = summary.subcontracts.reduce((counts, row) => {
      const state = row.estado || "sem_estado";
      counts[state] = (counts[state] || 0) + 1;
      return counts;
    }, {});
    const stateCounters = Object.entries(subcontractStates)
      .map(([state, count]) => `<span>${escapeHtml(state.replace(/_/g, " "))} <b>${count}</b></span>`).join("");
    const invoiceRows = workInvoices.map(invoice => `
      <${readOnly ? "div" : "button"} ${readOnly ? "" : 'data-action-view="invoices"'}>
        <span><strong>${escapeHtml(invoice.numero_doc || "Fatura")}</strong><small>${invoice.data_fatura ? prettyDate.format(safeDate(invoice.data_fatura)) : "SEM DATA"}</small></span>
        <b>${euro.format(number(invoice.valor))}</b><em>${readOnly ? "PENDENTE" : "REVER"}</em>
      </${readOnly ? "div" : "button"}>`).join("");
    return `<article class="panel overview-work-detail">
      <header><div><p class="eyebrow">OBRA ${escapeHtml(work.numero || "—")}</p><h2>${escapeHtml(work.nome || "Obra sem designação")}</h2></div><button data-meeting-work="${work.id}">REUNIÃO SEMANAL →</button></header>
      <div class="overview-work-metrics">
        <div><span>VENDA</span><strong>${euro.format(summary.sale)}</strong></div>
        <div><span>CUSTO DIRETO</span><strong>${euro.format(summary.directCost)}</strong></div>
        <div><span>MARGEM</span><strong>${euro.format(summary.margin)}</strong></div>
        <div><span>FATURADO</span><strong>${euro.format(summary.billed)}</strong><small>POR FATURAR ${euro.format(summary.unbilled)}</small></div>
      </div>
      <div class="overview-work-status">
        <div><span>OBRA EXECUTADA <b>${Math.round(progress)}%</b></span><i><em style="width:${progress}%"></em></i></div>
        <div><span>PRAZO CONSUMIDO <b>${Math.round(deadline)}%</b></span><i><em style="width:${deadline}%"></em></i></div>
      </div>
      <div class="overview-work-columns">
        <section><h3>A MINHA FILA <b>${workInvoices.length}</b></h3><div class="overview-actions compact">${invoiceRows || '<div class="overview-empty">SEM FATURAS PENDENTES</div>'}</div></section>
        <section><h3>TEEs</h3>
          <details><summary>APROVADOS <b>${summary.approvedTees.length}</b><em>${euro.format(sum(summary.approvedTees, "valor"))}</em></summary>${teeList(summary.approvedTees)}</details>
          <details><summary>EM ELABORAÇÃO <b>${summary.pendingTees.length}</b><em>${euro.format(sum(summary.pendingTees, "valor"))}</em></summary>${teeList(summary.pendingTees)}</details>
        </section>
        <section><h3>SUBEMPREITADAS <b>${summary.subcontracts.length + summary.consultations.length}</b></h3>
          <div class="overview-subcontract-counts"><span>ADJUDICADAS <b>${summary.subcontracts.length}</b></span><span>EM CONSULTA <b>${summary.consultations.length}</b></span>${stateCounters}</div>
        </section>
      </div>
    </article>`;
  }

  function renderOverview() {
    const works = getWorks();
    const pendingInvoices = getPendingInvoices();
    const financeInvoices = getFinanceInvoices();
    const activeWorks = works.filter(work => work.situacao === "em_curso");
    const unpaid = financeInvoices.filter(invoice => invoice.estado_aprovacao === "aprovado" && invoice.estado_pagamento === "por_pagar");
    const role = overviewState.profile?.funcao || (isSupabaseConfigured ? "administrativo" : "gerencia");
    document.body.dataset.userRole = role;
    const responsibleWorkIds = new Set(overviewState.responsibilities.map(row => row.obra_id));
    const isProductionRole = ["diretor_obra", "preparador"].includes(role);
    const readOnly = role === "administrativo";
    const canApprove = ["diretor_obra", "preparador", "gerencia"].includes(role);
    const canPay = ["financeiro", "gerencia"].includes(role);
    const scopedWorks = isProductionRole ? activeWorks.filter(work => responsibleWorkIds.has(work.id)) : activeWorks;
    const approvalActions = role === "gerencia" || readOnly
      ? pendingInvoices
      : isProductionRole ? pendingInvoices.filter(invoice => responsibleWorkIds.has(invoice.obra_id)) : [];
    const paymentActions = ["financeiro", "administrativo", "gerencia"].includes(role) ? unpaid : [];
    const actions = [...approvalActions.map(invoice => ({ ...invoice, action: "APROVAR" })), ...paymentActions.map(invoice => ({ ...invoice, action: "PAGAR" }))];
    const suppliers = getSuppliers();
    const consolidated = scopedWorks.reduce((total, work) => {
      const summary = workFinancialSummary(work.id);
      total.sale += summary.sale; total.cost += summary.directCost; total.margin += summary.margin;
      total.billed += summary.billed; total.unbilled += summary.unbilled;
      return total;
    }, { sale: 0, cost: 0, margin: 0, billed: 0, unbilled: 0 });
    const warning = overviewState.warnings.length
      ? `<div class="overview-warning">Alguns dados estão indisponíveis: ${escapeHtml(overviewState.warnings.join(" · "))}</div>` : "";

    document.querySelector("#overview-view").innerHTML = `
      <div class="page-heading">
        <div><p class="eyebrow">PAINEL OPERACIONAL · ${escapeHtml(role.replace(/_/g, " "))}</p><h1>VISÃO GERAL</h1><p>Resumo diário de produção, aprovações e tesouraria.</p></div>
        <div class="overview-today"><span>HOJE</span><strong>${prettyDate.format(new Date())}</strong></div>
      </div>
      ${warning}
      <section class="overview-kpis">
        <article><span>OBRAS EM CURSO</span><strong>${scopedWorks.length}</strong><small>produção ativa</small></article>
        <article><span>FATURAS PENDENTES</span><strong>${actions.length}</strong><small>à espera de ação</small></article>
        <article><span>ALERTAS PENDENTES</span><strong>${overviewState.alerts.length}</strong><small>por resolver</small></article>
        <article class="money"><span>POR PAGAR ESTA SEMANA</span><strong>${euro.format(sum(unpaid, "valor"))}</strong><small>faturas aprovadas</small></article>
      </section>
      ${["financeiro", "administrativo", "gerencia"].includes(role) ? `<section class="panel overview-consolidated">
        <div class="overview-section-head"><div><p class="eyebrow">TODAS AS OBRAS EM CURSO</p><h2>RESUMO FINANCEIRO CONSOLIDADO</h2></div><span>${scopedWorks.length}</span></div>
        <div class="overview-work-metrics"><div><span>VENDA</span><strong>${euro.format(consolidated.sale)}</strong></div><div><span>CUSTO DIRETO</span><strong>${euro.format(consolidated.cost)}</strong></div><div><span>MARGEM</span><strong>${euro.format(consolidated.margin)}</strong></div><div><span>FATURADO</span><strong>${euro.format(consolidated.billed)}</strong><small>POR FATURAR ${euro.format(consolidated.unbilled)}</small></div></div>
      </section>` : ""}
      <section class="overview-grid">
        <article class="panel overview-panel">
          <div class="overview-section-head"><div><p class="eyebrow">PRIORIDADES</p><h2>ALERTAS PENDENTES</h2></div><span>${overviewState.alerts.length}</span></div>
          <div class="overview-alerts">${overviewState.alerts.length ? overviewState.alerts.map(alert => `
            <div><time>${alert.data_gatilho ? prettyDate.format(safeDate(alert.data_gatilho)) : "SEM DATA"}</time>
              <span><strong>${escapeHtml(alert.titulo || alert.tipo || "Alerta")}</strong><small>${escapeHtml(alert.descricao || "")}</small></span>
              <em>${escapeHtml(alert.tipo || "GERAL").replace(/_/g, " ")}</em>
            </div>`).join("") : `<div class="overview-empty">SEM ALERTAS PENDENTES</div>`}</div>
        </article>
        <article class="panel overview-panel">
          <div class="overview-section-head"><div><p class="eyebrow">A MINHA FILA</p><h2>À ESPERA DE AÇÃO</h2></div><span>${actions.length}</span></div>
          <div class="overview-actions">${actions.length ? actions.map(invoice => {
            const work = works.find(item => item.id === invoice.obra_id);
            const supplier = suppliers.find(item => item.id === invoice.fornecedor_id);
            const actionable = !readOnly && ((invoice.action === "PAGAR" && canPay) || (invoice.action === "APROVAR" && canApprove));
            return `<${actionable ? "button" : "div"} ${actionable ? `data-action-view="${invoice.action === "PAGAR" ? "finance" : "invoices"}"` : ""}>
              <span><strong>${escapeHtml(supplier?.nome || invoice.numero_doc || "Fatura")}</strong><small>OBRA ${escapeHtml(work?.numero || "—")} · ${escapeHtml(invoice.numero_doc || "")}</small></span>
              <b>${euro.format(number(invoice.valor))}</b><em>${actionable ? invoice.action : `${invoice.action} · CONSULTA`}</em>
            </${actionable ? "button" : "div"}>`;
          }).join("") : `<div class="overview-empty">NÃO HÁ AÇÕES PENDENTES</div>`}</div>
        </article>
      </section>
      <section class="panel overview-works">
        <div class="overview-section-head"><div><p class="eyebrow">PRODUÇÃO</p><h2>OBRAS EM CURSO</h2></div><span>${scopedWorks.length}</span></div>
        <div class="overview-work-list">${scopedWorks.length ? scopedWorks
          .sort((a, b) => String(a.numero).localeCompare(String(b.numero), "pt", { numeric: true }))
          .map(work => {
            const progress = workExecution(work.id);
            return `<button data-meeting-work="${work.id}">
              <strong>${escapeHtml(work.numero || "—")}</strong>
              <span><b>${escapeHtml(work.nome || "Obra sem designação")}</b><small>${escapeHtml(work.cliente || "")}</small></span>
              <div><i style="width:${progress}%"></i></div><em>${Math.round(progress)}%</em><b>→</b>
            </button>`;
          }).join("") : `<div class="overview-empty">NÃO EXISTEM OBRAS EM CURSO</div>`}</div>
      </section>
      ${["diretor_obra", "preparador", "administrativo", "gerencia"].includes(role)
        ? `<section class="overview-work-sections">${scopedWorks.map(work => overviewWorkSection(work, pendingInvoices, readOnly)).join("")}</section>` : ""}`;
  }

  async function refreshOverview() {
    overviewState = emptyOverviewState();
    if (!isSupabaseConfigured) {
      overviewState.phases = getWorks().flatMap(work => Array.from({ length: 3 }, (_, index) => ({ id: `${work.id}-p${index}`, obra_id: work.id })));
      overviewState.planning = overviewState.phases.map((phase, index) => ({ fase_id: phase.id, percentual_executado: 25 + index * 15 }));
      overviewState.budget = overviewState.phases.map(phase => ({ fase_id: phase.id, venda_prevista: 10000 }));
      renderOverview();
      return;
    }
    const authId = getSession()?.user?.id;
    const [alerts, profiles, phases, planning, budget, contracts, tees, measurements, subcontracts, consultations] = await Promise.all([
      query("alertas?select=*&estado=eq.pendente&order=data_gatilho.asc", "Alertas"),
      authId ? query(`utilizadores?select=id,nome,funcao,auth_user_id&auth_user_id=eq.${encodeURIComponent(authId)}&limit=1`, "Perfil") : [],
      query("fases?select=id,obra_id,descricao,codigo", "Fases"),
      query("planeamento_fases_resumo?select=*", "Planeamento"),
      query("itens_orcamento?select=*", "Orçamento"),
      query("contratos?select=*", "Contratos"),
      query("alteracoes_tee?select=*", "TEEs"),
      query("autos_medicao?select=*", "Autos"),
      query("subempreitadas?select=id,obra_id,estado", "Subempreitadas"),
      query("consultas_subempreitada?select=id,obra_id,fase_id,estado", "Consultas"),
    ]);
    overviewState.alerts = alerts;
    overviewState.profile = profiles[0] || null;
    overviewState.phases = phases;
    overviewState.planning = planning;
    overviewState.budget = budget;
    overviewState.contracts = contracts;
    overviewState.tees = tees;
    overviewState.measurements = measurements;
    overviewState.subcontracts = subcontracts;
    overviewState.consultations = consultations;
    overviewState.responsibilities = overviewState.profile
      ? await query(`obra_responsaveis?select=obra_id,utilizador_id,papel&utilizador_id=eq.${encodeURIComponent(overviewState.profile.id)}`, "Responsabilidades")
      : [];
    renderOverview();
  }

  async function meetingQuery(path, label, warnings) {
    if (!isSupabaseConfigured) return [];
    const response = await supabase(path);
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      warnings.push(`${label}: ${detail.message || "sem acesso"}`);
      return [];
    }
    return response.json();
  }

  function buildMonths(startValue) {
    const start = safeDate(startValue) || new Date();
    const cursor = new Date(start.getFullYear(), start.getMonth(), 1, 12);
    const end = new Date();
    const result = [];
    while (cursor <= end) {
      result.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`);
      cursor.setMonth(cursor.getMonth() + 1);
    }
    return result;
  }

  function renderCashFlow(work, data) {
    const months = buildMonths(work.data_inicio);
    const values = months.map(month => {
      const incoming = data.measurements.filter(row => monthKey(row.mes_referencia) === month).reduce((total, row) => total + number(row.valor_a_faturar), 0);
      const subcontract = data.payments.filter(row => monthKey(row.data_pagamento) === month).reduce((total, row) => total + number(row.valor), 0);
      const labor = data.labor.filter(row => monthKey(row.data) === month).reduce((total, row) => total + number(row.horas) * number(row.valor_hora), 0);
      const site = data.siteExpenses.filter(row => monthKey(row.data_pagamento) === month).reduce((total, row) => total + number(row.valor_total), 0);
      return { month, incoming, outgoing: subcontract + labor + site };
    });
    let balance = 0;
    values.forEach(row => { balance += row.incoming - row.outgoing; row.balance = balance; });
    const ceiling = Math.max(1, ...values.flatMap(row => [row.incoming, row.outgoing]));
    return `<div class="cash-chart">${values.map(row => `
      <div class="cash-month">
        <div class="cash-bars"><i class="in" style="height:${Math.max(2, row.incoming / ceiling * 100)}%"></i><i class="out" style="height:${Math.max(2, row.outgoing / ceiling * 100)}%"></i></div>
        <strong>${monthLabel(row.month)}</strong><small>${euro.format(row.balance)}</small>
      </div>`).join("")}</div>
      <div class="cash-legend"><span><i class="in"></i>ENTRADAS</span><span><i class="out"></i>SAÍDAS</span><strong>SALDO ACUMULADO: ${euro.format(balance)}</strong></div>`;
  }

  function teeList(rows) {
    return rows.length ? `<div class="meeting-detail-list">${rows.map(row => `<div><span><strong>${escapeHtml(row.numero || row.designacao || row.descricao || "TEE")}</strong><small>${escapeHtml(row.descricao || "")}</small></span><b>${euro.format(number(row.valor))}</b></div>`).join("")}</div>`
      : `<div class="overview-empty">SEM REGISTOS</div>`;
  }

  function renderMeeting() {
    const { work, data, warnings } = meetingState;
    const contract = data.contracts[0] || {};
    const approvedTees = data.tees.filter(row => row.estado_aprovacao_cliente === "aprovado");
    const pendingTees = data.tees.filter(row => row.estado_aprovacao_cliente === "pendente");
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const pendingTeeSale = sum(pendingTees, "valor");
    const sale = number(contract.venda_efetiva || contract.venda_inicial);
    const budgetCost = data.budget.reduce((total, row) => total + number(row.custo_direto || row.custo_previsto || row.compra_prevista), 0);
    const directCost = number(contract.custo_direto || contract.custo_direto_contratual) || budgetCost;
    const expectedMargin = sale + approvedTeeSale - directCost - approvedTeeCost;
    const billed = sum(data.measurements, "valor_a_faturar");
    const totalSale = sale + approvedTeeSale;
    const billingPercent = totalSale ? clampPercent(billed / totalSale * 100) : 0;
    const execution = workExecution(work.id, data.phases, data.planning, data.budget);
    const deadline = deadlinePercent(work);
    const paidBySubcontract = new Map();
    data.payments.forEach(row => paidBySubcontract.set(row.subempreitada_id, (paidBySubcontract.get(row.subempreitada_id) || 0) + number(row.valor)));
    const consultationPhaseIds = new Set(data.consultations.map(row => row.fase_id).filter(Boolean));
    const subcontractPhaseIds = new Set(data.subcontracts.map(row => row.fase_id).filter(Boolean));
    const budgetPhaseIds = new Set(data.budget.map(row => row.fase_id));
    const notConsulted = data.phases.filter(phase => budgetPhaseIds.has(phase.id) && !consultationPhaseIds.has(phase.id) && !subcontractPhaseIds.has(phase.id));

    document.querySelector("#meeting-view").innerHTML = `
      <div class="meeting-heading"><button id="meeting-back">← VISÃO GERAL</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · OBRA ${escapeHtml(work.numero)}</p><h1>${escapeHtml(work.nome)}</h1><span>${escapeHtml(work.cliente || "")}</span></div><em class="work-status ${escapeHtml(work.situacao)}">${escapeHtml(String(work.situacao || "").replace(/_/g, " "))}</em></div>
      ${warnings.length ? `<div class="overview-warning">Dados parciais: ${escapeHtml(warnings.join(" · "))}</div>` : ""}
      <section class="meeting-kpis">
        <article><span>VENDA EFETIVA</span><strong>${euro.format(sale)}</strong><small>contrato atual</small></article>
        <article><span>CUSTO DIRETO CONTRATUAL</span><strong>${directCost ? euro.format(directCost) : "—"}</strong><small>sem duplicar mão de obra própria</small></article>
        <article><span>MARGEM PREVISTA</span><strong>${directCost ? euro.format(expectedMargin) : "—"}</strong><small>inclui TEEs aprovados</small></article>
        <article><span>POR FATURAR</span><strong>${euro.format(totalSale - billed)}</strong><small>${Math.round(billingPercent)}% faturado</small></article>
      </section>
      <section class="meeting-two">
        <article class="panel meeting-card"><div class="meeting-title"><span>RESUMO CONTRATUAL</span></div>
          <dl class="meeting-dl"><div><dt>Venda inicial</dt><dd>${euro.format(number(contract.venda_inicial))}</dd></div><div><dt>Venda efetiva</dt><dd>${euro.format(sale)}</dd></div><div><dt>TEEs aprovados</dt><dd>${euro.format(approvedTeeSale)}</dd></div><div><dt>Custo TEEs aprovados</dt><dd>${euro.format(approvedTeeCost)}</dd></div></dl>
          <details><summary>TEEs APROVADOS <b>${approvedTees.length}</b><em>${euro.format(approvedTeeSale)}</em></summary>${teeList(approvedTees)}</details>
          <details><summary>EM ELABORAÇÃO / AGUARDA RESPOSTA <b>${pendingTees.length}</b><em>${euro.format(pendingTeeSale)}</em></summary>${teeList(pendingTees)}</details>
        </article>
        <article class="panel meeting-card"><div class="meeting-title"><span>FATURAÇÃO E PROGRESSO</span></div>
          <div class="meeting-progress"><span>FATURADO <b>${Math.round(billingPercent)}%</b></span><div><i style="width:${billingPercent}%"></i></div><small>${euro.format(billed)} de ${euro.format(totalSale)}</small></div>
          <div class="meeting-progress"><span>OBRA EXECUTADA <b>${Math.round(execution)}%</b></span><div><i style="width:${execution}%"></i></div><small>ponderação financeira das fases</small></div>
          <div class="meeting-progress deadline"><span>PRAZO CONSUMIDO <b>${Math.round(deadline)}%</b></span><div><i style="width:${deadline}%"></i></div><small>${work.data_inicio ? prettyDate.format(safeDate(work.data_inicio)) : "—"} → ${work.data_fim_prevista ? prettyDate.format(safeDate(work.data_fim_prevista)) : "—"}</small></div>
        </article>
      </section>
      <section class="panel meeting-card meeting-subcontracts"><div class="meeting-title"><span>SUBEMPREITADAS</span></div>
        <div class="meeting-tabs">
          <details open><summary>ADJUDICADAS <b>${data.subcontracts.length}</b></summary><div class="meeting-table">${data.subcontracts.map(row => {
            const paid = paidBySubcontract.get(row.id) || 0;
            return `<div><span><strong>${escapeHtml(row.especialidade || "Especialidade")}</strong><small>${escapeHtml(getSuppliers().find(item => item.id === row.fornecedor_id)?.nome || "Fornecedor")}</small></span><b>${euro.format(number(row.valor_adjudicado))}</b><em>PAGO ${euro.format(paid)}</em><em>POR PAGAR ${euro.format(number(row.valor_adjudicado) - paid)}</em><i>${escapeHtml(row.estado || "—")}</i></div>`;
          }).join("") || `<div class="overview-empty">SEM ADJUDICAÇÕES</div>`}</div></details>
          <details><summary>EM CONSULTA <b>${data.consultations.filter(row => row.estado === "em_consulta").length}</b></summary><div class="meeting-detail-list">${data.consultations.filter(row => row.estado === "em_consulta").map(row => `<div><span><strong>${escapeHtml(row.especialidade || row.designacao || "Consulta")}</strong></span><b>EM CONSULTA</b></div>`).join("") || `<div class="overview-empty">SEM CONSULTAS</div>`}</div></details>
          <details><summary>NÃO CONSULTADAS <b>${notConsulted.length}</b></summary><div class="meeting-detail-list">${notConsulted.map(phase => `<div><span><strong>${escapeHtml(phase.codigo || "")} · ${escapeHtml(phase.descricao || "Fase")}</strong></span><b>NÃO CONSULTADA</b></div>`).join("") || `<div class="overview-empty">TODAS AS FASES FORAM TRATADAS</div>`}</div></details>
        </div>
      </section>
      <section class="panel meeting-card"><div class="meeting-title"><span>CASH FLOW MENSAL · REAL</span><small>Entradas, saídas e saldo acumulado</small></div>${renderCashFlow(work, data)}</section>
      <section class="panel meeting-card"><div class="meeting-title"><span>PLANEAMENTO DE FASES</span><small>${data.phases.length} fases</small></div>
        <div class="phase-plan">${data.phases.sort((a, b) => String(a.codigo || a.numero).localeCompare(String(b.codigo || b.numero), "pt", { numeric: true })).map(phase => {
          const plan = data.planning.find(row => row.fase_id === phase.id) || {};
          const progress = clampPercent(number(plan.percentual_executado));
          return `<div><strong>${escapeHtml(phase.codigo || phase.numero || "—")}</strong><span><b>${escapeHtml(phase.descricao || "Fase")}</b><small>${plan.data_inicio_prevista ? prettyDate.format(safeDate(plan.data_inicio_prevista)) : "—"} → ${plan.data_fim_prevista ? prettyDate.format(safeDate(plan.data_fim_prevista)) : "—"}</small></span><div><i style="width:${progress}%"></i></div><em>${Math.round(progress)}%</em></div>`;
        }).join("") || `<div class="overview-empty">SEM PLANEAMENTO DISPONÍVEL</div>`}</div>
      </section>`;
    document.querySelector("#meeting-back").addEventListener("click", () => showView("overview"));
  }

  async function openMeeting(workId) {
    const work = getWorks().find(item => item.id === workId);
    if (!work) return;
    showView("meeting");
    document.querySelector("#meeting-view").innerHTML = `<div class="meeting-loading">A CARREGAR REUNIÃO DA OBRA ${escapeHtml(work.numero)}…</div>`;
    const encoded = encodeURIComponent(workId);
    const warnings = [];
    const [baseSubcontracts, phases] = await Promise.all([
      meetingQuery(`subempreitadas?select=*&obra_id=eq.${encoded}`, "Subempreitadas", warnings),
      meetingQuery(`fases?select=*&obra_id=eq.${encoded}`, "Fases", warnings),
    ]);
    const subcontractIds = baseSubcontracts.map(row => row.id);
    const phaseIds = phases.map(row => row.id);
    const [
      contracts, tees, measurements, planning, budget, consultations,
      payments, labor, siteExpenses,
    ] = await Promise.all([
      meetingQuery(`contratos?select=*&obra_id=eq.${encoded}&limit=1`, "Contrato", warnings),
      meetingQuery(`alteracoes_tee?select=*&obra_id=eq.${encoded}`, "TEEs", warnings),
      meetingQuery(`autos_medicao?select=*&obra_id=eq.${encoded}`, "Autos", warnings),
      phaseIds.length ? meetingQuery(`planeamento_fases_resumo?select=*&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})`, "Planeamento", warnings) : [],
      phaseIds.length ? meetingQuery(`itens_orcamento?select=*&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})`, "Orçamento", warnings) : [],
      meetingQuery(`consultas_subempreitada?select=*&obra_id=eq.${encoded}`, "Consultas", warnings),
      subcontractIds.length ? meetingQuery(`pagamentos_subempreitada?select=*&subempreitada_id=in.(${subcontractIds.map(encodeURIComponent).join(",")})`, "Pagamentos", warnings) : [],
      meetingQuery(`lancamentos_mao_obra?select=*&obra_id=eq.${encoded}`, "Mão de obra", warnings),
      meetingQuery(`despesas_estaleiro?select=*&obra_id=eq.${encoded}`, "Estaleiro", warnings),
    ]);
    meetingState = { work, warnings, data: { contracts, tees, measurements, phases, planning, budget, subcontracts: baseSubcontracts, consultations, payments, labor, siteExpenses } };
    renderMeeting();
  }

  function bind() {
    document.querySelector("#overview-view").addEventListener("click", event => {
      const meetingButton = event.target.closest("[data-meeting-work]");
      if (meetingButton) return openMeeting(meetingButton.dataset.meetingWork);
      const actionButton = event.target.closest("[data-action-view]");
      if (actionButton) showView(actionButton.dataset.actionView);
    });
  }

  return { bind, refreshOverview, openMeeting };
}
