import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { csvRows, normalizedHeader, parsedDate, parsedNumber, parsedState } from "../src/planning-import.js";

const planning = await readFile(new URL("../src/planning.js", import.meta.url), "utf8");

test("a colagem do Sheets preserva cabeçalhos e células tabulares", () => {
  const rows = csvRows("Código\tDescrição\tResponsável\tPeso (%)\t% Executado\nF01.1\tMontagem, estaleiro\tJoão\t12,5%\t40%");
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], ["Código", "Descrição", "Responsável", "Peso (%)", "% Executado"]);
  assert.equal(rows[1][1], "Montagem, estaleiro");
  assert.equal(normalizedHeader("Data Início"), "data inicio");
  assert.equal(normalizedHeader("Peso (%)"), "peso %");
});

test("datas, percentagens e estados do formato português são normalizados", () => {
  assert.equal(parsedDate("04/08/2026"), "2026-08-04");
  assert.equal(parsedDate("2026-08-05"), "2026-08-05");
  assert.equal(parsedNumber("12,5%"), 12.5);
  assert.equal(parsedState("Em execução", 20), "em_execucao");
  assert.equal(parsedState("", 100), "concluido");
});

test("o planeamento oferece pré-visualização, criação, atualização e dependências", () => {
  assert.match(planning, /data-open-import/);
  assert.match(planning, /querySelector\("\[data-open-import\]"\).*addEventListener\("click"/s);
  assert.match(planning, /function openImportPanel\(\)/);
  assert.match(planning, /planning-import-panel.*scrollIntoView/s);
  assert.match(planning, /querySelector\("\[data-new-task\]"\).*addEventListener\("click"/s);
  assert.match(planning, /function addNewTask\(\)/);
  assert.match(planning, /em_atraso:\s*"EM ATRASO"/);
  assert.match(planning, /plannedEnd\s*&&\s*plannedEnd\s*<\s*currentDay/);
  assert.match(planning, /data_inicio_real/);
  assert.match(planning, /baseline-planned/);
  assert.match(planning, /baseline-real/);
  assert.match(planning, /planned-real/);
  assert.match(planning, /ATRASO CRÍTICO/);
  assert.match(planning, /querySelectorAll\("\[data-planning-view\]"\)/);
  assert.match(planning, /state\.view\s*=\s*button\.dataset\.planningView/);
  assert.match(planning, /data-confirm-import/);
  assert.match(planning, /A CRIAR/);
  assert.match(planning, /A ATUALIZAR/);
  assert.match(planning, /method:\s*item\._new\s*\?\s*"POST"\s*:\s*"PATCH"/);
  assert.match(planning, /data-remove-task/);
  assert.match(planning, /planeamento_itens_dependencias/);
  assert.match(planning, /data-remove-dependency/);
});
