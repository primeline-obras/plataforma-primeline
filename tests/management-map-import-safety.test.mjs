import assert from "node:assert/strict";
import test from "node:test";
import { parseManagementWorkbook, validateManagementImportRows } from "../src/management-map.js";

test("a pré-visualização bloqueia as obras reservadas ao Saldo de Abertura", () => {
  const errors = validateManagementImportRows([
    { linha: 2, obra_numero: "79" },
    { linha: 3, obra_numero: "085" },
    { linha: 4, obra_numero: 127 },
    { linha: 5, obra_numero: "120" },
  ]);

  assert.equal(errors.length, 3);
  assert.match(errors[0], /Obra 79 não aceita importação/);
  assert.match(errors[1], /Obra 085 não aceita importação/);
  assert.match(errors[2], /Obra 127 não aceita importação/);
  assert.ok(errors.every(error => error.includes("usar Saldo de Abertura")));
});

test("as restantes obras continuam permitidas na validação local", () => {
  assert.deepEqual(validateManagementImportRows([
    { linha: 2, obra_numero: "032" },
    { linha: 3, obra_numero: "118" },
    { linha: 4, obra_numero: "120" },
    { linha: 5, obra_numero: "128" },
  ]), []);
});

test("reconhece folhas sem distinguir caixa, espaços ou hífen e aceita Faturação em falta", () => {
  const previousXlsx = globalThis.XLSX;
  globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet.rows } };
  try {
    const workbook = {
      SheetNames: [" MATERIAIS ", "DESPESAS - ESTALEIRO", "SUBCONTRATOS", "FUNCIONÁRIOS - OBRA"],
      Sheets: {
        " MATERIAIS ": { rows: [] },
        "DESPESAS - ESTALEIRO": { rows: [] },
        SUBCONTRATOS: { rows: [] },
        "FUNCIONÁRIOS - OBRA": { rows: [] },
      },
    };
    assert.deepEqual(parseManagementWorkbook(workbook), { rows: [], errors: [] });
  } finally {
    globalThis.XLSX = previousXlsx;
  }
});

test("reconhece nomes extensos e abreviados da folha de mão de obra", () => {
  const previousXlsx = globalThis.XLSX;
  globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet.rows } };
  try {
    for (const laborSheet of ["FUNCIONÁRIOS-OBRA - MÃO DE OBRA", "MÃO DE OBRA", "Funcionários da Obra"]) {
      const workbook = {
        SheetNames: ["MATERIAIS", "DESPESAS - ESTALEIRO", "SUBCONTRATOS", laborSheet],
        Sheets: {
          MATERIAIS: { rows: [] },
          "DESPESAS - ESTALEIRO": { rows: [] },
          SUBCONTRATOS: { rows: [] },
          [laborSheet]: { rows: [] },
        },
      };
      assert.deepEqual(parseManagementWorkbook(workbook), { rows: [], errors: [] }, laborSheet);
    }
  } finally {
    globalThis.XLSX = previousXlsx;
  }
});

test("continua a exigir as quatro folhas operacionais", () => {
  const previousXlsx = globalThis.XLSX;
  globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet.rows } };
  try {
    const workbook = { SheetNames: ["MATERIAIS"], Sheets: { MATERIAIS: { rows: [] } } };
    const result = parseManagementWorkbook(workbook);
    assert.equal(result.errors.length, 3);
    assert.ok(result.errors.some(error => error.includes("Despesas-Estaleiro")));
    assert.ok(result.errors.some(error => error.includes("Subcontratos")));
    assert.ok(result.errors.some(error => error.includes("Funcionários-Obra")));
    assert.ok(result.errors.every(error => !error.includes("Faturação")));
  } finally {
    globalThis.XLSX = previousXlsx;
  }
});
