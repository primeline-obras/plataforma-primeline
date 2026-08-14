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
});

test("nomes no mapa de férias têm cor por função", () => {
  for (const role of ["direction", "foreman", "admin", "mason", "helper", "other"]) {
    assert.match(styles, new RegExp(`function-${role}`));
  }
});

test("feriados são configuráveis por administrativo e gerência", () => {
  assert.match(settings, /FERIADOS E DIAS DE FOLGA/);
  assert.match(settings, /data-holiday-toggle/);
  assert.match(sql, /fn_e_admin\(\) or public\.fn_e_administrativo\(\)/i);
  assert.match(sql, /Sintra/);
  assert.match(sql, /Cascais/);
});
