import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");

test("baixas e justificação pendente não recebem a marcação de férias", () => {
  const start = app.indexOf("function workforceAbsencePresentation(");
  const end = app.indexOf("function vacationMonthBounds(", start);
  const presentation = new Function("workforceAbsenceLabels", "shortPersonName", app.slice(start, end) + "; return workforceAbsencePresentation;")({}, p => p);
  const effective = [{person:{id:"synthetic",nome:"Synthetic"}}];
  for (const tipo of ["baixa_doenca", "baixa_maternidade", "baixa_parental"]) {
    const result = presentation([{colaborador_id:"synthetic",data:"2026-10-06",tipo,estado:"confirmada"}], effective, "2026-10-06");
    assert.equal(result.visualType, "absence");
    assert.equal(result.badge, "A");
  }
  const pending = presentation([{colaborador_id:"synthetic",data:"2026-10-06",tipo:"baixa_doenca",estado:"ausente_pendente"}], effective, "2026-10-06");
  assert.equal(pending.badge, "?");
  assert.match(pending.tooltip, /JUSTIFICAÇÃO PENDENTE/);
});

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
