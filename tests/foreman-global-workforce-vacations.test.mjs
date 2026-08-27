import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const access = readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/encarregado_quadro_ferias_global.sql", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

test("encarregado mantém Mapa de Férias, mas perde o Quadro de Pessoal", () => {
  assert.match(access, /encarregado:[\s\S]*views:\s*\["action-plan", "planning", "documents", "rnc", "team", "settings"\]/i);
  assert.match(app, /effectiveRole\(\) === "encarregado"[\s\S]*return \["vacations", "medicine"\]/i);
  assert.match(app, /#edit-workforce"\)\.hidden = !canManageWorkforce\(\)/i);
  assert.match(app, /CONSULTA · MAPA DE FÉRIAS COMPLETO, SEM PERMISSÃO DE EDIÇÃO/i);
});

test("leitura global expõe apenas os dados operacionais necessários", () => {
  assert.match(migration, /security definer/i);
  assert.match(migration, /u\.funcao = 'encarregado'/i);
  assert.match(migration, /public\.quadro_pessoal_alocacao/i);
  assert.match(migration, /a\.tipo = 'ferias'/i);
  assert.match(migration, /c\.data_saida is null/i);
  assert.match(migration, /revoke all[\s\S]*from public, anon/i);
  assert.doesNotMatch(migration, /grant (select|insert|update|delete)[\s\S]*on (table )?public\.(obras|quadro_pessoal_alocacao|ausencias)/i);
});

test("frontend usa todas as obras e apresenta férias num mapa mensal", () => {
  assert.doesNotMatch(app, /rpc\/fn_quadro_ferias_encarregado_global/i);
  assert.match(app, /tipo=eq\.ferias/i);
  assert.match(app, /function renderVacationMap/i);
  assert.match(app, /data-vacation-month/i);
  assert.match(styles, /\.vacation-map-grid/i);
  assert.match(styles, /grid-template-columns:\s*230px repeat\(var\(--vacation-days\), 31px\)/i);
});

test("linhas vazias usam a lista global e não voltam ao portefólio restrito", () => {
  const workforceRows = app.match(/function workforceRows\(activeWorks, allocations\) \{[\s\S]*?\n\}/)?.[0] || "";
  assert.match(workforceRows, /availableWorkById = new Map\(activeWorks\.map/i);
  assert.match(workforceRows, /availableWorkById\.get\(workId\)/i);
  assert.match(workforceRows, /const realWorkIds = new Set\(activeWorks\.map/i);
});
