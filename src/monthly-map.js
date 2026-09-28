import { STAGES, STAGE_LABELS } from './monthly-engine.js';
import { MONTH_STATES, protectedMonth } from './monthly-state.js';
import { readMonthlySummary, readMonthlyOrigins, changeMonthlyState, recalculateMonthly } from './monthly-api.js';
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

export function createFinancialMapModule({ root, supabase, isConfigured, getWorks, euro, toast, canManage = () => false }) {
  const state = { workId: '', year: new Date().getFullYear(), summary: null, loaded: false, busy: false, error: '', detail: null, generation: 0 };
  const money = value => euro.format(value / 100);
  const label = value => String(value).toUpperCase().replaceAll('_', ' ');
  function render() {
    const summary = state.summary, disabled = state.busy ? 'disabled' : '';
    const works = getWorks();
    root.innerHTML = `<section class="panel financial-map"><header><div><p class="eyebrow">ORIGENS FINANCEIRAS</p><h2>MAPA MENSAL</h2><p>Caixa por data de movimento ou previsão. Os estados referem-se à competência económica.</p></div></header>
      <div class="monthly-controls"><label>Obra<select data-monthly-work ${disabled}>${works.map(work => `<option value="${esc(work.id)}" ${work.id === state.workId ? 'selected' : ''}>${esc(work.numero)} · ${esc(work.nome)}</option>`).join('')}</select></label><label>Ano<input data-monthly-year type="number" min="2000" max="2200" value="${state.year}" ${disabled}></label><button data-monthly-refresh ${disabled}>ATUALIZAR</button>${summary && canManage() ? `<button data-monthly-recalculate ${disabled}>RECALCULAR PREVISÃO ABERTA</button>` : ''}</div>
      <p role="status">${state.busy ? 'A processar…' : ''}</p>${state.error ? `<div class="work-warning" role="alert">${esc(state.error)}</div>` : ''}
      ${summary ? renderSummary(summary) : '<div class="empty-state"><strong>RESUMO MENSAL INDISPONÍVEL</strong><span>Os totais rastreáveis serão apresentados quando o serviço estiver disponível.</span></div>'}
      ${renderDetail()}</section>`;
  }
  function renderSummary(summary) {
    const indicators = [['Saldo atual', summary.current_balance], ['Saldo final previsto do ano', summary.finalBalance], ['Mínimo acumulado', summary.minimum], ['Necessidade máxima de caixa', summary.maximumCashNeed], ['A receber vencido', summary.overdue], ['Entradas reais', summary.totals.received], ['Entradas futuras', summary.totals.receivable + summary.totals.future_income], ['Saídas reais', summary.totals.paid], ['Saídas futuras', summary.totals.payable + summary.totals.future_cost]];
    const valueRow = (name, key) => `<tr><th scope="row">${name}</th>${summary.rows.map(row => `<td>${money(row[key])}</td>`).join('')}</tr>`;
    return `<p>Dados de ${esc(summary.as_of)} · fim operacional ${esc(summary.operational_end)} · mínimo em ${esc(summary.minimumMonth || 'saldo inicial')} · atraso médio histórico ${summary.average_receipt_delay === null ? '—' : `${summary.average_receipt_delay.toFixed(1)} dias`}</p>
      <div class="monthly-indicators">${indicators.map(([name, value]) => `<div><span>${name}</span><strong>${money(value)}</strong></div>`).join('')}</div>
      ${summary.unprogrammed_count ? `<p class="work-warning">${summary.unprogrammed_count} origens por programar, excluídas da previsão.</p>` : ''}${summary.outside_period_count ? `<p class="work-warning">${summary.outside_period_count} parcelas fora deste ano. Consulte os anos correspondentes.</p>` : ''}
      <div class="financial-map-scroll"><table class="financial-map-table"><caption>Valores em EUR · cada célula abre as suas origens</caption><thead><tr><th>ESTÁGIO</th>${summary.rows.map(row => `<th scope="col">${esc(row.month)}</th>`).join('')}</tr></thead><tbody>
      ${STAGES.map((stage, index) => `<tr><th scope="row">${STAGE_LABELS[stage]}</th>${summary.rows.map(row => `<td><button data-monthly-cell="${row.month}:${stage}" ${state.busy ? 'disabled' : ''} aria-label="${STAGE_LABELS[stage]} ${row.month}: ${esc(money(row[stage]))}">${money(row[stage])}</button></td>`).join('')}</tr>${index === 2 ? valueRow('TOTAL ENTRADAS', 'incoming') : index === 5 ? valueRow('TOTAL SAÍDAS', 'outgoing') : ''}`).join('')}
      ${valueRow('SALDO MENSAL', 'net')}${valueRow('ACUMULADO', 'accumulated')}
      <tr><th>ESTADO DA COMPETÊNCIA</th>${summary.rows.map(row => `<td>${!canManage() || protectedMonth(row.state) ? esc(label(row.state)) : `<select data-monthly-state="${row.month}" aria-label="Estado ${row.month}" ${state.busy ? 'disabled' : ''}>${MONTH_STATES.map(value => `<option value="${value}" ${value === row.state ? 'selected' : ''}>${label(value)}</option>`).join('')}</select><button data-monthly-save-state="${row.month}" ${state.busy ? 'disabled' : ''}>CONFIRMAR ESTADO</button>`}</td>`).join('')}</tr>
      <tr><th>NOTAS</th>${summary.rows.map(row => `<td>${esc(row.notes || (protectedMonth(row.state) ? 'Competência protegida; caixa nas datas próprias.' : 'Realizado e remanescente previsto.'))}</td>`).join('')}</tr></tbody></table></div>`;
  }
  function renderDetail() {
    const detail = state.detail;
    if (!detail) return '';
    return `<section class="monthly-detail" aria-label="Origens da célula"><h3>${esc(detail.month)} · ${STAGE_LABELS[detail.stage]}</h3><button data-monthly-close-detail ${state.busy ? 'disabled' : ''}>FECHAR DETALHE</button>
      ${detail.error ? `<p role="alert">${esc(detail.error)}</p>` : ''}
      <p>${detail.rows.length} origens carregadas · total da célula ${money(detail.total)}</p><ol>${detail.rows.map(row => `<li><strong>${esc(row.label)} · ${money(row.amount)}</strong><p>Caixa ${esc(row.date)} · competência ${esc(row.competence_month)}</p><small>${esc(row.origin_type)} / ${esc(row.origin_id)}${row.document_id ? ` · documento ${esc(row.document_id)}` : ''}${row.movement_id ? ` · movimento ${esc(row.movement_id)}` : ''} · parcela ${esc(row.allocation_id)}</small></li>`).join('')}</ol>
      ${detail.cursor ? `<button data-monthly-more ${state.busy ? 'disabled' : ''}>CARREGAR MAIS 50</button>` : ''}</section>`;
  }
  async function load() {
    if (state.busy) return;
    state.workId ||= getWorks()[0]?.id || '';
    const generation = ++state.generation;
    state.summary = null; state.detail = null; state.error = ''; state.busy = true; render();
    try {
      if (!state.workId) throw new Error('Selecione uma obra.');
      if (!isConfigured) throw new Error('Ligue o serviço para consultar dados mensais oficiais.');
      const summary = await readMonthlySummary(supabase, state.workId, state.year);
      if (generation === state.generation) { state.summary = summary; state.loaded = true; }
    } catch (error) { if (generation === state.generation) { state.error = error.message; state.loaded = false; } }
    finally { state.busy = false; render(); }
  }
  async function detailPage(month, stage, more = false) {
    if (state.busy || !state.summary) return;
    const summary = state.summary, generation = state.generation;
    if (!more) state.detail = { month, stage, rows: [], cursor: null, total: summary.rows.find(row => row.month === month)[stage] };
    const detail = state.detail;
    state.busy = true; detail.error = ''; render();
    try {
      const page = await readMonthlyOrigins(supabase, summary, month, stage, more ? detail.cursor : null);
      if (generation !== state.generation) return;
      const rows = [...detail.rows, ...page.rows], ids = new Set(rows.map(row => row.allocation_id));
      const total = rows.reduce((sum, row) => sum + row.amount, 0);
      if (ids.size !== rows.length || total > detail.total || (!page.next_cursor && total !== detail.total) || (more && page.next_cursor === detail.cursor)) throw new Error('Paginação de origens inconsistente. Atualize o mapa.');
      detail.rows = rows; detail.cursor = page.next_cursor;
    } catch (error) { detail.error = error.message; }
    finally { state.busy = false; render(); }
  }
  root.addEventListener('change', event => {
    if (state.busy) return;
    if (event.target.matches('[data-monthly-work]')) { state.workId = event.target.value; state.loaded = false; void load(); }
    if (event.target.matches('[data-monthly-year]')) {
      const year = Number(event.target.value);
      if (Number.isInteger(year) && year >= 2000 && year <= 2200) { state.year = year; state.loaded = false; void load(); } else render();
    }
  });
  root.addEventListener('click', async event => {
    if (state.busy) return;
    if (event.target.closest('[data-monthly-refresh]')) return load();
    if (event.target.closest('[data-monthly-close-detail]')) { state.detail = null; render(); return; }
    const cell = event.target.closest('[data-monthly-cell]');
    if (cell) return detailPage(...cell.dataset.monthlyCell.split(':'));
    if (event.target.closest('[data-monthly-more]') && state.detail) return detailPage(state.detail.month, state.detail.stage, true);
    const transition = event.target.closest('[data-monthly-save-state]'), recalculate = event.target.closest('[data-monthly-recalculate]');
    if ((!transition && !recalculate) || !state.summary || !canManage()) return;
    const next = transition ? root.querySelector(`[data-monthly-state="${transition.dataset.monthlySaveState}"]`).value : null;
    state.busy = true; state.error = ''; render();
    try {
      if (!isConfigured) throw new Error('Serviço indisponível.');
      if (transition) {
        await changeMonthlyState(supabase, state.summary, transition.dataset.monthlySaveState, next, crypto.randomUUID());
        state.loaded = false; state.summary = null; state.detail = null;
        toast('Estado confirmado pelo servidor.');
      } else {
        state.summary = await recalculateMonthly(supabase, state.summary, crypto.randomUUID()); state.detail = null;
        toast('Previsão recalculada; histórico preservado.');
      }
    } catch (error) { state.error = `${error.message}${error.conflicts?.length ? ` Conflitos: ${JSON.stringify(error.conflicts)}` : ''}`; }
    finally { state.busy = false; render(); }
    if (!state.loaded) await load();
  });
  return {
    show: () => state.loaded ? render() : load(), refresh: load,
    invalidate: ({ workId }) => { if (state.workId === workId) { state.generation++; state.loaded = false; state.summary = null; state.detail = null; state.error = 'Planeamento alterado. Atualize o resumo mensal.'; render(); } },
  };
}
