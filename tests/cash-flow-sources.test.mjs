import assert from "node:assert/strict";
import { actualCashFlowByMonth, materialInvoiceValue } from "../src/production-dashboard.js";

const detailedInvoice = { id: "material-1", valor: 999, data_pagamento: "2026-03-20" };
const invoiceItems = [
  { fatura_id: "material-1", preco_total: 70 },
  { fatura_id: "material-1", quantidade: 2, preco_unitario: 15, preco_total: null },
];
assert.equal(materialInvoiceValue(detailedInvoice, invoiceItems), 100);
assert.equal(materialInvoiceValue({ id: "material-2", valor: 131.67 }, invoiceItems), 131.67);

const months = actualCashFlowByMonth({
  billings: [
    { data_recebimento: "2026-02-13", valor_recebido: 41628.32 },
    { data_recebimento: "2026-02-18", valor_recebido: 69095.52 },
    { data_recebimento: null, valor_recebido: 999999 },
  ],
  payments: [{ data_pagamento: "2026-02-15", valor: 500 }],
  materialInvoices: [detailedInvoice, { id: "material-2", valor: 131.67, data_pagamento: "2026-03-21" }],
  materialInvoiceItems: invoiceItems,
  labor: [{ data: "2026-02-20", horas: 8, valor_hora: 12 }],
  siteExpenses: [{ data_pagamento: "2026-02-22", valor_total: 50 }],
  directDebitEntries: [{ data: "2026-02-25", valor: 25 }],
});

assert.equal(months.get("2026-02").incoming, 110723.84);
assert.equal(months.get("2026-02").outgoing, 671);
assert.equal(months.get("2026-03").materials, 231.67);
assert.equal(months.get("2026-03").outgoing, 231.67);

const work120Receipts = actualCashFlowByMonth({
  billings: [
    ["2026-02-13", 41628.32], ["2026-03-18", 69095.52], ["2026-03-31", 10805.34],
    ["2026-04-28", 16272.97], ["2026-05-19", 15647.10], ["2026-06-24", 17980.52],
    ["2026-07-07", 45542.75],
  ].map(([data_recebimento, valor_recebido]) => ({ data_recebimento, valor_recebido })),
});
const received120 = [...work120Receipts.values()].reduce((total, month) => total + month.incoming, 0);
assert.equal(received120, 216972.52);

console.log("Fontes reais do cash flow e fallback das faturas de material validados.");
