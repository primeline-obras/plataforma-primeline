import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { accessFor } from "../src/access-control.js";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/encarregado_quadro_ferias_global.sql", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

test("encarregado mantém férias, ponto e o Quadro operacional restaurado", () => {
  // Decisão 96ad5f8: quadro_pessoal_operacional_relatorio.sql restaura este acesso.
  for (const role of ["encarregado", "diretor_obra"]) {
    assert.ok(accessFor({ role }).views.includes("workforce"));
  }
  assert.match(app, /effectiveRole\(\) === "encarregado"[\s\S]*return \["vacations", "attendance", "medicine"\]/i);
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
