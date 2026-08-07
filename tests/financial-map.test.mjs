import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const moduleSource = await readFile(new URL("../src/financial-map.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/mapa_financeiro.sql", import.meta.url), "utf8");

assert.match(app, /data-finance-tab="financial-map"/);
assert.match(app, /data-finance-panel="financial-map"/);
assert.match(app, /function canViewFinancialMap\(\)[\s\S]*?hasFullAccess\(\) \|\| isFinancial\(\)/);
assert.match(app, /financialMapTab\.hidden = !canViewFinancialMap\(\)/);

assert.match(moduleSource, /const MONTHS = \["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"\]/);
assert.match(moduleSource, /forecast\.entradas_reais[\s\S]*forecast\.saidas_reais_sem_iva/);
assert.match(moduleSource, /calculatedSource: hasReal \? "real" : "estimated"/);
assert.match(moduleSource, /valor_calculado_referencia: calculated/);
assert.match(moduleSource, /Remunerações e Encargos \(Sede\)/);
assert.match(moduleSource, /Peso dos Custos Fixos/);
assert.match(moduleSource, /Variação de tesouraria/);
assert.match(moduleSource, /row\.billing \/ totalBilling/);

assert.match(migration, /create table if not exists public\.mapa_financeiro_ajustes/);
assert.match(migration, /unique \(obra_id, ano, mes\)/);
assert.match(migration, /fn_e_admin\(\) or public\.fn_e_financeiro\(\)/);
assert.doesNotMatch(migration, /fn_e_administrativo\(\)/);
for (const category of ["remuneracoes_sede", "despesas_sede", "despesas_armazem"]) {
  assert.match(migration, new RegExp(`'${category}'`));
}

console.log("Mapa Financeiro anual validado.");
