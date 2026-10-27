const number = value => Number(value || 0);
const sum = (rows, field) => rows.reduce((total, row) => total + number(row[field]), 0);
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const clamp = value => Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
const safeDate = value => value ? new Date(`${String(value).slice(0, 10)}T12:00:00`) : null;
const monthKey = value => value ? String(value).slice(0, 7) : "";
const monthLabel = key => new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit" }).format(new Date(`${key}-01T12:00:00`)).toUpperCase();

export function createConsolidatedView(options) {
  const { root, supabase, isConfigured, getWorks, getInvoices, euro, toast } = options;
  let loading = false;

  async function read(path, label, warnings) {
    const response = await supabase(path);
    if (response.ok) return response.json();
    const detail = await response.json().catch(() => ({}));
    warnings.push(`${label}: ${detail.message || "sem acesso"}`);
    return [];
  }

  async function authorize() {
    if (!isConfigured) return true;
    const response = await supabase("rpc/fn_pode_ver_visao_consolidada", { method: "POST", body: "{}" });
    return response.ok && await response.json() === true;
  }

  function currentByWork(rows, scoreField) {
    const result = new Map();
    rows.forEach(row => {
      const current = result.get(row.obra_id);
      if (!current || number(row[scoreField]) > number(current[scoreField]) || String(row.atualizado_em || row.criado_em || "") > String(current.atualizado_em || current.criado_em || "")) result.set(row.obra_id, row);
    });
    return result;
  }

  function dueDate(invoice) {
    const due = safeDate(invoice.data_vencimento || invoice.data_fatura);
    if (!due || invoice.data_vencimento) return due;
    const days = invoice.condicao_pagamento === "30_dias" ? 30 : invoice.condicao_pagamento === "15_dias" ? 15 : 0;
    due.setDate(due.getDate() + days);
    return due;
  }

  function periodBounds() {
    const today = new Date();
    today.setHours(12, 0, 0, 0);
    const monday = new Date(today);
    monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
    const sunday = new Date(monday); sunday.setDate(monday.getDate() + 6);
    const monthStart = new Date(today.getFullYear(), today.getMonth(), 1, 12);
    const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0, 12);
    return { today, monday, sunday, monthStart, monthEnd };
  }

  function workExecution(workId, data) {
    const phaseIds = new Set(data.phases.filter(row => row.obra_id === workId).map(row => row.id));
    const plans = data.phasePlanning.filter(row => phaseIds.has(row.fase_id));
    const progress = new Map(plans.map(row => [row.fase_id, number(row.percentual_executado)]));
    const items = data.budgetItems.filter(row => phaseIds.has(row.fase_id));
    const totalSale = sum(items, "venda_prevista");
    if (totalSale) return clamp(items.reduce((total, item) => total + number(item.venda_prevista) / totalSale * (progress.get(item.fase_id) || 0), 0));
    return plans.length ? clamp(plans.reduce((total, row) => total + number(row.percentual_executado), 0) / plans.length) : 0;
  }

  function deadlinePercent(work) {
    const start = safeDate(work.data_inicio)?.getTime();
    const end = safeDate(work.data_fim_prevista)?.getTime();
    if (!start || !end || end <= start) return 0;
    return clamp((Date.now() - start) / (end - start) * 100);
  }

  function urgentAlert(alert) {
    const text = `${alert.urgencia || ""} ${alert.prioridade || ""} ${alert.tipo || ""} ${alert.titulo || ""}`.toLocaleLowerCase("pt-PT");
    return alert.estado === "pendente" && (/(urgente|cr[ií]tic|atrasad|vencid|bloque)/.test(text) || (safeDate(alert.data_gatilho) && safeDate(alert.data_gatilho) < new Date()));
  }

  function actualCost(workId, data) {
    const subcontractIds = new Set(data.subcontracts.filter(row => row.obra_id === workId).map(row => row.id));
    const debitIds = new Set(data.directDebits.filter(row => row.obra_id === workId).map(row => row.id));
    const subcontract = data.subcontractPayments.filter(row => subcontractIds.has(row.subempreitada_id)).reduce((total, row) => total + number(row.valor), 0);
    const labor = data.labor.filter(row => row.obra_id === workId).reduce((total, row) => total + number(row.valor_total ?? number(row.horas) * number(row.valor_hora)), 0);
    const site = data.siteExpenses.filter(row => row.obra_id === workId).reduce((total, row) => total + number(row.valor_total), 0);
    const debits = data.directDebitEntries.filter(row => debitIds.has(row.debito_direto_id)).reduce((total, row) => total + number(row.valor), 0);
    const materials = data.invoices.filter(row => row.obra_id === workId && row.tipo_origem === "material" && (row.estado_pagamento === "pago" || row.data_pagamento)).reduce((total, row) => total + number(row.valor), 0);
    return subcontract + labor + site + debits + materials;
  }

  function financialSummary(data) {
    const contracts = currentByWork(data.contracts, "venda_contratual_efetiva");
    const investments = currentByWork(data.investments, "orcamento_revisto_sem_iva");
    const clientWorks = data.works.filter(work => work.modalidade !== "investimento_proprio");
    const investmentWorks = data.works.filter(work => work.modalidade === "investimento_proprio");
    const client = clientWorks.reduce((total, work) => {
      const contract = contracts.get(work.id) || {};
      const tees = data.tees.filter(row => row.obra_id === work.id && row.estado_aprovacao_cliente === "aprovado");
      const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial) + sum(tees, "valor");
      const cost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial) + sum(tees, "preco_custo");
      total.sale += sale; total.cost += cost; total.margin += sale - cost;
      return total;
    }, { sale: 0, cost: 0, margin: 0 });
    const investment = investmentWorks.reduce((total, work) => {
      const row = investments.get(work.id) || {};
      total.initial += number(row.orcamento_inicial_sem_iva);
      total.revised += number(row.orcamento_revisto_sem_iva || row.orcamento_inicial_sem_iva);
      total.actual += actualCost(work.id, data);
      return total;
    }, { initial: 0, revised: 0, actual: 0 });
    investment.deviation = investment.actual - investment.revised;
    return { client, investment, clientCount: clientWorks.length, investmentCount: investmentWorks.length };
  }

  function cashFlowRows(rows) {
    const grouped = new Map();
    rows.forEach(row => {
      const key = monthKey(row.mes || row.mes_referencia);
      if (!key) return;
      const month = grouped.get(key) || { month: key, incomingReal: 0, incomingForecast: 0, outgoingReal: 0, outgoingForecast: 0 };
      month.incomingReal += number(row.entradas_reais);
      month.incomingForecast += number(row.entradas_previstas);
      month.outgoingReal += number(row.saidas_reais_com_iva ?? row.saidas_reais_sem_iva ?? row.saidas_reais);
      month.outgoingForecast += number(row.saidas_previstas_com_iva ?? row.saidas_previstas_sem_iva ?? row.saidas_previstas);
      grouped.set(key, month);
    });
    return [...grouped.values()].sort((a, b) => a.month.localeCompare(b.month));
  }

  function renderCashFlow(rows) {
    if (!rows.length) return '<div class="consolidated-empty">SEM PREVISÃO FINANCEIRA REGISTADA</div>';
    const max = Math.max(1, ...rows.flatMap(row => [row.incomingReal, row.incomingForecast, row.outgoingReal, row.outgoingForecast]));
    return `<div class="consolidated-cashflow-chart">${rows.map(row => `<article>
      <div class="consolidated-bars">
        <i class="incoming-real" style="height:${Math.max(2, row.incomingReal / max * 100)}%" title="Entradas reais: ${euro.format(row.incomingReal)}"></i>
        <i class="incoming-forecast" style="height:${Math.max(2, row.incomingForecast / max * 100)}%" title="Entradas previstas: ${euro.format(row.incomingForecast)}"></i>
        <i class="outgoing-real" style="height:${Math.max(2, row.outgoingReal / max * 100)}%" title="Saídas reais: ${euro.format(row.outgoingReal)}"></i>
        <i class="outgoing-forecast" style="height:${Math.max(2, row.outgoingForecast / max * 100)}%" title="Saídas previstas: ${euro.format(row.outgoingForecast)}"></i>
      </div><strong>${monthLabel(row.month)}</strong><small>R ${euro.format(row.incomingReal - row.outgoingReal)}</small>
    </article>`).join("")}</div>
    <div class="consolidated-legend"><span class="incoming-real">ENTRADAS REAIS</span><span class="incoming-forecast">ENTRADAS PREVISTAS</span><span class="outgoing-real">SAÍDAS REAIS</span><span class="outgoing-forecast">SAÍDAS PREVISTAS</span></div>`;
  }

  function render(data, warnings) {
    const financial = financialSummary(data);
    const bounds = periodBounds();
    const unpaid = data.invoices.filter(row => row.estado_aprovacao === "aprovado" && (row.estado_pagamento || "por_pagar") === "por_pagar");
    const dueWeek = unpaid.filter(row => { const date = dueDate(row); return date && date >= bounds.monday && date <= bounds.sunday; });
    const dueMonth = unpaid.filter(row => { const date = dueDate(row); return date && date >= bounds.monthStart && date <= bounds.monthEnd; });
    const openRncs = data.rncs.filter(row => row.estado !== "fechado");
    const pendingInvoices = data.invoices.filter(row => row.estado_aprovacao === "pendente");
    const monthIncidents = data.incidents.filter(row => monthKey(row.data) === monthKey(bounds.today.toISOString()));
    const cashFlow = cashFlowRows(data.forecasts);
    const supplierById = new Map(data.suppliers.map(row => [row.id, row]));
    const subcontractById = new Map(data.subcontracts.map(row => [row.id, row]));
    const rankings = [...data.evaluations.reduce((map, row) => {
      const supplierId = row.fornecedor_id || subcontractById.get(row.subempreitada_id)?.fornecedor_id;
      if (!supplierId) return map;
      const entry = map.get(supplierId) || { supplierId, total: 0, count: 0 };
      ["qualidade", "cumprimento_prazo", "seguranca", "comunicacao"].forEach(field => { if (row[field] != null) { entry.total += number(row[field]); entry.count += 1; } });
      map.set(supplierId, entry); return map;
    }, new Map()).values()].filter(row => row.count).map(row => ({ ...row, average: row.total / row.count })).sort((a, b) => b.average - a.average);
    const sortedWorks = [...data.works].sort((a, b) => number(a.numero) - number(b.numero) || String(a.nome).localeCompare(String(b.nome), "pt"));

    root.innerHTML = `<div class="consolidated-heading"><div><p class="eyebrow">GESTÃO · DIREÇÃO</p><h1>VISÃO CONSOLIDADA</h1><p>Leitura global financeira, operacional e de risco de todas as obras.</p></div><span>ATUALIZADO AGORA</span></div>
      ${warnings.length ? `<div class="overview-warning">Dados parciais: ${escapeHtml(warnings.join(" · "))}</div>` : ""}
      <section class="consolidated-counters">
        <article class="urgent"><span>RNCs ABERTAS</span><strong>${openRncs.length}</strong><small>toda a empresa</small></article>
        <article class="attention"><span>FATURAS PENDENTES</span><strong>${pendingInvoices.length}</strong><small>aguardam aprovação</small></article>
        <article><span>INCIDENTES ESTE MÊS</span><strong>${monthIncidents.length}</strong><small>segurança</small></article>
        <article><span>A PAGAR ESTA SEMANA</span><strong>${euro.format(sum(dueWeek, "valor"))}</strong><small>${dueWeek.length} faturas</small></article>
        <article><span>A PAGAR ESTE MÊS</span><strong>${euro.format(sum(dueMonth, "valor"))}</strong><small>${dueMonth.length} faturas</small></article>
      </section>
      <section class="consolidated-financial-grid">
        <article class="panel"><div class="consolidated-section-title"><span>OBRAS DE CLIENTE</span><small>${financial.clientCount} obras</small></div><div class="consolidated-metrics"><div><span>VENDA ATUALIZADA</span><strong>${euro.format(financial.client.sale)}</strong></div><div><span>CUSTO ATUALIZADO</span><strong>${euro.format(financial.client.cost)}</strong></div><div><span>MARGEM PREVISTA</span><strong class="${financial.client.margin < 0 ? "negative" : "positive"}">${euro.format(financial.client.margin)}</strong></div></div></article>
        <article class="panel"><div class="consolidated-section-title"><span>INVESTIMENTO PRÓPRIO</span><small>${financial.investmentCount} obras</small></div><div class="consolidated-metrics investment"><div><span>ORÇAMENTO INICIAL</span><strong>${euro.format(financial.investment.initial)}</strong></div><div><span>ORÇAMENTO REVISTO</span><strong>${euro.format(financial.investment.revised)}</strong></div><div><span>CUSTO REALIZADO</span><strong>${euro.format(financial.investment.actual)}</strong></div><div><span>DESVIO</span><strong class="${financial.investment.deviation > 0 ? "negative" : "positive"}">${euro.format(financial.investment.deviation)}</strong></div></div></article>
      </section>
      <section class="panel consolidated-panel"><div class="consolidated-section-title"><span>CASH FLOW CONSOLIDADO</span><small>${cashFlow.length} meses · todas as obras</small></div>${renderCashFlow(cashFlow)}</section>
      <section class="consolidated-lower">
        <article class="panel consolidated-panel"><div class="consolidated-section-title"><span>PORTFÓLIO DE OBRAS</span><small>${sortedWorks.length} obras</small></div><div class="consolidated-work-list">${sortedWorks.map(work => {
          const execution = workExecution(work.id, data); const deadline = deadlinePercent(work);
          const urgent = data.alerts.filter(row => row.obra_id === work.id && urgentAlert(row)).length;
          const rncs = openRncs.filter(row => row.obra_id === work.id).length;
          return `<div class="consolidated-work"><b>${escapeHtml(work.numero || "—")}</b><span><strong>${escapeHtml(work.nome || "Obra")}</strong><small>${work.modalidade === "investimento_proprio" ? "INVESTIMENTO PRÓPRIO" : "CLIENTE EXTERNO"}</small></span><div><small>EXECUÇÃO ${Math.round(execution)}%</small><i><em style="width:${execution}%"></em></i></div><div><small>PRAZO ${Math.round(deadline)}%</small><i class="deadline"><em style="width:${deadline}%"></em></i></div><mark class="${urgent ? "urgent" : ""}">${urgent} ALERTAS</mark><mark class="${rncs ? "urgent" : ""}">${rncs} RNCs</mark></div>`;
        }).join("") || '<div class="consolidated-empty">SEM OBRAS</div>'}</div></article>
        <article class="panel consolidated-panel"><div class="consolidated-section-title"><span>RANKING DE SUBEMPREITEIROS</span><small>avaliação média</small></div><div class="consolidated-ranking">${rankings.slice(0, 10).map((row, index) => `<div><b>${String(index + 1).padStart(2, "0")}</b><span><strong>${escapeHtml(supplierById.get(row.supplierId)?.nome || "Fornecedor")}</strong><small>${row.count} notas consideradas</small></span><em>${row.average.toFixed(1)}</em><i><mark style="width:${clamp(row.average / 5 * 100)}%"></mark></i></div>`).join("") || '<div class="consolidated-empty">SEM AVALIAÇÕES</div>'}</div></article>
      </section>`;
  }

  async function show() {
    if (loading) return;
    loading = true;
    root.innerHTML = '<div class="meeting-loading">A CARREGAR VISÃO CONSOLIDADA…</div>';
    try {
      if (!await authorize()) {
        root.innerHTML = '<div class="panel consolidated-denied"><strong>ACESSO RESERVADO</strong><p>Esta vista é exclusiva da gerência e dos administradores da plataforma.</p></div>';
        return;
      }
      if (!isConfigured) {
        render({ works: getWorks(), invoices: getInvoices(), contracts: [], tees: [], investments: [], phases: [], phasePlanning: [], budgetItems: [], forecasts: [], alerts: [], rncs: [], evaluations: [], suppliers: [], subcontracts: [], incidents: [], subcontractPayments: [], labor: [], siteExpenses: [], directDebits: [], directDebitEntries: [] }, []);
        return;
      }
      const warnings = [];
      const queries = [
        ["contratos?select=*", "Contratos"], ["alteracoes_tee?select=*", "TEEs"], ["investimentos?select=*", "Investimentos"],
        ["fases?select=*", "Fases"], ["planeamento_fases_resumo?select=*", "Progresso"], ["itens_orcamento?select=*", "Orçamento"],
        ["previsao_financeira_mensal?select=*&order=mes.asc", "Cash flow"], ["alertas?select=*", "Alertas"], ["rnc?select=*", "RNCs"],
        ["avaliacoes_subempreiteiro?select=*", "Avaliações"], ["fornecedores?select=*", "Fornecedores"], ["subempreitadas?select=*", "Subempreitadas"],
        ["seguranca_incidentes?select=*", "Segurança"], ["faturas?select=*", "Faturas"], ["pagamentos_subempreitada?select=*", "Pagamentos"],
        ["lancamentos_mao_obra?select=*", "Mão de obra"], ["despesas_estaleiro?select=*", "Estaleiro"], ["debitos_diretos?select=*", "Débitos diretos"],
        ["debitos_diretos_lancamentos?select=*", "Lançamentos de débitos"],
      ];
      const values = await Promise.all(queries.map(([path, label]) => read(path, label, warnings)));
      const [contracts, tees, investments, phases, phasePlanning, budgetItems, forecasts, alerts, rncs, evaluations, suppliers, subcontracts, incidents, queriedInvoices, subcontractPayments, labor, siteExpenses, directDebits, directDebitEntries] = values;
      render({ works: getWorks(), invoices: queriedInvoices, contracts, tees, investments, phases, phasePlanning, budgetItems, forecasts, alerts, rncs, evaluations, suppliers, subcontracts, incidents, subcontractPayments, labor, siteExpenses, directDebits, directDebitEntries }, warnings);
    } catch (error) {
      root.innerHTML = `<div class="panel consolidated-denied"><strong>NÃO FOI POSSÍVEL CARREGAR</strong><p>${escapeHtml(error.message)}</p></div>`;
      toast?.("Não foi possível carregar a Visão Consolidada.", "error");
    } finally { loading = false; }
  }

  return { show };
}
