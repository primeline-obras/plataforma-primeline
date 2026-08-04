import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/modelo_nova_obra.sql", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

test("o formulário permite escolher uma obra-modelo e copiar o orçamento estrutural", () => {
  assert.match(app, /name="modelo_obra_id"/);
  assert.match(app, /name="copiar_orcamento"/);
  assert.match(app, /rpc\/fn_criar_obra_de_modelo/);
  assert.match(app, /p_copiar_orcamento:\s*workForm\.elements\.copiar_orcamento\.checked/);
});

test("a RPC é transacional, restrita à Gerência e não concede acesso anon", () => {
  assert.match(sql, /^begin;/m);
  assert.match(sql, /security definer/i);
  assert.match(sql, /if not public\.fn_e_admin\(\)/i);
  assert.match(sql, /revoke all on function[\s\S]*from public, anon;/i);
  assert.match(sql, /grant execute on function[\s\S]*to authenticated;/i);
  assert.match(sql, /^commit;/m);
});

test("o modelo copia fases e apenas campos descritivos dos itens", () => {
  assert.match(sql, /insert into public\.fases/);
  assert.match(sql, /insert into public\.itens_orcamento/);
  const whitelist = sql.match(/c\.column_name = any\(array\[([\s\S]*?)\]\)/)?.[1] || "";
  for (const field of ["codigo", "descricao", "designacao", "unidade", "categoria", "especialidade", "capitulo", "subcapitulo", "ordem"]) {
    assert.match(whitelist, new RegExp(`'${field}'`));
  }
  for (const field of ["quantidade", "preco", "custo", "valor", "venda_prevista"]) {
    assert.doesNotMatch(whitelist, new RegExp(`'${field}'`));
  }
});

test("não replica dados operacionais ou financeiros de outras tabelas", () => {
  for (const table of ["contratos", "investimentos", "planeamento_itens", "subempreitadas", "faturas", "pagamentos_subempreitada", "documentos_obra", "obra_responsaveis"]) {
    assert.doesNotMatch(sql, new RegExp(`insert\\s+into\\s+public\\.${table}`, "i"));
  }
});

test("os formulários longos mantêm uma barra de rolagem lateral visível", () => {
  const modalScrollRule = styles.match(/\.dialog-backdrop\s*>\s*\.work-dialog-card\s*\{([\s\S]*?)\}/)?.[1] || "";
  assert.match(modalScrollRule, /overflow-y:\s*scroll/);
  assert.match(modalScrollRule, /scrollbar-gutter:\s*stable/);
  assert.match(styles, /\.dialog-backdrop\s*>\s*\.work-dialog-card::\-webkit-scrollbar/);
});
