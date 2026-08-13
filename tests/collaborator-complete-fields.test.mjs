import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/colaboradores_campos_completos.sql", import.meta.url), "utf8");

for (const field of ["nivel", "valor_hora", "nif", "email", "contacto", "morada"]) {
  assert.match(app, new RegExp(`name="${field}"`), `Falta o campo ${field} no formulário.`);
  assert.match(app, new RegExp(`p_${field}`), `Falta enviar ${field} para a função atómica.`);
  assert.match(sql, new RegExp(`p_${field}`), `Falta persistir ${field} na função SQL.`);
}

assert.match(app, /name="nome"[^>]*required/);
assert.match(app, /name="funcao"[^>]*required/);
assert.match(app, /name="data_admissao"[^>]*required/);
assert.match(app, /ALOCAÇÃO INICIAL OBRIGATÓRIA/);
assert.doesNotMatch(app.match(/function collaboratorFormFields[\s\S]*?function openCollaboratorDialog/)?.[0] || "", /name="observacoes"/);
assert.match(sql, /p_valor_hora is not null and p_valor_hora < 0/);

console.log("Campos completos do colaborador validados.");
