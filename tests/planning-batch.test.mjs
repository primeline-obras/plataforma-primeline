import test from 'node:test';
import assert from 'node:assert/strict';
import { planningChanges, requestPlanningBatch } from '../src/planning-batch.js';

test('lote só envia campos alterados, preservando datas sem edição manual', () => {
  const original = [{ id: 'a', descricao: 'A', data_inicio_prevista: '2026-10-01', peso_percentual: 100 }];
  assert.deepEqual(planningChanges(original, [{ ...original[0], descricao: 'B' }]), [{ id: 'a', descricao: 'B' }]);
  assert.deepEqual(planningChanges(original, original), []);
  assert.deepEqual(planningChanges(original, [{ ...original[0], _archive: false }]), []);
});
test('RPC indisponível não tenta escritas por linha nem altera o lote', async () => {
  const payload = { changes: [{ id: 'a', descricao: 'B' }] }, before = structuredClone(payload), calls = [];
  await assert.rejects(requestPlanningBatch(async (...args) => { calls.push(args); return new Response('{"code":"PGRST202"}', { status: 404 }); }, payload), /suporte transacional/);
  assert.equal(calls.length, 1);
  assert.deepEqual(payload, before);
});
test('preview e confirmação usam um pedido cada e token de confirmação', async () => {
  const calls = [];
  const api = async (path, options) => {
    const body = JSON.parse(options.body); calls.push({ path, body });
    return Response.json(body.p_confirmacao ? { version: 1, committed: true } : { version: 1, confirmation_token: 'token' });
  };
  const payload = { changes: [{ id: 'a' }, { id: 'b' }] };
  const preview = await requestPlanningBatch(api, payload);
  assert.equal((await requestPlanningBatch(api, payload, preview.confirmation_token)).committed, true);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1].body.p_lote.changes, payload.changes);
});
test('resposta incompleta nunca é tratada como confirmação atómica', async () => {
  await assert.rejects(requestPlanningBatch(async () => Response.json({}), {}), /inválida/);
  await assert.rejects(requestPlanningBatch(async () => Response.json({ version: 1, committed: false }), {}, 'token'), /inválida/);
});
