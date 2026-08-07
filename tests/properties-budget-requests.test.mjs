import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { accessFor } from "../src/access-control.js";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const properties = readFileSync(new URL("../src/properties.js", import.meta.url), "utf8");
const budgets = readFileSync(new URL("../src/budget-requests.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/bloco_13_imoveis_orcamentos.sql", import.meta.url), "utf8");

for (const role of ["gerencia", "administrativo"]) {
  const views = accessFor({ role }).views;
  assert(views.includes("properties"), `${role} deve ver Imóveis`);
  assert(views.includes("budget-requests"), `${role} deve ver Pedidos de Orçamento`);
}
for (const role of ["financeiro", "diretor_obra", "adjunto", "preparador", "encarregado"]) {
  const views = accessFor({ role }).views;
  assert(!views.includes("properties"), `${role} não deve ver Imóveis`);
  assert(!views.includes("budget-requests"), `${role} não deve ver Pedidos de Orçamento`);
}

assert.match(app, /data-view="properties"/);
assert.match(app, /data-view="budget-requests"/);
assert.match(properties, /NOVA REUNIÃO DE CONDOMÍNIO/);
assert.match(properties, /imoveis_reunioes_condominio\?select=/);
assert.match(budgets, /ENVIOS E RETIFICAÇÕES/);
assert.match(budgets, /pedidos_orcamento_versoes\?select=/);
assert.match(budgets, /situacao_atual/);
assert.match(sql, /cross join \(values \(15\), \(7\), \(3\)\)/i);
assert.match(sql, /'reuniao_condominio'[\s\S]*?\n\s*7,/i);
assert.match(sql, /fn_verificar_alertas_imoveis_orcamentos/i);
assert.match(sql, /v_imoveis_orcamentos := public\.fn_verificar_alertas_imoveis_orcamentos/i);

console.log("Bloco 13 de Imóveis e Pedidos de Orçamento validado.");
