import assert from "node:assert/strict";
import fs from "node:fs";
import { accessFor } from "../src/access-control.js";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const moduleSource = fs.readFileSync(new URL("../src/projects.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/projetos_agrupador_obras.sql", import.meta.url), "utf8");

for (const role of ["gerencia", "administrativo", "financeiro", "diretor_obra", "adjunto", "preparador"]) {
  assert.equal(accessFor({ role }).views.includes("projects"), true, `${role} deve poder consultar projetos`);
}
assert.equal(accessFor({ role: "encarregado" }).views.includes("projects"), false);

assert.match(app, /data-view="projects"/);
assert.match(app, /id="projects-view"/);
assert.match(app, /name="projeto_id"/);
assert.match(app, /projeto_id: fields\.projeto_id \|\| null/);
assert.match(moduleSource, /work\.projeto_id === selectedId/);
assert.match(moduleSource, /data-project-work/);
assert.match(moduleSource, /VENDA ATUAL/);
assert.match(moduleSource, /INVESTIMENTO PRÓPRIO/);
assert.match(migration, /create table if not exists public\.projetos/);
assert.match(migration, /add column if not exists projeto_id uuid references public\.projetos/);
assert.match(migration, /Av\. Bombeiros Voluntários/);
assert.doesNotMatch(migration, /insert into public\.obras/);

console.log("Projetos agrupam etapas sem criar ou misturar obras automaticamente.");
