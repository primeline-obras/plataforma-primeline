import test from 'node:test';
import assert from 'node:assert/strict';
import { __test } from '../src/xlsx-operational-import.js';

globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet } };
const headers = ['Nº TEE*', 'Obra (nº)*', 'Fase (código)', 'Descrição', 'Especialidade', 'Valor (€)', 'Preço de Custo (€)', 'Dias de Prorrogação', 'Data de Envio', 'Data de Resposta', 'Estado Aprovação Cliente', 'Revisão', 'Data Início Execução', 'Data Fim Execução'];
const itemHeaders = ['Nº TEE*', 'Nº Artigo*', 'Descrição*', 'Unidade', 'Quantidade', 'Preço Unitário (€)', 'Valor Total (€)'];
const previous = { id: 't1', obra_id: 'w1', numero: 'TEE 01', descricao: 'Anterior', fase_id: 'f1', valor: 100, preco_custo: 70, dias_prorrogacao: 3, revisao: 'R1', data_envio: '2026-09-01', data_resposta: '2026-09-10', data_inicio_execucao: '2026-10-01', data_fim_execucao: '2026-10-31', estado_aprovacao_cliente: 'pendente', estado_operacional: 'em_elaboracao' };
const context = { work: { id: 'w1', numero: 120, data_fim_contratual_atual: '2026-12-31' }, phases: [{ id: 'f1', codigo: 'F01' }], tees: [previous] };
const row = values => Array.from({ length: 15 }, (_, index) => values[index] ?? '');
const parse = (rows, items = [], operational = false) => __test.parseTees({ Sheets: {
  'TEE_Cabeçalho': [operational ? [...headers, 'Estado Operacional'] : headers, ...rows],
  'TEE_Itens': [itemHeaders, ...items],
} }, context);

test('novo aprovado sem fase/datas é permitido com aviso e payload completo', () => {
  const [result] = parse([row({ 0: 'TEE 02', 1: 120, 3: 'Novo', 5: '1.000,50', 10: 'aprovado' })]);
  assert.equal(result.previewStatus, 'NOVO');
  assert.equal(result.selected, true);
  assert.match(result.warnings.join(' '), /execução por programar/);
  assert.deepEqual(result.payload, { obra_id: 'w1', numero: 'TEE 02', descricao: 'Novo', valor: 1000.5, fase_id: null, estado_aprovacao_cliente: 'aprovado', estado_operacional: 'aprovado', id: undefined, expected: null });
});

test('revisão só envia células preenchidas; estado e itens omitidos são preservados', () => {
  const before = structuredClone(context);
  const [result] = parse([row({ 0: ' tee   01 ', 1: 120, 2: ' ', 3: ' ', 5: 0, 8: ' ', 11: 'R2', 12: ' ', 14: ' ' })]);
  assert.equal(result.previewStatus, 'VAI ATUALIZAR');
  assert.equal(result.selected, true);
  assert.deepEqual(result.payload, { id: 't1', expected: previous, valor: 0, revisao: 'R2' });
  assert.deepEqual(context, before);
});

test('SEM ALTERAÇÃO fica sem seleção; duplicados no ficheiro ficam BLOQUEADOS', () => {
  const [unchanged] = parse([row({ 0: 'TEE 01', 1: 120 })]);
  assert.equal(unchanged.previewStatus, 'SEM ALTERAÇÃO');
  assert.equal(unchanged.selected, false);
  assert.deepEqual(unchanged.payload, { id: 't1', expected: previous });
  assert.ok(parse([row({ 0: 'TEE 01', 1: 120 }), row({ 0: ' tee   01 ', 1: 120 })]).every(item => item.previewStatus === 'BLOQUEADO' && !item.selected));
});

test('coluna operacional opcional não confunde aprovação cliente nem apaga estado em branco', () => {
  const [operational] = parse([row({ 0: 'TEE 01', 1: 120, 14: 'aguarda_resposta' })], [], true);
  assert.deepEqual(operational.payload, { id: 't1', expected: previous, estado_operacional: 'aguarda_resposta' });
  const [client] = parse([row({ 0: 'TEE 01', 1: 120, 10: 'recusado' })], [], true);
  assert.deepEqual(client.payload, { id: 't1', expected: previous, estado_aprovacao_cliente: 'recusado' });
  assert.equal(parse([row({ 0: 'TEE 01', 1: 120, 10: 'rejeitado' })])[0].previewStatus, 'BLOQUEADO');
  assert.equal(parse([row({ 0: 'TEE 01', 1: 120, 14: 'recusado' })], [], true)[0].previewStatus, 'BLOQUEADO');
});

test('itens ligam pelo mesmo número normalizado sem transportar IDs medidos', () => {
  const [result] = parse([row({ 0: 'TEE 01', 1: 120 })], [[' tee   01 ', '1.1', 'Artigo', 'un', '2', '5,50', '11']]);
  assert.equal(result.previewStatus, 'VAI ATUALIZAR');
  assert.deepEqual(result.payload.itens, [{ linha: 2, numero_artigo: '1.1', descricao: 'Artigo', unidade: 'un', quantidade: 2, preco_unitario: 5.5, valor_total: 11 }]);
  assert.equal(result.payload.id, 't1');
  assert.equal(result.payload.expected, previous);
});

test('itens inválidos e órfãos bloqueiam a importação', () => {
  const rows = [row({ 0: 'TEE 01', 1: 120 })];
  for (const items of [
    [['TEE 01', '', 'Artigo']],
    [['TEE 01', '1', '']],
    [['TEE 01', '1', 'Artigo', 'un', 'inválido']],
  ]) {
    const [result] = parse(rows, items);
    assert.equal(result.previewStatus, 'BLOQUEADO');
    assert.equal(result.selected, false);
  }
  assert.throws(() => parse(rows, [['TEE 99', '1', 'Órfão']]), /sem cabeçalho/);
});

test('datas e números malformados não se confundem com células vazias', () => {
  for (const column of [5, 6, 7, 8, 9, 12, 13]) {
    assert.equal(parse([row({ 0: 'TEE 01', 1: 120, [column]: 'inválido' })])[0].previewStatus, 'BLOQUEADO');
  }
  assert.equal(parse([row({ 0: 'TEE 01', 1: 120, 8: '31/02/2026' })])[0].previewStatus, 'BLOQUEADO');
});

test('dias de prorrogação só alteram o TEE, preservando datas contratuais e de execução', () => {
  const before = structuredClone(context);
  const [result] = parse([row({ 0: 'TEE 01', 1: 120, 7: 10 })]);
  assert.deepEqual(result.payload, { id: 't1', expected: previous, dias_prorrogacao: 10 });
  assert.deepEqual(context, before);
});
