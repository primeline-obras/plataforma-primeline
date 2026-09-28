import test from 'node:test';
import assert from 'node:assert/strict';
import { legacyContractValues, clientFinancialComposition } from '../src/contract-composition.js';

test('TEEs não voltam a somar aos valores efetivos por reconciliar', () => {
  const contract = { venda_contratual_inicial: 1000, venda_contratual_efetiva: 1200, custo_direto_inicial: 700, custo_direto_efetivo: 800 };
  const before = structuredClone(contract);
  const result = clientFinancialComposition(contract, [{ valor: 200, preco_custo: 100 }]);
  assert.deepEqual(result.sale, [1000, 1200, 200, null]);
  assert.deepEqual(result.cost, [700, 800, 100, null]);
  assert.equal(result.status, 'por_reconciliar');
  assert.equal(result.reconciledResult, null);
  assert.deepEqual(contract, before);
});

test('zero efetivo é preservado e ausência não se transforma em zero', () => {
  assert.equal(legacyContractValues({ venda_contratual_efetiva: 0, venda_contratual_inicial: 100 }).sale, 0);
  assert.equal(legacyContractValues({ custo_direto_efetivo: 0, custo_direto_inicial: 100 }).cost, 0);
  assert.equal(legacyContractValues({}).sale, null);
  assert.equal(clientFinancialComposition({}).margin[0], null);
});

test('dados legados não ativam reconciliação nem criam movimentos históricos', () => {
  const result = legacyContractValues({ obra_id: '120', estado_reconciliacao: 'reconciliada', venda_contratual_efetiva: 10 });
  assert.equal(result.status, 'por_reconciliar');
  assert.equal(result.sale, 10);
  assert.equal(result.reconciledResult, null);
});
