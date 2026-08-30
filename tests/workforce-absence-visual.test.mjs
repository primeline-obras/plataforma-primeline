import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");

test("o quadro associa ausências à pessoa e ao dia da célula", () => {
  assert.match(app, /function workforceAbsencePresentation\(absences, effective, date\)/);
  assert.match(app, /item\.data === date && names\.has\(item\.colaborador_id\)/);
  assert.match(app, /workforceAbsencePresentation\(activeAbsences, effective, date\)/);
  assert.match(app, /data-absence-detail/);
  assert.match(app, /item\.comentario/);
});

test("férias, faltas justificadas e injustificadas têm marcações distintas", () => {
  assert.match(styles, /absence-vacation[\s\S]*rgba\(74, 85, 104, \.42\)/);
  assert.match(styles, /absence-justified[\s\S]*rgba\(107, 104, 95, \.36\)/);
  assert.match(styles, /absence-unjustified[\s\S]*rgba\(140, 74, 64, \.42\)/);
  assert.match(styles, /workforce-absence-badge\.vacation[\s\S]*#4a5568[\s\S]*#f1efe8/);
  assert.match(styles, /workforce-absence-badge\.justified[\s\S]*#6b685f/);
  assert.match(styles, /workforce-absence-badge\.unjustified[\s\S]*#8c4a40/);
});

test("o detalhe funciona por hover, foco e toque sem tentar alocar", () => {
  assert.match(styles, /workforce-absence-badge:hover::after/);
  assert.match(styles, /workforce-absence-badge:focus::after/);
  assert.match(app, /absenceBadge\.focus\(\)/);
  assert.match(app, /event\.stopPropagation\(\)/);
});
