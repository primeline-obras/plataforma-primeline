const number = value => Number(value || 0);
const sum = (rows, field) => rows.reduce((total, row) => total + number(row[field]), 0);
const clampPercent = value => Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
const monthKey = value => value ? String(value).slice(0, 7) : "";
const monthLabel = key => new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit" }).format(new Date(`${key}-01T12:00:00`)).toUpperCase();
const safeDate = value => value instanceof Date ? new Date(value.getTime()) : value ? new Date(`${String(value).slice(0, 10)}T12:00:00`) : null;
const plannedStart = plan => plan?.data_inicio_prevista || plan?.data_inicio_planeada || plan?.inicio_previsto || plan?.inicio_planeado || plan?.data_inicio || plan?.inicio || null;
const plannedEnd = plan => plan?.data_fim_prevista || plan?.data_fim_planeada || plan?.fim_previsto || plan?.fim_planeado || plan?.data_fim || plan?.fim || null;
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const measurementBilledValue = row => number(row?.valor_a_faturar);
const totalClientBilling = (contract, measurements) =>
  number(contract?.valor_adiantamento) + measurements.reduce((total, row) => total + measurementBilledValue(row), 0);
const budgetItemCost = row => number(
  row?.custo_direto ?? row?.custo_previsto ?? row?.compra_prevista
  ?? row?.preco_custo ?? row?.valor_custo ?? row?.custo_total
);
const effectiveDirectCost = (items, effectiveSale) => {
  const budgetSale = sum(items, "venda_prevista");
  const budgetCost = items.reduce((total, item) => total + budgetItemCost(item), 0);
  return budgetSale && effectiveSale ? budgetCost * effectiveSale / budgetSale : budgetCost;
};
const selectCurrentContract = contracts => [...contracts].sort((a, b) => {
  const completeness = contract => ["venda_contratual_inicial", "venda_contratual_efetiva", "valor_adiantamento"]
    .reduce((score, field) => score + (contract?.[field] != null ? 1 : 0), 0);
  return completeness(b) - completeness(a)
    || number(b.venda_contratual_inicial) - number(a.venda_contratual_inicial)
    || number(b.venda_contratual_efetiva) - number(a.venda_contratual_efetiva);
})[0] || {};

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
  let meetingReturnView = "overview";

  function alertSeverity(alert) {
    const text = `${alert.tipo || ""} ${alert.titulo || ""} ${alert.descricao || ""}`.toLocaleLowerCase("pt-PT");
    const trigger = safeDate(alert.data_gatilho);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    if (/(urgente|atrasad|vencid|crític|critic|bloque)/.test(text) || (trigger && trigger < today)) return "urgent";
    const attentionLimit = new Date(today);
    attentionLimit.setDate(attentionLimit.getDate() + 7);
    if (/(atenção|atencao|aviso|alerta|priorit)/.test(text) || (trigger && trigger <= attentionLimit)) return "attention";
    return "pending";
  }

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
    const contract = selectCurrentContract(overviewState.contracts.filter(row => row.obra_id === workId));
    const approvedTees = overviewState.tees.filter(row => row.obra_id === workId && row.estado_aprovacao_cliente === "aprovado");
    const pendingTees = overviewState.tees.filter(row => row.obra_id === workId && row.estado_aprovacao_cliente === "pendente");
    const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const phaseIds = new Set(overviewState.phases.filter(phase => phase.obra_id === workId).map(phase => phase.id));
    const workBudget = overviewState.budget.filter(item => phaseIds.has(item.fase_id));
    const directCost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial)
      || effectiveDirectCost(workBudget, sale);
    const billed = totalClientBilling(contract, overviewState.measurements.filter(row => row.obra_id === workId));
    const totalSale = sale + approvedTeeSale;
    const updatedDirectCost = directCost + approvedTeeCost;
    return {
      sale: totalSale, directCost: updatedDirectCost, margin: totalSale - updatedDirectCost,
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
            <div class="alert-${alertSeverity(alert)}"><time>${alert.data_gatilho ? prettyDate.format(safeDate(alert.data_gatilho)) : "SEM DATA"}</time>
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
      query("contratos?select=id,obra_id,venda_contratual_inicial,custo_direto_inicial,venda_contratual_efetiva,custo_direto_efetivo,valor_adiantamento,percentual_retencao_garantia,data_assinatura,atualizado_em", "Contratos"),
      query("alteracoes_tee?select=*", "TEEs"),
      query("autos_medicao?select=id,obra_id,mes_referencia,numero_auto,tipo,data_medicao,estado,valor_bruto_medido,valor_retencao_garantia,valor_deduzido_adiantamento,valor_a_faturar", "Autos"),
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

  function buildMonths(startValue, endValue = new Date()) {
    const start = safeDate(startValue) || new Date();
    const cursor = new Date(start.getFullYear(), start.getMonth(), 1, 12);
    const endDate = safeDate(endValue) || new Date();
    const end = new Date(endDate.getFullYear(), endDate.getMonth(), 1, 12);
    const result = [];
    while (cursor <= end) {
      result.push(`${cursor.getFullYear()}-${String(cursor.getMonth() + 1).padStart(2, "0")}`);
      cursor.setMonth(cursor.getMonth() + 1);
    }
    return result;
  }

  function monthSpan(startValue, endValue) {
    return Math.max(1, buildMonths(startValue, endValue).length);
  }

  function plannedMonthlyWeights(months, data, field) {
    const phaseItems = new Map();
    data.budget.forEach(item => {
      const value = field === "sale" ? number(item.venda_prevista) : budgetItemCost(item);
      phaseItems.set(item.fase_id, (phaseItems.get(item.fase_id) || 0) + value);
    });
    const weights = new Map(months.map(month => [month, 0]));
    data.phases.forEach(phase => {
      const plan = { ...phase, ...(data.planning.find(row => row.fase_id === phase.id) || {}) };
      const start = plannedStart(plan) || data.workStart;
      const end = plannedEnd(plan) || data.workEnd;
      const monthly = number(phaseItems.get(phase.id)) / monthSpan(start, end);
      months.forEach(month => {
        if (month >= monthKey(start) && month <= monthKey(end)) weights.set(month, weights.get(month) + monthly);
      });
    });
    if (![...weights.values()].some(Boolean)) months.forEach(month => weights.set(month, 1));
    return weights;
  }

  function renderCashFlow(work, data) {
    const todayMonth = monthKey(new Date().toISOString());
    const scheduleRows = [...data.phases, ...data.planning];
    const phaseStarts = scheduleRows.map(plannedStart).filter(Boolean).sort();
    const phaseEnds = scheduleRows.map(plannedEnd).filter(Boolean).sort();
    const scheduleStart = work.data_inicio || phaseStarts[0] || new Date();
    const scheduleEnd = work.data_fim_prevista || phaseEnds.at(-1) || new Date();
    const months = buildMonths(scheduleStart, scheduleEnd);
    const contract = selectCurrentContract(data.contracts);
    const values = months.map(month => {
      const advance = monthKey(contract.data_assinatura) === month ? number(contract.valor_adiantamento) : 0;
      const incoming = advance + data.measurements.filter(row => monthKey(row.mes_referencia) === month).reduce((total, row) => total + measurementBilledValue(row), 0);
      const subcontract = data.payments.filter(row => monthKey(row.data_pagamento) === month).reduce((total, row) => total + number(row.valor), 0);
      const labor = data.labor.filter(row => monthKey(row.data) === month).reduce((total, row) => total + number(row.horas) * number(row.valor_hora), 0);
      const site = data.siteExpenses.filter(row => monthKey(row.data_pagamento) === month).reduce((total, row) => total + number(row.valor_total), 0);
      const closed = month < todayMonth;
      return { month, incoming: closed ? incoming : 0, outgoing: closed ? subcontract + labor + site : 0, forecastIncoming: 0, forecastOutgoing: 0, closed };
    });
    const approvedTees = data.tees.filter(row => row.estado_aprovacao_cliente === "aprovado");
    const totalSale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial) + sum(approvedTees, "valor");
    const directCost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial)
      || effectiveDirectCost(data.budget, totalSale);
    const totalCost = directCost + sum(approvedTees, "preco_custo");
    const remainingMonths = months.filter(month => month >= todayMonth);
    const saleWeights = plannedMonthlyWeights(remainingMonths, { ...data, workStart: scheduleStart, workEnd: scheduleEnd }, "sale");
    const costWeights = plannedMonthlyWeights(remainingMonths, { ...data, workStart: scheduleStart, workEnd: scheduleEnd }, "cost");
    const remainingSale = Math.max(0, totalSale - values.reduce((total, row) => total + row.incoming, 0));
    const remainingCost = Math.max(0, totalCost - values.reduce((total, row) => total + row.outgoing, 0));
    const saleWeightTotal = [...saleWeights.values()].reduce((total, value) => total + value, 0) || 1;
    const costWeightTotal = [...costWeights.values()].reduce((total, value) => total + value, 0) || 1;
    values.forEach(row => {
      if (row.month >= todayMonth) {
        row.forecastIncoming = remainingSale * (saleWeights.get(row.month) || 0) / saleWeightTotal;
        row.forecastOutgoing = remainingCost * (costWeights.get(row.month) || 0) / costWeightTotal;
      }
    });
    let balance = 0;
    values.forEach(row => {
      balance += row.incoming + row.forecastIncoming - row.outgoing - row.forecastOutgoing;
      row.balance = balance;
      row.current = row.month === todayMonth;
    });
    const ceiling = Math.max(1, ...values.flatMap(row => [row.incoming, row.outgoing, row.forecastIncoming, row.forecastOutgoing]));
    return `<div class="cash-chart">${values.map(row => `
      <div class="cash-month ${row.current ? "current" : ""}">
        <div class="cash-bars"><i class="in" title="Entrada real" style="height:${row.incoming ? Math.max(2, row.incoming / ceiling * 100) : 0}%"></i><i class="out" title="Saída real" style="height:${row.outgoing ? Math.max(2, row.outgoing / ceiling * 100) : 0}%"></i><i class="forecast-in" title="Entrada prevista" style="height:${row.forecastIncoming ? Math.max(2, row.forecastIncoming / ceiling * 100) : 0}%"></i><i class="forecast-out" title="Saída prevista" style="height:${row.forecastOutgoing ? Math.max(2, row.forecastOutgoing / ceiling * 100) : 0}%"></i></div>
        <strong>${monthLabel(row.month)}</strong><small>${euro.format(row.balance)}</small>
      </div>`).join("")}</div>
      <div class="cash-legend"><span><i class="in"></i>ENTRADAS REAIS</span><span><i class="out"></i>SAÍDAS REAIS</span><span><i class="forecast-in"></i>ENTRADAS PREVISTAS</span><span><i class="forecast-out"></i>SAÍDAS PREVISTAS</span><strong>SALDO FINAL PREVISTO: ${euro.format(balance)}</strong></div>
      <div class="cash-detail-heading"><span>DETALHE MÊS A MÊS</span><small>${values.length} MESES</small></div>
      <div class="cash-month-details">${values.map(row => `
        <article class="${row.current ? "current" : ""}">
          <header><strong>${monthLabel(row.month)}</strong><span class="${(row.closed ? row.incoming - row.outgoing : row.forecastIncoming - row.forecastOutgoing) < 0 ? "negative" : "positive"}">${euro.format(row.closed ? row.incoming - row.outgoing : row.forecastIncoming - row.forecastOutgoing)}</span></header>
          <dl>
            ${row.closed
              ? `<div><dt>Entradas reais</dt><dd class="incoming">${euro.format(row.incoming)}</dd></div><div><dt>Saídas reais</dt><dd class="outgoing">${euro.format(row.outgoing)}</dd></div>`
              : `<div><dt>Entradas previstas</dt><dd class="forecast">${euro.format(row.forecastIncoming)}</dd></div><div><dt>Saídas previstas</dt><dd class="forecast">${euro.format(row.forecastOutgoing)}</dd></div>`}
            <div><dt>Saldo acumulado</dt><dd>${euro.format(row.balance)}</dd></div>
          </dl>
          <small class="cash-state">${row.closed ? "✓ REAL" : row.current ? "● MÊS EM ABERTO · PREVISÃO" : "PREVISÃO"}</small>
        </article>`).join("")}</div>`;
  }

  function teeList(rows) {
    return rows.length ? `<div class="meeting-detail-list">${rows.map(row => `<div><span><strong>${escapeHtml(row.numero || row.designacao || row.descricao || "TEE")}</strong><small>${escapeHtml(row.descricao || "")}</small></span><b>${euro.format(number(row.valor))}</b></div>`).join("")}</div>`
      : `<div class="overview-empty">SEM REGISTOS</div>`;
  }

  function renderPhaseTimeline(work, data) {
    const scheduleRows = [...data.phases, ...data.planning];
    const phaseStarts = scheduleRows.map(plannedStart).filter(Boolean).sort();
    const phaseEnds = scheduleRows.map(plannedEnd).filter(Boolean).sort();
    const start = safeDate(work.data_inicio || phaseStarts[0]);
    const end = safeDate(work.data_fim_prevista || phaseEnds.at(-1));
    if (!start || !end || end <= start) return `<div class="overview-empty">DATAS PREVISTAS DAS FASES NÃO DEFINIDAS</div>`;
    const total = end.getTime() - start.getTime();
    const today = new Date();
    const todayPosition = clampPercent((today.getTime() - start.getTime()) / total * 100);
    const months = buildMonths(work.data_inicio, work.data_fim_prevista);
    const sortedPhases = [...data.phases].sort((a, b) => String(a.codigo || a.numero).localeCompare(String(b.codigo || b.numero), "pt", { numeric: true }));
    return `<div class="phase-timeline" style="--months:${months.length}">
      <div class="phase-timeline-head"><span>FASE</span><div>${months.map(month => `<b>${monthLabel(month).split(" ")[0]}</b>`).join("")}<i style="left:${todayPosition}%"></i></div><em>%</em></div>
      ${sortedPhases.map(phase => {
        const plan = { ...phase, ...(data.planning.find(row => row.fase_id === phase.id) || {}) };
        const phaseStart = safeDate(plannedStart(plan));
        const phaseEnd = safeDate(plannedEnd(plan));
        const progress = clampPercent(number(plan.percentual_executado));
        if (!phaseStart || !phaseEnd) return `<div class="phase-timeline-row no-dates"><span><strong>${escapeHtml(phase.codigo || phase.numero || "—")}</strong><small>${escapeHtml(phase.descricao || "Fase")}</small></span><div><i style="left:${todayPosition}%"></i><small>SEM DATAS PREVISTAS</small></div><em>${Math.round(progress)}%</em></div>`;
        const left = clampPercent((phaseStart.getTime() - start.getTime()) / total * 100);
        const right = clampPercent((phaseEnd.getTime() - start.getTime()) / total * 100);
        const width = Math.max(1, right - left);
        const expected = today <= phaseStart ? 0 : today >= phaseEnd ? 100 : clampPercent((today.getTime() - phaseStart.getTime()) / (phaseEnd.getTime() - phaseStart.getTime()) * 100);
        const delta = progress - expected;
        const state = delta < -10 ? "late" : delta > 10 ? "ahead" : "on-time";
        const stateLabel = state === "late" ? "ATRASADA" : state === "ahead" ? "ADIANTADA" : "DENTRO DO PRAZO";
        return `<div class="phase-timeline-row ${state}">
          <span><strong>${escapeHtml(phase.codigo || phase.numero || "—")}</strong><small>${escapeHtml(phase.descricao || "Fase")}</small><i>${stateLabel}</i></span>
          <div><i class="today-line" style="left:${todayPosition}%"></i><b class="phase-window" style="left:${left}%;width:${width}%"><span style="width:${progress}%"></span><small>${prettyDate.format(phaseStart)} → ${prettyDate.format(phaseEnd)}</small></b></div>
          <em>${Math.round(progress)}%</em>
        </div>`;
      }).join("") || `<div class="overview-empty">SEM PLANEAMENTO DISPONÍVEL</div>`}
      <div class="phase-timeline-legend"><span><i class="late"></i>ATRASADA</span><span><i class="on-time"></i>DENTRO DO PRAZO</span><span><i class="ahead"></i>ADIANTADA</span><strong>A LINHA VERTICAL MARCA HOJE</strong></div>
    </div>`;
  }

  function renderMeeting() {
    const { work, data, warnings } = meetingState;
    const contract = selectCurrentContract(data.contracts);
    const approvedTees = data.tees.filter(row => row.estado_aprovacao_cliente === "aprovado");
    const pendingTees = data.tees.filter(row => row.estado_aprovacao_cliente === "pendente");
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const pendingTeeSale = sum(pendingTees, "valor");
    const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
    const directCost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial)
      || effectiveDirectCost(data.budget, sale);
    const expectedMargin = sale + approvedTeeSale - directCost - approvedTeeCost;
    const billed = totalClientBilling(contract, data.measurements);
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
      <div class="meeting-heading"><button id="meeting-back">← ${meetingReturnView === "works" ? "OBRA" : "VISÃO GERAL"}</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · OBRA ${escapeHtml(work.numero)}</p><h1>${escapeHtml(work.nome)}</h1><span>${escapeHtml(work.cliente || "")}</span></div><em class="work-status ${escapeHtml(work.situacao)}">${escapeHtml(String(work.situacao || "").replace(/_/g, " "))}</em></div>
      ${warnings.length ? `<div class="overview-warning">Dados parciais: ${escapeHtml(warnings.join(" · "))}</div>` : ""}
      <section class="meeting-kpis">
        <article><span>VENDA ATUALIZADA</span><strong>${euro.format(totalSale)}</strong><small>venda efetiva + TEEs aprovados</small></article>
        <article><span>CUSTO DIRETO ATUALIZADO</span><strong>${directCost ? euro.format(directCost + approvedTeeCost) : "—"}</strong><small>contratual + TEEs aprovados</small></article>
        <article><span>MARGEM PREVISTA</span><strong>${directCost ? euro.format(expectedMargin) : "—"}</strong><small>inclui TEEs aprovados</small></article>
        <article><span>POR FATURAR</span><strong>${euro.format(totalSale - billed)}</strong><small>${Math.round(billingPercent)}% faturado</small></article>
      </section>
      <section class="meeting-two">
        <article class="panel meeting-card"><div class="meeting-title"><span>RESUMO CONTRATUAL</span></div>
          <dl class="meeting-dl"><div><dt>Venda inicial</dt><dd>${euro.format(number(contract.venda_contratual_inicial))}</dd></div><div><dt>Venda efetiva</dt><dd>${euro.format(sale)}</dd></div><div><dt>Adiantamento</dt><dd>${euro.format(number(contract.valor_adiantamento))}</dd></div><div><dt>Custo direto efetivo</dt><dd>${euro.format(directCost)}</dd></div><div><dt>TEEs aprovados</dt><dd>${euro.format(approvedTeeSale)}</dd></div><div><dt>Custo TEEs aprovados</dt><dd>${euro.format(approvedTeeCost)}</dd></div></dl>
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
      <section class="panel meeting-card"><div class="meeting-title"><span>CASH FLOW MENSAL · REAL E PREVISTO</span><small>Meses encerrados com valores reais; período atual e futuro com previsão</small></div>${renderCashFlow(work, data)}</section>
      <section class="panel meeting-card"><div class="meeting-title"><span>PLANEAMENTO DE FASES</span><small>${data.phases.length} fases · posição atual e cumprimento do prazo</small></div>${renderPhaseTimeline(work, data)}</section>`;
    document.querySelector("#meeting-back").addEventListener("click", () => showView(meetingReturnView));
  }

  async function openMeeting(workId, returnView = "overview") {
    const work = getWorks().find(item => item.id === workId);
    if (!work) return;
    meetingReturnView = returnView;
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
      meetingQuery(`contratos?select=id,obra_id,venda_contratual_inicial,custo_direto_inicial,venda_contratual_efetiva,custo_direto_efetivo,valor_adiantamento,percentual_retencao_garantia,data_assinatura,atualizado_em&obra_id=eq.${encoded}`, "Contrato", warnings),
      meetingQuery(`alteracoes_tee?select=*&obra_id=eq.${encoded}`, "TEEs", warnings),
      meetingQuery(`autos_medicao?select=id,obra_id,mes_referencia,numero_auto,tipo,data_medicao,estado,valor_bruto_medido,valor_retencao_garantia,valor_deduzido_adiantamento,valor_a_faturar&obra_id=eq.${encoded}`, "Autos", warnings),
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
