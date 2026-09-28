import test from 'node:test';
import assert from 'node:assert/strict';
import { previewTeeIndex, teeState } from '../src/tee-index.js';
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
