import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = path => readFile(new URL(path, import.meta.url), "utf8");
const [documents, properties, budgets, companyDocuments, app, storage, sql] = await Promise.all([
  read("../src/documents.js"),
  read("../src/properties.js"),
  read("../src/budget-requests.js"),
  read("../src/company-documents.js"),
  read("../src/app.js"),
  read("../src/supabase-browser.js"),
  read("../supabase/eliminacoes_restritas_documentos_imoveis_orcamentos.sql"),
]);

test("documentos gerais podem ser apagados por utilizadores autorizados e removidos do Storage", () => {
  assert.match(documents, /data-document-delete/);
  assert.match(documents, /rpc\/fn_apagar_documento_obra/);
  assert.match(documents, /deleteWorkDocument\(path\)/);
  assert.match(storage, /export async function deleteWorkDocument/);
  assert.match(sql, /fn_pode_editar_documentos_obra\(v_obra_id\)/);
  assert.match(sql, /documentos_obra_storage_delete/);
});

test("documentos da empresa, colaboradores e viaturas também têm caminho de eliminação", () => {
  assert.match(companyDocuments, /data-company-document-delete/);
  assert.match(companyDocuments, /rpc\/fn_apagar_documento_entidade/);
  assert.match(app, /data-entity-document-delete/);
  assert.match(app, /rpc\/fn_apagar_documento_entidade/);
  assert.match(sql, /documentos_empresa_storage_delete/);
  assert.match(sql, /trg_auditoria_documentos/);
});

test("imóveis e reuniões têm eliminação restrita e auditada", () => {
  assert.match(properties, /data-delete-property=/);
  assert.match(properties, /data-delete-property-meeting=/);
  assert.match(properties, /rpc\/fn_apagar_imovel_empresa/);
  assert.match(properties, /rpc\/fn_apagar_reuniao_condominio/);
  assert.match(sql, /if not public\.fn_e_administrativo\(\)/);
  assert.match(sql, /trg_auditoria_imoveis_empresa/);
});

test("pedido é cancelado logicamente e apenas a versão pode ser apagada", () => {
  assert.match(budgets, /data-cancel-budget-request/);
  assert.match(budgets, /rpc\/fn_cancelar_pedido_orcamento/);
  assert.match(budgets, /data-delete-budget-version/);
  assert.match(sql, /update public\.pedidos_orcamento[\s\S]*set estado = 'cancelado'/i);
  assert.doesNotMatch(sql, /delete from public\.pedidos_orcamento\s/i);
  assert.match(sql, /delete from public\.pedidos_orcamento_versoes/);
});

test("todas as eliminações materiais ficam no log de auditoria", () => {
  for (const table of ["documentos_obra", "imoveis_empresa", "imoveis_reunioes_condominio", "pedidos_orcamento", "pedidos_orcamento_versoes"]) {
    assert.match(sql, new RegExp(`'${table}'`));
  }
  assert.match(sql, /after insert or update or delete/);
});
