const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);
const number = value => Number(value || 0);
const MONTHS = ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"];
const FIXED_ROWS = [
  ["remuneracoes_sede", "Remunerações e Encargos (Sede)"],
  ["despesas_sede", "Despesas Sede"],
  ["despesas_armazem", "Despesas Armazém"],
];

const monthDate = (year, month) => `${year}-${String(month).padStart(2, "0")}-01`;
const monthIndex = value => value ? Number(String(value).slice(5, 7)) - 1 : -1;
const isActiveWork = work => !["concluida", "concluído", "concluido", "cancelada"].includes(String(work.situacao || "").toLocaleLowerCase("pt-PT"));

function inclusiveMonths(start, end) {
  if (!start || !end) return 0;
  const first = new Date(`${start}T12:00:00`); const last = new Date(`${end}T12:00:00`);
  if (last < first) return 0;
  return (last.getFullYear() - first.getFullYear()) * 12 + last.getMonth() - first.getMonth() + 1;
}

function activeInMonth(work, year, month) {
  if (!work.data_inicio || !work.data_fim_prevista) return false;
  const start = new Date(`${work.data_inicio}T12:00:00`);
  const end = new Date(`${work.data_fim_prevista}T12:00:00`);
  const monthStart = new Date(year, month, 1, 12);
  const monthEnd = new Date(year, month + 1, 0, 12);
  return start <= monthEnd && end >= monthStart;
}

export function createFinancialMapModule({ root, supabase, isConfigured, getWorks, getProfile, euro, toast }) {
  const state = {
    year: new Date().getFullYear(), loaded: false, loading: false, error: "",
    contracts: [], investments: [], forecast: [], adjustments: [], debits: [], entries: [], editing: null,
  };

  async function api(path, options) {
    const response = await supabase(path, options);
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.message || payload.details || "Não foi possível consultar o mapa financeiro.");
    }
    return response.status === 204 ? [] : response.json();
  }

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) Object.assign(state, { contracts: [], investments: [], forecast: [], adjustments: [], debits: [], entries: [] });
      else [state.contracts, state.investments, state.forecast, state.adjustments, state.debits, state.entries] = await Promise.all([
        api("contratos?select=*&order=atualizado_em.desc.nullslast"),
        api("investimentos?select=*"),
        api("previsao_financeira_mensal?select=*&tipo=eq.previsao&order=mes.asc"),
        api(`mapa_financeiro_ajustes?select=*&ano=eq.${state.year}&order=mes.asc`),
        api("debitos_diretos?select=id,categoria,descricao"),
        api(`debitos_diretos_lancamentos?select=id,debito_direto_id,data,valor&data=gte.${state.year}-01-01&data=lte.${state.year}-12-31&order=data.asc`),
      ]);
      state.loaded = true;
    } catch (error) { state.error = `${error.message} Confirme se executou o SQL do Mapa Financeiro.`; }
    finally { state.loading = false; render(); }
  }

  const currentByWork = (rows, preferred) => {
    const map = new Map();
    rows.forEach(row => {
      const current = map.get(row.obra_id);
      if (!current || number(row[preferred]) || !number(current[preferred])) map.set(row.obra_id, row);
    });
    return map;
  };

  function buildRows() {
    const contracts = currentByWork(state.contracts, "venda_contratual_efetiva");
    const investments = currentByWork(state.investments, "orcamento_revisto_sem_iva");
    const yearlyForecast = state.forecast.filter(row => Number(String(row.mes).slice(0, 4)) === state.year);
    const forecastByWorkMonth = new Map(yearlyForecast.map(row => [`${row.obra_id}:${monthIndex(row.mes)}`, row]));
    const adjustmentByWorkMonth = new Map(state.adjustments.map(row => [`${row.obra_id}:${row.mes - 1}`, row]));
    return getWorks().filter(isActiveWork).sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true })).map(work => {
      const investmentMode = work.modalidade === "investimento_proprio";
      const contract = contracts.get(work.id) || {};
      const investment = investments.get(work.id) || {};
      const pv = investmentMode
        ? number(investment.orcamento_revisto_sem_iva || investment.orcamento_inicial_sem_iva)
        : number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
      const actualOutflows = state.forecast.filter(row => row.obra_id === work.id).reduce((sum, row) => sum + number(row.saidas_reais_sem_iva || row.saidas_reais_com_iva), 0);
      const pc = investmentMode
        ? number(investment.custo_realizado_sem_iva || investment.custo_realizado || actualOutflows)
        : number(contract.custo_direto_efetivo || contract.custo_direto_inicial);
      const margin = investmentMode ? null : pv - pc;
      const duration = inclusiveMonths(work.data_inicio, work.data_fim_prevista);
      const estimate = margin == null || !duration ? null : margin / duration;
      const billing = state.forecast.filter(row => row.obra_id === work.id).reduce((sum, row) => {
        const useReal = Boolean(row.fechado) || number(row.entradas_reais) !== 0;
        return sum + number(useReal ? row.entradas_reais : row.entradas_previstas);
      }, 0);
      const months = MONTHS.map((_, month) => {
        const forecast = forecastByWorkMonth.get(`${work.id}:${month}`);
        const hasReal = Boolean(forecast?.fechado) || number(forecast?.entradas_reais) !== 0 || number(forecast?.saidas_reais_sem_iva || forecast?.saidas_reais_com_iva) !== 0;
        const calculated = hasReal
          ? number(forecast.entradas_reais) - number(forecast.saidas_reais_sem_iva || forecast.saidas_reais_com_iva)
          : (activeInMonth(work, state.year, month) ? estimate : null);
        const adjustment = adjustmentByWorkMonth.get(`${work.id}:${month}`);
        return { calculated, final: adjustment ? number(adjustment.valor_ajustado) : calculated, adjustment, calculatedSource: hasReal ? "real" : "estimated", source: adjustment ? "adjusted" : hasReal ? "real" : "estimated" };
      });
      return { work, investmentMode, pv, pc, margin, duration, estimate, billing, months, total: months.reduce((sum, row) => sum + number(row.final), 0) };
    });
  }

  function format(value, dash = false) {
    if (value == null && dash) return "—";
    return euro.format(number(value));
  }

  function renderCell(row, month) {
    const cell = row.months[month];
    if (cell.final == null) return `<td class="map-month empty"><button type="button" data-map-adjust="${row.work.id}:${month + 1}" title="Criar ajuste">—</button></td>`;
    return `<td class="map-month ${cell.source}"><button type="button" data-map-adjust="${row.work.id}:${month + 1}" title="Ajustar valor"><strong>${format(cell.final)}</strong><small>${cell.source === "adjusted" ? `CALC. ${format(cell.calculated)}` : cell.source === "real" ? "REAL" : "ESTIMADO"}</small></button></td>`;
  }

  function businessVolume(month) {
    return state.forecast.filter(row => Number(String(row.mes).slice(0, 4)) === state.year && monthIndex(row.mes) === month).reduce((sum, row) => {
      const useReal = Boolean(row.fechado) || number(row.entradas_reais) !== 0;
      return sum + number(useReal ? row.entradas_reais : row.entradas_previstas);
    }, 0);
  }

  function fixedExpenses(category, month) {
    const debitIds = new Set(state.debits.filter(row => row.categoria === category).map(row => row.id));
    return state.entries.filter(row => debitIds.has(row.debito_direto_id) && monthIndex(row.data) === month).reduce((sum, row) => sum + number(row.valor), 0);
  }

  function renderSummary(rows) {
    const totalBilling = rows.reduce((sum, row) => sum + row.billing, 0);
    const totalMargin = rows.filter(row => !row.investmentMode).reduce((sum, row) => sum + number(row.margin), 0);
    const monthTotals = MONTHS.map((_, month) => rows.reduce((sum, row) => sum + number(row.months[month].final), 0));
    return `<div class="financial-map-scroll"><table class="financial-map-table"><thead><tr><th class="map-work">OBRA</th>${MONTHS.map(month => `<th>${month}</th>`).join("")}<th>TOTAL</th><th>PV</th><th>PC</th><th>MARGEM</th><th>PRAZO<br>(MESES)</th><th>CFLOW<br>MÉDIO/MÊS</th><th>% FATURAÇÃO</th><th>% MARGEM</th></tr></thead><tbody>
      ${rows.map(row => `<tr><th class="map-work"><span>${esc(row.work.numero)}</span><strong>${esc(row.work.nome)}</strong>${row.investmentMode ? "<small>INVESTIMENTO PRÓPRIO</small>" : ""}</th>${MONTHS.map((_, month) => renderCell(row, month)).join("")}<td><strong>${format(row.total)}</strong></td><td>${format(row.pv)}</td><td>${format(row.pc)}</td><td>${format(row.margin, true)}</td><td>${row.duration || "—"}</td><td>${format(row.estimate, true)}</td><td>${!totalBilling ? "—" : `${(row.billing / totalBilling * 100).toFixed(1)}%`}</td><td>${row.investmentMode || !totalMargin ? "—" : `${(number(row.margin) / totalMargin * 100).toFixed(1)}%`}</td></tr>`).join("")}
      <tr class="map-total"><th>TOTAL OBRAS</th>${monthTotals.map(value => `<td>${format(value)}</td>`).join("")}<td>${format(monthTotals.reduce((sum, value) => sum + value, 0))}</td><td>${format(rows.reduce((sum, row) => sum + row.pv, 0))}</td><td>${format(rows.reduce((sum, row) => sum + row.pc, 0))}</td><td>${format(totalMargin)}</td><td>—</td><td>—</td><td>100%</td><td>100%</td></tr>
    </tbody></table></div>`;
  }

  function renderFixedExpenses() {
    const values = new Map(FIXED_ROWS.map(([category]) => [category, MONTHS.map((_, month) => fixedExpenses(category, month))]));
    const totals = MONTHS.map((_, month) => FIXED_ROWS.reduce((sum, [category]) => sum + values.get(category)[month], 0));
    const volumes = MONTHS.map((_, month) => businessVolume(month));
    const variations = MONTHS.map((_, month) => volumes[month] - totals[month]);
    let running = 0; const accumulated = variations.map(value => (running += value));
    const row = (label, monthly, formatter = format) => `<tr><th>${label}</th>${monthly.map(value => `<td>${formatter(value)}</td>`).join("")}<td>${formatter(monthly.reduce((sum, value) => sum + value, 0))}</td></tr>`;
    return `<section class="panel fixed-expenses"><header><div><p class="eyebrow">ESTRUTURA DA EMPRESA</p><h2>DESPESAS FIXAS E TESOURARIA</h2></div><small>Lançamentos reais dos débitos diretos</small></header><div class="financial-map-scroll"><table class="fixed-expenses-table"><thead><tr><th>INDICADOR</th>${MONTHS.map(month => `<th>${month}</th>`).join("")}<th>TOTAL</th></tr></thead><tbody>
      ${FIXED_ROWS.map(([category, label]) => row(label, values.get(category))).join("")}
      ${row("Total das despesas", totals)}
      ${row("Peso dos Custos Fixos", MONTHS.map((_, month) => volumes[month] ? totals[month] / volumes[month] * 100 : 0), value => `${number(value).toFixed(1)}%`)}
      ${row("Variação de tesouraria", variations)}
      ${row("Acumulado", accumulated)}
    </tbody></table></div></section>`;
  }

  function renderAdjustment(rows) {
    if (!state.editing) return "";
    const row = rows.find(item => item.work.id === state.editing.workId); const cell = row?.months[state.editing.month - 1];
    if (!row || !cell) return "";
    return `<section class="panel map-adjustment"><header><div><p class="eyebrow">AJUSTE MANUAL</p><h2>OBRA ${esc(row.work.numero)} · ${MONTHS[state.editing.month - 1]} ${state.year}</h2></div><button type="button" data-map-adjust-close>×</button></header><div class="map-adjustment-reference"><span>VALOR CALCULADO</span><strong>${format(cell.calculated, true)}</strong><small>${cell.calculatedSource === "real" ? "Origem real" : "Distribuição automática"}</small></div><form data-map-adjustment-form><input type="hidden" name="obra_id" value="${row.work.id}"><input type="hidden" name="mes" value="${state.editing.month}"><label>VALOR AJUSTADO (€)<input name="valor_ajustado" type="number" step="0.01" required value="${cell.adjustment?.valor_ajustado ?? cell.calculated ?? 0}"></label><label>MOTIVO DO AJUSTE<input name="motivo" maxlength="300" value="${esc(cell.adjustment?.motivo || "")}" placeholder="Ex. prorrogação do prazo da obra"></label><button class="primary-button" type="submit">GUARDAR AJUSTE <span>→</span></button>${cell.adjustment ? `<button type="button" class="outline-action" data-map-adjust-remove>REMOVER AJUSTE</button>` : ""}<p class="form-error"></p></form></section>`;
  }

  function render() {
    const rows = buildRows();
    root.innerHTML = `${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)}</span></div>` : ""}${state.loading ? `<div class="fleet-loading">A CARREGAR MAPA FINANCEIRO…</div>` : `<section class="panel financial-map"><header><div><p class="eyebrow">CONTROLO ANUAL</p><h2>MAPA FINANCEIRO · ${state.year}</h2><p>Margem distribuída pelo prazo, substituída por valores reais nos meses já realizados.</p></div><div class="map-legend"><span class="real">REAL</span><span class="estimated">ESTIMADO</span><span class="adjusted">AJUSTADO</span></div></header>${renderSummary(rows)}</section>${renderAdjustment(rows)}${renderFixedExpenses()}`}`;
  }

  async function removeAdjustment() {
    const editing = state.editing;
    if (!editing) return;
    if (isConfigured) await api(`mapa_financeiro_ajustes?obra_id=eq.${encodeURIComponent(editing.workId)}&ano=eq.${state.year}&mes=eq.${editing.month}`, { method: "DELETE" });
    state.adjustments = state.adjustments.filter(row => !(row.obra_id === editing.workId && row.ano === state.year && row.mes === editing.month));
    state.editing = null; toast("Ajuste removido; o valor calculado voltou a ser usado."); render();
  }

  root.addEventListener("click", async event => {
    const adjust = event.target.closest("[data-map-adjust]");
    if (adjust) { const [workId, month] = adjust.dataset.mapAdjust.split(":"); state.editing = { workId, month: Number(month) }; render(); root.querySelector(".map-adjustment")?.scrollIntoView({ behavior: "smooth", block: "center" }); return; }
    if (event.target.closest("[data-map-adjust-close]")) { state.editing = null; render(); return; }
    if (event.target.closest("[data-map-adjust-remove]")) {
      try { await removeAdjustment(); } catch (error) { toast(error.message, "error"); }
    }
  });

  root.addEventListener("submit", async event => {
    const form = event.target.closest("[data-map-adjustment-form]");
    if (!form) return; event.preventDefault();
    const errorNode = form.querySelector(".form-error"); const button = form.querySelector('button[type="submit"]'); button.disabled = true; errorNode.textContent = "";
    try {
      const fields = Object.fromEntries(new FormData(form));
      const row = buildRows().find(item => item.work.id === fields.obra_id);
      const calculated = row?.months[Number(fields.mes) - 1]?.calculated;
      const payload = { obra_id: fields.obra_id, ano: state.year, mes: Number(fields.mes), valor_calculado_referencia: calculated, valor_ajustado: Number(fields.valor_ajustado), motivo: fields.motivo.trim() || null, atualizado_por: getProfile()?.id || null, atualizado_em: new Date().toISOString() };
      let saved = { id: crypto.randomUUID(), ...payload };
      if (isConfigured) [saved] = await api("mapa_financeiro_ajustes?on_conflict=obra_id,ano,mes&select=*", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=representation" }, body: JSON.stringify(payload) });
      state.adjustments = state.adjustments.filter(row => !(row.obra_id === payload.obra_id && row.ano === payload.ano && row.mes === payload.mes)); state.adjustments.push(saved); state.editing = null;
      toast("Ajuste mensal guardado sem alterar o valor calculado."); render();
    } catch (error) { errorNode.textContent = error.message || "Não foi possível guardar o ajuste."; button.disabled = false; }
  });

  return { show: () => load(), refresh: () => load(true) };
}
