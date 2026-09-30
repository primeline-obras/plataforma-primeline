import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { planningChanges, batchPreview } from '../src/planning-batch.js';
import { redistributeWeights, weightSummary } from '../src/planning-operational.js';

const sql = (await readFile(new URL('../supabase/planeamento_lote_preview_safeupdate.sql', import.meta.url), 'utf8')).replace(/\r\n/g, '\n');
const fixture = JSON.parse(await readFile(new URL('./fixtures/planning-obra120-safeupdate.json', import.meta.url), 'utf8'));
const current = structuredClone(fixture.items);
for (const phase of fixture.phases.filter(p => ['F06', 'F08', 'F09', 'F10'].includes(p.codigo))) {
  const weights = new Map(redistributeWeights(current.filter(i => i.fase_id === phase.id)).map(i => [i.id, i.peso_percentual]));
  current.forEach(i => { if (weights.has(i.id)) i.peso_percentual = weights.get(i.id); });
}
const task = current.find(i => i.codigo === 'F05.4');
task.percentual_executado = 0;
task.estado = 'por_iniciar';
const changes = planningChanges(fixture.items, current);

test('SQL completo preserva a definição instalada exceto o WHERE aprovado', () => {
  assert.equal((sql.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1);
  assert.match(sql, /FUNCTION public\.fn_planeamento_lote_preview_v1\(p_lote jsonb\)/);
  const addition = '\n  WHERE id IS NOT NULL';
  assert.equal(sql.split(addition).length, 2);
  // Hash da definição instalada lida em 30/09/2026, normalizada para LF.
  // pg_get_functiondef não inclui o terminador final do CREATE FUNCTION.
  const original = sql.replace(addition, '').trimEnd().slice(0, -1) + '\n';
  assert.equal(createHash('sha256').update(original).digest('hex'),
    'cb5b9d79a18cbea271237f327627483ae9f4414fdaa0c7ee5cf7eec8ddf49608');
  const updates = sql.match(/UPDATE pg_temp\.pl_lote_items\b[\s\S]*?;/g);
  assert.equal(updates.length, 3);
  assert.match(updates[0], /WHERE id = v_id;/);
  assert.match(updates[1], /END\n  WHERE id IS NOT NULL;/);
  assert.match(updates[2], /WHERE alvo.id = req.item_id/);
  assert.doesNotMatch(sql, /safeupdate\.enabled|UPDATE public\./i);
});

test('Obra 120: 21 pesos e execução F05.4 produzem exatamente 22 alterações válidas', () => {
  assert.equal(fixture.items.length, 64);
  assert.deepEqual(planningChanges(fixture.items, structuredClone(fixture.items)), []);
  assert.equal(changes.length, 22);
  const counts = {};
  for (const change of changes) {
    const item = current.find(i => i.id === change.id);
    const phase = fixture.phases.find(p => p.id === item.fase_id).codigo;
    counts[phase] = (counts[phase] || 0) + 1;
    assert.deepEqual(Object.keys(change).sort(), item.codigo === 'F05.4'
      ? ['estado', 'id', 'percentual_executado'] : ['id', 'peso_percentual']);
  }
  assert.deepEqual(counts, { F05: 1, F06: 8, F08: 4, F09: 4, F10: 5 });
  const before = fixture.items.find(i => i.id === task.id);
  assert.equal(before.percentual_executado, 100);
  assert.equal(before.estado, 'concluido');
  assert.equal(before.peso_percentual, 5);
  assert.equal(task.peso_percentual, 5);
  assert.deepEqual(changes.find(c => c.id === task.id), { id: task.id, percentual_executado: 0, estado: 'por_iniciar' });
  const summary = weightSummary(current.filter(i => i.fase_id === task.fase_id));
  assert.equal(summary.assigned, 100);
  assert.equal(summary.valid, true);
  const preview = batchPreview(fixture.items, current, fixture.phases, fixture.dependencies);
  assert.equal(preview.valid, true);
  assert.equal(preview.edited.length, 22);
  for (const field of ['created', 'archived', 'automatic', 'conflicts']) assert.deepEqual(preview[field], []);
});

test('função SQL completa instala e valida o lote em PostgreSQL local em memória', async () => {
  const { PGlite } = await import(process.env.QUADRO_PGLITE
    ? pathToFileURL(process.env.QUADRO_PGLITE).href
    : './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js');
  const db = new PGlite();
  try {
    // Schema mínimo isolado; sem ligação à BD real. safeupdate é verificado
    // estruturalmente acima, pois a extensão não está incluída no PGlite.
    await db.exec(`
      CREATE TABLE public.fases (id uuid PRIMARY KEY, obra_id uuid, codigo text, peso_percentual numeric);
      CREATE TABLE public.planeamento_itens (
        id uuid PRIMARY KEY, fase_id uuid, codigo text, descricao text, responsavel text,
        duracao_dias numeric, data_inicio_prevista date, data_fim_prevista date,
        data_fim_real date, peso_percentual numeric, percentual_executado numeric,
        estado text, causa_atraso text, impacto text, impedido boolean,
        observacao_impedimento text, data_inicio_baseline date, data_fim_baseline date,
        data_inicio_real date, especialidade_id uuid, executado_por text,
        item_orcamento_id uuid, custo_estado text, valor_estimado numeric,
        valor_orca_pl numeric, arquivado_em timestamptz);
      CREATE TABLE public.planeamento_itens_dependencias (
        id uuid PRIMARY KEY, item_id uuid, depende_de_item_id uuid, tipo text, atraso_dias integer);
      CREATE FUNCTION public.fn_pode_editar_obra(uuid) RETURNS boolean LANGUAGE sql AS 'SELECT true';
    `);
    const workId = '7c2a0c29-5eca-40d9-aff0-3e1b00d8e973';
    await db.query('INSERT INTO public.fases SELECT * FROM jsonb_populate_recordset(NULL::public.fases, $1::jsonb)',
      [JSON.stringify(fixture.phases.map(p => ({ ...p, obra_id: workId })))]);
    await db.query('INSERT INTO public.planeamento_itens SELECT * FROM jsonb_populate_recordset(NULL::public.planeamento_itens, $1::jsonb)', [JSON.stringify(fixture.items)]);
    await db.query('INSERT INTO public.planeamento_itens_dependencias SELECT * FROM jsonb_populate_recordset(NULL::public.planeamento_itens_dependencias, $1::jsonb)', [JSON.stringify(fixture.dependencies)]);
    await db.exec(sql);
    const snapshot = () => db.query('SELECT to_jsonb(i) AS item FROM public.planeamento_itens i ORDER BY id');
    const before = await snapshot();
    await db.exec('BEGIN');
    const payload = { version: 1, obra_id: workId, expected_items: fixture.items,
      expected_dependencies: fixture.dependencies, dependencies: fixture.dependencies,
      changes, approved_cascade: [] };
    const { rows } = await db.query('SELECT public.fn_planeamento_lote_preview_v1($1::jsonb) AS result', [JSON.stringify(payload)]);
    assert.deepEqual(rows[0].result, { conflicts: [], approved_cascade: [] });
    const derived = await db.query("SELECT peso_percentual::float8 AS weight, percentual_executado::float8 AS progress, estado FROM pg_temp.pl_lote_items WHERE codigo='F05.4'");
    assert.deepEqual(derived.rows, [{ weight: 5, progress: 0, estado: 'por_iniciar' }]);
    const totals = await db.query('SELECT fase_id, sum(peso_percentual)::float8 AS weight FROM pg_temp.pl_lote_items GROUP BY fase_id');
    assert.equal(totals.rows.length, 10);
    totals.rows.forEach(row => assert.equal(row.weight, 100));
    assert.deepEqual((await snapshot()).rows, before.rows);
    await db.exec('ROLLBACK');
    assert.deepEqual((await snapshot()).rows, before.rows);
  } finally { await db.close(); }
});
