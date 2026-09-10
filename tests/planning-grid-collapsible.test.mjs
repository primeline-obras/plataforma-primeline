import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const planning = await readFile(new URL("../src/planning.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");
const identityStyles = await readFile(new URL("../src/visual-identity-final.css", import.meta.url), "utf8");

test("detalhes das tarefas começam fechados e podem ser expandidos sem perder edições", () => {
  assert.match(planning, /expandedTasks:\s*new Set\(\)/);
  assert.match(planning, /class="planning-editor-details" \$\{detailsOpen \? "" : "hidden"\}/);
  assert.match(planning, /data-toggle-task="\$\{item\.id\}"/);
  assert.match(planning, /details\.hidden = !opening/);
  assert.match(styles, /\.planning-editor-row\s*>\s*section\[hidden\]\s*\{\s*display:none;/);
});

test("grelha simples replica os campos operacionais do planeamento", () => {
  assert.match(styles, /--planning-grid-columns:/);
  assert.match(styles, /grid-template-columns:var\(--planning-grid-columns\)/);
  assert.match(planning, /class="planning-row-actions/);
  assert.match(styles, /\.planning-row-actions\s*\{[^}]*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(styles, /minmax\(280px,1\.6fr\)/);
  assert.match(styles, /\s112px 112px 112px\s/);
  assert.match(planning, /<span>CÓDIGO<\/span><span>DESCRIÇÃO \/ TRABALHOS<\/span>/);
  assert.match(planning, /data-weighted/);
  assert.match(planning, /data-derived-state/);
  assert.match(identityStyles, /\.planning-editor-head,[\s\S]*grid-template-columns:\s*var\(--planning-grid-columns\)/);
  assert.doesNotMatch(identityStyles, /planning-editor-head,[\s\S]{0,160}grid-template-columns:\s*160px 90px/);
});

test("fases são recolhíveis e o Gantt não ocupa o ecrã operacional", () => {
  assert.match(planning, /collapsedEditorPhases:\s*new Set\(\)/);
  assert.match(planning, /data-toggle-editor-phase="\$\{phase\.id\}"/);
  assert.match(planning, /planning-editor-phase-rows/);
  assert.doesNotMatch(planning, /<p class="eyebrow">GANTT POR FASE<\/p>/);
});
