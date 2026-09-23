import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/rh-cadastro.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/rh_cadastro_importacao.sql", import.meta.url), "utf8");

for (const field of ["codigo_rh", "seguranca_social_ok", "registo_trabalhador_ok", "seguro_ok", "epi_data", "medicina_data", "niss"]) {
  assert.match(app, new RegExp(field));
  assert.match(sql, new RegExp(field));
}
assert.match(sql, /insert into public\.epis/);
assert.match(sql, /insert into public\.medicina_trabalho/);
assert.match(sql, /public\.fn_criar_colaborador_com_alocacao/);
assert.match(app, /ALOCAÇÃO INICIAL/);

console.log("Dados RH e conformidade na admissão validados.");
