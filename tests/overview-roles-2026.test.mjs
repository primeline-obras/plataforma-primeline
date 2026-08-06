import assert from "node:assert/strict";
import fs from "node:fs";
import { planningBaselineDelays, upcomingDirectDebitRows } from "../src/production-dashboard.js";

const source = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const planning = fs.readFileSync(new URL("../src/planning.js", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/visao_geral_papeis_2026.sql", import.meta.url), "utf8");

const debits = [
  { id: "monthly", ativo: true, recorrencia: "mensal", dia_mes: 10, data_inicio: "2026-01-10", valor_previsto: 100 },
  { id: "once", ativo: true, recorrencia: null, data_inicio: "2026-08-12", valor_previsto: 250 },
];
assert.deepEqual(upcomingDirectDebitRows(debits, [], new Date("2026-08-05T12:00:00"), 7).map(row => row.debito_direto_id), ["monthly", "once"]);
assert.deepEqual(upcomingDirectDebitRows(debits, [{ debito_direto_id: "monthly", data: "2026-08-10" }], new Date("2026-08-05T12:00:00"), 7).map(row => row.debito_direto_id), ["once"]);

const work = { id: "work", planeamento_baseline_congelado: true };
const phases = [{ id: "phase", obra_id: "work", codigo: "F01", descricao: "Estaleiro" }];
const delayed = planningBaselineDelays(work, phases, [{ fase_id: "phase", data_fim_baseline: "2026-08-01", data_fim_prevista: "2026-08-11" }]);
assert.equal(delayed.length, 1);
assert.equal(delayed[0].days, 10);
assert.deepEqual(planningBaselineDelays({ ...work, planeamento_baseline_congelado: false }, phases, []), []);

assert.match(source, /INCIDENTES ESTE MÊS/);
assert.match(source, /EPIs A VENCER · 30 DIAS/);
assert.match(source, /DÉBITOS DIRETOS · 7 DIAS/);
assert.match(source, /RNCs FECHADAS SEM AVALIAÇÃO/);
assert.match(source, /TAREFAS IMPEDIDAS · URGENTE/);
assert.match(source, /VER RESUMO POR FASE/);
assert.match(source, /technicalRole \|\| financialRole \? query\("rnc/);
assert.match(planning, /options\.workId/);
assert.match(planning, /options\.view/);
assert.match(app, /planningModule\.show\(context\)/);
assert.match(migration, /fn_e_financeiro\(\)/);
assert.match(migration, /estado = 'fechado'/);
assert.match(migration, /subempreitada_id is not null/);
assert.doesNotMatch(migration, /for (insert|update|delete|all)/i);

console.log("Visão Geral 2026 validada para Administrativo, Financeiro e Equipa Técnica.");
