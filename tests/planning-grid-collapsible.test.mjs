import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const planning = await readFile(new URL("../src/planning.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

test("detalhes das tarefas começam fechados e podem ser expandidos sem perder edições", () => {
  assert.match(planning, /expandedTasks:\s*new Set\(\)/);
  assert.match(planning, /class="planning-editor-details" \$\{detailsOpen \? "" : "hidden"\}/);
  assert.match(planning, /data-toggle-task="\$\{item\.id\}"/);
  assert.match(planning, /details\.hidden = !opening/);
  assert.match(styles, /\.planning-editor-row\s*>\s*section\[hidden\]\s*\{\s*display:none;/);
});

test("grelha partilha uma única definição de colunas e reserva ações", () => {
  assert.match(styles, /--planning-grid-columns:/);
  assert.match(styles, /grid-template-columns:var\(--planning-grid-columns\)/);
  assert.match(planning, /class="planning-row-actions"/);
  assert.match(styles, /\.planning-row-actions\s*\{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(styles, /minmax\(300px,1\.35fr\)/);
  assert.match(styles, /\s112px 112px 112px\s/);
});
