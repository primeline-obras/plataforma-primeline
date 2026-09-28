import test from 'node:test';
import assert from 'node:assert/strict';
import { movementBalance, recordReceipt } from '../src/financial-movements.js';
test('parcelas somam em cêntimos sem substituir recebimentos anteriores', () => {
  const rows = [{ id: 'a', data: '2026-09-01', valor: .1 }, { id: 'b', data: '2026-10-01', valor: .2 }];
  assert.deepEqual(movementBalance(1, rows), { settled: .3, outstanding: .7, state: 'parcial' });
  assert.equal(movementBalance(.3, rows).state, 'pago');
  assert.throws(() => movementBalance(.2, rows));
  assert.throws(() => movementBalance(1, [rows[0], rows[0]]));
});
test('RPC inexistente preserva a fatura e nunca chama a marcação integral antiga', async () => {
  const billing = { id: 'bill', valor: 100, valor_recebido: 30 }, before = structuredClone(billing), calls = [];
  await assert.rejects(recordReceipt(async path => { calls.push(path); return new Response('{"code":"PGRST202"}', { status: 404 }); }, billing, { data: '2026-09-28', valor: 20, requestId: 'request' }), /suporte transacional/);
  assert.deepEqual(calls, ['rpc/fn_registar_recebimento_parcial']);
  assert.deepEqual(billing, before);
});
test('movimento inválido bloqueia antes do pedido e sucesso usa saldo oficial', async () => {
  const billing = { id: 'bill', valor: 100, valor_recebido: 30 };
  await assert.rejects(recordReceipt(() => assert.fail('não deve chamar'), billing, { data: '2026-09-28', valor: 71, requestId: 'r' }));
  const updated = { ...billing, valor_recebido: 50, estado_pagamento: 'por_pagar' };
  assert.deepEqual(await recordReceipt(async () => Response.json({ version: 1, committed: true, billing: updated }), billing, { data: '2026-09-28', valor: 20, requestId: 'r' }), updated);
  assert.equal(billing.valor_recebido, 30);
});
