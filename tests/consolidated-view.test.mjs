import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const access = fs.readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const module = fs.readFileSync(new URL("../src/consolidated-view.js", import.meta.url), "utf8");
const sql = fs.readFileSync(new URL("../supabase/visao_consolidada.sql", import.meta.url), "utf8");

assert.match(app, /data-view="consolidated"/);
assert.match(app, /createConsolidatedView/);
assert.match(access, /views: \[\.\.\.FULL_VIEWS, "consolidated"(?:, "management-map")?\]/);
assert.doesNotMatch(access.match(/administrativo:\s*\{[\s\S]*?\n\s*\},/)[0], /consolidated/);
assert.match(module, /rpc\/fn_pode_ver_visao_consolidada/);
assert.match(module, /previsao_financeira_mensal\?select=/);
assert.match(module, /alteracoes_tee\?select=/);
assert.match(module, /seguranca_incidentes\?select=/);
assert.match(sql, /select public\.fn_e_admin\(\)/);
assert.match(sql, /revoke all[\s\S]*from anon/);

console.log("Visão Consolidada protegida e ligada às fontes globais.");
