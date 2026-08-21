import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

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
  assert.match(planning, /especialidade_id: value\("especialidade_id"\) \|\| null/);
  assert.match(planning, /executado_por: value\("executado_por"\) \|\| null/);
  assert.match(planning, /especialidades\?select=id,nome&order=nome/);
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
