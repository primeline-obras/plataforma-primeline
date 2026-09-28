import test from 'node:test';
import assert from 'node:assert/strict';
import { projectSource, monthlyEngine, equalMonthly } from '../src/monthly-engine.js';
const source = { id: 'contract', origin_type: 'contract_scope', direction: 'income', amount: 10000, competence_month: '2026-10', active_months: ['2026-10', '2026-11'], documents: [{ id: 'invoice', amount: 6000, due_date: '2026-11-15', movements: [{ id: 'receipt', amount: 2000, date: '2026-11-20' }] }] };
const model = entries => ({ version: 1, source: 'traceable_v1', entries, states: ['10', '11', '12'].map(month => ({ month: `2026-${month}`, state: 'aberto', revision: 'r1' })), from: '2026-10', to: '2026-12', today: '2026-12-01' });
test('cada euro passa de futuro a faturado e recebido sem duplicação', () => {
  const before = structuredClone(source), entries = projectSource(source);
  assert.equal(entries.reduce((total, row) => total + row.amount, 0), 10000);
  const result = monthlyEngine(model(entries));
  assert.equal(result.totals.received, 2000);
  assert.equal(result.totals.receivable, 4000);
  assert.equal(result.totals.future_income, 4000);
  assert.equal(result.overdue, 4000);
  assert.equal(result.averageReceiptDelay, 5);
  assert.equal(result.rows[1].receivable, 4000); // overdue stays in November
  assert.deepEqual(source, before);
});
test('saídas parciais e custos remanescentes usam estágios distintos', () => {
  const entries = projectSource({ ...source, direction: 'cost', committed: false });
  const result = monthlyEngine(model(entries));
  assert.equal(result.totals.paid, 2000);
  assert.equal(result.totals.payable, 4000);
  assert.equal(result.totals.future_cost, 4000);
  assert.equal(result.maximumCashNeed, 10000);
  assert.equal(result.minimumMonth, '2026-11');
});
test('parcelas mensais iguais preservam cêntimos e prioridade de calendário', () => {
  assert.deepEqual(equalMonthly(100, ['2026-11', '2026-10', '2026-12']).map(row => row.amount), [34, 33, 33]);
  const entries = projectSource({ ...source, documents: [], due_date: '2026-12-15', remaining_calendar: [{ date: '2026-10-01', amount: 10000 }] });
  assert.equal(entries[0].date, '2026-10-01');
  assert.equal(projectSource({ ...source, documents: [], due_date: '2026-12-15' })[0].date, '2026-12-15');
});
test('competência fechada não impede caixa posterior nem permite regenerar economia', () => {
  const input = model(projectSource(source)); input.states[0].state = 'fechado';
  assert.throws(() => monthlyEngine(input), /protegida/);
  input.entries = input.entries.filter(row => !row.stage.startsWith('future'));
  assert.equal(monthlyEngine(input).rows[1].received, 2000);
  const preserved = projectSource({ ...source, preserved: true });
  assert.equal(monthlyEngine({ ...input, entries: preserved }).totals.future_income, 4000);
});
test('identidades repetidas, valores inconsistentes e legado são recusados', () => {
  const entries = projectSource(source);
  assert.throws(() => monthlyEngine(model([...entries, entries[0]])), /duplicada/);
  assert.throws(() => monthlyEngine({ ...model(entries), source: 'legacy' }));
  assert.throws(() => projectSource({ ...source, amount: 100 }));
  assert.throws(() => projectSource({ ...source, documents: [], active_months: [] }));
});
