import assert from "node:assert/strict";
import fs from "node:fs";

const planning = fs.readFileSync(new URL("../src/planning.js", import.meta.url), "utf8");
const sql = fs.readFileSync(new URL("../supabase/custos_estimados_especificacao_final.sql", import.meta.url), "utf8");

for (const label of ["CUSTOS ESTIMADOS", "MATERIAIS", "MÃO DE OBRA", "SUBEMPREITADAS", "ESTADO CUSTO"]) {
  assert.match(planning, new RegExp(label));
}
for (const state of ["orcamentado", "em_consulta", "adjudicado", "em_execucao", "concluido", "cancelado"]) {
  assert.match(sql, new RegExp(`'${state}'`));
}
assert.match(planning, /DETALHE ORÇAMENTO/);
assert.match(sql, /fn_confirmar_compromisso_subempreitada/i);
assert.match(sql, /greatest\(v_orc_material-v_real_material,0\)/i);
assert.match(sql, /greatest\(v_orc_mao_obra-v_real_mao_obra,0\)/i);
assert.match(sql, /greatest\(coalesce\(v_linha\.valor_adjudicado,0\)-v_linha\.faturado,0\)/i);
assert.doesNotMatch(planning, /name="valor_real"/i);
assert.doesNotMatch(sql, /add column if not exists valor_real/i);
assert.match(sql, /'recebida'[\s\S]*'em_validacao'[\s\S]*'aprovada_tecnicamente'[\s\S]*'enviada_financeiro'[\s\S]*'paga'/i);
assert.doesNotMatch(sql, /programada_pagamento/i);
assert.doesNotMatch(sql, /auto_medicao/i);

console.log("Especificação final de custos estimados validada.");
