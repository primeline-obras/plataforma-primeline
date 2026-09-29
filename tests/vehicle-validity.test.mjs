import test from 'node:test';
import assert from 'node:assert/strict';
import { renewalExpiry, validityPayload, saveVehicleValidity } from '../src/vehicle-validity.js';
import { alertsForOverviewRole } from '../src/production-dashboard.js';

const vehicle = { id: 'v1', seguro_data: '2026-10-01', data_inspecao_proxima: null };
test('renovação usa anos de calendário e trata 29 de fevereiro', () => {
  assert.equal(renewalExpiry('2026-09-29', '1_ano'), '2027-09-29');
  assert.equal(renewalExpiry('2026-09-29', '2_anos'), '2028-09-29');
  assert.equal(renewalExpiry('2024-02-29', '1_ano'), '2025-02-28');
  assert.equal(renewalExpiry('2024-02-29', '2_anos'), '2026-02-28');
  assert.equal(renewalExpiry('2026-09-29', 'outra', '2029-04-02'), '2029-04-02');
  assert.throws(() => renewalExpiry('2026-02-30', '1_ano'));
  assert.throws(() => renewalExpiry('2026-09-29', 'outra', '2026-09-29'));
  assert.throws(() => renewalExpiry('2026-09-29', '3_anos'));
});
test('payload exato de edição inclui motivo, data esperada e idempotência', () => {
  const before = structuredClone(vehicle);
  assert.deepEqual(validityPayload(vehicle, 'seguro', 'editar_data', { nova_data: '2026-11-01', motivo: ' Correção do documento ' }, 'r1'), {
    p_version: 1, p_viatura_id: 'v1', p_tipo: 'seguro', p_operacao: 'editar_data',
    p_data_atual_esperada: '2026-10-01', p_data_base: null, p_validade_opcao: null,
    p_nova_data: '2026-11-01', p_motivo: 'Correção do documento', p_request_id: 'r1',
  });
  assert.deepEqual(vehicle, before);
  assert.throws(() => validityPayload(vehicle, 'seguro', 'editar_data', { nova_data: '2026-11-01', motivo: ' ' }, 'r'));
});
test('renovação envia data explícita apenas para Outra, preservando data esperada NULL', () => {
  for (const option of ['1_ano', '2_anos', 'outra']) {
    const payload = validityPayload(vehicle, 'inspecao', 'renovar', { data_base: '2026-09-29', validade_opcao: option, nova_data: '2028-11-12' }, 'r');
    assert.equal(payload.p_operacao, 'renovar');
    assert.equal(payload.p_data_atual_esperada, null);
    assert.equal(payload.p_data_base, '2026-09-29');
    assert.equal(payload.p_validade_opcao, option);
    assert.equal(payload.p_nova_data, option === 'outra' ? '2028-11-12' : null);
  }
});
test('RPC só confirma versão 1, committed=true e viatura válida, sem repetição', async () => {
  const payload = validityPayload(vehicle, 'seguro', 'renovar', { data_base: '2026-09-29', validade_opcao: '1_ano' }, 'r');
  const response = { version: 1, committed: true, idempotent: false, vehicle: { ...vehicle, seguro_data: '2027-09-29' }, validity: {}, event: {}, alert: {} };
  const calls = [];
  const result = await saveVehicleValidity(async (path, options) => { calls.push({ path, method: options.method, body: JSON.parse(options.body) }); return Response.json(response); }, payload);
  assert.deepEqual(result, response);
  assert.deepEqual(calls, [{ path: 'rpc/fn_guardar_validade_viatura', method: 'POST', body: payload }]);
  for (const bad of [{}, { ...response, committed: false }, { ...response, committed: undefined }, { ...response, version: 2 }, { ...response, vehicle: { id: 'other' } }]) {
    let count = 0;
    await assert.rejects(saveVehicleValidity(async () => { count++; return Response.json(bad); }, payload), /não confirmou/);
    assert.equal(count, 1);
  }
  assert.equal((await saveVehicleValidity(async () => Response.json({ ...response, idempotent: true }), payload)).idempotent, true);
});
test('stale revision, permissão e validação não modificam dados locais', async () => {
  const payload = validityPayload(vehicle, 'seguro', 'editar_data', { nova_data: '2026-11-01', motivo: 'Correção' }, 'r'), before = structuredClone(payload);
  for (const [code, status, message] of [['STALE_REVISION',409,/outro utilizador/], ['42501',403,/permissão/], ['VALIDATION_FAILED',422,/inválidos/]]) {
    await assert.rejects(saveVehicleValidity(async () => Response.json({ code }, { status }), payload), message);
    assert.deepEqual(payload, before);
  }
});
test('o mesmo alerta de viatura é visível ao Administrativo, Gerência e destinatário', () => {
  for (const tipo of ['seguro_viatura', 'inspecao_viatura']) {
    const alerts = [{ id: 'a', tipo, destinatario_utilizador_id: 'driver', obra_id: 'work' }];
    for (const role of ['gerencia', 'administrativo']) assert.equal(alertsForOverviewRole(alerts, role, new Set(), 'admin').length, 1);
    for (const role of ['encarregado', 'financeiro', 'diretor_obra']) {
      assert.equal(alertsForOverviewRole(alerts, role, new Set(), 'driver').length, 1);
      assert.equal(alertsForOverviewRole(alerts, role, new Set(['work']), 'other').length, 0);
    }
    assert.equal(alertsForOverviewRole([{ tipo }], 'encarregado').length, 0);
  }
  assert.equal(alertsForOverviewRole([{ tipo: 'compromisso_agenda', destinatario_utilizador_id: 'other' }], 'administrativo', new Set(), 'admin').length, 0);
});
