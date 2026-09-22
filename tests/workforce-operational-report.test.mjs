import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { accessFor } from "../src/access-control.js";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const attendance = await readFile(new URL("../src/attendance.js", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/quadro_pessoal_operacional_relatorio.sql", import.meta.url), "utf8");

test("Diretor e Encarregado recuperam o mapa sem alargar a Adjunto ou Preparador", () => {
  assert(accessFor({ role: "diretor_obra" }).views.includes("workforce"));
  assert(accessFor({ role: "encarregado" }).views.includes("workforce"));
  assert(!accessFor({ role: "adjunto" }).views.includes("workforce"));
  assert(!accessFor({ role: "preparador" }).views.includes("workforce"));
  assert.match(app, /\["diretor_obra", "encarregado"\]\.includes\(effectiveRole\(\)\)/);
});

test("escrita fica limitada à obra responsável e cada mudança é auditada", () => {
  assert.match(sql, /fn_pode_gerir_quadro\(obra_id\)/);
  assert.match(sql, /fn_e_encarregado_da_obra\(p_obra_id\)/);
  assert.match(sql, /trg_quadro_pessoal_movimentos/);
  assert.match(sql, /alterado_por/);
  assert.match(sql, /alterado_em/);
});

test("Administrativo escolhe o mês e descarrega horas por colaborador e obra", () => {
  assert.match(sql, /fn_relatorio_mensal_ponto\(p_mes date\)/);
  assert.match(sql, /order by lower\(c\.nome\)/);
  assert.match(attendance, /data-attendance-report-month/);
  assert.match(attendance, /fn_relatorio_mensal_ponto/);
  assert.match(attendance, /XLSX\.writeFile/);
  assert.match(attendance, /Horas/);
});
