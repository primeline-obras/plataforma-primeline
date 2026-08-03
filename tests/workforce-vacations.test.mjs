import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

assert.match(source, /openVacationDaysDialog/, "O quadro deve abrir o editor diário de férias.");
assert.match(source, /name="vacation_date"/, "O editor deve permitir selecionar cada dia separadamente.");
assert.match(source, /method: "DELETE"/, "O editor deve permitir remover dias de férias já registados.");
assert.doesNotMatch(source, /saveVacationWeek/, "O fluxo antigo de semana inteira não deve continuar ativo.");

console.log("Edição diária de férias validada.");
