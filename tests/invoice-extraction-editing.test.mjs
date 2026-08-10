import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

test("todos os campos extraídos permanecem editáveis, incluindo a obra", () => {
  const review = app.match(/function enableExtractedInvoiceReview\(\)[\s\S]*?\n}/)?.[0] || "";
  for (const field of ["obra_id", "fornecedor_id", "numero_doc", "data_fatura", "valor", "condicao_pagamento"]) {
    assert.match(review, new RegExp(`form\\.${field}`), `${field} deve fazer parte da revisão editável`);
  }
  assert.match(review, /#material-items-list \[data-item-field\]/);
  assert.match(review, /field\.disabled\s*=\s*false/);
  assert.match(review, /field\.readOnly\s*=\s*false/);
  assert.match(app, /async function extractPdfData[\s\S]*enableExtractedInvoiceReview\(\)/);
});

test("a obra corrigida é usada no upload e na gravação", () => {
  assert.match(app, /const payload\s*=\s*Object\.fromEntries\(new FormData\(form\)\)/);
  assert.match(app, /uploadInvoicePdf\(selectedPdf, payload\.obra_id\)/);
  assert.match(app, /form\.obra_id\.addEventListener\("change", renderSubcontracts\)/);
  assert.doesNotMatch(app, /form\.obra_id\.(?:disabled|readOnly)\s*=\s*true/);
});
