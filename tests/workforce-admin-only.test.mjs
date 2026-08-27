import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { accessFor } from "../src/access-control.js";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/quadro_pessoal_apenas_administrativo_gerencia.sql", import.meta.url), "utf8");
const teamSql = await readFile(new URL("../supabase/equipa_restringir_ausencias_horas_extra.sql", import.meta.url), "utf8");

test("Quadro de Pessoal é uma vista principal apenas de Administrativo e Gerência", () => {
  assert.match(app, /data-view="workforce"[^>]*>[\s\S]*?Quadro de pessoal/i);
  for (const role of ["diretor_obra", "adjunto", "preparador", "encarregado", "financeiro"]) {
    assert.equal(accessFor({ role }).views.includes("workforce"), false, `${role} não pode ver o Quadro`);
  }
  for (const role of ["administrativo", "gerencia"]) {
    assert.equal(accessFor({ role }).views.includes("workforce"), true, `${role} deve ver o Quadro`);
  }
});

test("Preparador não vê nem gere Ausências ou Horas Extra", () => {
  assert.match(app, /function canManageAbsences\(\) \{\s*return canManageTeam\(\);/);
  assert.match(app, /function canManageOvertime\(\) \{\s*return canManageTeam\(\);/);
  assert.match(app, /return tab === "vacations"/);
  assert.doesNotMatch(app, /return \["vacations", "absences", "overtime"\]\.includes\(tab\)/);
  assert.match(teamSql, /tipo = 'ferias' or public\.fn_e_administrativo\(\)/);
  assert.match(teamSql, /create policy horas_extra_rh/);
  assert.match(teamSql, /drop policy if exists documentos_ausencias_equipa_select/);
});

test("Equipa não apresenta números de alocação", () => {
  const kpis = app.match(/\$\("#team-kpis"\)\.innerHTML = \[[\s\S]*?\.join\(""\);/)?.[0] || "";
  assert.doesNotMatch(kpis, /ALOCADOS|SEM ALOCAÇÃO/);
  assert.match(kpis, /COLABORADORES ATIVOS/);
  assert.match(kpis, /AUSENTES NA SEMANA/);
});

test("frontend não consulta alocações nem RPC global sem acesso ao Quadro", () => {
  assert.match(app, /canManageWorkforce\(\) \? supabase\(`quadro_pessoal_alocacao/);
  assert.doesNotMatch(app, /rpc\/fn_quadro_ferias_encarregado_global/);
  assert.match(app, /function canManageWorkforce\(\) \{\s*return canManageTeam\(\);/);
});

test("RLS remove políticas antigas e reserva os dados ao Administrativo/Gerência", () => {
  assert.match(sql, /from pg_policies[\s\S]*tablename = 'quadro_pessoal_alocacao'/);
  for (const action of ["select", "insert", "update", "delete"]) assert.match(sql, new RegExp(`create policy quadro_pessoal_rh_${action}`));
  assert.match(sql, /using \(public\.fn_e_administrativo\(\)\)/);
  assert.match(sql, /revoke all on function public\.fn_quadro_ferias_encarregado_global/);
});
