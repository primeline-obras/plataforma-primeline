import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { accessFor } from "../src/access-control.js";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(
  new URL("../supabase/bloco_10_cruzamento_rh_obra_financeiro.sql", import.meta.url),
  "utf8",
);

const foreman = accessFor({ role: "encarregado" });
for (const view of ["action-plan", "planning", "documents", "rnc", "team", "workforce", "settings"]) {
  assert.ok(foreman.views.includes(view), `O encarregado deve manter acesso a ${view}.`);
}
for (const view of ["finance", "invoices", "works", "overview"]) {
  assert.ok(!foreman.views.includes(view), `O encarregado não deve receber acesso a ${view}.`);
}

assert.match(app, /data-finance-tab="tracking"/);
assert.match(app, /rpc\/fn_listar_rastreio_faturas/);
assert.match(app, /invoiceJourneyState/);
assert.match(app, /effectiveRole\(\) === "encarregado"\) return \["absences", "medicine"\]/);
assert.match(app, /allowedViews\(\)\.has\("team"\)/);
assert.match(app, /rpc\/fn_quadro_ferias_encarregado_global/);
assert.match(app, /teamData\.boardWorks = globalPayload\.obras/);
assert.match(app, /#workforce-movements/);

assert.match(sql, /add column if not exists criado_por uuid/);
assert.match(sql, /new\.aprovado_por := public\.fn_utilizador_atual_id\(\)/);
assert.match(sql, /new\.pago_por := public\.fn_utilizador_atual_id\(\)/);
assert.match(sql, /fn_listar_rastreio_faturas/);
assert.match(sql, /q\.data <= current_date/);
assert.match(sql, /order by\s+q\.data desc nulls last,\s+q\.criado_em desc nulls last,\s+q\.id desc/s);
assert.match(sql, /pl_medicina_encarregado_atual_select/);
assert.match(sql, /pl_ausencias_ferias_encarregado_atual_select/);
assert.match(sql, /tipo = 'ferias'/);
assert.doesNotMatch(sql, /insert into public\.alertas/i);

console.log("Cruzamento RH, Obra e Financeiro validado.");
