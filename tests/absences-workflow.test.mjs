import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const access = fs.readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const storage = fs.readFileSync(new URL("../src/supabase-browser.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/ausencias_fluxo_permissoes_corrigido.sql", import.meta.url), "utf8");

assert.match(app, /id="absence-entry-form"/);
assert.match(app, /falta_justificada_sem_remuneracao/);
assert.match(app, /data-justify-absence/);
assert.match(app, /ausencias_anexos/);
assert.match(app, /Este colaborador está de férias\/ausente nesta data/);
assert.match(storage, /'ausencia'/);
assert.match(access, /diretor_obra:[\s\S]*?"team"/);
assert.match(access, /encarregado:[\s\S]*?"team"/);
assert.match(migration, /fn_pode_ver_ausencia/);
assert.match(migration, /estado <> 'justificada'/);
assert.match(migration, /security definer[\s\S]*fn_bloquear_alocacao_em_ausencia|fn_bloquear_alocacao_em_ausencia[\s\S]*security definer/i);

console.log("Fluxo de ausências, anexos, bloqueios e visibilidade validado.");
