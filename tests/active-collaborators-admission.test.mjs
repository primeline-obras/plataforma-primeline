import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/alerta_primeira_consulta_medicina.sql", import.meta.url), "utf8");

assert.match(app, /colaboradores\?select=[^"\n]+data_admissao[^"\n]+data_saida=is\.null/);
assert.match(app, /const activeMedicine = teamData\.medicine\.filter\(item => personById\.has\(item\.colaborador_id\)\)/);
assert.match(app, /data-team-vacation-person/);
assert.match(migration, /c\.data_saida is null/);
assert.match(migration, /c\.data_admissao \+ 30 <= current_date/);
assert.match(migration, /not exists \(\s*select 1\s*from public\.medicina_trabalho/s);
assert.match(migration, /primeline-alertar-primeira-consulta-diario/);
assert.match(migration, /primeline-congelar-baselines-diario/);
assert.match(migration, /pg_cron não está ativo/);

console.log("Active collaborator and admission alert checks passed.");
