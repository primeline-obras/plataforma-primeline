import assert from "node:assert/strict";
import fs from "node:fs";

const read = path => fs.readFileSync(new URL(path, import.meta.url), "utf8");
const app = read("../src/app.js");
const styles = read("../src/styles.css");
const migration = read("../supabase/faturas_guias_aviso_temporario.sql");

assert.match(app, /Esta fatura não tem guia de remessa anexada\. A aprovação é permitida temporariamente\./);
assert.match(app, /const approvingWithoutGuide =/);
assert.match(app, /Fatura aprovada sem guia de remessa/);
assert.match(app, /APROVADA SEM GUIA DE REMESSA/);
assert.doesNotMatch(app, /Anexe pelo menos uma guia antes de aprovar a fatura/);
assert.doesNotMatch(app, /\$\{hasGuide \? "" : "disabled"\}/);
assert.match(styles, /\.invoice-guide-warning/);
assert.match(styles, /\.invoice-guide-status/);

assert.match(migration, /add column if not exists aprovada_sem_guia boolean not null default false/i);
assert.match(migration, /v_bloquear_sem_guia constant boolean := false/i);
assert.match(migration, /if v_bloquear_sem_guia and p_decisao = 'aprovado'/i);
assert.match(migration, /aprovada_sem_guia = case/i);
assert.match(migration, /estado_aprovacao = 'aprovado'/i);

console.log("Aprovação temporária sem guia e identificação histórica validadas.");
