import { dateDay } from './planning-operational.js';
import { isMonth, monthlyStates, mayRegenerate } from './monthly-state.js';

export const STAGES = Object.freeze(['received', 'receivable', 'future_income', 'paid', 'payable', 'future_cost']);
export const STAGE_LABELS = Object.freeze({ received: 'Recebidas reais', receivable: 'Faturadas a receber', future_income: 'Futuras não faturadas', paid: 'Pagas reais', payable: 'Faturadas / comprometidas a pagar', future_cost: 'Futuras não comprometidas' });
export const integerMoney = value => {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error('Montante inválido: use cêntimos inteiros não negativos.');
  return value;
};
const date = value => { if (dateDay(value) === null) throw new Error('Data inválida.'); return value; };
export function contractualDueDate(emission, days) {
  date(emission);
  if (!Number.isInteger(days) || days < 0) throw new Error('Prazo contratual inválido.');
  return new Date((dateDay(emission) + days) * 86400000).toISOString().slice(0, 10);
}
const sum = values => { const result = values.reduce((total, value) => total + integerMoney(value), 0); return integerMoney(result); };
export function monthsBetween(first, last) {
  if (!isMonth(first) || !isMonth(last) || last < first) throw new Error('Intervalo mensal inválido.');
  const rows = [];
  for (let cursor = first; cursor <= last;) {
    rows.push(cursor);
    if (rows.length > 1200) throw new Error('Intervalo mensal demasiado extenso.');
    const [year, month] = cursor.split('-').map(Number);
    cursor = `${month === 12 ? year + 1 : year}-${String(month === 12 ? 1 : month + 1).padStart(2, '0')}`;
  }
  return rows;
}
export function equalMonthly(amount, months) {
  integerMoney(amount);
  const ordered = [...new Set(months)].sort();
  if (!ordered.length || ordered.length !== months.length || ordered.some(month => !isMonth(month))) throw new Error('Meses ativos inválidos.');
  const base = Math.floor(amount / ordered.length), remainder = amount % ordered.length;
  return ordered.map((month, index) => ({ date: `${month}-01`, amount: base + (index < remainder ? 1 : 0) }));
}

// A source must be scoped to one work and have an explicit economic identity.
// Documents consume the source value; movements consume document balances.
export function projectSource(source) {
  if (!source.id || !source.origin_type || !['income', 'cost'].includes(source.direction) || !isMonth(source.competence_month)) throw new Error('Origem financeira inválida.');
  if (source.origin_type === 'tee' && source.approved !== true) throw new Error('Só TEEs aprovados podem gerar previsão.');
  integerMoney(source.amount);
  const entries = [], seen = new Set();
  const add = (id, stage, amount, cashDate, extra = {}) => {
    integerMoney(amount); if (!amount) return;
    if (seen.has(id)) throw new Error('Identidade financeira duplicada.'); seen.add(id);
    entries.push({ allocation_id: `${source.id}:${id}`, origin_id: source.id, origin_type: source.origin_type, stage, amount, date: date(cashDate), competence_month: source.competence_month, ...extra });
  };
  const incoming = source.direction === 'income';
  const documents = source.documents || [], documentIds = new Set(), movementIds = new Set();
  const invoiced = sum(documents.map(document => document.amount));
  if (invoiced > source.amount) throw new Error('Documentos excedem o valor económico da origem.');
  for (const document of documents) {
    if (!document.id || documentIds.has(document.id)) throw new Error('Documento duplicado.'); documentIds.add(document.id);
    const movements = document.movements || [];
    const settled = sum(movements.map(movement => movement.amount));
    if (settled > document.amount) throw new Error('Movimentos excedem o documento.');
    for (const movement of movements) {
      if (!movement.id || movementIds.has(movement.id)) throw new Error('Movimento duplicado.'); movementIds.add(movement.id);
      add(`movement:${movement.id}`, incoming ? 'received' : 'paid', movement.amount, movement.date, { document_id: document.id, movement_id: movement.id, due_date: document.due_date || null });
    }
    const outstanding = document.amount - settled;
    if (outstanding) add(`document:${document.id}`, incoming ? 'receivable' : 'payable', outstanding, document.forecast_date || document.due_date, { document_id: document.id, due_date: document.due_date || null });
  }
  const remaining = source.amount - invoiced;
  if (remaining) {
    // Explicit calendar > due date > subcontract condition date > equal months.
    // The calendar describes the REMAINING value, never the original total.
    const calendar = source.remaining_calendar?.length ? source.remaining_calendar
      : source.due_date ? [{ date: source.due_date, amount: remaining }]
      : source.subcontract_date ? [{ date: source.subcontract_date, amount: remaining }]
      : equalMonthly(remaining, source.active_months || []);
    if (sum(calendar.map(row => row.amount)) !== remaining) throw new Error('Calendário não corresponde ao remanescente.');
    calendar.forEach((row, index) => add(`remaining:${index}`, incoming ? 'future_income' : source.committed ? 'payable' : 'future_cost', row.amount, row.date, { preserved: source.preserved === true }));
  }
  return entries;
}

export function summarizeRows(rows, openingBalance = 0) {
  if (!Number.isSafeInteger(openingBalance)) throw new Error('Saldo inicial inválido.');
  let balance = openingBalance, minimum = openingBalance, minimumMonth = null;
  const totals = Object.fromEntries(STAGES.map(stage => [stage, 0]));
  const ordered = [...rows].sort((a, b) => a.month.localeCompare(b.month));
  const seen = new Set();
  const result = ordered.map(row => {
    if (!isMonth(row.month) || seen.has(row.month)) throw new Error('Resumo mensal duplicado ou inválido.'); seen.add(row.month);
    for (const stage of STAGES) { integerMoney(row[stage]); totals[stage] += row[stage]; integerMoney(totals[stage]); }
    const incoming = sum(STAGES.slice(0, 3).map(stage => row[stage]));
    const outgoing = sum(STAGES.slice(3).map(stage => row[stage]));
    balance += incoming - outgoing;
    if (!Number.isSafeInteger(balance)) throw new Error('Saldo fora do limite.');
    if (balance < minimum) { minimum = balance; minimumMonth = row.month; }
    return { ...row, incoming, outgoing, net: incoming - outgoing, accumulated: balance };
  });
  return { rows: result, totals, finalBalance: balance, minimum, minimumMonth, maximumCashNeed: Math.max(0, -minimum) };
}

export function monthlyEngine({ version, source, entries, states, from, to, today, opening_balance = 0 }) {
  if (version !== 1 || source !== 'traceable_v1') throw new Error('O motor requer origens rastreáveis, sem agregados legados.');
  date(today);
  const stateMap = monthlyStates(states), ids = new Set();
  const months = new Map(monthsBetween(from, to).map(month => [month, { month, ...Object.fromEntries(STAGES.map(stage => [stage, 0])) }]));
  let overdue = 0, currentBalance = opening_balance, delayValue = 0, delayWeight = 0;
  const outsidePeriod = [];
  for (const entry of entries) {
    if (!entry.allocation_id || ids.has(entry.allocation_id) || !entry.origin_id || !entry.origin_type || !STAGES.includes(entry.stage) || !isMonth(entry.competence_month)) throw new Error('Origem ou parcela duplicada/inválida.');
    ids.add(entry.allocation_id); integerMoney(entry.amount); date(entry.date);
    if (entry.due_date) date(entry.due_date);
    if (['future_income', 'future_cost'].includes(entry.stage) && !mayRegenerate(entry.competence_month, stateMap) && entry.preserved !== true) throw new Error('Previsão genérica em competência protegida.');
    const month = entry.date.slice(0, 7);
    if (months.has(month)) months.get(month)[entry.stage] += entry.amount;
    else outsidePeriod.push({ ...entry });
    if (entry.stage === 'receivable' && entry.due_date && entry.due_date < today) overdue += entry.amount;
    if (entry.date >= `${from}-01` && entry.date <= today && ['received', 'paid'].includes(entry.stage)) currentBalance += entry.stage === 'received' ? entry.amount : -entry.amount;
    if (entry.stage === 'received' && entry.due_date) { delayValue += Math.max(0, dateDay(entry.date) - dateDay(entry.due_date)) * entry.amount; delayWeight += entry.amount; }
  }
  const rows = [...months.values()].map(row => ({ ...row, state: stateMap.get(row.month)?.state ?? null, revision: stateMap.get(row.month)?.revision ?? null }));
  return { ...summarizeRows(rows, opening_balance), currentBalance, overdue, averageReceiptDelay: delayWeight ? delayValue / delayWeight : null, outsidePeriod };
}
