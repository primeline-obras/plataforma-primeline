import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const frontend = readFileSync(new URL("../src/procurement.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/mapa_comparativo_entrada.sql", import.meta.url), "utf8");

for (const table of [
  "consultas_subempreitada",
  "consultas_subempreitada_itens",
  "consultas_subempreitada_candidatos",
  "consultas_subempreitada_candidatos_itens",
]) {
  assert.match(frontend, new RegExp(table), `O frontend deve usar ${table}.`);
}

assert.match(frontend, /fn_adjudicar_candidato_subempreitada/, "A adjudicação deve reutilizar a função existente.");
assert.match(frontend, /fn_guardar_precos_candidato_subempreitada/, "Os preços devem ser gravados pela função transacional.");
assert.match(migration, /fn_pode_editar_obra\(p_obra_id\)/, "Criar uma consulta deve validar a permissão da obra.");
assert.match(migration, /fn_pode_editar_obra\(v_obra_id\)/, "Guardar preços deve validar a permissão da obra.");
assert.match(migration, /item\.quantidade/, "O total deve usar a quantidade do item do orçamento.");
assert.doesNotMatch(migration, /create\s+table\s+.*consultas_subempreitada/is, "A migração não deve duplicar as tabelas já existentes.");

console.log("Fluxo de entrada e comparação de subempreitadas validado.");
