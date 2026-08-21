import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const procurement = await readFile(new URL("../src/procurement.js", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/autos_faturacao_aprovacao_pendente.sql", import.meta.url), "utf8");
const linesSql = await readFile(new URL("../supabase/faturacao_autos_linhas_discriminadas.sql", import.meta.url), "utf8");

test("Auto de Medição cria rascunho pendente em vez de emitir a fatura", () => {
  assert.match(app, /PREPARAR RASCUNHO DE FATURA/);
  assert.match(app, /estado: "rascunho"/);
  assert.match(app, /Rascunho de fatura criado e enviado para aprovação do Diretor/);
  assert.doesNotMatch(app, /Fatura emitida e associada aos autos/);
});

test("o rascunho discrimina cada Auto e calcula o total sem permitir edição", () => {
  assert.match(app, /billingAutoReference/);
  assert.match(app, /Adicional\/TEE/);
  assert.match(app, /VALOR DA FATURA — SOMA AUTOMÁTICA/);
  assert.match(app, /name="valor"[^>]*readonly/);
  assert.match(app, /const billingTotal = lineItems\.reduce/);
  assert.match(app, /valor: billingTotal/);
  assert.doesNotMatch(app, /valor: Number\(data\.get\("valor"\)\)/);
  assert.match(app, /tipo_auto: item\.tipo \|\| "contratual"/);
  assert.match(app, /referencia_auto: billingAutoReference\(item\)/);
  assert.match(app, /valor_linha: Number\(item\.valor_a_faturar/);
  assert.match(linesSql, /add column if not exists tipo_auto text/);
  assert.match(linesSql, /add column if not exists referencia_auto text/);
  assert.match(linesSql, /add column if not exists valor_linha numeric\(14,2\)/);
  assert.match(linesSql, /from public\.autos_medicao auto/);
});

test("Diretor decide e apenas Financeiro marca a fatura como paga", () => {
  assert.match(app, /data-decide-billing="aprovado"/);
  assert.match(app, /rpc\/fn_decidir_faturacao_auto/);
  assert.match(app, /canPayInvoices\(\) && billingApproved && !paid/);
  assert.match(app, /rpc\/fn_marcar_faturacao_auto_paga/);
  assert.match(sql, /public\.fn_pode_editar_obra\(v_faturacao\.obra_id\)/);
  assert.match(sql, /public\.fn_e_financeiro\(\)/);
  assert.match(sql, /estado_aprovacao <> 'aprovado'/);
  assert.match(sql, /revoke update on table public\.faturacao from authenticated/);
});

test("Subempreitadas tolera schema de classificação em falta enquanto a migração não é aplicada", () => {
  assert.match(procurement, /optionalClassification/);
  assert.match(procurement, /schema cache\|especialidades_aliases\|fornecedores_especialidades\|aplicavel_subempreiteiro/);
  assert.match(procurement, /optionalClassification\("especialidades_aliases\?select=\*"\)/);
});
