import assert from "node:assert/strict";
import test from "node:test";
import { parseManagementWorkbook, prepareManagementImportRows, summarizeManagementImportErrors, validateManagementImportRows } from "../src/management-map.js";

test("a pré-visualização bloqueia as obras reservadas ao Saldo de Abertura", () => {
  const errors = validateManagementImportRows([
    { linha: 2, obra_numero: "79" },
    { linha: 3, obra_numero: "085" },
    { linha: 4, obra_numero: 127 },
    { linha: 5, obra_numero: "120" },
    { linha: 6, obra_numero: "079" },
  ]);

  assert.equal(errors.length, 3);
  assert.match(errors[0], /Obra 79 não aceita importação/);
  assert.match(errors[1], /Obra 85 não aceita importação/);
  assert.match(errors[2], /Obra 127 não aceita importação/);
  assert.ok(errors.every(error => error.includes("usar Saldo de Abertura")));
  assert.match(errors[0], /2 linha\(s\) afetada\(s\)/);
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

test("remove duplicados do próprio ficheiro antes de o enviar em lotes", () => {
  const first = { categoria: "materiais", obra_numero: "120", numero_documento: "FT 01", fornecedor: "Fornecedor Exemplo", valor_total: 12.345 };
  const same = { ...first, obra_numero: "0120", numero_documento: " ft 01 ", fornecedor: "FORNECEDOR EXEMPLO", valor_total: "12,345" };
  const different = { ...first, numero_documento: "FT 02" };
  const invalid = { categoria: "materiais", obra_numero: "120", numero_documento: "", fornecedor: "", valor_total: null };
  const result = prepareManagementImportRows([first, same, different, invalid, invalid]);

  assert.equal(result.duplicates, 1);
  assert.deepEqual(result.rows, [first, different, invalid, invalid]);
});

test("lê a estrutura real com título na primeira linha e cabeçalhos na segunda", () => {
  const previousXlsx = globalThis.XLSX;
  globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet.rows } };
  try {
    const workbook = {
      SheetNames: ["FUNCIONÁRIOS EM OBRA", "MATERIAIS", "SUBCONTRATOS", "DESPESAS - ESTALEIRO"],
      Sheets: {
        "FUNCIONÁRIOS EM OBRA": { rows: [["FUNCIONÁRIOS EM OBRA"], ["Nº", "OBRA Nº", "DATA", "Nº INTERNO", "  NOME FUNCIONÁRIO", "QUANT", "VALOR HORA", "VALOR TOTAL"], [null, 118, "01/09/2026", 4, "William Coimbra (Enc. Obra - Nível 1)", 8, 15.61, 124.88]] },
        MATERIAIS: { rows: [["MATERIAIS EM OBRA"], ["N.º Doc", "OBRA Nº", "DATA", "FORNECEDOR", "DESIGNAÇÃO", "UN MEDIDA", "QUANT", "VALOR UNIT", "#VALUE!", "DATA DE PAGAMENTO"], ["FT 01", 120, "01/09/2026", "Fornecedor A", "Material A", "un", 2, 3.5, 7, "02/09/2026"]] },
        SUBCONTRATOS: { rows: [["SUBCONTRATOS"], ["Nº", "OBRA Nº", "DATA", "FORNECEDOR", "DESIGNAÇÃO", "UN MEDIDA", "QUANT", "VALOR UNIT", "VALOR TOTAL", "DATA DE PAGAMENTO"], ["FT 02", 122, "01/09/2026", "Fornecedor B", "Serviço B", "un", 1, 50, 50, "02/09/2026"]] },
        "DESPESAS - ESTALEIRO": { rows: [["OUTRAS DESPESAS"], ["Nº", "OBRA Nº", "DATA", "FORNECEDOR", "DESIGNAÇÃO", "UN MEDIDA", "QUANT", "VALOR UNIT", "VALOR TOTAL", "DATA DE PAGAMENTO"], ["FT 03", 120, "01/09/2026", "Fornecedor C", "Despesa C", "un", 1, 20, 20, "02/09/2026"]] },
      },
    };
    const result = parseManagementWorkbook(workbook);
    assert.deepEqual(result.errors, []);
    assert.equal(result.rows.length, 4);
    const labor = result.rows.find(row => row.categoria === "mao_obra");
    const material = result.rows.find(row => row.categoria === "materiais");
    assert.deepEqual(labor, { categoria: "mao_obra", linha: 3, obra_numero: "118", colaborador: "William Coimbra", data: "2026-09-01", horas: 8, valor_hora: 15.61 });
    assert.equal(material.numero_documento, "FT 01");
    assert.equal(material.valor_total, 7);
    assert.equal(material.data_pagamento, "2026-09-02");
  } finally {
    globalThis.XLSX = previousXlsx;
  }
});

test("agrupa erros repetidos sem perder a contagem total da pré-visualização", () => {
  assert.deepEqual(summarizeManagementImportErrors([
    "Linha 3: colaborador João Afonso não encontrado.",
    "Linha 4: colaborador João Afonso não encontrado.",
    "Linha 8: fornecedor Galp não encontrado.",
  ]), ["colaborador João Afonso não encontrado. (2 linhas)", "fornecedor Galp não encontrado."]);
});
