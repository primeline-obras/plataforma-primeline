import assert from "node:assert/strict";
import fs from "node:fs";

const sql = fs.readFileSync(new URL("../supabase/custos_estimados_modelo_final.sql", import.meta.url), "utf8");
const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

assert.match(sql, /create table if not exists public\.planeamento_custos_componentes/);
assert.match(sql, /tipo in \('PL', 'subempreitada'\)/);
assert.match(sql, /item_orcamento_id uuid/);
for (const state of ["orcamentado_nao_comprometido", "em_consulta", "adjudicado", "em_execucao", "concluido", "cancelado"]) assert.match(sql, new RegExp(state));
assert.match(sql, /fn_e_diretor_obra/);
assert.match(sql, /fn_confirmar_remocao_custo_estimado_subempreitada/);
assert.match(sql, /greatest\(coalesce\(valor_adjudicado,0\)-pago_sub,0\)/);
assert.match(sql, /fn_concluir_custo_pl/);
assert.match(sql, /coalesce\(p_valor_real,valor_orcamentado\)/);
for (const state of ["recebida", "em_validacao", "aprovada_tecnicamente", "enviada_financeiro", "paga"]) assert.match(sql, new RegExp(state));
assert.match(sql, /percentagem_faturado/);
assert.match(sql, /percentagem_pago/);

assert.match(dashboard, /CUSTO REAL/);
assert.match(dashboard, /CUSTOS ESTIMADOS/);
assert.match(dashboard, /ESTIMATIVA FINAL/);
assert.match(dashboard, /data-confirm-sub-cost/);
assert.match(dashboard, /data-complete-pl-cost/);
assert.match(dashboard, /meetingReturnView !== "rsp"/);
assert.match(dashboard, /COMPOSIÇÃO AUDITÁVEL DO CUSTO · SÓ LEITURA/);
assert.doesNotMatch(dashboard, /Custos fixos · 8,5%/);
assert.match(app, /Valor adjudicado — confirmar remoção dos Custos Estimados\?/);

console.log("Modelo final de custos estimados validado.");
