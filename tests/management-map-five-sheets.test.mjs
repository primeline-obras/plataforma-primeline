import test from "node:test";
import assert from "node:assert/strict";
import { normalizeManagementRows } from "../src/management-map.js";

test("mão de obra calcula o total a partir de horas e valor/hora", () => {
  const [row] = normalizeManagementRows("mao_obra", [{ Colaborador: "William Coimbra", Obra: 118, Data: "18/06/2026", Horas: "8,00", "Valor/Hora": "17,30€" }]);
  assert.deepEqual(row, { categoria: "mao_obra", linha: 2, obra_numero: "118", colaborador: "William Coimbra", data: "2026-06-18", horas: 8, valor_hora: 17.3 });
  assert.equal("valor_total" in row, false);
});

test("faturação preserva emissão, recebimento, valores e estado", () => {
  const [row] = normalizeManagementRows("faturacao", [{ "Nº Fatura": "FT 2026/054", Obra: 120, "Data Emissão": "2026-08-10", Valor: "41.333,93€", "Data Recebimento": "2026-08-20", "Valor Recebido": "41.333,93€", Estado: "recebida" }]);
  assert.equal(row.numero_fatura, "FT 2026/054");
  assert.equal(row.valor, 41333.93);
  assert.equal(row.valor_recebido, 41333.93);
  assert.equal(row.estado, "recebida");
});
