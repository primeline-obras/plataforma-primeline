import test from 'node:test';
import assert from 'node:assert/strict';
import { previewTeeIndex, teeState, requestTeeRevisionImport } from '../src/tee-index.js';
const prior = { id: 'tee', obra_id: 'work', numero: ' TEE 01 ', descricao: 'Existente', fase_id: 'phase', data_inicio_execucao: '2026-10-01', data_fim_execucao: '2026-10-31', valor: 100, preco_custo: 70, estado_aprovacao_cliente: 'aprovado', rfi_id: 'rfi' };
const run = row => previewTeeIndex([{ obra_id: 'work', numero: 'tee 01', ...row }], [prior], 'work')[0];

test('índice vazio preserva fase, execução, relações e valores existentes', () => {
  const result = run({ fase_id: null, descricao: '', data_inicio_execucao: null });
  assert.equal(result.status, 'SEM ALTERAÇÃO');
  assert.deepEqual(result.changes, {});
  assert.equal(result.margin, 30);
  assert.equal(result.marginPercent, 30);
  assert.equal(result.previous.rfi_id, 'rfi');
});
test('novo TEE sem fase e sem execução fica por programar', () => {
  const result = previewTeeIndex([{ obra_id: 'work', numero: '2', descricao: 'Novo', estado_aprovacao_cliente: 'aprovado', data_envio: '2026-09-28' }], [], 'work')[0];
  assert.equal(result.status, 'NOVO');
  assert.equal(result.changes.fase_id, null);
  assert.equal(result.unprogrammed, true);
  assert.equal(result.changes.data_inicio_execucao, undefined);
});
test('atualização envia apenas campos preenchidos e não altera origem', () => {
  const before = structuredClone(prior);
  const result = run({ valor: 0, revisao: 'REV02' });
  assert.equal(result.status, 'VAI ATUALIZAR');
  assert.deepEqual(result.changes, { valor: 0, revisao: 'REV02' });
  assert.deepEqual(prior, before);
});
test('duplicados, outra obra e datas inválidas bloqueiam o índice', () => {
  const rows = [{ obra_id: 'work', numero: '1' }, { obra_id: 'work', numero: ' 1 ' }];
  assert.ok(previewTeeIndex(rows, [], 'work').every(row => row.status === 'BLOQUEADO'));
  assert.equal(run({ obra_id: 'other' }).status, 'BLOQUEADO');
  assert.equal(run({ data_inicio_execucao: '2026-02-30' }).status, 'BLOQUEADO');
});
test('estados operacionais mapeiam aprovação sem usar envio como execução', () => {
  assert.deepEqual(teeState('', null), { operational: 'em_elaboracao', client: 'pendente', suggested: true });
  assert.equal(teeState('', '2026-10-01').operational, 'aguarda_resposta');
  assert.equal(teeState('rejeitado').client, 'recusado');
  assert.equal(teeState('aprovado').client, 'aprovado');
  assert.throws(() => teeState('desconhecido'));
});
test('RPC de revisões exige confirmação sem fallback e preserva preview', async () => {
  const payload = { p_version: 1, p_obra_id: 'work', p_linhas: [{ id: 'tee', valor: 100, expected: prior }], p_nome_ficheiro: 'teste.xlsx' }, before = structuredClone(payload), calls = [];
  const api = async (path, options) => { calls.push({ path, body: JSON.parse(options.body) }); return Response.json({ code: 'PGRST202' }, { status: 404 }); };
  await assert.rejects(requestTeeRevisionImport(api, payload), /suporte transacional/);
  assert.deepEqual(calls, [{ path: 'rpc/fn_importar_tees_revisoes', body: payload }]);
  assert.deepEqual(payload, before);
  await assert.rejects(requestTeeRevisionImport(async () => Response.json({ version: 1, committed: false }), payload));
  assert.equal((await requestTeeRevisionImport(async () => Response.json({ version: 1, committed: true, importadas: 1 }), payload)).importadas, 1);
});

test('revisão preserva o estado operacional quando só muda outro campo', () => {
  const existing = { ...prior, estado_operacional: 'em_elaboracao', estado_aprovacao_cliente: 'pendente', data_envio: '2026-09-01' };
  const [result] = previewTeeIndex([{ obra_id: 'work', numero: 'TEE 01', revisao: 'REV03', estado_operacional: ' ', estado_aprovacao_cliente: '' }], [existing], 'work');
  assert.deepEqual(result.changes, { revisao: 'REV03' });
  assert.equal(result.state.operational, 'em_elaboracao');
});

test('os estados do cliente e operacional são independentes nas revisões', () => {
  const existing = { ...prior, estado_operacional: 'aguarda_resposta', estado_aprovacao_cliente: 'pendente' };
  const runState = fields => previewTeeIndex([{ obra_id: 'work', numero: 'TEE 01', ...fields }], [existing], 'work')[0];
  assert.deepEqual(runState({ estado_aprovacao_cliente: 'recusado' }).changes, { estado_aprovacao_cliente: 'recusado' });
  assert.deepEqual(runState({ estado_operacional: 'rejeitado' }).changes, { estado_operacional: 'rejeitado' });
  assert.equal(runState({ estado_aprovacao_cliente: 'rejeitado' }).status, 'BLOQUEADO');
  assert.equal(runState({ estado_operacional: 'recusado' }).status, 'BLOQUEADO');
  for (const state of ['em_elaboracao', 'aguarda_resposta', 'aprovado', 'rejeitado']) {
    assert.notEqual(runState({ estado_operacional: state }).status, 'BLOQUEADO');
  }
});

test('número normalizado não duplica TEE e ambiguidade existente bloqueia', () => {
  assert.equal(run({ numero: '  TEE   01  ', revisao: 'R2' }).previous.id, prior.id);
  const rows = [{ obra_id: 'work', numero: 'TEE 01' }];
  assert.equal(previewTeeIndex(rows, [prior, { ...prior, id: 'other' }], 'work')[0].status, 'BLOQUEADO');
  assert.equal(previewTeeIndex([{ ...rows[0], descricao: 'Novo' }], [{ ...prior, obra_id: 'other' }], 'work')[0].status, 'NOVO');
});

test('RPC rejeita stale revision e respostas inválidas sem mutar o pedido ou tentar fallback', async () => {
  const payload = { p_version: 1, p_obra_id: 'work', p_linhas: [{ id: prior.id, expected: prior, revisao: 'R2' }], p_nome_ficheiro: 'revisao.xlsx' };
  const before = structuredClone(payload), calls = [];
  await assert.rejects(requestTeeRevisionImport(async (path, options) => {
    calls.push({ path, method: options.method, body: JSON.parse(options.body) });
    return Response.json({ code: 'STALE_REVISION', message: 'Revisão desatualizada.' }, { status: 409 });
  }, payload), /Revisão desatualizada/);
  assert.deepEqual(calls, [{ path: 'rpc/fn_importar_tees_revisoes', method: 'POST', body: payload }]);
  assert.deepEqual(payload, before);
  for (const result of [null, {}, { version: 2, committed: true, importadas: 1 }, { version: 1, committed: true }, { version: 1, committed: true, importadas: -1 }, { version: 1, committed: true, importadas: 1.5 }, { version: 1, committed: true, importadas: '1' }]) {
    await assert.rejects(requestTeeRevisionImport(async () => Response.json(result), payload));
  }
  assert.equal((await requestTeeRevisionImport(async () => Response.json({ version: 1, committed: true, importadas: 0 }), payload)).importadas, 0);
});
