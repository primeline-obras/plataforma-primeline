import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { accessFor } from "../src/access-control.js";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/quadro_pessoal_operacional_relatorio.sql", import.meta.url), "utf8");
const teamSql = await readFile(new URL("../supabase/equipa_restringir_ausencias_horas_extra.sql", import.meta.url), "utf8");

test("Quadro de Pessoal é uma vista operacional de Administrativo, Diretores e Encarregados", () => {
  assert.match(app, /data-view="workforce"[^>]*>[\s\S]*?Quadro de pessoal/i);
  for (const role of ["adjunto", "preparador", "financeiro"]) {
    assert.equal(accessFor({ role }).views.includes("workforce"), false, `${role} não pode ver o Quadro`);
  }
  for (const role of ["administrativo", "gerencia", "diretor_obra", "encarregado"]) {
    assert.equal(accessFor({ role }).views.includes("workforce"), true, `${role} deve ver o Quadro`);
  }
  assert.match(sql, /u\.funcao = 'diretor_obra'/);
  assert.match(sql, /fn_e_encarregado_da_obra\(p_obra_id\)/);
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

test("Equipa Técnica vê só o Mapa de Férias, sem indicadores de RH", () => {
  const kpis = app.match(/\$\("#team-kpis"\)\.innerHTML = \[[\s\S]*?\.join\(""\);/)?.[0] || "";
  assert.doesNotMatch(kpis, /ALOCADOS|SEM ALOCAÇÃO/);
  assert.match(app, /const vacationOnly = !canManageTeam\(\);/);
  assert.match(app, /\$\("#team-active-stat"\)\.hidden = vacationOnly/);
  assert.match(app, /\$\("#team-kpis"\)\.hidden = vacationOnly/);
  assert.match(app, /\$\("#team-alert-summary"\)\.hidden = vacationOnly/);
  assert.match(app, /Mapa de Férias, ponto diário da equipa em obra e medicina do trabalho\./);
  assert.match(app, /\$\("#team-kpis"\)\.innerHTML = vacationOnly \? ""/);
  assert.match(app, /\$\("#team-alert-summary"\)\.innerHTML = vacationOnly \? ""/);
});

test("diretório da Equipa calcula as alocações da semana antes de as consultar", () => {
  assert.match(app, /const currentAllocations = allocations[\s\S]*?selectedTeamWeek[\s\S]*?currentAllocations\.find/);
});

test("frontend consulta alocações apenas para papéis com acesso ao Quadro", () => {
  assert.match(app, /canManageWorkforce\(\) \? supabase\(`quadro_pessoal_alocacao/);
  assert.doesNotMatch(app, /rpc\/fn_quadro_ferias_encarregado_global/);
  assert.match(app, /function canManageWorkforce\(\) \{\s*return canManageTeam\(\) \|\| \["diretor_obra", "encarregado"\]/);
});

test("RLS remove políticas antigas e limita escrita à obra responsável", () => {
  assert.match(sql, /from pg_policies[\s\S]*tablename = 'quadro_pessoal_alocacao'/);
  for (const action of ["select", "insert", "update", "delete"]) assert.match(sql, new RegExp(`create policy quadro_pessoal_operacional_${action}`));
  assert.match(sql, /fn_pode_gerir_quadro\(obra_id\)/);
  assert.match(sql, /fn_pode_consultar_quadro\(\)/);
});
