import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const [directory, procurement, app, migration, css] = await Promise.all([
  readFile(new URL("../src/subcontractors.js", import.meta.url), "utf8"),
  readFile(new URL("../src/procurement.js", import.meta.url), "utf8"),
  readFile(new URL("../src/app.js", import.meta.url), "utf8"),
  readFile(new URL("../supabase/especialidades_subempreiteiros.sql", import.meta.url), "utf8"),
  readFile(new URL("../src/specialties.css", import.meta.url), "utf8"),
]);

assert.match(migration, /create table if not exists public\.fornecedores_especialidades/i);
assert.match(migration, /unique \(fornecedor_id, especialidade_id\)/i);
assert.match(migration, /'Revestimentos \/ Pintura', 'PINTURAS'/);
assert.match(migration, /'Revestimentos \/ Pintura', 'PAVIMENTOS E REVESTIMENTOS'/);
assert.match(migration, /'Serralharia \/ Inox', 'SOLUÇÕES EM INOX'/);
assert.match(migration, /'AQS', 'CANALIZAÇÃO E HIDRÁULICA'/);
assert.match(migration, /'Vala', 'MOVIMENTO DE TERRAS'/);
assert.match(migration, /fornecedores_especialidades_write/);

assert.match(directory, /data-supplier-specialty/);
assert.match(directory, /data-specialties-editor/);
assert.match(directory, /canManageSpecialties/);
assert.match(directory, /fornecedores_especialidades\?select=/);
assert.match(app, /canManageSpecialties: \(\) => hasFullAccess\(\) \|\| isAdministrative\(\)/);

assert.match(procurement, /especialidades_aliases\?select=/);
assert.match(procurement, /fornecedores_especialidades\?select=/);
assert.match(procurement, /★ ESPECIALISTA/);
assert.match(procurement, /Number\(b\.recommended\) - Number\(a\.recommended\)/);

assert.match(css, /supplier-specialty-badges/);
assert.match(css, /supplier-specialties-editor/);

console.log("Subcontractor specialties tests passed.");
