import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");
const html = await readFile(new URL("../index.html", import.meta.url), "utf8");

test("a lista do portfólio conserva rolagem depois da geometria global", () => {
  const globalGeometry = styles.indexOf(".panel, .work-detail, .works-list, .finance-column");
  const scrollOverride = styles.indexOf(".works-list {", globalGeometry + 1);
  const rule = styles.slice(scrollOverride, styles.indexOf("}", scrollOverride) + 1);

  assert.ok(globalGeometry >= 0, "regra global de geometria não encontrada");
  assert.ok(scrollOverride > globalGeometry, "a correção deve vir depois da regra que aplica overflow:hidden");
  assert.match(rule, /overflow-y:\s*auto/);
  assert.match(rule, /scrollbar-gutter:\s*stable/);
  assert.match(styles, /\.works-list::\-webkit-scrollbar\s*\{\s*width:\s*10px/);
});

test("a publicação invalida o cache do CSS corrigido", () => {
  assert.match(html, /styles\.css\?v=85/);
});
