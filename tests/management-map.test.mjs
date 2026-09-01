import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const access = readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const moduleSource = readFileSync(new URL("../src/management-map.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/mapa_gestao_obras.sql", import.meta.url), "utf8");
const excelMigration = readFileSync(new URL("../supabase/mapa_gestao_obras_colunas_excel.sql", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

assert.match(app, /data-view="management-map"/);
assert.match(app, /id="management-map-view"/);
assert.doesNotMatch(app, /data-finance-tab="management-map"/);
assert.match(app, /createManagementMapModule/);
assert.match(access, /gestao_plataforma:[\s\S]*"management-map"/);
assert.match(access, /administrativo:[\s\S]*"management-map"/);
assert.match(access, /diretor_obra:[\s\S]*"management-map"/);
assert.doesNotMatch(access.match(/financeiro:\s*\{[\s\S]*?\n\s*\},/)[0], /management-map/);
for (const filter of ["obra_id", "categoria", "data_inicio", "data_fim", "entidade"]) assert.match(moduleSource, new RegExp(filter));
for (const category of ["materiais", "estaleiro", "mao_obra", "subempreitadas"]) assert.match(moduleSource, new RegExp(category));
assert.match(moduleSource, /rpc\/fn_mapa_gestao_obras/);
assert.match(moduleSource, /gestao_obras_lancamentos/);
assert.match(moduleSource, /fn_guardar_lancamento_gestao_obras/);
assert.match(moduleSource, /fn_apagar_lancamento_gestao_obras/);
assert.match(moduleSource, /VALOR TOTAL/);
for (const field of ["unidade_medida", "quantidade", "valor_unitario", "data_pagamento"]) {
  assert.match(moduleSource, new RegExp(field));
  assert.match(excelMigration, new RegExp(field));
}
for (const heading of ["UN. MEDIDA", "QUANTIDADE", "VALOR UNITÁRIO", "DATA DE PAGAMENTO"]) assert.match(moduleSource, new RegExp(heading));
assert.match(moduleSource, /VALOR \(TOTAL\)/);
assert.match(styles, /\.management-map-scroll thead \{ position:sticky; top:0; z-index:4; \}/);
assert.match(styles, /\.management-wrap \{[^}]*white-space:normal;[^}]*overflow-wrap:anywhere;/);
assert.match(moduleSource, /management-wrap management-entity/);
assert.match(moduleSource, /management-wrap management-description/);
assert.match(excelMigration, /drop function if exists public\.fn_guardar_lancamento_gestao_obras\(uuid,uuid,text,date,text,text,text,numeric\)/i);

assert.match(sql, /create or replace function public\.fn_mapa_gestao_obras/i);
assert.match(sql, /public\.fn_e_admin\(\) or public\.fn_e_financeiro\(\)/i);
assert.match(sql, /to_regclass\('public\.lancamentos_materiais'\)/i);
for (const source of ["lancamentos_materiais", "despesas_estaleiro", "lancamentos_mao_obra", "pagamentos_subempreitada"]) assert.match(sql, new RegExp(source));
assert.match(sql, /f\.estado_pagamento = 'pago'/i);
assert.match(sql, /o\.empresa_id = v_atual\.empresa_id/i);

console.log("Mapa de Gestão de Obras detalhado e respetivos filtros validados.");
