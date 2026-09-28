export const MONTH_STATES = Object.freeze(['real', 'fechado', 'em_fecho', 'aberto', 'previsao']);
export const isMonth = value => typeof value === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(value);
export const protectedMonth = state => state === 'real' || state === 'fechado';
export function monthlyStates(rows) {
  const result = new Map();
  for (const row of rows) {
    if (!isMonth(row.month) || !MONTH_STATES.includes(row.state) || result.has(row.month) || typeof row.revision !== 'string') throw new Error('Estados mensais incompletos ou duplicados.');
    result.set(row.month, { ...row });
  }
  return result;
}
// Competence locks economic generation; cash remains on its actual/due date.
export function mayRegenerate(competenceMonth, states) {
  const row = states.get(competenceMonth);
  if (!row) throw new Error(`Estado de ${competenceMonth} não configurado.`);
  return !protectedMonth(row.state);
}
export function validateTransition(current, next) {
  if (!MONTH_STATES.includes(next)) throw new Error('Estado mensal inválido.');
  if (protectedMonth(current) && current !== next) throw new Error('Reabertura de competência exige processo auditado no servidor.');
  return current !== next;
}
