import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

assert.match(source, /openVacationDaysDialog/, "O quadro deve abrir o editor diário de férias.");
assert.match(source, /name="vacation_date"/, "O editor deve permitir selecionar cada dia separadamente.");
const save=source.slice(source.indexOf('async function saveVacationDays'),source.indexOf('async function loadTeamData'));
assert.match(save, /execute\('vacation_replace'/, "Adicionar/remover dias deve ser uma única operação controlada.");
assert.match(save, /scope_dates:weekDates/);
assert.match(save, /expected_revision:Number\(formElement.dataset.revision\)/);
assert.doesNotMatch(save, /method:\s*['"](?:POST|PATCH|DELETE)['"]/, "O editor não pode usar DML direto.");
assert.doesNotMatch(source, /saveVacationWeek/, "O fluxo antigo de semana inteira não deve continuar ativo.");

console.log("Edição diária de férias validada.");
