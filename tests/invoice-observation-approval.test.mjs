import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_observacao_aprovacao.sql", import.meta.url), "utf8");

assert.match(app, /textarea name="observacao"/);
assert.match(app, /data-approval-observation/);
assert.match(app, /data-detail-approval-observation/);
assert.match(app, /p_observacao: payload\.observacao/);
assert.match(app, /p_observacao: approvalObservation/);
assert.match(app, /APROVADA POR/);
assert.match(app, /aprovado_por_nome/);
assert.match(app, /traceMoment\(approvalDate\)/);
assert.match(css, /invoice-approval-observation/);
assert.match(css, /finance-approval/);

assert.match(sql, /add column if not exists observacao text/i);
assert.match(sql, /fn_decidir_fatura\(uuid, text, text\)/i);
assert.match(sql, /observacao = case/i);
assert.match(sql, /fn_editar_fatura_pendente[\s\S]*p_observacao text/i);

console.log("Observação da fatura e identificação da aprovação no pagamento validadas.");
