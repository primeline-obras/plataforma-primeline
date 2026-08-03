import assert from "node:assert/strict";
import { directDebitForecastByMonth, directDebitOccurrences } from "../src/direct-debits.js";

const monthly = {
  id: "mensal",
  ativo: true,
  recorrencia: "mensal",
  dia_mes: 31,
  data_inicio: "2026-01-31",
  data_fim: "2026-04-30",
  valor_previsto: 125,
  obra_id: "obra-1",
};

assert.deepEqual(
  directDebitOccurrences(monthly, "2026-01-01", "2026-04-30").map(row => row.data),
  ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"],
  "O dia 31 deve adaptar-se ao último dia de cada mês.",
);

const quarterly = { ...monthly, id: "trimestral", recorrencia: "trimestral", dia_mes: 10, data_inicio: "2026-02-10", data_fim: null, valor_previsto: 300 };
assert.deepEqual(
  directDebitOccurrences(quarterly, "2026-01-01", "2026-12-31").map(row => row.data),
  ["2026-02-10", "2026-05-10", "2026-08-10", "2026-11-10"],
);

assert.equal(directDebitOccurrences({ ...monthly, ativo: false }, "2026-01-01", "2026-12-31").length, 0);
assert.equal(directDebitOccurrences({ ...monthly, recorrencia: null }, "2026-01-01", "2026-12-31").length, 0);

const totals = directDebitForecastByMonth([monthly, quarterly], "2026-01-01", "2026-04-30");
assert.equal(totals.get("2026-02"), 425);
assert.equal(totals.get("2026-03"), 125);

console.log("Recorrências e previsões de débitos diretos validadas.");
