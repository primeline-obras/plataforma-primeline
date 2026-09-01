import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(
  new URL("../supabase/faturas_semelhanca_global_empresa.sql", import.meta.url),
  "utf8",
);

assert.match(app, /async function findDuplicateInvoice/);
assert.match(app, /rpc\/fn_verificar_fatura_semelhante/);
assert.match(app, /p_fornecedor_id: supplierId/);
assert.match(app, /p_valor: Number\(valor\)/);
assert.doesNotMatch(app.slice(app.indexOf('supabase("rpc\/fn_verificar_fatura_semelhante"'), app.indexOf("if \(!response.ok\)", app.indexOf('supabase("rpc\/fn_verificar_fatura_semelhante"'))), /obra_id/);
assert.match(app, /exactDuplicate && !hasFullAccess\(\)/);
assert.match(app, /Isto vai criar uma fatura duplicada/);
assert.match(app, /AVISO DE POSSÍVEL DUPLICAÇÃO ENTRE OBRAS/);
assert.match(app, /confirmSimilarInvoice\(match, "aprovar esta fatura"\)/);
assert.match(app, /confirmSimilarInvoice\(match, "marcar esta fatura como paga"\)/);
assert.match(app, /platformConfirm/);
assert.doesNotMatch(app, /window\.confirm/);

const checkPosition = app.indexOf("await findDuplicateInvoice(payload)");
const uploadPosition = app.indexOf("await uploadInvoicePdf(selectedPdf, payload.obra_id)");
assert(checkPosition > 0 && checkPosition < uploadPosition, "a verificação deve acontecer antes do upload");

assert.match(sql, /o\.empresa_id = v_atual\.empresa_id/);
assert.match(sql, /f\.fornecedor_id = new\.fornecedor_id/);
assert.match(sql, /abs\(f\.valor - p_valor\) <= v_tolerancia/);
assert.doesNotMatch(sql, /f\.obra_id\s*=/);
assert.match(sql, /security definer/);
assert.match(sql, /raise exception/);

console.log("Bloqueio e confirmação de fatura duplicada validados.");
