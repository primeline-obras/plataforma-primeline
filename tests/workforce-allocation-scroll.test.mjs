import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const saveStart = app.indexOf("async function saveWorkforceAllocation(personId, date, target)");
const saveEnd = app.indexOf("async function removeWorkforceAllocation()", saveStart);
const saveAllocation = app.slice(saveStart, saveEnd);

test("alocar atualiza o estado local sem recarregar todos os dados", () => {
  assert.match(saveAllocation, /Prefer: "return=representation"/);
  assert.match(saveAllocation, /replaceLocalAllocations/);
  assert.doesNotMatch(saveAllocation, /loadTeamData\(true\)/);
});

test("a atualização da grelha preserva o scroll da página e da grelha", () => {
  assert.match(app, /function renderTeamPreservingScroll\(\)/);
  assert.match(app, /window\.scrollX/);
  assert.match(app, /window\.scrollTo\(pagePosition\.x, pagePosition\.y\)/);
  assert.match(app, /element\.scrollTo\(\{ top: position\.top, left: position\.left/);
  assert.match(saveAllocation, /renderTeamPreservingScroll\(\)/);
});
