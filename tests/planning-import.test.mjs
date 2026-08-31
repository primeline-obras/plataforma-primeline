import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { csvRows, normalizedHeader, parsedDate, parsedNumber, parsedState } from "../src/planning-import.js";
import { isoDate } from "../src/planning.js";

const planning = await readFile(new URL("../src/planning.js", import.meta.url), "utf8");
const planningStyles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

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

test("datas calculadas das vistas de resumo e controlo são apresentáveis", () => {
  assert.equal(isoDate(new Date("2026-08-04T00:00:00Z")), "2026-08-04");
  assert.equal(isoDate("2026-08-05"), "2026-08-05");
});

test("a aba única mantém o Gantt por fase e a grelha detalhada", () => {
  assert.match(planning, /function renderUnifiedPlanning\(\)/);
  assert.match(planning, /GANTT POR FASE/);
  assert.match(planning, /GRELHA DETALHADA/);
  assert.doesNotMatch(planning, /<aside class="planning-layer-nav"/);
  assert.match(planningStyles, /\.planning-baseline-head,\s*\.planning-baseline-row/);
  assert.match(planningStyles, /\.planning-baseline-track\s*>\s*i/);
  assert.match(planningStyles, /\.planning-summary-kpis/);
  assert.match(planningStyles, /\.planning-summary-head,\s*\.planning-summary-row/);
  assert.match(planningStyles, /\.planning-summary-track\s*>\s*i\.baseline/);
  assert.match(planningStyles, /\.planning-summary-track\s*>\s*i\.effective/);
  assert.match(planningStyles, /\.planning-editor-phase\s*>\s*header/);
  ["% PONDERADA", "CAUSA DO ATRASO", "IMPACTO", "DESVIO INÍCIO", "DESVIO FIM", "COMPARAÇÃO DE PRAZO", "CLASSIFICAÇÃO"].forEach(label => assert.ok(planning.includes(label), `falta ${label}`));
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
  assert.match(planning, /function taskDeviation\(item\)/);
  assert.match(planning, /value\s+instanceof\s+Date/);
  assert.match(planning, /value\.toISOString\(\)\.slice\(0,\s*10\)/);
  assert.match(planning, /data-confirm-import/);
  assert.match(planning, /A CRIAR/);
  assert.match(planning, /A ATUALIZAR/);
  assert.match(planning, /method:\s*item\._new\s*\?\s*"POST"\s*:\s*"PATCH"/);
  assert.match(planning, /data-remove-task/);
  assert.match(planning, /planeamento_itens_dependencias/);
  assert.match(planning, /data-remove-dependency/);
});
