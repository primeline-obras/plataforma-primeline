import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const css = await readFile(new URL("src/visual-identity-final.css", root), "utf8");
const js = await readFile(new URL("src/visual-identity-final.js", root), "utf8");
const index = await readFile(new URL("index.html", root), "utf8");

test("a identidade final é carregada depois dos estilos legados", () => {
  assert.ok(index.indexOf("styles.css") < index.indexOf("visual-identity-final.css"));
  assert.match(index, /visual-identity-final\.js/);
});

test("usa a paleta final exata", () => {
  ["#FAF8F3", "#20242B", "#3B3830", "#6B685F", "#8A8578", "#A8A398",
    "#F1EFE8", "#B4B2A9", "#FFFDF9", "#EFEBE1", "#DDD8CC", "#CFC9BB",
    "#4A5568", "#8A6420", "#E6EDE4", "#3F6248", "#F2E3E0", "#8C4A40",
    "#F7EDD6"].forEach(color => assert.ok(css.includes(color), `falta ${color}`));
});

test("preserva o toggle com tokens próprios para claro e escuro", () => {
  assert.match(css, /:root\[data-theme="light"\]/);
  assert.match(css, /:root\[data-theme="dark"\][\s\S]*?--bg:\s*#1A1D23/);
  assert.match(css, /:root\[data-theme="dark"\][\s\S]*?--card:\s*#23262D/);
  assert.match(css, /:root\[data-theme="dark"\][\s\S]*?--card-border:\s*#3A3D45/);
  assert.match(css, /:root\[data-theme="dark"\][\s\S]*?--action:\s*#D4A854/);
  assert.match(css, /--pos-bg:\s*#1F2E22[\s\S]*?--pos-text:\s*#A8C4AE/);
  assert.match(css, /--neg-bg:\s*#352321[\s\S]*?--neg-text:\s*#E0A49B/);
  assert.match(css, /--warn-bg:\s*#342B1D[\s\S]*?--warn-text:\s*#E0BD78/);
});

test("usa IBM Plex e geometria final", () => {
  assert.match(css, /IBM\+Plex\+Mono/);
  assert.match(css, /IBM\+Plex\+Sans/);
  assert.match(css, /border-radius:\s*4px/);
  assert.match(css, /border-radius:\s*6px/);
  assert.match(css, /border-radius:\s*999px/);
});

test("botão primário é antracite e não dourado", () => {
  assert.match(css, /\.primary-button[^}]*\{[\s\S]*?background:\s*#20242B\s*!important/);
  assert.doesNotMatch(css, /\.primary-button[^}]*\{[^}]*background:\s*#D9A441/i);
});

test("tabelas recebem números monoespaçados e links sem azul", () => {
  assert.match(css, /table \.ui-number-cell[\s\S]*?text-align:\s*right/);
  assert.match(css, /table a[\s\S]*?color:\s*var\(--action\)/);
  assert.match(js, /numericPattern/);
  assert.match(js, /ui-number-cell/);
});

test("badges usam a classificação semântica comum", () => {
  assert.match(js, /ui-state-positive/);
  assert.match(js, /ui-state-negative/);
  assert.match(js, /ui-state-progress/);
  assert.match(js, /ui-state-decision/);
  assert.match(css, /\.ui-state-badge/);
});
