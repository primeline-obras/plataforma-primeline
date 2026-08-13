import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/novo_colaborador_rh_conformidade.sql", import.meta.url), "utf8");

for (const field of ["codigo_rh", "seguranca_social", "registo_trabalhador", "seguro", "epi_data", "medicina_data"]) {
  assert.match(app, new RegExp(`name="${field}"`));
  assert.match(app, new RegExp(`p_${field}`));
  assert.match(sql, new RegExp(`p_${field}`));
}
assert.match(sql, /insert into public\.epis/);
assert.match(sql, /insert into public\.medicina_trabalho/);
assert.match(sql, /v_resultado := public\.fn_criar_colaborador_com_alocacao/);
assert.match(app, /ALOCAÇÃO INICIAL OBRIGATÓRIA/);

console.log("Dados RH e conformidade na admissão validados.");
