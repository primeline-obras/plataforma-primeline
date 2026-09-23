import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const rh = readFileSync(new URL("../src/rh-cadastro.js", import.meta.url), "utf8");
const { RH_FIELDS } = await import("../src/rh-cadastro.js");
const sql = readFileSync(new URL("../supabase/colaboradores_campos_completos.sql", import.meta.url), "utf8");

for (const field of ["nivel", "valor_hora", "nif", "email", "contacto", "morada"]) {
  assert.ok(RH_FIELDS.some(([key]) => key === field), `Falta o campo ${field}.`);
  assert.match(sql, new RegExp(`p_${field}`), `Falta persistir ${field} na função SQL.`);
}

assert.match(rh, /\['nome','funcao','data_admissao'\]\.includes\(k\)/);
assert.match(rh, /ALOCAÇÃO INICIAL/);
assert.ok(RH_FIELDS.some(([key]) => key === 'observacoes'));
assert.match(app, /rhCadastro\(\)\.open\(person\)/);
assert.match(sql, /p_valor_hora is not null and p_valor_hora < 0/);

console.log("Campos completos do colaborador validados.");
