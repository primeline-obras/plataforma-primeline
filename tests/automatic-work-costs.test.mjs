import assert from "node:assert/strict";
import fs from "node:fs";

const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const sql = fs.readFileSync(new URL("../supabase/custos_obra_automaticos.sql", import.meta.url), "utf8");

assert.match(sql, /create table if not exists public\.ajustes_custo_obra/);
assert.match(sql, /motivo text not null/);
assert.match(sql, /criado_por uuid not null references public\.utilizadores/);
assert.match(sql, /fn_resumo_custos_obra\(p_obra_id uuid\)/);
for (const source of ["lancamentos_materiais", "lancamentos_mao_obra", "despesas_estaleiro", "pagamentos_subempreitada"]) {
  assert.match(sql, new RegExp(source));
}
assert.match(sql, /valor_adjudicado/);
assert.match(sql, /estado_aprovacao_cliente/);
assert.match(sql, /consultas_subempreitada_itens/);
assert.match(sql, /\*0\.085/);
assert.match(sql, /v_labor\/v_elapsed/);
assert.match(sql, /lancamentos_sem_apropriacao/);
assert.match(sql, /fn_registar_log_auditoria/);

assert.match(dashboard, /rpc\/fn_resumo_custos_obra/);
assert.match(dashboard, /COMPOSIÇÃO AUDITÁVEL DO CUSTO/);
assert.match(dashboard, /data-cost-adjustment/);
assert.doesNotMatch(dashboard, /id="staff-vehicle-cost"/);
assert.match(dashboard, /Custos fixos · 8,5%/);

console.log("Custos automáticos, apropriação e ajustes auditáveis validados.");
