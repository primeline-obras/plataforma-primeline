import test from "node:test";
import assert from "node:assert/strict";
import { formatManagementDate, managementRowMatches } from "../src/management-map.js";

const row = {
  obra_id: "obra-120",
  categoria: "materiais",
  data_lancamento: "2026-09-02",
  entidade_nome: "Leroy Merlin",
  descricao: "Torneira para casa de banho",
  documento: "FT 2026/054",
  valor: 123.45,
};

test("apresenta datas no formato DD/MM/AAAA", () => {
  assert.equal(formatManagementDate("2026-09-02"), "02/09/2026");
  assert.equal(formatManagementDate(null), "—");
});

test("combina filtros específicos dentro da categoria", () => {
  assert.equal(managementRowMatches(row, {
    obra_id: "obra-120",
    categoria: "materiais",
    data_inicio: "2026-09-01",
    data_fim: "2026-09-03",
    entidade: "leroy",
    descricao: "casa de banho",
    documento: "2026/054",
    valor: "123,45",
  }), true);

  assert.equal(managementRowMatches(row, { descricao: "cimento" }), false);
  assert.equal(managementRowMatches(row, { documento: "NC 01" }), false);
  assert.equal(managementRowMatches(row, { valor: "123,46" }), false);
});

test("respeita a categoria pedida pelo bloco", () => {
  assert.equal(managementRowMatches(row, {}, { category: "materiais" }), true);
  assert.equal(managementRowMatches(row, {}, { category: "estaleiro" }), false);
});
