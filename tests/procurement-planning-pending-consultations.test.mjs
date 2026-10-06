import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";
import { planningChanges, requestPlanningBatch } from "../src/planning-batch.js";

const procurement = await readFile(new URL("../src/procurement.js", import.meta.url), "utf8");
const planning = await readFile(new URL("../src/planning.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/planeamento_consultas_pendentes_especialidades.sql", import.meta.url), "utf8");

test("o selector de consulta usa exclusivamente a tabela controlada de especialidades", () => {
  const formRenderer = procurement.slice(
    procurement.indexOf("function renderNewConsultation()"),
    procurement.indexOf("function renderBudgetItems"),
  );
  assert.match(formRenderer, /state\.specialties\.map/);
  assert.doesNotMatch(formRenderer, /state\.consultations\.map/);
  assert.doesNotMatch(formRenderer, /getSubcontracts\(\)/);
  assert.doesNotMatch(formRenderer, /datalist/);
  assert.match(migration, /update public\.especialidades[\s\S]*initcap\(lower\(btrim\(nome\)\)\)/);
});

test("cada tarefa permite especialidade controlada e executor PL ou subempreitada", () => {
  assert.match(migration, /add column if not exists especialidade_id uuid references public\.especialidades/);
  assert.match(migration, /add column if not exists executado_por text/);
  assert.match(migration, /executado_por in \('PL', 'subempreitada'\)/);
  assert.match(planning, /name="especialidade_id"/);
  assert.match(planning, /name="executado_por"/);
  assert.match(planning, /especialidades\?select=id,nome&order=nome/);
});

test("edição simultânea captura especialidade/executor e persiste ambos no lote confirmado", async () => {
  const original = [{ id: 'synthetic-task', especialidade_id: null, executado_por: 'PL' }];
  const state = { original, items: structuredClone(original), batchSaving: false, preview: {}, dependenciesLoaded: true };
  const row = { dataset: { editItem: original[0].id }, classList: { toggle() {} } };
  // Execute the actual UI handler, with only the surrounding DOM replaced.
  const handler = planning.slice(planning.indexOf('  function captureInput(input) {'), planning.indexOf('  function removeTask('));
  const context = vm.createContext({ state, planningChanges, readOnly: () => false, dirtyCount: () => 1, content: { querySelector: () => null } });
  vm.runInContext(handler + '; globalThis.capture = captureInput;', context);
  for (const [name, value] of [['especialidade_id', 'synthetic-specialty'], ['executado_por', 'subempreitada']]) context.capture({ name, value, closest: () => row });
  const payload = { version: 1, obra_id: 'synthetic-work', changes: planningChanges(original, state.items) };
  const persisted = structuredClone(original);
  const api = async (path, options) => {
    assert.equal(path, 'rpc/fn_guardar_planeamento_lote');
    const body = JSON.parse(options.body);
    assert.deepEqual(body.p_lote.changes, [{ id: original[0].id, especialidade_id: 'synthetic-specialty', executado_por: 'subempreitada' }]);
    if (!body.p_confirmacao) return Response.json({ version: 1, confirmation_token: 'synthetic-token' });
    assert.equal(body.p_confirmacao, 'synthetic-token');
    Object.assign(persisted[0], body.p_lote.changes[0]);
    return Response.json({ version: 1, committed: true });
  };
  const preview = await requestPlanningBatch(api, payload);
  await requestPlanningBatch(api, payload, preview.confirmation_token);
  assert.equal(persisted[0].especialidade_id, 'synthetic-specialty');
  assert.equal(persisted[0].executado_por, 'subempreitada');
  assert.equal(original[0].especialidade_id, null);
});

test("Consultas Pendentes é uma vista calculada, ordenada por início e sem remoção manual", () => {
  assert.match(migration, /create or replace view public\.consultas_pendentes_planeamento/);
  assert.match(migration, /pi\.executado_por = 'subempreitada'[\s\S]*pi\.subempreitada_id is null/);
  assert.doesNotMatch(migration, /create table[^;]*consultas_pendentes/i);
  assert.match(procurement, /consultas_pendentes_planeamento\?select=\*&obra_id=eq\.[^`]+&order=data_inicio_prevista\.asc\.nullslast/);
  assert.match(procurement, /data-pending-consultation/);
  assert.match(procurement, /state\.prefillPlanningItemId = pendingButton\.dataset\.pendingConsultation/);
  assert.doesNotMatch(procurement, /remover.{0,30}pendente|delete.{0,30}consultas_pendentes/is);
});

test("a adjudicação liga a subempreitada à tarefa e retira-a naturalmente da vista", () => {
  assert.match(migration, /add column if not exists planeamento_item_id uuid/);
  assert.match(migration, /create trigger trg_sincronizar_subempreitada_planeamento/);
  assert.match(migration, /update public\.planeamento_itens[\s\S]*set[\s\S]*subempreitada_id = new\.id/);
  assert.match(migration, /and subempreitada_id is null/);
  assert.match(procurement, /rpc\/fn_criar_consulta_planeamento/);
});
