import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_fluxo_validacao_consistente.sql", import.meta.url), "utf8");

test("a decisão negativa usa apenas a devolução formal com nota", () => {
  assert.doesNotMatch(app, /data-action="recusado"/);
  assert.doesNotMatch(app, /data-detail-decision="recusado"/);
  assert.match(app, /DEVOLVER AO ADMINISTRATIVO/);
  assert.match(app, /rpc\/fn_devolver_fatura_administrativo/);
  assert.match(app, /NOTA OBRIGATÓRIA/);
});

test("guias selecionadas são gravadas antes da aprovação técnica", () => {
  const start = app.indexOf("if (advanceButton)");
  const end = app.indexOf("const detailButton", start);
  const flow = app.slice(start, end);
  assert.match(flow, /selectedGuides/);
  assert.match(flow, /uploadSelectedInvoiceGuides/);
  assert.match(flow, /invoiceGuides\.push/);
  assert.match(flow, /guideInput\.value = ""/);
  assert.ok(flow.indexOf("uploadSelectedInvoiceGuides") < flow.indexOf("advanceInvoiceFlow"));
  assert.match(app, /faturas_guias\?select=\*/);
});

test("aprovação e pagamento mantêm a verificação do limite contratual", () => {
  assert.match(app, /confirmSubcontractContractLimit\(invoice, nextState\)/);
  assert.match(app, /confirmSubcontractContractLimit\(invoice, "paga"\)/);
});

test("observação e estado sem guia são gravados atomicamente com a aprovação", () => {
  assert.match(app, /p_observacao: observation \|\| null/);
  assert.match(sql, /p_observacao text default null/);
  assert.match(sql, /observacao = case/);
  assert.match(sql, /aprovada_sem_guia = case/);
  assert.match(sql, /from public\.faturas_guias/);
});

console.log("Prontidão do fluxo de faturas validada.");
