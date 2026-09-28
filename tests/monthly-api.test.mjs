import test from 'node:test';
import assert from 'node:assert/strict';
import { readMonthlySummary, readMonthlyOrigins, changeMonthlyState, recalculateMonthly, validateMonthlySummary, planningFinancialSummary } from '../src/monthly-api.js';
import { summaryFixture, preservedFixture } from './monthly-fixture.mjs';
const summary = () => validateMonthlySummary(summaryFixture(), 'work', 2026);
const mock = (result, calls) => async (path, options) => { calls.push({ path, body: JSON.parse(options.body) }); return Response.json(result); };
test('resumo exige fonte exclusiva e identidade; pedido é apenas por obra/ano', async () => {
  const calls = [], result = await readMonthlySummary(mock(summaryFixture(), calls), 'work', 2026);
  assert.equal(result.finalBalance, 120);
  assert.deepEqual(calls, [{ path: 'rpc/fn_resumo_financeiro_mensal_v1', body: { p_obra_id: 'work', p_ano: 2026 } }]);
  for (const patch of [{ source: 'legacy' }, { work_id: 'other' }, { rows: [] }, { overdue: -1 }]) assert.throws(() => validateMonthlySummary({ ...summaryFixture(), ...patch }, 'work', 2026));
});
test('detalhe paginado corresponde ao snapshot e total da célula', async () => {
  const calls = [], data = { version: 1, work_id: 'work', snapshot_id: 'snap1', month: '2026-09', stage: 'received', total_amount: 100, next_cursor: null, rows: [{ allocation_id: 'a', origin_id: 'invoice', origin_type: 'faturacao', label: 'FT1', amount: 100, date: '2026-09-20', competence_month: '2026-08' }] };
  assert.equal((await readMonthlyOrigins(mock(data, calls), summary(), '2026-09', 'received')).rows.length, 1);
  assert.deepEqual(calls[0].body, { p_obra_id: 'work', p_snapshot_id: 'snap1', p_mes: '2026-09', p_estagio: 'received', p_cursor: null, p_limite: 50 });
  await assert.rejects(readMonthlyOrigins(mock({ ...data, snapshot_id: 'old' }, []), summary(), '2026-09', 'received'), /corresponde/);
});
test('transição usa revisão e idempotência sem alterar cache antes da confirmação', async () => {
  const data = summary(), before = structuredClone(data), calls = [];
  await changeMonthlyState(mock({ version: 1, committed: true, month: '2026-02', state: 'em_fecho', revision: 'r2' }, calls), data, '2026-02', 'em_fecho', 'req1');
  assert.deepEqual(calls[0].body, { p_obra_id: 'work', p_mes: '2026-02', p_estado: 'em_fecho', p_revisao_esperada: 'r1', p_request_id: 'req1' });
  assert.deepEqual(data, before);
  await assert.rejects(changeMonthlyState(() => assert.fail('não chamar'), data, '2026-01', 'aberto', 'req2'), /Reabertura/);
});
test('recálculo exclui fechado e exige preservação e resumo válido', async () => {
  const calls = [], result = await recalculateMonthly(mock({ version: 1, committed: true, preserved: preservedFixture, summary: summaryFixture() }, calls), summary(), 'req3');
  assert.equal(result.snapshot_id, 'snap1');
  assert.equal(calls[0].body.p_meses.length, 11);
  assert.ok(!calls[0].body.p_meses.includes('2026-01'));
  await assert.rejects(recalculateMonthly(mock({ version: 1, committed: true, preserved: {} }, []), summary(), 'req4'), /preservação/);
});
test('todas as RPCs falham em segurança sem fallback e conservam conflitos', async () => {
  const missing = async () => Response.json({ code: 'PGRST202' }, { status: 404 });
  for (const action of [() => readMonthlySummary(missing, 'work', 2026), () => readMonthlyOrigins(missing, summary(), '2026-09', 'received'), () => changeMonthlyState(missing, summary(), '2026-02', 'em_fecho', 'r'), () => recalculateMonthly(missing, summary(), 'r')]) await assert.rejects(action(), error => error.code === 'UNAVAILABLE');
  await assert.rejects(recalculateMonthly(async () => Response.json({ code: 'STALE_SNAPSHOT', message: 'Concorrência', conflicts: [{ month: '2026-02' }] }, { status: 409 }), summary(), 'r'), error => error.code === 'STALE_SNAPSHOT' && error.conflicts.length === 1);
  assert.throws(() => planningFinancialSummary({ committed: true }, 'work'));
  assert.equal(planningFinancialSummary({ committed: true, preserved: preservedFixture, financial_summary: summaryFixture() }, 'work').finalBalance, 120);
});
