import test from 'node:test';
import assert from 'node:assert/strict';
import { monthlyStates, mayRegenerate, validateTransition } from '../src/monthly-state.js';
test('competência antiga pode estar aberta e futura pode estar fechada', () => {
  const states = monthlyStates([{ month: '2020-01', state: 'aberto', revision: '1' }, { month: '2030-01', state: 'fechado', revision: '2' }]);
  assert.equal(mayRegenerate('2020-01', states), true);
  assert.equal(mayRegenerate('2030-01', states), false);
  assert.throws(() => mayRegenerate('2026-01', states));
});
test('estado desconhecido, duplicação e reabertura não são inferidos', () => {
  assert.throws(() => monthlyStates([{ month: '2026-01', state: 'antigo', revision: '1' }]));
  const row = { month: '2026-01', state: 'real', revision: '1' };
  assert.throws(() => monthlyStates([row, row]));
  assert.throws(() => validateTransition('fechado', 'aberto'));
  assert.equal(validateTransition('aberto', 'em_fecho'), true);
});
