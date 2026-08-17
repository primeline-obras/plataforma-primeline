import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const settings = await readFile(new URL("../src/settings.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");
const sql = await readFile(new URL("../supabase/feriados_empresa.sql", import.meta.url), "utf8");

test("mapas distinguem fins de semana, feriados e férias", () => {
  assert.match(app, /SÁB.*DOM/s);
  assert.match(app, /activeHoliday/);
  assert.match(styles, /\.workforce-day-cell\.weekend/);
  assert.match(styles, /\.vacation-map \.holiday/);
  assert.match(styles, /\.vacation-map-row > i\.vacation[\s\S]*#d9a441/);
  assert.match(styles, /weekend[\s\S]*rgba\(107, 104, 95, \.09\)/);
  assert.match(styles, /holiday[\s\S]*rgba\(217, 164, 65, \.17\)/);
});

test("linhas e alocações usam a paleta final de função sem dourado", () => {
  for (const role of ["direction", "foreman", "admin", "mason", "helper"]) {
    assert.match(styles, new RegExp(`function-${role}`));
  }
  assert.match(styles, /vacation-map-row\.function-direction[\s\S]*rgba\(32, 36, 43, \.14\)/);
  assert.match(styles, /vacation-map-row\.function-foreman[\s\S]*rgba\(63, 152, 98, \.22\)/);
  assert.match(styles, /vacation-map-row\.function-admin[\s\S]*rgba\(140, 74, 120, \.16\)/);
  assert.match(styles, /vacation-map-row\.function-mason[\s\S]*rgba\(140, 74, 64, \.16\)/);
  assert.match(styles, /vacation-map-row\.function-helper[\s\S]*rgba\(70, 86, 110, \.16\)/);
  assert.match(styles, /vacation-map-row > strong \{ color: #3b3830; border-left: 4px solid transparent; \}/);
  assert.doesNotMatch(styles, /data-theme="dark"[^}]*vacation-map-row > strong/);
  for (const color of ["#20242b", "#3f6248", "#8c4a78", "#8c4a40", "#46566e"]) {
    assert.match(styles, new RegExp(`border-left-color: ${color}`));
  }
  assert.doesNotMatch(app.match(/const functionRowTints = \{[\s\S]*?\n\};/)?.[0] || "", /217, 164, 65|138, 100, 32/);
  assert.match(app, /workforceFunctionTint/);
  assert.match(styles, /workforce-day-cell\.function-tinted/);
});

test("feriados são configuráveis por administrativo e gerência", () => {
  assert.match(settings, /FERIADOS E DIAS DE FOLGA/);
  assert.match(settings, /data-holiday-toggle/);
  assert.match(sql, /fn_e_admin\(\) or public\.fn_e_administrativo\(\)/i);
  assert.match(sql, /Sintra/);
  assert.match(sql, /Cascais/);
});
