import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

globalThis.XLSX = { utils: { sheet_to_json: sheet => sheet } };
const { __test } = await import("../src/xlsx-operational-import.js");

const subcontractHeaders = [
  "Obra (nº)*", "Fase (código)", "Trabalho / Especialidade*", "Fornecedor (nome)", "Custo Direto (€)", "Preço de Venda (€)", "Margem Prevista (€)", "Data do Pedido", "Data da Proposta", "Data do Contrato", "Valor Adjudicado (€)", "Tipo de Pagamento", "Condição de Pagamento", "Data Início Prevista", "Data Fim Prevista", "Estado*",
];
const teeHeaders = ["Nº TEE*", "Obra (nº)*", "Fase (código)", "Descrição", "Especialidade", "Valor (€)", "Preço de Custo (€)", "Dias de Prorrogação", "Data de Envio", "Data de Resposta", "Estado Aprovação Cliente", "Revisão", "Data Início Execução", "Data Fim Execução"];
const teeItemHeaders = ["Nº TEE*", "Nº Artigo*", "Descrição*", "Unidade", "Quantidade", "Preço Unitário (€)", "Valor Total (€)"];

test("Subempreitadas valida o modelo, fornecedor e estado antes de gravar", () => {
  const workbook = { Sheets: { Subempreitadas: [subcontractHeaders, [120, "F03", "Caixilharia", "Fornecedor A", 100, 130, 30, "01/08/2026", "02/08/2026", "03/08/2026", 100, "por_fase", "15_dias", "04/08/2026", "30/08/2026", "em_execucao"], [120, "F03", "Pintura", "Fornecedor A", 80, 100, 20, "01/08/2026", "02/08/2026", "03/08/2026", 80, "por_fase", "15_dias", "04/08/2026", "30/08/2026", "adjudicado"]] } };
  const rows = __test.parseSubcontracts(workbook, { work: { id: "w1", numero: 120 }, phases: [{ id: "f3", codigo: "F03" }], suppliers: [{ id: "s1", nome: "Fornecedor A" }], consultations: [], subcontracts: [] });
  assert.equal(rows.length, 2); assert.deepEqual(rows[0].errors, []); assert.deepEqual(rows[1].errors, []); assert.equal(rows[0].payload.fornecedor_id, "s1"); assert.equal(rows[0].payload.data_inicio_prevista, "2026-08-04");
});

test("TEEs liga cabeçalho e itens pelo Nº TEE e avisa quando não há itens", () => {
  const workbook = { Sheets: {
    "TEE_Cabeçalho": [teeHeaders, ["TEE 01", 120, "F01", "Trabalho", "Geral", 1000, 700, 0, "01/08/2026", "", "pendente", "REV00", "", ""], ["TEE 02", 120, "F01", "Sem itens", "Geral", 10, 5, 0, "", "", "pendente", "REV00", "", ""]],
    "TEE_Itens": [teeItemHeaders, ["TEE 01", "1.1", "Artigo", "un", 2, 5, 10]],
  } };
  const rows = __test.parseTees(workbook, { work: { id: "w1", numero: 120 }, phases: [{ id: "f1", codigo: "F01", descricao: "Estaleiro" }], tees: [] });
  assert.equal(rows[0].payload.itens.length, 1); assert.equal(rows[1].warnings.length, 1); assert.deepEqual(rows[0].errors, []);
});

test("Mapa Financeiro reconhece Obra + Jan-Dez e os três grupos fixos", () => {
  const header = ["Obra", "Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
  const workbook = { SheetNames: ["Mapa"], Sheets: { Mapa: [header, ["120 · Quinta", ...Array(12).fill(100)], ["Despesas Sede", ...Array(12).fill(20)]] } };
  const rows = __test.parseFinancial(workbook, { year: 2026, works: [{ id: "w1", numero: 120, nome: "Quinta" }], adjustments: [] });
  assert.equal(rows.length, 2); assert.equal(rows[0].payload.tipo, "obra"); assert.equal(rows[1].payload.categoria, "despesas_sede");
});

test("Os três ecrãs expõem o botão e a confirmação explícita", () => {
  const sources = ["src/procurement.js", "src/app.js", "src/financial-map.js", "src/xlsx-operational-import.js"].map(path => fs.readFileSync(new URL(`../${path}`, import.meta.url), "utf8")).join("\n");
  assert.match(sources, /data-import-subcontracts/); assert.match(sources, /data-import-tees/); assert.match(sources, /data-import-financial-map/); assert.match(sources, /CONFIRMAR IMPORTAÇÃO/);
});

test("o importador é inicializado antes dos módulos que o consomem", () => {
  const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
  const initialization = app.indexOf("const operationalXlsxImportModule = createOperationalXlsxImport");
  assert.ok(initialization >= 0);
  assert.ok(initialization < app.indexOf("const financialMapModule = createFinancialMapModule"));
  assert.match(fs.readFileSync(new URL("../src/procurement.js", import.meta.url), "utf8"), /typeof onImportExcel !== "function"/);
});

