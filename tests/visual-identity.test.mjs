import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const [html, css] = await Promise.all([
  readFile(new URL("index.html", root), "utf8"),
  readFile(new URL("src/visual-identity.css", root), "utf8"),
]);

test("central visual identity stylesheet is loaded after the legacy styles", () => {
  const legacy = html.indexOf("/src/styles.css");
  const identity = html.indexOf("/src/visual-identity.css");
  assert.ok(legacy >= 0);
  assert.ok(identity > legacy);
});

test("brand palette is fixed and available to all themes", () => {
  for (const color of ["#20242b", "#d9a441", "#f1efe8", "#b4b2a9", "#eaf3de", "#faeeda", "#fcebeb"]) {
    assert.match(css.toLowerCase(), new RegExp(color));
  }
  assert.doesNotMatch(css, /\[data-theme=[^\]]+\]\s*\{[^}]*--pl-/s);
});

test("shared KPI groups, tables and badges use centralized rules", () => {
  for (const selector of [".overview-kpis", ".meeting-kpis", ".rsp-kpis", ".team-kpis", ".work-kpis", ".planning-summary-kpis", ".subcontractors-kpis", ".tee-kpis"]) {
    assert.ok(css.includes(selector), `${selector} is not covered`);
  }
  assert.match(css, /table thead th/);
  assert.match(css, /border-bottom:\s*\.5px/);
  assert.match(css, /border-radius:\s*999px/);
  assert.match(css, /\.adjudicado/);
  assert.match(css, /\.aguarda_resposta/);
  assert.match(css, /\.recusado/);
});
