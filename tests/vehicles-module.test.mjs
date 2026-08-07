import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { accessFor } from "../src/access-control.js";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const moduleSource = await readFile(new URL("../src/vehicles.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/bloco_06_viaturas.sql", import.meta.url), "utf8");

assert(accessFor({ role: "gerencia" }).views.includes("vehicles"));
assert(accessFor({ role: "administrativo" }).views.includes("vehicles"));
["financeiro", "diretor_obra", "adjunto", "preparador", "encarregado"].forEach(role => {
  assert(!accessFor({ role }).views.includes("vehicles"), `${role} não deve ver Viaturas`);
});

assert.match(app, /data-view="vehicles"/);
assert.match(app, /id="vehicles-view"/);
assert.doesNotMatch(app, /data-team-tab="vehicles"/);
assert.match(moduleSource, /viaturas_eventos\?select=\*/);
assert.match(moduleSource, /viaturas_sinistros\?select=\*/);
assert.match(moduleSource, /multas\?select=\*/);
assert.match(moduleSource, /data_proxima_revisao/);
assert.match(moduleSource, /data_inspecao_proxima/);
assert.match(moduleSource, /saveFiles\([^\n]+"colaborador", payload\.colaborador_id/);

for (const table of ["viaturas_eventos", "viaturas_sinistros", "viaturas_sinistros_anexos", "multas", "multas_anexos"]) {
  assert.match(migration, new RegExp(`create table if not exists public\\.${table}`));
}
assert.match(migration, /v\.seguro_data - 15 <= current_date/);
assert.match(migration, /'seguro_viatura'/);
assert.match(migration, /fn_executar_rotinas_diarias/);

console.log("Bloco 6 de Viaturas validado.");
