import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const settings = readFileSync(new URL("../src/settings.js", import.meta.url), "utf8");

test("Auditoria aparece como separador administrativo e carrega de forma limitada", () => {
  assert.match(settings, /data-settings-admin-tab="audit"/i);
  assert.match(settings, /data-settings-admin-panel="audit"/i);
  assert.match(settings, /log_auditoria\?select=/i);
  assert.match(settings, /order=criado_em\.desc&limit=200/i);
  assert.match(settings, /if \(!isAdmin\(\)/i);
});

test("Histórico permite filtrar e comparar valores", () => {
  assert.match(settings, /data-audit-table/i);
  assert.match(settings, /data-audit-user/i);
  assert.match(settings, /data-audit-field/i);
  assert.match(settings, /data-audit-from/i);
  assert.match(settings, /data-audit-to/i);
  assert.match(settings, /VALOR ANTERIOR/i);
  assert.match(settings, /VALOR NOVO/i);
});

test("Eventos distinguem criação, alteração e eliminação", () => {
  assert.match(settings, /__INSERT__[\s\S]*CRIAÇÃO/i);
  assert.match(settings, /__DELETE__[\s\S]*ELIMINAÇÃO/i);
  assert.match(settings, /ALTERAÇÃO/i);
});
