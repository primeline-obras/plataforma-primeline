import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL(path, import.meta.url), "utf8");
const sql = read("../supabase/gestao_plataforma_mapa_orcamento_fases.sql");
const access = read("../src/access-control.js");
const settings = read("../src/settings.js");
const importer = read("../src/xlsx-operational-import.js");
const dashboard = read("../src/production-dashboard.js");

assert.match(access, /gestao_plataforma/);
assert.match(settings, /Gestão da Plataforma/);
assert.match(sql, /funcao='gestao_plataforma'/);
assert.match(sql, /primeline\.gestao@gmail\.com/);
assert.match(sql, /create table if not exists public\.orcamento_fases/i);
for (const field of ["venda_prevista", "custo_total_estimado", "margem_prevista", "deslocacoes", "mao_obra", "maquinas", "materiais", "mao_obra_sub", "subempreitada"]) assert.match(sql, new RegExp(field));
assert.match(sql, /fn_importar_orcamento_fases/);
assert.match(sql, /fn_concluir_custo_pl_fase/);
assert.match(importer, /0_Orçamento/);
assert.match(importer, /parsePhaseBudget/);
assert.match(dashboard, /IMPORTAR 0_ORÇAMENTO/);
assert.match(dashboard, /data-complete-pl-phase/);

console.log("Gestão da Plataforma e orçamento PL por fase validados.");
