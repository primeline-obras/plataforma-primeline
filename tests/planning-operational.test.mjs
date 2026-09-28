import test from 'node:test';
import assert from 'node:assert/strict';
import { weightSummary, phaseProgress, workProgress, redistributeWeights, previewPlanningBatch, workDates, dateDay } from '../src/planning-operational.js';

const task = (id, weight = 50, extra = {}) => ({ id, fase_id: 'phase', descricao: id, peso_percentual: weight, percentual_executado: 20, data_inicio_prevista: '2026-10-01', data_fim_prevista: '2026-10-10', ...extra });
const phase = { id: 'phase', peso_percentual: 100 };
const dependency = (source, target) => ({ item_id: target, depende_de_item_id: source, tipo: 'fim_inicio', atraso_dias: 0 });
const preview = options => previewPlanningBatch({ items: [task('a'), task('b')], phases: [phase], ...options });

test('pesos têm de totalizar 100, sem normalização nem média simples', () => {
  assert.equal(weightSummary([task('a'), task('b')]).valid, true);
  for (const weight of [49, 51, null, '', ' ', -1, Infinity, 'abc', 101]) {
    assert.equal(weightSummary([task('a'), task('b', weight)]).valid, false);
    assert.equal(phaseProgress([task('a'), task('b', weight)]), null);
  }
  assert.equal(phaseProgress([task('a', 20, { percentual_executado: 100 }), task('b', 80, { percentual_executado: 50 })]), 60);
  assert.equal(phaseProgress([]), null);
});
test('tolerância decimal pequena e progresso inválido', () => {
  assert.equal(weightSummary([task('a', 33.33), task('b', 33.33), task('c', 33.33)]).valid, true);
  assert.equal(phaseProgress([task('a', 100, { percentual_executado: null })]), null);
  assert.equal(phaseProgress([task('a', 100, { percentual_executado: 101 })]), null);
});
test('arquivo exclui tarefa sem redistribuir os pesos ou apagar relações', () => {
  const items = [task('a', 20, { tee_id: 'tee', _archive: true }), task('b', 30), task('c', 50)];
  const before = structuredClone(items);
  assert.equal(weightSummary(items).assigned, 80);
  assert.equal(weightSummary(items).missing, 20);
  assert.equal(phaseProgress(items), null);
  assert.deepEqual(items, before);
  const result = preview({ items });
  assert.equal(result.items[0].tee_id, 'tee');
  assert.equal(result.items.length, 3);
});
test('redistribuição explícita preserva arquivo e fecha os cêntimos de percentagem', () => {
  const items = [task('a', 20, { arquivado_em: '2026-09-28' }), task('b', 30), task('c', 50)];
  const result = redistributeWeights(items);
  assert.deepEqual(result.map(row => row.peso_percentual), [20, 37.5, 62.5]);
  assert.equal(items[1].peso_percentual, 30);
  assert.deepEqual(redistributeWeights([task('a', 1), task('b', 1), task('c', 1)]).map(row => row.peso_percentual), [33.34, 33.33, 33.33]);
  assert.throws(() => redistributeWeights([task('a', 0)]));
  assert.throws(() => redistributeWeights([task('a', null)]));
});
test('progresso global exige pesos completos das fases e das tarefas', () => {
  const items = [task('a', 100, { percentual_executado: 50 }), task('b', 100, { fase_id: 'other', percentual_executado: 100 })];
  assert.equal(workProgress([{ ...phase, peso_percentual: 40 }, { id: 'other', peso_percentual: 60 }], items), 80);
  assert.equal(workProgress([{ ...phase, peso_percentual: null }], items), null);
  assert.equal(workProgress([phase], [task('a', 80)]), null);
});
test('preview protege todas as datas manuais e propaga sucessores em ordem', () => {
  const items = [task('a', 30), task('b', 30, { data_inicio_prevista: '2026-10-10', data_fim_prevista: '2026-10-12' }), task('c', 40, { data_inicio_prevista: '2026-10-12', data_fim_prevista: '2026-10-15' })];
  const dependencies = [dependency('b', 'c'), dependency('a', 'b')];
  const result = preview({ items, dependencies, changes: [{ id: 'a', data_fim_prevista: '2026-10-15' }] });
  assert.equal(result.valid, true);
  assert.equal(result.items.find(row => row.id === 'c').data_inicio_prevista, '2026-10-17');
  assert.equal(result.automatic.length, 2);
  assert.equal(items[1].data_inicio_prevista, '2026-10-10');
  const conflict = preview({ items, dependencies, changes: [{ id: 'a', data_fim_prevista: '2026-10-15' }, { id: 'b', data_inicio_prevista: '2026-10-11' }] });
  assert.equal(conflict.valid, false);
  assert.ok(conflict.conflicts.some(row => row.type === 'manual_date_collision'));
  assert.equal(conflict.items.find(row => row.id === 'b').data_inicio_prevista, '2026-10-11');
});
test('datas manuais compatíveis vencem cascata e conclusão real é preservada', () => {
  const result = preview({ changes: [{ id: 'b', data_inicio_prevista: '2026-10-15', data_fim_prevista: '2026-10-20' }], dependencies: [dependency('a', 'b')] });
  assert.equal(result.valid, true);
  assert.equal(result.automatic.length, 0);
  const completed = preview({ items: [task('a'), task('b', 50, { data_fim_real: '2026-10-05' })], dependencies: [dependency('a', 'b')] });
  assert.equal(completed.automatic.length, 0);
});
test('dependência de arquivo exige resolução explícita e ciclos bloqueiam', () => {
  const result = preview({ changes: [{ id: 'a', _archive: true }, { id: 'b', peso_percentual: 100 }], dependencies: [dependency('a', 'b')] });
  assert.ok(result.conflicts.some(row => row.type === 'archived_dependency'));
  assert.equal(result.valid, false);
  assert.equal(preview({ dependencies: [dependency('a', 'b'), dependency('b', 'a')] }).valid, false);
  assert.equal(preview({ dependencies: [dependency('missing', 'b')] }).valid, false);
});
test('lote identifica novas, editadas e retiradas sem mutar dados de entrada', () => {
  const changes = [{ id: 'a', _archive: true }, { id: 'b', descricao: 'alterada' }, task('c', 50, { _new: true })];
  const result = preview({ changes });
  assert.equal(result.valid, true);
  assert.deepEqual(result.archived, ['a']);
  assert.deepEqual(result.edited, ['b']);
  assert.deepEqual(result.created, ['c']);
  assert.equal(preview({ changes: [{ id: 'unknown' }] }).valid, false);
  assert.equal(preview({ changes: [{ id: 'a' }, { id: 'a' }] }).valid, false);
});
test('tarefa nova pode desaparecer localmente', () => {
  const result = preview({ changes: [task('draft', 0, { _new: true, _archive: true })] });
  assert.equal(result.items.length, 2);
  assert.equal(result.archived.length, 0);
});
test('datas reais inválidas, fase desconhecida e datas invertidas bloqueiam', () => {
  for (const change of [{ id: 'a', data_inicio_prevista: '2026-02-30' }, { id: 'a', data_fim_real: 'ontem' }, { id: 'a', fase_id: 'unknown' }, { id: 'a', data_inicio_prevista: '2026-10-20' }]) assert.equal(preview({ changes: [change] }).valid, false);
  assert.equal(dateDay('2026-02-30'), null);
});
test('prazo contratual separado da previsão operacional e sem datas inventadas', () => {
  const work = { data_inicio: '2026-10-01', data_fim_contratual_atual: '2026-10-11', data_fim_prevista: '2026-10-15' };
  assert.deepEqual(workDates(work, 60, '2026-10-06'), { progress: 60, consumed: 50, difference: 10, contractualEnd: '2026-10-11', operationalEnd: '2026-10-15', delayDays: 4 });
  assert.equal(workDates({ ...work, data_fim_contratual_atual: null }, 60, '2026-10-06').consumed, null);
  assert.equal(workDates(work, null, '2026-10-06').difference, null);
});
