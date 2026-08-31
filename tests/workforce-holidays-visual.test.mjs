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
  assert.match(styles, /\.vacation-map-row > i\.vacation[\s\S]*#4a5568[\s\S]*#f1efe8/);
  assert.match(styles, /weekend[\s\S]*rgba\(107, 104, 95, \.09\)/);
  assert.match(styles, /holiday[\s\S]*(?:rgba\(74, 85, 104, \.17\)|#4a5568)/);
});

test("linhas e alocações usam a paleta final de função sem dourado", () => {
  const palette = {
    direction: ["32, 36, 43", "#20242b"],
    foreman: ["46, 125, 91", "#2e7d5b"],
    admin: ["166, 68, 122", "#a6447a"],
    preparer: ["61, 90, 158", "#3d5a9e"],
    estimator: ["123, 79, 160", "#7b4fa0"],
    purchases: ["27, 143, 160", "#1b8fa0"],
    warehouse: ["139, 94, 52", "#8b5e34"],
    mason: ["124, 140, 62", "#7c8c3e"],
    cleaning: ["89, 168, 110", "#59a86e"],
    helper: ["191, 54, 54", "#bf3636"],
    other: ["117, 117, 117", "#757575"],
  };
  for (const [role, [rgb, solid]] of Object.entries(palette)) {
    assert.match(styles, new RegExp(`function-${role}`));
    assert.match(styles, new RegExp(`vacation-map-row\\.function-${role} \\{ background: rgba\\(${rgb.replaceAll(", ", ", ")}, \\.18\\)`));
    assert.match(styles, new RegExp(`vacation-map-row\\.function-${role} > strong \\{ border-left-color: ${solid}`));
    assert.match(styles, new RegExp(`workforce-magnet\\.function-${role} \\{ border-left: 4px solid ${solid}; background: rgba\\(${rgb.replaceAll(", ", ", ")}, \\.18\\)`));
  }
  assert.match(styles, /vacation-map-row > strong \{ color: #3b3830; border-left: 4px solid transparent; \}/);
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
