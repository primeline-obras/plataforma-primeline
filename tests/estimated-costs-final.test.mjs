import assert from "node:assert/strict";
import fs from "node:fs";

const planning = fs.readFileSync(new URL("../src/planning.js", import.meta.url), "utf8");
const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const sql = fs.readFileSync(new URL("../supabase/correcoes_pos_auditoria_custos_faturas.sql", import.meta.url), "utf8");

for (const label of ["COMPOSIÇÃO AUDITÁVEL DO CUSTO", "CUSTO REAL", "CUSTOS ESTIMADOS", "ESTIMATIVA FINAL", "ESTADO"]) {
  assert.match(dashboard, new RegExp(label));
}
for (const state of ["orcamentado_nao_comprometido", "em_consulta", "adjudicado", "em_execucao", "concluido", "cancelado"]) {
  assert.match(sql, new RegExp(state));
}
assert.match(planning, /DETALHE ORÇAMENTO/);
assert.match(sql, /fn_confirmar_remocao_custo_estimado_subempreitada/i);
assert.match(sql, /fn_concluir_custos_pl_tarefa/i);
assert.match(sql, /greatest\(coalesce\(valor_adjudicado,0\)-pago_sub,0\)/i);
assert.doesNotMatch(planning, /name="valor_real"/i);
assert.doesNotMatch(planning, /fn_confirmar_compromisso_subempreitada/i);
assert.match(sql, /'recebida'[\s\S]*'em_validacao'[\s\S]*'aprovada_tecnicamente'[\s\S]*'enviada_financeiro'[\s\S]*'paga'/i);
assert.doesNotMatch(sql, /programada_pagamento/i);
assert.doesNotMatch(sql, /auto_medicao/i);

console.log("Especificação final de custos estimados validada.");
