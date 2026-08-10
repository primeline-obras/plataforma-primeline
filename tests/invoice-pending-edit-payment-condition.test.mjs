import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_edicao_pendente_condicao_pagamento.sql", import.meta.url), "utf8");

test("fatura pendente pode ser aberta e corrigida no formulário", () => {
  assert.match(app, /data-edit-invoice=/);
  assert.match(app, /function canEditPendingInvoice\(invoice\)/);
  assert.match(app, /invoice\.estado_aprovacao !== "pendente"/);
  assert.match(app, /isAdministrative\(\)[\s\S]*invoice\.criado_por[\s\S]*accessContext\.profile\?\.id/);
  assert.match(app, /form\.obra_id\.value = invoice\.obra_id/);
  assert.match(app, /rpc\/fn_editar_fatura_pendente/);
  assert.match(app, /p_itens: materialItems\.map\(materialItemDatabasePayload\)/);
  assert.match(app, /CANCELAR EDIÇÃO/);
  assert.match(styles, /\.invoice-edit-action/);
});

test("a quarta condição revela uma única data manual", () => {
  assert.match(app, /option value="outra_data">Outra data/);
  assert.match(app, /id="custom-payment-date-field" hidden/);
  assert.match(app, /form\.data_vencimento\.required = isCustom/);
  assert.match(app, /payload\.condicao_pagamento === "outra_data" \? payload\.data_vencimento \|\| null : null/);
  assert.match(app, /\["outra_data", "OUTRA DATA"\]/);
});

test("RPC protege estado, autoria e campos relacionados", () => {
  assert.match(sql, /estado_aprovacao <> 'pendente'/);
  assert.match(sql, /public\.fn_e_admin\(\)/);
  assert.match(sql, /public\.fn_e_administrativo\(\)/);
  assert.match(sql, /v_fatura\.criado_por = v_utilizador_id/);
  assert.match(sql, /p_condicao_pagamento not in \('imediato', '15_dias', '30_dias', 'outra_data'\)/);
  assert.match(sql, /delete from public\.faturas_itens where fatura_id = p_fatura_id/);
  assert.match(sql, /security definer/);
  assert.doesNotMatch(sql, /grant update on (?:table )?public\.faturas to authenticated/i);
});

console.log("Edição de faturas pendentes e condição Outra data validadas.");
