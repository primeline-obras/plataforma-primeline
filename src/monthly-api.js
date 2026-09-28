import { STAGES, integerMoney, summarizeRows, monthsBetween } from './monthly-engine.js';
import { monthlyStates, protectedMonth, validateTransition } from './monthly-state.js';
import { dateDay } from './planning-operational.js';
export class MonthlyError extends Error {
  constructor(code, message, conflicts = []) { super(message); this.code = code; this.conflicts = conflicts; }
}
async function rpc(api, name, payload) {
  const response = await api(`rpc/${name}`, { method: 'POST', body: JSON.stringify(payload) });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 404 || data?.code === 'PGRST202') throw new MonthlyError('UNAVAILABLE', 'O serviço mensal ainda não está disponível. Nenhuma gravação foi confirmada.');
    throw new MonthlyError(data?.code || 'REQUEST_FAILED', data?.message || 'Não foi possível confirmar a operação mensal.', data?.conflicts || []);
  }
  if (data?.version !== 1) throw new MonthlyError('INVALID_RESPONSE', 'Resposta mensal incompatível. Atualize os dados antes de repetir uma gravação.');
  return data;
}
export function validateMonthlySummary(data, workId, year) {
  if (data?.version !== 1 || data.source !== 'traceable_v1' || data.work_id !== workId || data.year !== year || typeof data.snapshot_id !== 'string' || !data.snapshot_id || dateDay(data.as_of) === null || dateDay(data.operational_end) === null || !Number.isSafeInteger(data.opening_balance) || !Number.isSafeInteger(data.current_balance)) throw new MonthlyError('INVALID_RESPONSE', 'Resumo mensal sem identidade ou origem rastreável válida.');
  const states = monthlyStates(data.states);
  const expected = monthsBetween(`${year}-01`, `${year}-12`);
  if (!Array.isArray(data.rows) || data.rows.length !== 12 || data.rows.some(row => !expected.includes(row.month) || !states.has(row.month))) throw new MonthlyError('INVALID_RESPONSE', 'O resumo anual exige os doze meses e estados explícitos.');
  integerMoney(data.overdue);
  if (data.average_receipt_delay !== null && (!Number.isFinite(data.average_receipt_delay) || data.average_receipt_delay < 0)) throw new MonthlyError('INVALID_RESPONSE', 'Atraso histórico inválido.');
  for (const field of ['unprogrammed_count', 'outside_period_count']) integerMoney(data[field]);
  const computed = summarizeRows(data.rows.map(row => ({ ...row, state: states.get(row.month).state, revision: states.get(row.month).revision })), data.opening_balance);
  return { ...data, ...computed };
}
export async function readMonthlySummary(api, workId, year) {
  const data = await rpc(api, 'fn_resumo_financeiro_mensal_v1', { p_obra_id: workId, p_ano: year });
  return validateMonthlySummary(data, workId, year);
}
export async function readMonthlyOrigins(api, summary, month, stage, cursor = null, limit = 50) {
  if (!STAGES.includes(stage) || !summary.rows.some(row => row.month === month) || ![50, 100].includes(limit)) throw new MonthlyError('INVALID_REQUEST', 'Célula mensal inválida.');
  const data = await rpc(api, 'fn_origens_financeiras_mensais_v1', { p_obra_id: summary.work_id, p_snapshot_id: summary.snapshot_id, p_mes: month, p_estagio: stage, p_cursor: cursor, p_limite: limit });
  const cell = summary.rows.find(row => row.month === month)[stage];
  if (data.snapshot_id !== summary.snapshot_id || data.work_id !== summary.work_id || data.month !== month || data.stage !== stage || data.total_amount !== cell || !Array.isArray(data.rows) || data.rows.length > limit || !(data.next_cursor === null || typeof data.next_cursor === 'string')) throw new MonthlyError('STALE_SNAPSHOT', 'O detalhe não corresponde ao resumo. Atualize o mapa.');
  const ids = new Set();
  for (const row of data.rows) {
    if (!row.allocation_id || ids.has(row.allocation_id) || !row.origin_id || !row.origin_type || typeof row.label !== 'string' || dateDay(row.date) === null || row.date.slice(0, 7) !== month || !/^\d{4}-(0[1-9]|1[0-2])$/.test(row.competence_month)) throw new MonthlyError('INVALID_RESPONSE', 'Origem sem identificação ou data válida.');
    ids.add(row.allocation_id); integerMoney(row.amount);
  }
  if (data.rows.reduce((total, row) => total + row.amount, 0) > cell) throw new MonthlyError('INVALID_RESPONSE', 'Detalhe excede o total da célula.');
  return data;
}
export async function changeMonthlyState(api, summary, month, next, requestId) {
  const row = summary.rows.find(item => item.month === month);
  if (!row || !requestId || !validateTransition(row.state, next)) throw new MonthlyError('INVALID_REQUEST', 'Transição mensal inválida.');
  const data = await rpc(api, 'fn_definir_estado_mensal_v1', { p_obra_id: summary.work_id, p_mes: month, p_estado: next, p_revisao_esperada: row.revision, p_request_id: requestId });
  if (data.committed !== true || data.month !== month || data.state !== next || typeof data.revision !== 'string') throw new MonthlyError('UNCONFIRMED', 'Alteração de estado não confirmada. Recarregue antes de repetir.');
  return data;
}
export async function recalculateMonthly(api, summary, requestId) {
  if (!requestId) throw new MonthlyError('INVALID_REQUEST', 'Identidade da operação em falta.');
  const months = summary.rows.filter(row => !protectedMonth(row.state)).map(row => row.month);
  if (!months.length) throw new MonthlyError('PROTECTED_PERIOD', 'Todos os meses estão protegidos.');
  const data = await rpc(api, 'fn_recalcular_previsao_mensal_v1', { p_obra_id: summary.work_id, p_snapshot_id: summary.snapshot_id, p_meses: months, p_request_id: requestId });
  if (data.committed !== true || data.preserved?.closed_months !== true || data.preserved?.historical_measurements !== true || data.preserved?.actual_movements !== true) throw new MonthlyError('UNCONFIRMED', 'Recálculo não confirmou a preservação do histórico. Recarregue antes de repetir.');
  return validateMonthlySummary(data.summary, summary.work_id, summary.year);
}

export function planningFinancialSummary(result, workId) {
  if (result?.committed !== true || result.preserved?.closed_months !== true || result.preserved?.historical_measurements !== true || result.preserved?.actual_movements !== true) throw new MonthlyError('UNCONFIRMED', 'Recálculo financeiro por confirmar.');
  return validateMonthlySummary(result.financial_summary, workId, result.financial_summary?.year);
}
