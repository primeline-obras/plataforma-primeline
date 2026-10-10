import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const saveStart = app.indexOf("async function saveWorkforceAllocation(personId, date, target)");
const saveEnd = app.indexOf("async function removeWorkforceAllocation()", saveStart);
const saveAllocation = app.slice(saveStart, saveEnd);

test("contrato diário mantém atualização local; permanência recarrega projeção semanal", () => {
  assert.match(saveAllocation, /workforceAllocationClient\.execute/);
  assert.match(saveAllocation, /applyWorkforceResult/);
  assert.match(app, /replaceLocalAllocations/);
  assert.doesNotMatch(saveAllocation, /loadTeamData\(true\)/);
});

test("a atualização da grelha preserva o scroll da página e da grelha", () => {
  assert.match(app, /function renderTeamPreservingScroll\(renderOperation=renderTeam\)/);
  assert.match(app, /window\.scrollX/);
  assert.match(app, /window\.scrollTo\(pagePosition\.x, pagePosition\.y\)/);
  assert.match(app, /element\.scrollTo\(\{ top: position\.top, left: position\.left/);
  assert.match(app, /renderTeamPreservingScroll\(\)/);
});
