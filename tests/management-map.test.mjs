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
for (const category of ["materiais", "estaleiro", "mao_obra", "subempreitadas", "faturacao"]) assert.match(moduleSource, new RegExp(category));
assert.match(moduleSource, /rpc\/fn_mapa_gestao_obras/);
assert.match(moduleSource, /POR OBRA · TODAS AS CATEGORIAS/);
assert.match(moduleSource, /IMPORTAR EXCEL/);
assert.match(moduleSource, /rpc\/fn_importar_mapa_gestao/);

assert.match(sql, /create or replace function public\.fn_mapa_gestao_obras/i);
assert.match(sql, /public\.fn_e_admin\(\) or public\.fn_e_financeiro\(\)/i);
assert.match(sql, /to_regclass\('public\.lancamentos_materiais'\)/i);
for (const source of ["lancamentos_materiais", "despesas_estaleiro", "lancamentos_mao_obra", "pagamentos_subempreitada", "faturacao"]) assert.match(sql, new RegExp(source));
assert.match(sql, /f\.estado_pagamento = 'pago'/i);
assert.match(sql, /o\.empresa_id = v_atual\.empresa_id/i);
assert.match(sql, /fn_importar_mapa_gestao\(p_linhas jsonb,p_confirmar boolean/i);
assert.match(sql, /regexp_replace[\s\S]*?'79','85','127'/i);
assert.match(sql, /não aceita importação por este caminho — usar Saldo de Abertura/i);
assert.match(sql, /v_chaves_existentes[\s\S]*?array_agg[\s\S]*?from public\.fn_mapa_gestao_obras\(\)/i);
assert.match(sql, /v_chave=any\(v_chaves\) or v_chave=any\(v_chaves_existentes\)/i);
assert.match(sql, /valor_recebido/i);
assert.match(sql, /horas.*valor_hora/is);

console.log("Mapa de Gestão de Obras detalhado e respetivos filtros validados.");
