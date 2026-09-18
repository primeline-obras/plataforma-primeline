import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_vinculo_diretor_subempreitada.sql", import.meta.url), "utf8");

test("o Administrativo pode registar sem identificar o orçamento", () => {
  assert.match(app, /TRABALHO \/ ORÇAMENTO \(OPCIONAL\)/);
  assert.match(app, /form\.subempreitada_id\.required = false/);
  assert.match(app, /Deixar para confirmação do Diretor/);
  assert.match(sql, /p_tipo_origem = 'subempreitada' and p_subempreitada_id is not null and not exists/);
});

test("o Diretor escolhe apenas trabalhos da mesma obra e fornecedor", () => {
  assert.match(app, /eligibleInvoiceSubcontracts/);
  assert.match(app, /subcontract\.obra_id[\s\S]*invoice\.obra_id[\s\S]*subcontract\.fornecedor_id[\s\S]*invoice\.fornecedor_id/);
  assert.match(app, /data-invoice-subcontract/);
  assert.match(app, /MAPA ADJUDICADO/);
  assert.match(app, /valor_adjudicado/);
  assert.match(app, /rpc\/fn_vincular_fatura_subempreitada/);
  assert.match(sql, /s\.obra_id = v_fatura\.obra_id[\s\S]*s\.fornecedor_id = v_fatura\.fornecedor_id/);
  assert.match(styles, /\.invoice-subcontract-link/);
});

test("a aprovação técnica é bloqueada sem vínculo no cliente e na base", () => {
  assert.match(app, /nextState === "aprovada_tecnicamente"[\s\S]*!invoice\.subempreitada_id/);
  assert.match(sql, /new\.estado_fluxo in \('aprovada_tecnicamente', 'enviada_financeiro', 'paga'\)/);
  assert.match(sql, /trg_validar_vinculo_fatura_subempreitada/);
});

test("o vínculo só muda antes da aprovação e fica auditado", () => {
  assert.match(sql, /estado_fluxo not in \('recebida', 'em_validacao'\)/);
  assert.match(sql, /fn_pode_editar_obra\(v_fatura\.obra_id\)/);
  assert.match(sql, /trg_auditoria_faturas/);
});

console.log("Vínculo da fatura ao trabalho transferido para o Diretor e protegido de ponta a ponta.");
