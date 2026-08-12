import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { accessFor } from "../src/access-control.js";

const access = accessFor({ role: "financeiro", isAdmin: false });
assert(!access.views.includes("planning"), "Financeiro não deve ver Planeamento");
assert(!access.views.includes("subcontractors"), "Financeiro não deve ver Subempreiteiros/Subempreitadas");

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
assert.match(app, /if \(financialReadOnly\) selectedWorkTab = "summary"/);
assert.match(app, /financialReadOnly \? "" : `<button data-work-tab="subcontracts"/);

const migration = await readFile(new URL("../supabase/remover_acesso_financeiro_operacional.sql", import.meta.url), "utf8");
for (const table of ["subempreitadas", "alteracoes_tee", "planeamento_itens", "planeamento_itens_dependencias"]) {
  assert(migration.includes(`'${table}'`), `A migração deve proteger ${table}`);
}
assert.match(migration, /as restrictive for select to authenticated/i);
assert.match(migration, /not public\.fn_e_financeiro\(\) or public\.fn_e_admin\(\)/i);

console.log("Acesso operacional do Financeiro removido no frontend e na RLS.");
