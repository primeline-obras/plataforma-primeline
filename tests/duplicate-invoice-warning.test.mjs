import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(
  new URL("../supabase/bloco_08_faturas_duplicadas.sql", import.meta.url),
  "utf8",
);

assert.match(app, /async function findDuplicateInvoice/);
assert.match(app, /fornecedor_id=eq\.\$\{encodeURIComponent\(supplierId\)\}/);
assert.match(app, /numero_doc=eq\.\$\{encodeURIComponent\(normalizedNumber\)\}/);
assert.match(app, /duplicateInvoice && !hasFullAccess\(\)/);
assert.match(app, /Isto vai criar uma fatura duplicada/);
assert.match(app, /window\.confirm/);

const checkPosition = app.indexOf("await findDuplicateInvoice(payload)");
const uploadPosition = app.indexOf("await uploadInvoicePdf(selectedPdf, payload.obra_id)");
assert(checkPosition > 0 && checkPosition < uploadPosition, "a verificação deve acontecer antes do upload");

assert.match(sql, /if public\.fn_e_admin\(\) then/);
assert.match(sql, /f\.fornecedor_id = new\.fornecedor_id/);
assert.match(sql, /f\.numero_doc = new\.numero_doc/);
assert.match(sql, /raise exception/);

console.log("Bloqueio e confirmação de fatura duplicada validados.");
