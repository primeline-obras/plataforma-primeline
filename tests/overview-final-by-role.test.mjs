import assert from "node:assert/strict";
import fs from "node:fs";
import {
  alertsForOverviewRole,
  consolidatedCashFlowSummary,
  invoiceDueDate,
} from "../src/production-dashboard.js";

const alerts = [
  { id: "rh", tipo: "validade_epi", obra_id: null },
  { id: "finance", tipo: "debito_direto", destinatario_role: "financeiro" },
  { id: "own", tipo: "tarefa_impedida", obra_id: "obra-a" },
  { id: "other", tipo: "rnc", obra_id: "obra-b" },
  { id: "weekly", tipo: "informacao_reuniao_semanal", entidade_id: "user-a" },
];

assert.equal(alertsForOverviewRole(alerts, "gerencia").length, 5);
assert.equal(alertsForOverviewRole(alerts, "administrativo").length, 5);
assert.deepEqual(alertsForOverviewRole(alerts, "financeiro").map(row => row.id), ["finance"]);
assert.deepEqual(
  new Set(alertsForOverviewRole(alerts, "preparador", new Set(["obra-a"]), "user-a").map(row => row.id)),
  new Set(["own", "weekly"]),
);

assert.equal(invoiceDueDate({ data_fatura: "2026-08-01", condicao_pagamento: "15_dias" }), "2026-08-16");
assert.equal(invoiceDueDate({ data_fatura: "2026-08-01", condicao_pagamento: "outra_data", data_vencimento: "2026-09-03" }), "2026-09-03");

const cash = consolidatedCashFlowSummary([
  { mes: "2026-08-01", fechado: true, entradas_reais: 100, saidas_reais_sem_iva: 40, entradas_previstas: 999, saidas_previstas_sem_iva: 999 },
  { mes: "2026-09-01", fechado: false, entradas_reais: 0, saidas_reais_sem_iva: 0, entradas_previstas: 200, saidas_previstas_sem_iva: 80 },
], new Date("2026-08-11T12:00:00"));
assert.equal(cash.monthIncoming, 100);
assert.equal(cash.monthOutgoing, 40);
assert.equal(cash.yearIncoming - cash.yearOutgoing, 180);

const sql = fs.readFileSync(new URL("../supabase/visao_geral_final_por_papel.sql", import.meta.url), "utf8");
assert.match(sql, /fn_criar_lembretes_equipa_tecnica/);
assert.match(sql, /extract\(isodow from p_data\) = 4/);
assert.match(sql, /pedido_mensal_horas/);
assert.match(sql, /entidade_id = public\.fn_utilizador_atual_id\(\)/);

console.log("Visão Geral final por papel validada.");
