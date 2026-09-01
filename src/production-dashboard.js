import { directDebitOccurrences } from "./direct-debits.js?v=1";
import { platformConfirm, platformPrompt } from "./platform-dialogs.js?v=1";

const number = value => Number(value || 0);
const sum = (rows, field) => rows.reduce((total, row) => total + number(row[field]), 0);
const DAY_MS = 86400000;
const clampPercent = value => Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
const monthKey = value => value ? String(value).slice(0, 7) : "";
const monthLabel = key => new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit" }).format(new Date(`${key}-01T12:00:00`)).toUpperCase();
const safeDate = value => value instanceof Date ? new Date(value.getTime()) : value ? new Date(`${String(value).slice(0, 10)}T12:00:00`) : null;
const addDaysDate = (value, days) => {
  const date = safeDate(value) || new Date();
  date.setDate(date.getDate() + Number(days || 0));
  return date;
};
const calendarDays = (start, end) => Math.max(0, Math.ceil(((safeDate(end)?.getTime() || 0) - (safeDate(start)?.getTime() || 0)) / DAY_MS));
const plannedStart = plan => plan?.data_inicio_prevista || plan?.data_inicio_planeada || plan?.inicio_previsto || plan?.inicio_planeado || plan?.data_inicio || plan?.inicio || null;
const plannedEnd = plan => plan?.data_fim_prevista || plan?.data_fim_planeada || plan?.fim_previsto || plan?.fim_planeado || plan?.data_fim || plan?.fim || null;
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
export const teeClientState = value => String(value ?? "")
  .normalize("NFD")
  .replace(/[\u0300-\u036f]/g, "")
  .trim()
  .toLowerCase()
  .replace(/[\s-]+/g, "_");
export const isApprovedTee = row => teeClientState(row?.estado_aprovacao_cliente) === "aprovado";
export const isPendingTee = row => !["aprovado", "recusado", "rejeitado"].includes(teeClientState(row?.estado_aprovacao_cliente));
const measurementBilledValue = row => number(row?.valor_a_faturar);
export const totalClientBilling = (contract, measurements) =>
  number(contract?.valor_adiantamento) + measurements.reduce((total, row) => total + measurementBilledValue(row), 0);
export const isInvestmentWork = work => work?.modalidade === "investimento_proprio";
export const investmentFinancialValues = (investment = {}, actualCost = 0) => {
  const initialBudget = number(investment.orcamento_inicial_sem_iva);
  const revisedBudget = number(investment.orcamento_revisto_sem_iva || investment.orcamento_inicial_sem_iva);
  return { initialBudget, revisedBudget, actualCost: number(actualCost), deviation: number(actualCost) - revisedBudget };
};
export const clientFinancialComposition = (contract = {}, approvedTees = [], fallbackEffectiveCost = 0) => {
  const initialSale = number(contract.venda_contratual_inicial);
  const effectiveSale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
  const teeSale = sum(approvedTees, "valor");
  const initialCost = number(contract.custo_direto_inicial);
  const effectiveCost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial) || number(fallbackEffectiveCost);
  const teeCost = sum(approvedTees, "preco_custo");
  const sale = [initialSale, effectiveSale, teeSale, effectiveSale + teeSale];
  const cost = [initialCost, effectiveCost, teeCost, effectiveCost + teeCost];
  return {
    sale,
    cost,
    margin: sale.map((value, index) => value - cost[index]),
    fixedCosts: cost.map(value => Math.round(value * 0.085 * 100) / 100),
  };
};
export const materialInvoiceValue = (invoice, items = []) => {
  const invoiceItems = items.filter(item => item.fatura_id === invoice.id);
  if (!invoiceItems.length) return number(invoice.valor);
  return invoiceItems.reduce((total, item) => total + number(
    item.valor_total ?? item.preco_total
      ?? number(item.quantidade) * number(item.valor_unitario ?? item.preco_unitario)
  ), 0);
};
export function actualCashFlowByMonth(data = {}) {
  const months = new Map();
  const bucket = value => {
    const key = monthKey(value);
    if (!key) return null;
    if (!months.has(key)) months.set(key, { incoming: 0, outgoing: 0, subcontract: 0, materials: 0, labor: 0, site: 0, directDebit: 0 });
    return months.get(key);
  };
  (data.billings || []).forEach(row => {
    const month = bucket(row.data_recebimento);
    if (month) month.incoming += number(row.valor_recebido);
  });
  (data.payments || []).forEach(row => {
    const month = bucket(row.data_pagamento);
    if (!month) return;
    month.subcontract += number(row.valor);
    month.outgoing += number(row.valor);
  });
  (data.materialInvoices || []).forEach(invoice => {
    const month = bucket(invoice.data_pagamento || invoice.data_fatura);
    if (!month) return;
    const value = materialInvoiceValue(invoice, data.materialInvoiceItems || []);
    month.materials += value;
    month.outgoing += value;
  });
  (data.labor || []).forEach(row => {
    const month = bucket(row.data);
    if (!month) return;
    const value = number(row.valor_total ?? number(row.horas) * number(row.valor_hora));
    month.labor += value;
    month.outgoing += value;
  });
  (data.siteExpenses || []).forEach(row => {
    const month = bucket(row.data_pagamento);
    if (!month) return;
    month.site += number(row.valor_total);
    month.outgoing += number(row.valor_total);
  });
  (data.directDebitEntries || []).forEach(row => {
    const month = bucket(row.data);
    if (!month) return;
    month.directDebit += number(row.valor);
    month.outgoing += number(row.valor);
  });
  return months;
}
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
const selectCurrentInvestment = investments => [...investments].sort((a, b) =>
  number(b.orcamento_revisto_sem_iva) - number(a.orcamento_revisto_sem_iva)
  || String(b.criado_em || "").localeCompare(String(a.criado_em || ""))
)[0] || {};

const localIso = date => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export function upcomingDirectDebitRows(debits = [], entries = [], startDate = new Date(), days = 7) {
  const start = safeDate(startDate) || new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + days); end.setHours(23, 59, 59, 999);
  const settled = new Set(entries.map(row => `${row.debito_direto_id}|${String(row.data || "").slice(0, 10)}`));
  return debits.flatMap(debit => {
    const recurring = directDebitOccurrences(debit, localIso(start), localIso(end));
    if (recurring.length || debit.recorrencia || !debit.ativo) return recurring;
    const due = safeDate(debit.data_inicio);
    return due && due >= start && due <= end ? [{ debito_direto_id: debit.id, data: localIso(due), valor: number(debit.valor_previsto), descricao: debit.descricao, obra_id: debit.obra_id || null }] : [];
  }).filter(row => !settled.has(`${row.debito_direto_id}|${row.data}`)).sort((a, b) => a.data.localeCompare(b.data));
}

export function planningBaselineDelays(work, phases = [], items = []) {
  if (!work?.planeamento_baseline_congelado) return [];
  return phases.filter(phase => phase.obra_id === work.id).map(phase => {
    const rows = items.filter(item => item.fase_id === phase.id);
    const baselineDates = rows.map(item => safeDate(item.data_fim_baseline)).filter(Boolean);
    const effectiveDates = rows.map(item => safeDate(item.data_fim_real || item.data_fim_prevista)).filter(Boolean);
    if (!baselineDates.length || !effectiveDates.length) return null;
    const baselineEnd = new Date(Math.max(...baselineDates.map(date => date.getTime())));
    const effectiveEnd = new Date(Math.max(...effectiveDates.map(date => date.getTime())));
    const days = Math.round((effectiveEnd - baselineEnd) / DAY_MS);
    return days > 0 ? { phase, days, baselineEnd, effectiveEnd } : null;
  }).filter(Boolean).sort((a, b) => b.days - a.days);
}

export function alertPriority(alert = {}) {
  const text = `${alert.tipo || ""} ${alert.entidade_tipo || ""} ${alert.titulo || ""}`
    .toLocaleLowerCase("pt-PT");
  if (/(viatura|seguro.*auto|inspe[cç][aã]o.*viatura)/.test(text)) return 0;
  if (/(medicina|consulta.*m[eé]dic)/.test(text)) return 1;
  if (/(fim_contrato_rh|contrato.*trabalho|contrato.*prazo)/.test(text)) return 2;
  if (/(f[eé]rias|ferias|anivers[aá]rio|aniversario)/.test(text)) return 4;
  return 3;
}

export function sortAlertsByPriority(alerts = []) {
  return [...alerts].sort((left, right) =>
    alertPriority(left) - alertPriority(right)
    || String(left.data_gatilho || "9999-12-31").localeCompare(String(right.data_gatilho || "9999-12-31"))
    || String(left.titulo || left.tipo || "").localeCompare(String(right.titulo || right.tipo || ""), "pt-PT"));
}

const FINANCIAL_ALERT_PATTERN = /(fatura|pagamento|recebimento|cobran[cç]a|d[eé]bito|tesouraria|cash.?flow|financeir)/i;
const TECHNICAL_RECURRING_TYPES = new Set(["pedido_mensal_horas", "pedido_semanal_horas", "informacao_reuniao_semanal", "informacao_reuniao_producao"]);
const isMeetingInformation = alert => alert?.tipo === "reserva_sala";

export function invoiceDueDate(invoice = {}) {
  if (invoice.condicao_pagamento === "outra_data") return invoice.data_vencimento || null;
  const base = safeDate(invoice.data_fatura);
  if (!base) return null;
  const days = invoice.condicao_pagamento === "30_dias" ? 30 : invoice.condicao_pagamento === "15_dias" ? 15 : 0;
  return localIso(addDaysDate(base, days));
}

export function alertsForOverviewRole(alerts = [], role, responsibleWorkIds = new Set(), currentUserId = "") {
  const personalMeeting = alert => isMeetingInformation(alert) && alert.destinatario_utilizador_id === currentUserId;
  if (["gerencia", "administrativo"].includes(role)) return sortAlertsByPriority(alerts.filter(alert => !isMeetingInformation(alert) || personalMeeting(alert)));
  if (role === "financeiro") return sortAlertsByPriority(alerts.filter(alert => personalMeeting(alert) || FINANCIAL_ALERT_PATTERN.test(`${alert.tipo || ""} ${alert.entidade_tipo || ""} ${alert.titulo || ""}`)));
  if (["diretor_obra", "adjunto", "preparador"].includes(role)) {
    return sortAlertsByPriority(alerts.filter(alert =>
      personalMeeting(alert)
      || (alert.obra_id && responsibleWorkIds.has(alert.obra_id))
      || (TECHNICAL_RECURRING_TYPES.has(alert.tipo) && (!alert.entidade_id || alert.entidade_id === currentUserId))
    ));
  }
  return sortAlertsByPriority(alerts.filter(personalMeeting));
}

export function consolidatedCashFlowSummary(rows = [], referenceDate = new Date()) {
  const year = referenceDate.getFullYear();
  const currentMonth = `${year}-${String(referenceDate.getMonth() + 1).padStart(2, "0")}`;
  const values = rows.filter(row => String(row.mes || "").startsWith(String(year))).map(row => {
    const useReal = Boolean(row.fechado) || number(row.entradas_reais) !== 0 || number(row.saidas_reais_sem_iva || row.saidas_reais_com_iva) !== 0;
    const incoming = number(useReal ? row.entradas_reais : row.entradas_previstas);
    const outgoing = number(useReal ? (row.saidas_reais_sem_iva || row.saidas_reais_com_iva) : (row.saidas_previstas_sem_iva || row.saidas_previstas_com_iva));
    return { month: monthKey(row.mes), incoming, outgoing, real: useReal };
  });
  const total = key => values.reduce((accumulator, row) => accumulator + row[key], 0);
  const monthRows = values.filter(row => row.month === currentMonth);
  return {
    currentMonth,
    monthIncoming: monthRows.reduce((totalValue, row) => totalValue + row.incoming, 0),
    monthOutgoing: monthRows.reduce((totalValue, row) => totalValue + row.outgoing, 0),
    yearIncoming: total("incoming"),
    yearOutgoing: total("outgoing"),
    realMonths: new Set(values.filter(row => row.real).map(row => row.month)).size,
  };
}

export function createProductionDashboard(options) {
  const {
    supabase, isSupabaseConfigured, getSession, getWorks, getPendingInvoices,
    getFinanceInvoices, getSuppliers, euro, prettyDate, toast, showView, getAccessContext, onImportPhaseBudget,
  } = options;
  const emptyOverviewState = () => ({
    alerts: [], profile: null, responsibilities: [], phases: [], planning: [], budget: [],
    contracts: [], tees: [], investments: [], impacts: [], measurements: [], subcontracts: [], consultations: [],
    payments: [], labor: [], siteExpenses: [], directDebits: [], directDebitEntries: [],
    planningItems: [], rncs: [], incidents: [], inspections: [], epis: [], activeCollaborators: [],
    customerBillings: [], financeForecast: [], warnings: [],
  });
  let overviewState = emptyOverviewState();
  let meetingState = null;
  let meetingReturnView = "overview";
  let costEditMode = false;
  let rspLoadVersion = 0;

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

  function actualCostForWork(workId, data = overviewState) {
    const subcontractIds = new Set(data.subcontracts.filter(row => row.obra_id === workId).map(row => row.id));
    const directDebitIds = new Set((data.directDebits || []).filter(row => row.obra_id === workId).map(row => row.id));
    const subcontract = (data.payments || []).filter(row => subcontractIds.has(row.subempreitada_id)).reduce((total, row) => total + number(row.valor), 0);
    const labor = (data.labor || []).filter(row => row.obra_id === workId).reduce((total, row) => total + number(row.valor_total || number(row.horas) * number(row.valor_hora)), 0);
    const site = (data.siteExpenses || []).filter(row => row.obra_id === workId).reduce((total, row) => total + number(row.valor_total), 0);
    const directDebit = (data.directDebitEntries || []).filter(row => directDebitIds.has(row.debito_direto_id)).reduce((total, row) => total + number(row.valor), 0);
    return subcontract + labor + site + directDebit;
  }

  function workFinancialSummary(work) {
    const workId = work.id;
    if (isInvestmentWork(work)) {
      const investment = selectCurrentInvestment(overviewState.investments.filter(row => row.obra_id === workId));
      const actualCost = actualCostForWork(workId);
      const { initialBudget, revisedBudget, deviation } = investmentFinancialValues(investment, actualCost);
      return {
        mode: "investment", initialBudget, revisedBudget, actualCost, deviation,
        impacts: overviewState.impacts.filter(row => row.obra_id === workId),
        subcontracts: overviewState.subcontracts.filter(row => row.obra_id === workId),
        consultations: overviewState.consultations.filter(row => row.obra_id === workId && row.estado === "em_consulta"),
      };
    }
    const contract = selectCurrentContract(overviewState.contracts.filter(row => row.obra_id === workId));
    const approvedTees = overviewState.tees.filter(row => row.obra_id === workId && isApprovedTee(row));
    const pendingTees = overviewState.tees.filter(row => row.obra_id === workId && isPendingTee(row));
    const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const phaseIds = new Set(overviewState.phases.filter(phase => phase.obra_id === workId).map(phase => phase.id));
    const workBudget = overviewState.budget.filter(item => phaseIds.has(item.fase_id));
    const directCost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial)
      || effectiveDirectCost(workBudget, sale);
    const composition = clientFinancialComposition(contract, approvedTees, directCost);
    const billed = totalClientBilling(contract, overviewState.measurements.filter(row => row.obra_id === workId));
    const totalSale = sale + approvedTeeSale;
    const updatedDirectCost = directCost + approvedTeeCost;
    return {
      mode: "client",
      sale: totalSale, directCost: updatedDirectCost, margin: totalSale - updatedDirectCost,
      composition,
      billed, unbilled: totalSale - billed, approvedTees, pendingTees,
      subcontracts: overviewState.subcontracts.filter(row => row.obra_id === workId),
      consultations: overviewState.consultations.filter(row => row.obra_id === workId && row.estado === "em_consulta"),
    };
  }

  function financialWorkComposition(work) {
    const summary = workFinancialSummary(work);
    if (summary.mode === "investment") {
      return `<article class="overview-composition-work investment">
        <header><div><span>OBRA ${escapeHtml(work.numero || "—")}</span><h3>${escapeHtml(work.nome || "Obra sem designação")}</h3></div><em>INVESTIMENTO PRÓPRIO</em></header>
        <div class="overview-composition-scroll"><table><thead><tr><th>INDICADOR</th><th>ORÇAMENTO INICIAL</th><th>ORÇAMENTO REVISTO</th><th>CUSTO REALIZADO</th><th>DESVIO</th></tr></thead>
          <tbody><tr><th>INVESTIMENTO</th><td>${euro.format(summary.initialBudget)}</td><td>${euro.format(summary.revisedBudget)}</td><td>${euro.format(summary.actualCost)}</td><td class="${summary.deviation > 0 ? "negative" : "positive"}">${euro.format(summary.deviation)}</td></tr></tbody>
        </table></div>
      </article>`;
    }
    const rows = [
      ["VALOR VENDA", summary.composition.sale, "value"],
      ["CUSTO DIRETO", summary.composition.cost, "cost"],
      ["MARGEM PREVISTA", summary.composition.margin, "margin"],
      ["CUSTOS FIXOS (TOTAL C.D. × 8,5%)", summary.composition.fixedCosts, "fixed"],
    ];
    return `<article class="overview-composition-work">
      <header><div><span>OBRA ${escapeHtml(work.numero || "—")}</span><h3>${escapeHtml(work.nome || "Obra sem designação")}</h3></div><em>CLIENTE EXTERNO</em></header>
      <div class="overview-composition-scroll"><table><thead><tr><th>INDICADOR</th><th>CONTRATUAL INICIAL</th><th>CONTRATUAL EFETIVO</th><th>TEEs / AJUSTES</th><th>TOTAL ATUALIZADO</th></tr></thead>
        <tbody>${rows.map(([label, values, className]) => `<tr class="${className}"><th>${label}</th>${values.map(value => `<td>${euro.format(value)}</td>`).join("")}</tr>`).join("")}</tbody>
      </table></div>
    </article>`;
  }

  const rncCode = (work, row) => `RNC-${String(work?.numero || "OBRA")}-${String(row?.numero || 0).padStart(3, "0")}`;
  const criticalRnc = row => row.gravidade === "critica";
  function technicalWorkData(work) {
    const phaseIds = new Set(overviewState.phases.filter(phase => phase.obra_id === work.id).map(phase => phase.id));
    const blocked = overviewState.planningItems.filter(item => phaseIds.has(item.fase_id) && item.impedido === true);
    const rncs = overviewState.rncs.filter(row => row.obra_id === work.id && row.estado !== "fechado")
      .sort((a, b) => Number(criticalRnc(b)) - Number(criticalRnc(a)) || String(b.data_deteccao || "").localeCompare(String(a.data_deteccao || "")));
    return { blocked, rncs, delays: planningBaselineDelays(work, overviewState.phases, overviewState.planningItems) };
  }

  function technicalWorkOverview(work, technical) {
    const blockedRows = technical.blocked.slice(0, 5).map(item => {
      const phase = overviewState.phases.find(row => row.id === item.fase_id);
      return `<button data-planning-work="${work.id}"><span><strong>${escapeHtml(item.codigo || phase?.codigo || "Tarefa")}</strong><small>${escapeHtml(item.descricao || "Tarefa impedida")}</small></span><em>${escapeHtml(item.observacao_impedimento || "Sem observação registada")}</em></button>`;
    }).join("");
    const rncRows = technical.rncs.slice(0, 5).map(row => `<button class="${criticalRnc(row) ? "critical" : "attention"}" data-rnc-work="${work.id}"><span><strong>${escapeHtml(rncCode(work, row))}</strong><small>${escapeHtml(row.local_ocorrencia || row.descricao || "Não conformidade")}</small></span><em>${escapeHtml(row.gravidade || "—").toUpperCase()}</em></button>`).join("");
    const delayRows = technical.delays.slice(0, 4).map(row => `<div><span><strong>${escapeHtml(row.phase.codigo || "Fase")}</strong><small>${escapeHtml(row.phase.descricao || "")}</small></span><em>+${row.days} DIAS</em></div>`).join("");
    return `${technical.blocked.length ? `<section class="overview-blocked-priority"><header><span>TAREFAS IMPEDIDAS · URGENTE</span><b>${technical.blocked.length}</b></header><div>${blockedRows}</div></section>` : ""}
      <div class="overview-technical-grid alert-only">
        <section class="overview-technical-card"><header><span>RNCs ABERTAS</span><b class="${technical.rncs.some(criticalRnc) ? "critical" : ""}">${technical.rncs.length}</b></header><div>${rncRows || '<p class="overview-empty">SEM RNCs ABERTAS</p>'}</div></section>
        <section class="overview-technical-card"><header><span>DESVIO FACE À BASELINE</span><b class="${technical.delays.length ? "attention" : ""}">${technical.delays.length}</b></header><div>${delayRows || '<p class="overview-empty">SEM FASES ATRASADAS</p>'}</div><button class="overview-planning-link" data-planning-summary="${work.id}">VER RESUMO POR FASE →</button></section>
      </div>`;
  }

  function overviewWorkSection(work, pendingInvoices, readOnly, technicalRole = false) {
    const summary = workFinancialSummary(work);
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
    const technical = technicalRole ? technicalWorkData(work) : null;
    return `<article class="panel overview-work-detail">
      <header><div><p class="eyebrow">OBRA ${escapeHtml(work.numero || "—")}</p><h2>${escapeHtml(work.nome || "Obra sem designação")}</h2></div><button data-meeting-work="${work.id}">REUNIÃO SEMANAL →</button></header>
      ${technical ? technicalWorkOverview(work, technical) : ""}
      <div class="overview-work-metrics">${summary.mode === "investment" ? `
        <div><span>ORÇAMENTO INICIAL</span><strong>${euro.format(summary.initialBudget)}</strong></div>
        <div><span>ORÇAMENTO REVISTO</span><strong>${euro.format(summary.revisedBudget)}</strong></div>
        <div><span>CUSTO REALIZADO</span><strong>${euro.format(summary.actualCost)}</strong></div>
        <div><span>DESVIO</span><strong class="${summary.deviation > 0 ? "negative" : "positive"}">${euro.format(summary.deviation)}</strong><small>${summary.deviation > 0 ? "ACIMA DO ORÇAMENTO" : "DENTRO DO ORÇAMENTO"}</small></div>` : `
        <div><span>VENDA</span><strong>${euro.format(summary.sale)}</strong></div>
        <div><span>CUSTO DIRETO</span><strong>${euro.format(summary.directCost)}</strong></div>
        <div><span>MARGEM</span><strong>${euro.format(summary.margin)}</strong></div>
        <div><span>FATURADO</span><strong>${euro.format(summary.billed)}</strong><small>POR FATURAR ${euro.format(summary.unbilled)}</small></div>`}
      </div>
      <div class="overview-work-status">
        <div><span>OBRA EXECUTADA <b>${Math.round(progress)}%</b></span><i><em style="width:${progress}%"></em></i></div>
        <div><span>PRAZO CONSUMIDO <b>${Math.round(deadline)}%</b></span><i><em style="width:${deadline}%"></em></i></div>
      </div>
      <div class="overview-work-columns">
        <section><h3>A MINHA FILA <b>${workInvoices.length}</b></h3><div class="overview-actions compact">${invoiceRows || '<div class="overview-empty">SEM FATURAS PENDENTES</div>'}</div></section>
        ${summary.mode === "investment" ? `<section><h3>IMPACTOS DA OBRA</h3>
          <details><summary>REGISTADOS <b>${summary.impacts.length}</b><em>${euro.format(sum(summary.impacts, "valor_sem_iva"))}</em></summary><div class="meeting-detail-list">${summary.impacts.map(row => `<div><span><strong>${escapeHtml(row.numero)} · ${escapeHtml(row.descricao)}</strong><small>${escapeHtml(row.tipo_impacto || "Impacto")}</small></span><b>${euro.format(number(row.valor_sem_iva))}</b></div>`).join("") || '<div class="overview-empty">SEM IMPACTOS REGISTADOS</div>'}</div></details>
        </section>` : `<section><h3>TEEs</h3>
          <details><summary>APROVADOS <b>${summary.approvedTees.length}</b><em>${euro.format(sum(summary.approvedTees, "valor"))}</em></summary>${teeList(summary.approvedTees)}</details>
          <details><summary>EM ELABORAÇÃO <b>${summary.pendingTees.length}</b><em>${euro.format(sum(summary.pendingTees, "valor"))}</em></summary>${teeList(summary.pendingTees)}</details>
        </section>`}
        <section><h3>SUBEMPREITADAS <b>${summary.subcontracts.length + summary.consultations.length}</b></h3>
          <div class="overview-subcontract-counts"><span>ADJUDICADAS <b>${summary.subcontracts.length}</b></span><span>EM CONSULTA <b>${summary.consultations.length}</b></span>${stateCounters}</div>
        </section>
      </div>
    </article>`;
  }

  function renderOverview() {
    const works = getWorks();
    const activeWorks = works.filter(work => work.situacao === "em_curso");
    const access = typeof getAccessContext === "function" ? getAccessContext() : {};
    const role = access.isAdmin || access.role === "gerencia"
      ? "gerencia"
      : overviewState.profile?.funcao || access.role || (isSupabaseConfigured ? "administrativo" : "gerencia");
    document.body.dataset.userRole = role;
    const responsibleWorkIds = new Set(overviewState.responsibilities.map(row => row.obra_id));
    const isProductionRole = ["diretor_obra", "adjunto", "preparador"].includes(role);
    const scopedWorks = isProductionRole ? activeWorks.filter(work => responsibleWorkIds.has(work.id)) : activeWorks;
    const visibleAlerts = alertsForOverviewRole(overviewState.alerts, role, responsibleWorkIds, overviewState.profile?.id || "");
    overviewState.visibleAlerts = visibleAlerts;
    const notificationCount = document.querySelector("#notification-button i");
    if (notificationCount) notificationCount.textContent = String(visibleAlerts.length);
    renderNotificationDrawer();
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const dueDirectDebits = upcomingDirectDebitRows(overviewState.directDebits, overviewState.directDebitEntries, today, 7);
    const supplierInvoices = role === "financeiro" ? getFinanceInvoices().filter(invoice => invoice.estado_aprovacao === "aprovado" && invoice.estado_pagamento === "por_pagar").map(invoice => ({ ...invoice, dueDate: invoiceDueDate(invoice) })).sort((left, right) => String(left.dueDate || "9999-12-31").localeCompare(String(right.dueDate || "9999-12-31"))) : [];
    const customerInvoices = role === "financeiro" ? overviewState.customerBillings.filter(invoice => number(invoice.valor) > number(invoice.valor_recebido)).sort((left, right) => String(left.data_emissao_fatura || "").localeCompare(String(right.data_emissao_fatura || ""))) : [];
    const cashFlow = consolidatedCashFlowSummary(overviewState.financeForecast, today);
    const financialCards = role === "financeiro" ? `<section class="overview-financial-alerts">
      <article class="panel"><header><span>FATURAS POR PAGAR</span><b>${supplierInvoices.length}</b></header><div>${supplierInvoices.length ? supplierInvoices.map(invoice => `<div class="overview-financial-row"><span><strong>${escapeHtml(invoice.numero_doc || "Sem número")}</strong><small>${escapeHtml(getSuppliers().find(item => item.id === invoice.fornecedor_id)?.nome || "Fornecedor")}</small></span><span><b>${euro.format(number(invoice.valor))}</b><small class="${invoice.dueDate && safeDate(invoice.dueDate) < today ? "urgent" : ""}">${invoice.dueDate ? `Vence ${prettyDate.format(safeDate(invoice.dueDate))}` : "Sem vencimento"}</small></span></div>`).join("") : '<p class="overview-empty">SEM FATURAS POR PAGAR</p>'}</div></article>
      <article class="panel"><header><span>FATURAS A CLIENTES · POR RECEBER</span><b>${customerInvoices.length}</b></header><div>${customerInvoices.length ? customerInvoices.map(invoice => `<div class="overview-financial-row"><span><strong>${escapeHtml(invoice.numero_fatura || "Sem número")}</strong><small>${escapeHtml(works.find(work => work.id === invoice.obra_id)?.nome || "Obra")}</small></span><span><b>${euro.format(number(invoice.valor) - number(invoice.valor_recebido))}</b><small>Emitida ${invoice.data_emissao_fatura ? prettyDate.format(safeDate(invoice.data_emissao_fatura)) : "—"}</small></span></div>`).join("") : '<p class="overview-empty">SEM VALORES POR RECEBER</p>'}</div></article>
      <article class="panel"><header><span>DÉBITOS A VENCER · 7 DIAS</span><b>${dueDirectDebits.length}</b></header><div>${dueDirectDebits.length ? dueDirectDebits.map(debit => `<div class="overview-financial-row"><span><strong>${escapeHtml(debit.descricao || "Débito direto")}</strong><small>${debit.data ? prettyDate.format(safeDate(debit.data)) : "—"}</small></span><b>${euro.format(number(debit.valor))}</b></div>`).join("") : '<p class="overview-empty">SEM DÉBITOS NOS PRÓXIMOS 7 DIAS</p>'}</div></article>
      <article class="panel overview-cash-summary"><header><span>CASH FLOW CONSOLIDADO</span><small>${escapeHtml(monthLabel(cashFlow.currentMonth))}</small></header><div class="overview-cash-values"><span><small>ENTRADAS DO MÊS</small><b>${euro.format(cashFlow.monthIncoming)}</b></span><span><small>SAÍDAS DO MÊS</small><b>${euro.format(cashFlow.monthOutgoing)}</b></span><span class="${cashFlow.monthIncoming - cashFlow.monthOutgoing < 0 ? "negative" : "positive"}"><small>SALDO DO MÊS</small><b>${euro.format(cashFlow.monthIncoming - cashFlow.monthOutgoing)}</b></span><span><small>SALDO ANUAL</small><b>${euro.format(cashFlow.yearIncoming - cashFlow.yearOutgoing)}</b></span></div><small>${cashFlow.realMonths} mês(es) com valores reais; restantes conforme previsão do Mapa Financeiro.</small></article>
    </section>` : "";
    const warning = overviewState.warnings.length
      ? `<div class="overview-warning">Alguns dados estão indisponíveis: ${escapeHtml(overviewState.warnings.join(" · "))}</div>` : "";

    document.querySelector("#overview-view").innerHTML = `
      <div class="page-heading">
        <div><p class="eyebrow">PAINEL OPERACIONAL · ${escapeHtml(role.replace(/_/g, " "))}</p><h1>VISÃO GERAL</h1><p>Resumo diário de produção, aprovações e tesouraria.</p></div>
        <div class="overview-today"><span>HOJE</span><strong>${prettyDate.format(new Date())}</strong></div>
      </div>
      ${warning}
      ${financialCards}
      <section class="overview-alert-layout">
        <article class="panel overview-panel">
          <div class="overview-section-head"><div><p class="eyebrow">PRIORIDADES</p><h2>ALERTAS PENDENTES</h2></div><span>${visibleAlerts.length}</span></div>
          <div class="overview-alerts">${visibleAlerts.length ? visibleAlerts.map(alert => `
            <div class="alert-${alertSeverity(alert)}"><time>${alert.data_gatilho ? prettyDate.format(safeDate(alert.data_gatilho)) : "SEM DATA"}</time>
              <span><strong>${escapeHtml(alert.titulo || alert.tipo || "Alerta")}</strong><small>${escapeHtml(alert.descricao || "")}</small></span>
              <span class="overview-alert-actions"><em>${escapeHtml(alert.tipo || "GERAL").replace(/_/g, " ")}</em>${isMeetingInformation(alert) ? '<small>INFORMATIVO</small>' : `<button type="button" data-resolve-alert="${alert.id}">MARCAR COMO RESOLVIDO</button>`}</span>
            </div>`).join("") : `<div class="overview-empty">SEM ALERTAS PENDENTES</div>`}</div>
        </article>
      </section>
      ${isProductionRole && scopedWorks.length
        ? `<section class="overview-alert-work-sections">${scopedWorks.map(work => {
          const technical = technicalWorkData(work);
          if (!technical.blocked.length && !technical.rncs.length && !technical.delays.length) return "";
          return `<article class="panel overview-alert-work"><header><div><p class="eyebrow">OBRA ${escapeHtml(work.numero || "—")}</p><h2>${escapeHtml(work.nome || "Obra sem designação")}</h2></div></header>${technicalWorkOverview(work, technical)}</article>`;
        }).join("")}</section>` : ""}`;
  }

  function alertDestination(alert) {
    if (alert.tipo === "reserva_sala") return { view: "rooms" };
    if (["consulta_medicina", "primeira_consulta_medicina"].includes(alert.tipo)) return { view: "team", teamTab: "medicine" };
    if (["inspecao_viatura", "seguro_viatura"].includes(alert.tipo)) return { view: "vehicles" };
    if (alert.tipo === "fim_contrato_rh") return { view: "team", teamTab: "contracts" };
    if (alert.tipo === "pedido_semanal_horas") return { view: "team", teamTab: "overtime" };
    if (["validade_epi", "validade_documento"].includes(alert.tipo)) return { view: "team", teamTab: "collaborators" };
    if (alert.obra_id) return { view: "works" };
    return { view: "overview" };
  }

  function closeNotificationDrawer() {
    const drawer = document.querySelector("#notification-drawer");
    const scrim = document.querySelector("#notification-scrim");
    drawer?.classList.remove("open");
    drawer?.setAttribute("aria-hidden", "true");
    if (scrim) scrim.hidden = true;
  }

  function openNotificationDrawer() {
    const drawer = document.querySelector("#notification-drawer");
    const scrim = document.querySelector("#notification-scrim");
    renderNotificationDrawer();
    drawer?.classList.add("open");
    drawer?.setAttribute("aria-hidden", "false");
    if (scrim) scrim.hidden = false;
    document.querySelector("#notification-close")?.focus();
  }

  function renderNotificationDrawer() {
    const list = document.querySelector("#notification-drawer-list");
    if (!list) return;
    const alerts = overviewState.visibleAlerts || overviewState.alerts;
    list.innerHTML = alerts.length ? sortAlertsByPriority(alerts).map(alert => {
      const destination = alertDestination(alert);
      return `<article class="notification-drawer-item alert-${alertSeverity(alert)}">
        <div><time>${alert.data_gatilho ? prettyDate.format(safeDate(alert.data_gatilho)) : "SEM DATA"}</time><span><em>${escapeHtml(alert.tipo || "GERAL").replace(/_/g, " ")}</em><em class="notification-channel">${alert.enviar_email ? "PLATAFORMA + EMAIL" : "PLATAFORMA"}</em></span></div>
        <strong>${escapeHtml(alert.titulo || alert.tipo || "Alerta")}</strong>
        <p>${escapeHtml(alert.descricao || "")}</p>
        ${isMeetingInformation(alert) ? "" : `<footer><button type="button" data-notification-view="${destination.view}" data-notification-tab="${destination.teamTab || ""}">VER ÁREA</button><button type="button" data-resolve-alert="${alert.id}">MARCAR COMO RESOLVIDO</button></footer>`}
      </article>`;
    }).join("") : `<div class="notification-drawer-empty"><strong>TUDO EM DIA</strong><span>Não existem alertas pendentes.</span></div>`;
  }

  async function resolveAlert(alertId, resolveButton) {
    resolveButton.disabled = true;
    if (isSupabaseConfigured) {
      const response = await supabase("rpc/fn_resolver_alerta", {
        method: "POST",
        body: JSON.stringify({ p_alerta_id: alertId }),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        resolveButton.disabled = false;
        return toast(detail.message || "Não foi possível resolver o alerta.", "error");
      }
    }
    overviewState.alerts = overviewState.alerts.filter(alert => alert.id !== alertId);
    renderOverview();
    toast("Alerta marcado como resolvido.");
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
    const access = typeof getAccessContext === "function" ? getAccessContext() : {};
    const requestedRole = access.isAdmin || access.role === "gerencia" ? "gerencia" : access.role || "";
    const technicalRole = ["diretor_obra", "adjunto", "preparador"].includes(requestedRole);
    const technicalAlertRole = technicalRole;
    const needsDirectDebits = requestedRole !== "encarregado";
    const [
      alerts, profiles, phases, planning, budget, contracts, tees, investments, impacts,
      measurements, subcontracts, consultations, payments, labor, siteExpenses, directDebits, directDebitEntries,
      planningItems, rncs, incidents, inspections, epis, activeCollaborators, customerBillings, financeForecast,
    ] = await Promise.all([
      query(`alertas?select=*&estado=eq.pendente&data_gatilho=lte.${new Date().toISOString().slice(0, 10)}&order=data_gatilho.asc`, "Alertas"),
      authId ? query(`utilizadores?select=id,nome,funcao,auth_user_id&auth_user_id=eq.${encodeURIComponent(authId)}&limit=1`, "Perfil") : [],
      query("fases?select=id,obra_id,descricao,codigo", "Fases"),
      [], [], [], [], [], [], [], [], [], [], [], [],
      needsDirectDebits ? query("debitos_diretos?select=id,obra_id,descricao,categoria,valor_previsto,recorrencia,dia_mes,data_inicio,data_fim,ativo", "Débitos diretos") : [],
      needsDirectDebits ? query("debitos_diretos_lancamentos?select=id,debito_direto_id,data,valor", "Lançamentos de débitos diretos") : [],
      technicalAlertRole ? query("planeamento_itens?select=id,fase_id,codigo,descricao,data_inicio_prevista,data_fim_prevista,data_fim_real,data_inicio_baseline,data_fim_baseline,estado,impedido,observacao_impedimento", "Tarefas do planeamento") : [],
      technicalAlertRole ? query("rnc?select=id,obra_id,numero,subempreitada_id,data_deteccao,data_fecho,local_ocorrencia,descricao,gravidade,estado", "RNCs") : [],
      [],
      [],
      [], [],
      requestedRole === "financeiro" ? query("faturacao?select=id,obra_id,numero_fatura,data_emissao_fatura,valor,data_recebimento,valor_recebido&order=data_emissao_fatura.asc", "Faturação a clientes") : [],
      requestedRole === "financeiro" ? query("previsao_financeira_mensal?select=obra_id,mes,fechado,entradas_reais,entradas_previstas,saidas_reais_sem_iva,saidas_reais_com_iva,saidas_previstas_sem_iva,saidas_previstas_com_iva&tipo=eq.previsao&order=mes.asc", "Cash flow") : [],
    ]);
    overviewState.alerts = sortAlertsByPriority(alerts);
    overviewState.profile = profiles[0] || null;
    overviewState.phases = phases;
    overviewState.planning = planning;
    overviewState.budget = budget;
    overviewState.contracts = contracts;
    overviewState.tees = tees;
    overviewState.investments = investments;
    overviewState.impacts = impacts;
    overviewState.measurements = measurements;
    overviewState.subcontracts = subcontracts;
    overviewState.consultations = consultations;
    overviewState.payments = payments;
    overviewState.labor = labor;
    overviewState.siteExpenses = siteExpenses;
    overviewState.directDebits = directDebits;
    overviewState.directDebitEntries = directDebitEntries;
    overviewState.planningItems = planningItems;
    overviewState.rncs = rncs;
    overviewState.incidents = incidents;
    overviewState.inspections = inspections;
    overviewState.epis = epis;
    overviewState.activeCollaborators = activeCollaborators;
    overviewState.customerBillings = customerBillings;
    overviewState.financeForecast = financeForecast;
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

  function renderCashFlow(work, data) {
    const todayMonth = monthKey(new Date().toISOString());
    const scheduleRows = [...data.phases, ...data.planning];
    const phaseStarts = scheduleRows.map(plannedStart).filter(Boolean).sort();
    const phaseEnds = scheduleRows.map(plannedEnd).filter(Boolean).sort();
    const actuals = actualCashFlowByMonth(data);
    const forecastByMonth = new Map((data.monthlyForecast || []).map(row => [monthKey(row.mes), row]));
    const monthCandidates = [
      monthKey(work.data_inicio || phaseStarts[0]),
      monthKey(work.data_fim_prevista || phaseEnds.at(-1)),
      ...actuals.keys(),
      ...forecastByMonth.keys(),
      todayMonth,
    ].filter(Boolean).sort();
    const months = buildMonths(monthCandidates[0] || new Date(), monthCandidates.at(-1) || new Date());
    const values = months.map(month => {
      const actual = actuals.get(month) || {};
      const forecast = forecastByMonth.get(month) || {};
      const closed = forecast.fechado === true || month < todayMonth;
      return {
        month,
        incoming: closed ? number(actual.incoming) : 0,
        outgoing: closed ? number(actual.outgoing) : 0,
        directDebitReal: closed ? number(actual.directDebit) : 0,
        materialsReal: closed ? number(actual.materials) : 0,
        forecastIncoming: closed ? 0 : number(forecast.entradas_previstas),
        forecastOutgoing: closed ? 0 : number(forecast.saidas_previstas_com_iva ?? forecast.saidas_previstas_sem_iva),
        closed,
      };
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
              ? `<div><dt>Entradas reais</dt><dd class="incoming">${euro.format(row.incoming)}</dd></div><div><dt>Saídas reais</dt><dd class="outgoing">${euro.format(row.outgoing)}</dd></div>${row.materialsReal ? `<div><dt>Inclui materiais</dt><dd>${euro.format(row.materialsReal)}</dd></div>` : ""}${row.directDebitReal ? `<div><dt>Inclui débitos diretos</dt><dd>${euro.format(row.directDebitReal)}</dd></div>` : ""}`
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

  function financialProjection(work, data, totalSale, updatedBudgetCost, execution, investmentMode = false) {
    const today = new Date();
    const currentMonth = monthKey(today.toISOString());
    const subcontractPaid = sum(data.payments, "valor");
    const subcontractCommitted = sum(data.subcontracts, "valor_adjudicado");
    const laborActual = data.labor.reduce((total, row) =>
      total + number(row.valor_total || number(row.horas) * number(row.valor_hora)), 0);
    const siteActual = sum(data.siteExpenses, "valor_total");
    const directDebitActual = sum(data.directDebitEntries || [], "valor");
    const actualCost = subcontractPaid + laborActual + siteActual + directDebitActual;
    const remainingCommitments = Math.max(0, subcontractCommitted - subcontractPaid);
    const closedLaborRows = data.labor.filter(row => monthKey(row.data) && monthKey(row.data) < currentMonth);
    const closedLaborMonths = new Set(closedLaborRows.map(row => monthKey(row.data)));
    const closedLaborTotal = closedLaborRows.reduce((total, row) =>
      total + number(row.valor_total || number(row.horas) * number(row.valor_hora)), 0);
    const historicalMonthlyStaff = closedLaborMonths.size ? closedLaborTotal / closedLaborMonths.size : laborActual;
    const monthlyStaffVehicle = historicalMonthlyStaff ? Math.ceil(historicalMonthlyStaff / 100) * 100 : 0;
    const contractualEnd = safeDate(work.data_fim_prevista);
    const remainingMonths = contractualEnd && contractualEnd > today
      ? Math.max(1, Math.ceil(calendarDays(today, contractualEnd) / 30.4375)) : 0;
    const start = safeDate(work.data_inicio);
    const elapsedDays = start && today > start ? Math.max(1, calendarDays(start, today)) : 0;
    const progress = clampPercent(execution);
    const dailyProgress = elapsedDays && progress > 0 ? progress / elapsedDays : 0;
    const projectedFinish = dailyProgress
      ? addDaysDate(today, Math.ceil(Math.max(0, 100 - progress) / dailyProgress))
      : contractualEnd || today;
    const automatic = data.costSummary || null;
    const automaticReal = number(automatic?.real?.total);
    const automaticRemaining = number(automatic?.por_concluir?.total);
    const estimatedFinalCost = automatic
      ? number(automatic.estimativa_terminus_total)
      : actualCost + remainingCommitments + monthlyStaffVehicle * remainingMonths;
    return {
      totalSale, updatedBudgetCost,
      actualCost: automatic ? automaticReal : actualCost,
      remainingCommitments: automatic ? automaticRemaining : remainingCommitments,
      monthlyStaffVehicle: automatic ? number(automatic.pessoal_viatura_estimado) : monthlyStaffVehicle,
      fixedCosts: number(automatic?.custos_fixos), adjustments: number(automatic?.ajustes_total),
      directFinalCost: number(automatic?.estimativa_terminus_direta), costSummary: automatic,
      data: { planningItems: data.planningItems || [], budgetItems: data.budget || [] },
      investmentMode,
      remainingMonths, estimatedFinalCost, contractualEnd, projectedFinish, progress, start, dailyProgress,
    };
  }

  function deadlineScenario(model, factor, label, description) {
    const today = new Date();
    const finish = model.dailyProgress
      ? addDaysDate(today, Math.ceil(Math.max(0, 100 - model.progress) / (model.dailyProgress * factor)))
      : model.contractualEnd || today;
    const deviationDays = model.dailyProgress && model.contractualEnd
      ? Math.ceil((finish.getTime() - model.contractualEnd.getTime()) / DAY_MS) : 0;
    return { label, description, finish, deviationDays, available: Boolean(model.dailyProgress && model.contractualEnd) };
  }

  const canAdjustWorkCosts = () => costEditMode
    && ["gestao_plataforma", "gerencia", "diretor_obra"].includes(getAccessContext()?.role || "");

  function renderCostTrace(model, editable = true) {
    const summary = model.costSummary;
    const real = summary.real || {};
    const remaining = summary.por_concluir || {};
    const components = summary.componentes || [];
    const adjustments = summary.ajustes || [];
    const components = summary.componentes || {};
    const packages = components.pacotes || [];
    const canEdit = editable && canAdjustWorkCosts();
    return `<details class="cost-trace" open><summary>COMPOSIÇÃO AUDITÁVEL DO CUSTO</summary>
      ${components.formula ? `<div class="cost-trace-formula"><span>FÓRMULA APLICADA</span><strong>${escapeHtml(components.formula)}</strong><dl><div><dt>CUSTO REAL</dt><dd>${euro.format(number(components.custo_real_total))}</dd></div><div><dt>CUSTOS ESTIMADOS</dt><dd>${euro.format(number(components.custos_estimados_total))}</dd></div><div><dt>COMPROMISSO</dt><dd>${euro.format(number(components.compromisso_total))}</dd></div></dl></div>` : ""}
      <div class="cost-trace-grid">
        <section><strong>REAL ACUMULADO</strong><span>PL confirmado <b>${euro.format(number(components.pl_real))}</b></span><span>Subempreitadas pagas <b>${euro.format(number(components.sub_real))}</b></span><span>Estaleiro registado <b>${euro.format(number(real.estaleiro))}</b></span><em>Total reconhecido ${euro.format(number(components.custo_real_total || real.total))}</em></section>
        <section><strong>POR CONCLUIR / COMPROMETIDO</strong><span>PL · valor Orca <b>${euro.format(number(components.pl_estimado))}</b></span><span>Adjudicações por confirmar <b>${euro.format(number(components.sub_estimado))}</b></span><span>Compromisso confirmado <b>${euro.format(number(components.compromisso_total))}</b></span><em>Estimado ${euro.format(number(components.custos_estimados_total || remaining.total))}</em></section>
      </div>
      ${packages.length ? `<div class="cost-component-list"><header><strong>COMPONENTES POR PACOTE / ESPECIALIDADE</strong><span>PL e subempreitada tratados separadamente</span></header>${packages.map(row => `<article><div class="cost-component-title"><strong>${escapeHtml(row.codigo || "SEM CÓDIGO")} · ${escapeHtml(row.descricao || "Pacote")}</strong><span>${escapeHtml(String(row.executado_por || "por definir").toUpperCase())}</span></div><dl><div><dt>ORCA PL</dt><dd>${euro.format(number(row.valor_orca_pl))}</dd></div><div><dt>REAL PL</dt><dd>${euro.format(number(row.valor_real_pl))}</dd></div><div><dt>ADJUDICADO</dt><dd>${euro.format(number(row.valor_adjudicado))}</dd></div><div><dt>FATURADO / PAGO</dt><dd>${number(row.percentual_faturado).toFixed(1)}% / ${number(row.percentual_pago).toFixed(1)}%</dd></div></dl>${row.pl_confirmacao_pendente ? (canEdit ? `<form data-confirm-pl-cost data-item-id="${row.planeamento_item_id}"><label>VALOR REAL PL (€)<input name="valor_real" type="number" min="0" step="0.01" value="${number(row.valor_orca_pl).toFixed(2)}" required></label><button class="secondary-button" type="submit">CONFIRMAR PL CONCLUÍDO</button><p class="form-error"></p></form>` : '<p class="cost-decision-pending">PL concluído · confirmação pendente no ecrã da obra</p>') : ""}${row.sub_confirmacao_pendente ? (canEdit ? `<button class="secondary-button" type="button" data-confirm-sub-cost="${row.planeamento_item_id}">CONFIRMAR ADJUDICAÇÃO</button>` : '<p class="cost-decision-pending">Adjudicação pendente de confirmação no ecrã da obra</p>') : ""}</article>`).join("")}</div>` : ""}
      ${number(summary.lancamentos_sem_apropriacao) ? `<div class="cost-trace-warning"><strong>${number(summary.lancamentos_sem_apropriacao)} LANÇAMENTOS SEM APROPRIAÇÃO</strong><span>Contam no realizado, mas ainda não indicam TEE/artigo de origem. Não foram abatidos por inferência.</span></div>` : ""}
      <div class="cost-adjustments"><header><strong>AJUSTES MANUAIS JUSTIFICADOS</strong><span>${euro.format(number(summary.ajustes_total))}</span></header>
        ${adjustments.map(row => `<article><div><strong>${escapeHtml(row.motivo)}</strong><small>${escapeHtml(row.autor || "Utilizador")} · ${prettyDate.format(safeDate(row.criado_em))}</small></div><b>${euro.format(number(row.valor))}</b>${canEdit ? `<button type="button" data-delete-cost-adjustment="${row.id}">REMOVER</button>` : ""}</article>`).join("") || '<p class="overview-empty">SEM AJUSTES REGISTADOS</p>'}
        ${canEdit ? `<form data-cost-adjustment><label>VALOR (€)<input name="valor" type="number" step="0.01" required></label><label>MOTIVO OBRIGATÓRIO<input name="motivo" minlength="3" required placeholder="Explique a origem do ajuste"></label><button class="secondary-button" type="submit">REGISTAR AJUSTE</button><p class="form-error"></p></form>` : ""}
      </div>
    </details>`;
  }

  function renderFinancialForecast(work, model) {
    const scenarios = [
      deadlineScenario(model, 1.25, "RECUPERAÇÃO", "Ritmo de execução 25% superior ao atual"),
      deadlineScenario(model, 1, "RITMO ATUAL", "Mantém a velocidade média observada"),
      deadlineScenario(model, .8, "RISCO", "Ritmo 20% inferior ao atual"),
    ];
    const initialDeviation = model.estimatedFinalCost - model.updatedBudgetCost;
    const delayMax = 120;
    return `<section class="financial-forecast">
      <div class="meeting-title financial-forecast-title"><span>PREVISÃO FINANCEIRA E CENÁRIOS DE PRAZO</span><small>Análise dinâmica · não altera dados da obra</small></div>
      <div class="financial-forecast-grid">
        <article class="panel financial-forecast-card">
          <header><span>CUSTOS ESTIMADOS</span><strong data-forecast-status class="${initialDeviation > 0 ? "negative" : "positive"}">${initialDeviation > 0 ? "ACIMA" : "DENTRO"}</strong></header>
          <dl class="financial-forecast-values">
            <div><dt>Orçamento de custo</dt><dd>${euro.format(model.updatedBudgetCost)}</dd></div>
            <div><dt>Custo real incorrido</dt><dd>${euro.format(model.actualCost)}</dd></div>
            <div><dt>Custo estimado até à conclusão</dt><dd>${euro.format(model.remainingCommitments)}</dd></div>
            ${model.costSummary ? `<div><dt>Estimativa no términus · custo direto</dt><dd>${euro.format(model.directFinalCost)}</dd></div><div><dt>Ajustes justificados</dt><dd>${euro.format(model.adjustments)}</dd></div>` : ""}
            <div><dt>Estimativa final</dt><dd data-estimated-final>${euro.format(model.estimatedFinalCost)}</dd></div>
            <div class="forecast-deviation"><dt>Desvio ao orçamento</dt><dd data-budget-deviation class="${initialDeviation > 0 ? "negative" : "positive"}">${euro.format(initialDeviation)}</dd></div>
          </dl>
          ${model.costSummary ? renderCostTrace(model, true) : `<div class="financial-number-control"><span>PESSOAL + VIATURA</span><small>Resumo automático indisponível até executar a migração de custos.</small></div>`}
        </article>
        <article class="panel financial-forecast-card">
          <header><span>CENÁRIOS DE PRAZO</span><strong>${Math.round(model.progress)}% EXECUTADO</strong></header>
          <div class="deadline-scenarios">${scenarios.map(scenario => {
            const state = !scenario.available ? "warning" : scenario.deviationDays <= 0 ? "positive" : scenario.deviationDays <= 30 ? "warning" : "negative";
            const deviationLabel = !scenario.available ? "SEM BASE" : scenario.deviationDays > 0 ? `+${scenario.deviationDays} DIAS` : scenario.deviationDays < 0 ? `${scenario.deviationDays} DIAS` : "NO PRAZO";
            return `<div class="${state}"><span><b>${scenario.label}</b><small>${scenario.description}</small></span><strong>${scenario.available ? prettyDate.format(scenario.finish) : "—"}</strong><em>${deviationLabel}</em></div>`;
          }).join("")}</div>
          <p class="financial-method-note">Projeção baseada na relação entre percentagem executada e dias decorridos. É uma estimativa de apoio à decisão.</p>
        </article>
        <article class="panel financial-forecast-card delay-simulator">
          <header><span>SIMULADOR DE ATRASOS</span><strong data-delay-label>0 DIAS</strong></header>
          <label><span>ATRASO ADICIONAL</span><input id="delay-simulator" type="range" min="0" max="${delayMax}" step="5" value="0"><small>0</small><small>${delayMax} dias</small></label>
          <dl class="financial-forecast-values">
            <div><dt>Conclusão projetada</dt><dd data-delay-finish>${prettyDate.format(model.projectedFinish)}</dd></div>
            <div><dt>Custo adicional</dt><dd data-delay-cost>${euro.format(0)}</dd></div>
            <div><dt>Estimativa final com atraso</dt><dd data-delay-final>${euro.format(model.estimatedFinalCost)}</dd></div>
            <div class="forecast-deviation"><dt>${model.investmentMode ? "Desvio projetado" : "Margem estimada"}</dt><dd data-delay-margin>${euro.format(model.investmentMode ? model.estimatedFinalCost - model.updatedBudgetCost : model.totalSale - model.estimatedFinalCost)}</dd></div>
          </dl>
          <div class="delay-warning" data-delay-warning>SEM ATRASO ADICIONAL SIMULADO</div>
        </article>
      </div>
    </section>`;
  }

  function bindFinancialForecast(model) {
    const root = document.querySelector("#meeting-view .financial-forecast");
    const delayInput = root?.querySelector("#delay-simulator");
    if (!root || !delayInput) return;
    const update = () => {
      const delayDays = Math.max(0, number(delayInput.value));
      const monthly = model.remainingMonths ? model.monthlyStaffVehicle / model.remainingMonths : 0;
      const estimatedFinal = model.estimatedFinalCost;
      const deviation = estimatedFinal - model.updatedBudgetCost;
      const delayCost = monthly / 30.4375 * delayDays;
      const finalWithDelay = estimatedFinal + delayCost;
      const margin = model.investmentMode ? finalWithDelay - model.updatedBudgetCost : model.totalSale - finalWithDelay;
      const finish = addDaysDate(model.projectedFinish, delayDays);
      const write = (selector, value) => { const element = root.querySelector(selector); if (element) element.textContent = value; };
      write("[data-estimated-final]", euro.format(estimatedFinal));
      write("[data-budget-deviation]", euro.format(deviation));
      write("[data-forecast-status]", deviation > 0 ? "ACIMA" : "DENTRO");
      write("[data-delay-label]", `${delayDays} ${delayDays === 1 ? "DIA" : "DIAS"}`);
      write("[data-delay-finish]", prettyDate.format(finish));
      write("[data-delay-cost]", euro.format(delayCost));
      write("[data-delay-final]", euro.format(finalWithDelay));
      write("[data-delay-margin]", euro.format(margin));
      const deviationElement = root.querySelector("[data-budget-deviation]");
      const statusElement = root.querySelector("[data-forecast-status]");
      const marginElement = root.querySelector("[data-delay-margin]");
      [deviationElement, statusElement].forEach(element => element?.classList.toggle("negative", deviation > 0));
      [deviationElement, statusElement].forEach(element => element?.classList.toggle("positive", deviation <= 0));
      marginElement?.classList.toggle("negative", model.investmentMode ? margin > 0 : margin < 0);
      marginElement?.classList.toggle("positive", model.investmentMode ? margin <= 0 : margin >= 0);
      const warning = root.querySelector("[data-delay-warning]");
      if (warning) {
        warning.className = `delay-warning ${delayDays > 60 ? "negative" : delayDays > 0 ? "warning" : ""}`;
        warning.textContent = delayDays > 60 ? `RISCO ELEVADO DE IMPACTO EM PRAZO E ${model.investmentMode ? "ORÇAMENTO" : "MARGEM"}`
          : delayDays > 0 ? "O ATRASO AUMENTA O CUSTO DE ESTRUTURA DA OBRA" : "SEM ATRASO ADICIONAL SIMULADO";
      }
    };
    delayInput.addEventListener("input", update);
    update();
  }

  function meetingModel(state) {
    const { work, data, warnings } = state;
    const investmentMode = isInvestmentWork(work);
    const contract = selectCurrentContract(data.contracts);
    const investment = selectCurrentInvestment(data.investments || []);
    const impacts = data.impacts || [];
    const approvedTees = investmentMode ? [] : data.tees.filter(isApprovedTee);
    const pendingTees = investmentMode ? [] : data.tees.filter(isPendingTee);
    const approvedTeeSale = sum(approvedTees, "valor");
    const approvedTeeCost = sum(approvedTees, "preco_custo");
    const pendingTeeSale = sum(pendingTees, "valor");
    const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
    const initialBudget = number(investment.orcamento_inicial_sem_iva);
    const revisedBudget = number(investment.orcamento_revisto_sem_iva || investment.orcamento_inicial_sem_iva);
    const directCost = investmentMode ? revisedBudget : number(contract.custo_direto_efetivo || contract.custo_direto_inicial)
      || effectiveDirectCost(data.budget, sale);
    const expectedMargin = sale + approvedTeeSale - directCost - approvedTeeCost;
    const billed = investmentMode ? 0 : totalClientBilling(contract, data.measurements);
    const totalSale = investmentMode ? 0 : sale + approvedTeeSale;
    const billingPercent = totalSale ? clampPercent(billed / totalSale * 100) : 0;
    const execution = workExecution(work.id, data.phases, data.planning, data.budget);
    const deadline = deadlinePercent(work);
    const paidBySubcontract = new Map();
    data.payments.forEach(row => paidBySubcontract.set(row.subempreitada_id, (paidBySubcontract.get(row.subempreitada_id) || 0) + number(row.valor)));
    const consultationPhaseIds = new Set(data.consultations.map(row => row.fase_id).filter(Boolean));
    const subcontractPhaseIds = new Set(data.subcontracts.map(row => row.fase_id).filter(Boolean));
    const budgetPhaseIds = new Set(data.budget.map(row => row.fase_id));
    const notConsulted = data.phases.filter(phase => budgetPhaseIds.has(phase.id) && !consultationPhaseIds.has(phase.id) && !subcontractPhaseIds.has(phase.id));
    const projection = financialProjection(work, data, totalSale, directCost + approvedTeeCost, execution, investmentMode);
    const actualCost = projection.actualCost;
    const investmentDeviation = actualCost - revisedBudget;
    return {
      work, data, warnings, investmentMode, contract, investment, impacts, approvedTees, pendingTees,
      approvedTeeSale, approvedTeeCost, pendingTeeSale, sale, initialBudget, revisedBudget, directCost,
      expectedMargin, billed, totalSale, billingPercent, execution, deadline, paidBySubcontract,
      notConsulted, projection, actualCost, investmentDeviation,
    };
  }

  function renderMeeting() {
    const {
      work, data, warnings, investmentMode, contract, investment, impacts, approvedTees, pendingTees,
      approvedTeeSale, approvedTeeCost, pendingTeeSale, sale, initialBudget, revisedBudget, directCost,
      expectedMargin, billed, totalSale, billingPercent, execution, deadline, paidBySubcontract,
      notConsulted, projection, actualCost, investmentDeviation,
    } = meetingModel(meetingState);

    document.querySelector("#meeting-view").innerHTML = `
      <div class="meeting-heading"><button id="meeting-back">← ${meetingReturnView === "works" ? "OBRA" : meetingReturnView === "rsp" ? "RSP" : "VISÃO GERAL"}</button><div><p class="eyebrow">REUNIÃO SEMANAL DE PRODUÇÃO · OBRA ${escapeHtml(work.numero)}</p><h1>${escapeHtml(work.nome)}</h1><span>${escapeHtml(work.cliente || "")}</span></div><em class="work-status ${escapeHtml(work.situacao)}">${escapeHtml(String(work.situacao || "").replace(/_/g, " "))}</em></div>
      ${warnings.length ? `<div class="overview-warning">Dados parciais: ${escapeHtml(warnings.join(" · "))}</div>` : ""}
      <section class="meeting-kpis">${investmentMode ? `
        <article><span>ORÇAMENTO INICIAL</span><strong>${euro.format(initialBudget)}</strong><small>sem IVA</small></article>
        <article><span>ORÇAMENTO REVISTO</span><strong>${euro.format(revisedBudget)}</strong><small>sem IVA</small></article>
        <article><span>CUSTO REALIZADO</span><strong>${euro.format(actualCost)}</strong><small>custos reais registados</small></article>
        <article><span>DESVIO</span><strong class="${investmentDeviation > 0 ? "negative" : "positive"}">${euro.format(investmentDeviation)}</strong><small>${investmentDeviation > 0 ? "acima do orçamento" : "dentro do orçamento"}</small></article>` : `
        <article><span>VENDA ATUALIZADA</span><strong>${euro.format(totalSale)}</strong><small>venda efetiva + TEEs aprovados</small></article>
        <article><span>CUSTO DIRETO ATUALIZADO</span><strong>${directCost ? euro.format(directCost + approvedTeeCost) : "—"}</strong><small>contratual + TEEs aprovados</small></article>
        <article><span>MARGEM PREVISTA</span><strong>${directCost ? euro.format(expectedMargin) : "—"}</strong><small>inclui TEEs aprovados</small></article>
        <article><span>POR FATURAR</span><strong>${euro.format(totalSale - billed)}</strong><small>${Math.round(billingPercent)}% faturado</small></article>`}
      </section>
      <section class="meeting-two">
        ${investmentMode ? `<article class="panel meeting-card"><div class="meeting-title"><span>RESUMO DO INVESTIMENTO</span></div>
          <dl class="meeting-dl"><div><dt>Orçamento inicial sem IVA</dt><dd>${euro.format(initialBudget)}</dd></div><div><dt>Orçamento inicial com IVA</dt><dd>${euro.format(number(investment.orcamento_inicial_com_iva))}</dd></div><div><dt>Orçamento revisto sem IVA</dt><dd>${euro.format(revisedBudget)}</dd></div><div><dt>Orçamento revisto com IVA</dt><dd>${euro.format(number(investment.orcamento_revisto_com_iva))}</dd></div><div><dt>Impactos registados</dt><dd>${euro.format(sum(impacts, "valor_sem_iva"))}</dd></div><div><dt>Custo realizado</dt><dd>${euro.format(actualCost)}</dd></div></dl>
          <details><summary>IMPACTOS DA OBRA <b>${impacts.length}</b><em>${euro.format(sum(impacts, "valor_sem_iva"))}</em></summary><div class="meeting-detail-list">${impacts.map(row => `<div><span><strong>${escapeHtml(row.numero)} · ${escapeHtml(row.descricao)}</strong><small>${escapeHtml(row.tipo_impacto || "Impacto")} · ${row.data ? prettyDate.format(safeDate(row.data)) : "SEM DATA"}</small></span><b>${euro.format(number(row.valor_sem_iva))}</b></div>`).join("") || '<div class="overview-empty">SEM IMPACTOS REGISTADOS</div>'}</div></details>
        </article>` : `<article class="panel meeting-card"><div class="meeting-title"><span>RESUMO CONTRATUAL</span></div>
          <dl class="meeting-dl"><div><dt>Venda inicial</dt><dd>${euro.format(number(contract.venda_contratual_inicial))}</dd></div><div><dt>Venda efetiva</dt><dd>${euro.format(sale)}</dd></div><div><dt>Adiantamento</dt><dd>${euro.format(number(contract.valor_adiantamento))}</dd></div><div><dt>Custo direto efetivo</dt><dd>${euro.format(directCost)}</dd></div><div><dt>TEEs aprovados</dt><dd>${euro.format(approvedTeeSale)}</dd></div><div><dt>Custo TEEs aprovados</dt><dd>${euro.format(approvedTeeCost)}</dd></div></dl>
          <details><summary>TEEs APROVADOS <b>${approvedTees.length}</b><em>${euro.format(approvedTeeSale)}</em></summary>${teeList(approvedTees)}</details>
          <details><summary>EM ELABORAÇÃO / AGUARDA RESPOSTA <b>${pendingTees.length}</b><em>${euro.format(pendingTeeSale)}</em></summary>${teeList(pendingTees)}</details>
        </article>`}
        <article class="panel meeting-card"><div class="meeting-title"><span>${investmentMode ? "CUSTO E PROGRESSO" : "FATURAÇÃO E PROGRESSO"}</span></div>
          ${investmentMode ? `<div class="meeting-progress"><span>ORÇAMENTO CONSUMIDO <b>${revisedBudget ? Math.round(clampPercent(actualCost / revisedBudget * 100)) : 0}%</b></span><div><i style="width:${revisedBudget ? clampPercent(actualCost / revisedBudget * 100) : 0}%"></i></div><small>${euro.format(actualCost)} de ${euro.format(revisedBudget)}</small></div>` : `<div class="meeting-progress"><span>FATURADO <b>${Math.round(billingPercent)}%</b></span><div><i style="width:${billingPercent}%"></i></div><small>${euro.format(billed)} de ${euro.format(totalSale)}</small></div>`}
          <div class="meeting-progress"><span>OBRA EXECUTADA <b>${Math.round(execution)}%</b></span><div><i style="width:${execution}%"></i></div><small>ponderação financeira das fases</small></div>
          <div class="meeting-progress deadline"><span>PRAZO CONSUMIDO <b>${Math.round(deadline)}%</b></span><div><i style="width:${deadline}%"></i></div><small>${work.data_inicio ? prettyDate.format(safeDate(work.data_inicio)) : "—"} → ${work.data_fim_prevista ? prettyDate.format(safeDate(work.data_fim_prevista)) : "—"}</small></div>
        </article>
      </section>
      ${renderFinancialForecast(work, projection)}
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
    bindFinancialForecast(projection);
  }

  async function loadMeetingState(work) {
    const investmentMode = isInvestmentWork(work);
    const encoded = encodeURIComponent(work.id);
    const warnings = [];
    const [baseSubcontracts, phases, directDebits] = await Promise.all([
      meetingQuery(`subempreitadas?select=*&obra_id=eq.${encoded}`, "Subempreitadas", warnings),
      meetingQuery(`fases?select=*&obra_id=eq.${encoded}`, "Fases", warnings),
      meetingQuery(`debitos_diretos?select=id,obra_id,descricao,categoria,valor_previsto,recorrencia,dia_mes,data_inicio,data_fim,ativo&obra_id=eq.${encoded}`, "Débitos diretos", warnings),
    ]);
    const subcontractIds = baseSubcontracts.map(row => row.id);
    const phaseIds = phases.map(row => row.id);
    const directDebitIds = directDebits.map(row => row.id);
    const [
      contracts, tees, investments, impacts, measurements, planning, planningItems, budget, consultations,
      payments, labor, siteExpenses, directDebitEntries, billings, monthlyForecast, materialInvoices,
    ] = await Promise.all([
      investmentMode ? [] : meetingQuery(`contratos?select=id,obra_id,venda_contratual_inicial,custo_direto_inicial,venda_contratual_efetiva,custo_direto_efetivo,valor_adiantamento,percentual_retencao_garantia,data_assinatura,atualizado_em&obra_id=eq.${encoded}`, "Contrato", warnings),
      investmentMode ? [] : meetingQuery(`alteracoes_tee?select=*&obra_id=eq.${encoded}`, "TEEs", warnings),
      investmentMode ? meetingQuery(`investimentos?select=*&obra_id=eq.${encoded}`, "Investimento", warnings) : [],
      investmentMode ? meetingQuery(`impactos_obra?select=*&obra_id=eq.${encoded}&order=data.desc`, "Impactos de obra", warnings) : [],
      investmentMode ? [] : meetingQuery(`autos_medicao?select=id,obra_id,mes_referencia,numero_auto,tipo,data_medicao,estado,valor_bruto_medido,valor_retencao_garantia,valor_deduzido_adiantamento,valor_a_faturar&obra_id=eq.${encoded}`, "Autos", warnings),
      phaseIds.length ? meetingQuery(`planeamento_fases_resumo?select=*&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})`, "Planeamento", warnings) : [],
      phaseIds.length ? meetingQuery(`planeamento_itens?select=id,fase_id,codigo,descricao,especialidade_id,executado_por,subempreitada_id,item_orcamento_id,estado&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})&order=codigo`, "Tarefas de planeamento", warnings) : [],
      phaseIds.length ? meetingQuery(`itens_orcamento?select=*&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})`, "Orçamento", warnings) : [],
      meetingQuery(`consultas_subempreitada?select=*&obra_id=eq.${encoded}`, "Consultas", warnings),
      subcontractIds.length ? meetingQuery(`pagamentos_subempreitada?select=*&subempreitada_id=in.(${subcontractIds.map(encodeURIComponent).join(",")})`, "Pagamentos", warnings) : [],
      meetingQuery(`lancamentos_mao_obra?select=*&obra_id=eq.${encoded}`, "Mão de obra", warnings),
      meetingQuery(`despesas_estaleiro?select=*&obra_id=eq.${encoded}`, "Estaleiro", warnings),
      directDebitIds.length ? meetingQuery(`debitos_diretos_lancamentos?select=id,debito_direto_id,data,valor&debito_direto_id=in.(${directDebitIds.map(encodeURIComponent).join(",")})`, "Lançamentos de débitos diretos", warnings) : [],
      meetingQuery(`faturacao?select=id,obra_id,data_recebimento,valor_recebido&obra_id=eq.${encoded}&data_recebimento=not.is.null`, "Recebimentos reais", warnings),
      meetingQuery(`previsao_financeira_mensal?select=obra_id,mes,tipo,entradas_reais,entradas_previstas,saidas_reais_sem_iva,saidas_reais_com_iva,saidas_previstas_sem_iva,saidas_previstas_com_iva,fechado&obra_id=eq.${encoded}&tipo=eq.previsao&order=mes.asc`, "Previsão financeira mensal", warnings),
      meetingQuery(`faturas?select=id,obra_id,tipo_origem,valor,data_fatura,data_pagamento,estado_aprovacao,estado_pagamento&obra_id=eq.${encoded}&tipo_origem=eq.material&estado_pagamento=eq.pago`, "Faturas de materiais", warnings),
    ]);
    const materialInvoiceIds = materialInvoices.map(row => row.id);
    const materialInvoiceItems = materialInvoiceIds.length
      ? await meetingQuery(`faturas_itens?select=*&fatura_id=in.(${materialInvoiceIds.map(encodeURIComponent).join(",")})`, "Itens das faturas de materiais", warnings)
      : [];
    let costSummary = null;
    if (isSupabaseConfigured) {
      const costResponse = await supabase("rpc/fn_resumo_custos_obra", { method: "POST", body: JSON.stringify({ p_obra_id: work.id }) });
      if (costResponse.ok) costSummary = await costResponse.json();
      else warnings.push("Custos automáticos: execute a migração custos_obra_automaticos.sql");
      const componentsResponse = await supabase("rpc/fn_resumo_componentes_custo_obra", { method: "POST", body: JSON.stringify({ p_obra_id: work.id }) });
      if (componentsResponse.ok) costSummary = { ...(costSummary || {}), componentes: await componentsResponse.json() };
      else warnings.push("Componentes de custo: execute a migração custos_estimados_consolidado.sql");
    }
    return { work, warnings, data: { contracts, tees, investments, impacts, measurements, phases, planning, planningItems, budget, subcontracts: baseSubcontracts, consultations, payments, labor, siteExpenses, directDebits, directDebitEntries, billings, monthlyForecast, materialInvoices, materialInvoiceItems, costSummary } };
  }

  async function saveCostAdjustment(form) {
    if (!meetingState || !canAdjustWorkCosts()) return;
    const fields = Object.fromEntries(new FormData(form));
    const button = form.querySelector('[type="submit"]');
    const error = form.querySelector(".form-error");
    error.textContent = "";
    button.disabled = true;
    const response = await supabase("ajustes_custo_obra", {
      method: "POST", headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ obra_id: meetingState.work.id, valor: number(fields.valor), motivo: fields.motivo.trim(), criado_por: getAccessContext()?.profile?.id }),
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      error.textContent = detail.message || "Não foi possível registar o ajuste.";
      button.disabled = false;
      return;
    }
    toast("Ajuste de custo registado e auditado.");
    await showWorkCosts(meetingState.work.id);
  }

  async function deleteCostAdjustment(id, button) {
    if (!meetingState || !canAdjustWorkCosts() || !await platformConfirm("Remover este ajuste de custo? O evento continuará registado na auditoria.", { title: "Remover ajuste", danger: true, confirmLabel: "REMOVER" })) return;
    button.disabled = true;
    const response = await supabase(`ajustes_custo_obra?id=eq.${encodeURIComponent(id)}`, { method: "DELETE" });
    if (!response.ok) return toast("Não foi possível remover o ajuste.", "error");
    toast("Ajuste removido.");
    await showWorkCosts(meetingState.work.id);
  }

  async function saveCostComponent(form) {
    if (!meetingState || !canAdjustWorkCosts()) return;
    const fields = Object.fromEntries(new FormData(form));
    const button = form.querySelector('[type="submit"]');
    const error = form.querySelector(".form-error");
    error.textContent = ""; button.disabled = true;
    const response = await supabase("rpc/fn_guardar_componente_custo", {
      method: "POST", body: JSON.stringify({
        p_planeamento_item_id: fields.planeamento_item_id,
        p_tipo: fields.tipo, p_valor_orcamentado: number(fields.valor_orcamentado),
        p_estado_custo: fields.estado_custo, p_valor_real_pl: null,
        p_item_orcamento_id: fields.item_orcamento_id || null,
      }),
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      error.textContent = detail.message || "Não foi possível guardar o pacote de custo.";
      button.disabled = false; return;
    }
    toast("Pacote de custo guardado.");
    await showWorkCosts(meetingState.work.id);
  }

  async function confirmSubcontractEstimatedCost(subcontractId, button) {
    if (!meetingState || !canAdjustWorkCosts()
      || !await platformConfirm("Valor adjudicado — confirmar remoção dos Custos Estimados?", { title: "Confirmar custo adjudicado" })) return;
    button.disabled = true;
    const response = await supabase("rpc/fn_confirmar_remocao_custo_estimado_subempreitada", {
      method: "POST", body: JSON.stringify({ p_subempreitada_id: subcontractId }),
    });
    if (!response.ok) return toast("Não foi possível confirmar a remoção do custo estimado.", "error");
    toast("Custo orçamentado removido; compromisso adjudicado assumido.");
    await showWorkCosts(meetingState.work.id);
  }

  async function completePlCost(componentId, defaultValue, button) {
    if (!meetingState || !canAdjustWorkCosts()) return;
    const entered = await platformPrompt("Pode ajustar o valor do orça antes de concluir.", number(defaultValue).toFixed(2), { title: "Valor real do trabalho PL", label: "VALOR REAL (€)" });
    if (entered === null) return;
    const value = Number(String(entered).replace(",", "."));
    if (!Number.isFinite(value) || value < 0) return toast("Introduza um valor real válido.", "error");
    button.disabled = true;
    const response = await supabase("rpc/fn_concluir_custo_pl", {
      method: "POST", body: JSON.stringify({ p_componente_id: componentId, p_valor_real: value }),
    });
    if (!response.ok) return toast("Não foi possível concluir o custo PL.", "error");
    toast("Pacote PL concluído e transferido para Custo Real.");
    await showWorkCosts(meetingState.work.id);
  }

  async function completePlPhase(budgetId, defaultValue, button) {
    if (!meetingState || !canAdjustWorkCosts()) return;
    const entered = await platformPrompt("O valor do 0_Orçamento é usado por defeito; ajuste apenas se o custo real da fase foi diferente.", number(defaultValue).toFixed(2), { title: "Concluir custo PL da fase", label: "VALOR REAL (€)" });
    if (entered === null) return;
    const value = Number(String(entered).replace(",", "."));
    if (!Number.isFinite(value) || value < 0) return toast("Introduza um valor real válido.", "error");
    button.disabled = true;
    const response = await supabase("rpc/fn_concluir_custo_pl_fase", { method: "POST", body: JSON.stringify({ p_orcamento_fase_id: budgetId, p_valor_real: value }) });
    if (!response.ok) return toast("Não foi possível concluir o custo PL desta fase.", "error");
    toast("Fase PL concluída e transferida para Custo Real.");
    await showWorkCosts(meetingState.work.id);
  }

  async function showWorkCosts(workId) {
    const host = document.querySelector(`[data-work-cost-card="${CSS.escape(String(workId))}"]`);
    const work = getWorks().find(item => String(item.id) === String(workId));
    if (!host || !work) return;
    costEditMode = true;
    host.innerHTML = '<div class="overview-loading">A CARREGAR COMPOSIÇÃO DE CUSTO…</div>';
    meetingState = await loadMeetingState(work);
    const projection = meetingModel(meetingState).projection;
    host.innerHTML = projection.costSummary
      ? renderCostTrace(projection, false)
      : '<div class="overview-warning">Resumo automático indisponível. Confirme se a migração consolidada de custos foi aplicada.</div>';
  }

  async function confirmPlCost(form) {
    if (!meetingState || !canAdjustWorkCosts()) return;
    const button = form.querySelector('[type="submit"]');
    const error = form.querySelector(".form-error");
    button.disabled = true;
    error.textContent = "";
    const response = await supabase("rpc/fn_confirmar_custo_real_pl", {
      method: "POST",
      body: JSON.stringify({ p_planeamento_item_id: form.dataset.itemId, p_valor_real: number(new FormData(form).get("valor_real")) }),
    });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      error.textContent = detail.message || "Não foi possível confirmar o custo real PL.";
      button.disabled = false;
      return;
    }
    toast("Custo real PL confirmado e auditado.");
    await openMeeting(meetingState.work.id, meetingReturnView);
  }

  async function confirmSubcontractCost(itemId, button) {
    if (!meetingState || !canAdjustWorkCosts() || !confirm("Confirmar a remoção do valor orçamentado dos Custos Estimados e reconhecer a adjudicação como compromisso?")) return;
    button.disabled = true;
    const response = await supabase("rpc/fn_confirmar_compromisso_subempreitada", { method: "POST", body: JSON.stringify({ p_planeamento_item_id: itemId }) });
    if (!response.ok) return toast(`Não foi possível confirmar a adjudicação: ${await response.text()}`, "error");
    toast("Adjudicação confirmada como compromisso.");
    await openMeeting(meetingState.work.id, meetingReturnView);
  }

  async function openMeeting(workId, returnView = "overview") {
    const work = getWorks().find(item => item.id === workId);
    if (!work) return;
    meetingReturnView = returnView;
    costEditMode = false;
    showView("meeting");
    document.querySelector("#meeting-view").innerHTML = '<div class="overview-loading">A CARREGAR REUNIÃO SEMANAL…</div>';
    meetingState = await loadMeetingState(work);
    renderMeeting();
  }

  function renderRspWork(state) {
    const model = meetingModel(state);
    const {
      work, data, warnings, investmentMode, approvedTees, pendingTees, impacts,
      totalSale, directCost, approvedTeeCost, expectedMargin, initialBudget, revisedBudget,
      actualCost, investmentDeviation, billed, billingPercent, execution, deadline,
      paidBySubcontract, notConsulted, projection,
    } = model;
    const paidTotal = [...paidBySubcontract.values()].reduce((total, value) => total + number(value), 0);
    const openConsultations = data.consultations.filter(row => row.estado === "em_consulta").length;
    return `
      <article class="rsp-work panel">
        <header class="rsp-work-header">
          <div><p class="eyebrow">OBRA ${escapeHtml(work.numero)}</p><h2>${escapeHtml(work.nome)}</h2><span>${escapeHtml(work.cliente || "")}</span></div>
          <button class="secondary-button" data-rsp-open-meeting="${escapeHtml(work.id)}">ABRIR DETALHE →</button>
        </header>
        ${warnings.length ? `<div class="overview-warning">Dados parciais: ${escapeHtml(warnings.join(" · "))}</div>` : ""}
        <div class="rsp-kpis">
          ${investmentMode ? `
            <div><span>ORÇAMENTO INICIAL</span><strong>${euro.format(initialBudget)}</strong></div>
            <div><span>ORÇAMENTO REVISTO</span><strong>${euro.format(revisedBudget)}</strong></div>
            <div><span>CUSTO REALIZADO</span><strong>${euro.format(actualCost)}</strong></div>
            <div><span>DESVIO</span><strong class="${investmentDeviation > 0 ? "negative" : "positive"}">${euro.format(investmentDeviation)}</strong></div>` : `
            <div><span>VENDA ATUALIZADA</span><strong>${euro.format(totalSale)}</strong></div>
            <div><span>CUSTO DIRETO</span><strong>${directCost ? euro.format(directCost + approvedTeeCost) : "—"}</strong></div>
            <div><span>MARGEM PREVISTA</span><strong>${directCost ? euro.format(expectedMargin) : "—"}</strong></div>
            <div><span>FATURADO</span><strong>${euro.format(billed)}</strong><small>${Math.round(billingPercent)}%</small></div>`}
        </div>
        <div class="rsp-progress-grid">
          <div class="meeting-progress"><span>OBRA EXECUTADA <b>${Math.round(execution)}%</b></span><div><i style="width:${execution}%"></i></div></div>
          <div class="meeting-progress deadline"><span>PRAZO CONSUMIDO <b>${Math.round(deadline)}%</b></span><div><i style="width:${deadline}%"></i></div></div>
        </div>
        <div class="rsp-operational-grid">
          <div><span>${investmentMode ? "IMPACTOS" : "TEEs APROVADOS"}</span><strong>${investmentMode ? impacts.length : approvedTees.length}</strong><small>${investmentMode ? euro.format(sum(impacts, "valor_sem_iva")) : euro.format(sum(approvedTees, "valor"))}</small></div>
          <div><span>${investmentMode ? "IMPACTOS REGISTADOS" : "TEEs PENDENTES"}</span><strong>${investmentMode ? impacts.length : pendingTees.length}</strong><small>${investmentMode ? "investimento próprio" : euro.format(sum(pendingTees, "valor"))}</small></div>
          <div><span>SUBEMPREITADAS</span><strong>${data.subcontracts.length}</strong><small>pago ${euro.format(paidTotal)}</small></div>
          <div><span>EM CONSULTA / NÃO CONSULTADAS</span><strong>${openConsultations} / ${notConsulted.length}</strong><small>situação atual</small></div>
        </div>
        ${projection.costSummary ? renderCostTrace(projection, false) : ""}
        <details class="rsp-detail"><summary>CASH FLOW MENSAL</summary>${renderCashFlow(work, data)}</details>
        <details class="rsp-detail"><summary>PLANEAMENTO DE FASES</summary>${renderPhaseTimeline(work, data)}</details>
      </article>`;
  }

  async function showRsp() {
    const root = document.querySelector("#rsp-view");
    if (!root) return;
    const version = ++rspLoadVersion;
    const works = getWorks()
      .filter(work => work.situacao === "em_curso")
      .sort((left, right) => Number(left.numero) - Number(right.numero) || String(left.nome).localeCompare(String(right.nome), "pt"));
    root.innerHTML = `
      <div class="page-heading rsp-heading"><div><p class="eyebrow">GESTÃO DE PRODUÇÃO</p><h1>REUNIÃO SEMANAL DE PRODUÇÃO</h1><span>Visão consolidada, obra a obra, com a mesma informação da reunião individual.</span></div></div>
      <div class="overview-loading" id="rsp-loading">A CARREGAR 0 DE ${works.length} OBRAS…</div>`;
    if (!works.length) {
      root.insertAdjacentHTML("beforeend", '<div class="overview-empty panel">NÃO EXISTEM OBRAS EM CURSO</div>');
      return;
    }
    const states = [];
    for (let index = 0; index < works.length; index += 1) {
      if (version !== rspLoadVersion) return;
      const loading = root.querySelector("#rsp-loading");
      if (loading) loading.textContent = `A CARREGAR ${index + 1} DE ${works.length} OBRAS…`;
      states.push(await loadMeetingState(works[index]));
    }
    if (version !== rspLoadVersion) return;
    root.querySelector("#rsp-loading")?.remove();
    root.insertAdjacentHTML("beforeend", `<section class="rsp-list">${states.map(renderRspWork).join("")}</section>`);
  }

  function bind() {
    document.querySelector("#notification-button")?.addEventListener("click", openNotificationDrawer);
    document.querySelector("#notification-close")?.addEventListener("click", closeNotificationDrawer);
    document.querySelector("#notification-scrim")?.addEventListener("click", closeNotificationDrawer);
    document.addEventListener("keydown", event => {
      if (event.key === "Escape") closeNotificationDrawer();
    });
    document.querySelector("#notification-drawer")?.addEventListener("click", event => {
      const viewButton = event.target.closest("[data-notification-view]");
      if (viewButton) {
        closeNotificationDrawer();
        showView(viewButton.dataset.notificationView, { teamTab: viewButton.dataset.notificationTab || undefined });
        return;
      }
      const resolveButton = event.target.closest("[data-resolve-alert]");
      if (resolveButton) resolveAlert(resolveButton.dataset.resolveAlert, resolveButton);
    });
    document.querySelector("#overview-view").addEventListener("click", event => {
      const resolveButton = event.target.closest("[data-resolve-alert]");
      if (resolveButton) {
        resolveAlert(resolveButton.dataset.resolveAlert, resolveButton);
        return;
      }
      const meetingButton = event.target.closest("[data-meeting-work]");
      if (meetingButton) return openMeeting(meetingButton.dataset.meetingWork);
      const actionButton = event.target.closest("[data-action-view]");
      if (actionButton) showView(actionButton.dataset.actionView);
      const planningSummary = event.target.closest("[data-planning-summary]");
      if (planningSummary) return showView("planning", { workId: planningSummary.dataset.planningSummary, view: "summary" });
      const planningWork = event.target.closest("[data-planning-work]");
      if (planningWork) return showView("planning", { workId: planningWork.dataset.planningWork, view: "effective" });
      const rncWork = event.target.closest("[data-rnc-work]");
      if (rncWork) return showView("rnc", { workId: rncWork.dataset.rncWork });
    });
    document.querySelector("#rsp-view")?.addEventListener("click", event => {
      const meetingButton = event.target.closest("[data-rsp-open-meeting]");
      if (meetingButton) openMeeting(meetingButton.dataset.rspOpenMeeting, "rsp");
    });
    document.querySelector("#meeting-view")?.addEventListener("submit", event => {
      const adjustment = event.target.closest("[data-cost-adjustment]");
      if (adjustment) { event.preventDefault(); saveCostAdjustment(adjustment); return; }
      const plCost = event.target.closest("[data-confirm-pl-cost]");
      if (plCost) { event.preventDefault(); confirmPlCost(plCost); }
    });
    document.querySelector("#meeting-view")?.addEventListener("click", event => {
      const button = event.target.closest("[data-delete-cost-adjustment]");
      if (button) { deleteCostAdjustment(button.dataset.deleteCostAdjustment, button); return; }
      const subcontract = event.target.closest("[data-confirm-sub-cost]");
      if (subcontract) confirmSubcontractCost(subcontract.dataset.confirmSubCost, subcontract);
    });
  }

  return { bind, refreshOverview, openMeeting, showRsp, showWorkCosts };
}
