import test from "node:test";
import assert from "node:assert/strict";
import { access, readFile, stat } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const app = await readFile(new URL("src/app.js", root), "utf8");
const reset = await readFile(new URL("src/reset-password.js", root), "utf8");
const css = await readFile(new URL("src/styles.css", root), "utf8");
const index = await readFile(new URL("index.html", root), "utf8");
const documentPdf = await readFile(new URL("src/document-index-pdf.js", root), "utf8");
const rncPdf = await readFile(new URL("src/rnc-pdf.js", root), "utf8");

test("usa os dois logótipos oficiais e destaca GO com separador", () => {
  for (const source of [app, reset]) {
    assert.match(source, /assets\/brand\/logo\.png/);
    assert.match(source, /assets\/brand\/logo_branco\.png/);
    assert.match(source, /brand-separator/);
    assert.match(source, /brand-go[^>]*[^]*?>GO</);
    assert.doesNotMatch(source, /brand-mark/);
  }
  assert.match(css, /grid-template-columns:\s*minmax\(0, 1fr\) 1px auto/);
  assert.match(css, /\.brand-go[^}]*font:\s*800 22px/);
});

test("inclui os recursos oficiais no pacote publicado", async () => {
  for (const name of ["logo.png", "logo_branco.png"]) {
    const url = new URL(`assets/brand/${name}`, root);
    await access(url);
    assert.ok((await stat(url)).size > 1000, `${name} não contém uma imagem válida`);
  }
});

test("renomeia a ferramenta e remove o placeholder dos PDFs", () => {
  assert.match(index, /<title>PRIMELINE GO — Gestão de Obras<\/title>/);
  for (const source of [documentPdf, rncPdf]) {
    assert.match(source, /assets\/brand\/logo_branco\.png/);
    assert.match(source, /addImage\(brandLogo/);
    assert.match(source, /pdf\.text\("GO"/);
    assert.doesNotMatch(source, /\/\/\/ PRIMELINE/);
  }
});
