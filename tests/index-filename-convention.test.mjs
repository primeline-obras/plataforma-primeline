import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");

test("PDE e PAME sugerem TIPO_NÚMERO_REVXX_DESCRIÇÃO", () => {
  assert.match(app, /pdes_rfis: \{ prefix: "PDE", drawing: false \}/);
  assert.match(app, /pames: \{ prefix: "PAME", drawing: false \}/);
  assert.match(app, /`\$\{definition\.prefix\}_\$\{normalizedNumber\}_REV\$\{normalizedRevision\}_\$\{shortDescription\}\$\{extension\}`/);
  assert.match(app, /\^PDE_\[\^_\\s\]\+_REV\\d\{2\}_/);
  assert.match(app, /\^PAME_\[\^_\\s\]\+_REV\\d\{2\}_/);
});

test("Desenhos incluem revisão e folha no padrão próprio", () => {
  assert.match(app, /desenhos_preparacao: \{ prefix: "DES", drawing: true \}/);
  assert.match(app, /_REV\$\{normalizedRevision\}_FL01\$\{extension\}/);
  assert.match(app, /_REV\\d\{2\}_FL\\d\{2\}/);
});

test("o aviso é atualizado sem bloquear o envio", () => {
  assert.match(app, /data-index-filename-warning/);
  assert.match(app, /NOME FORA DO PADRÃO/);
  assert.match(app, /Pode enviar o ficheiro sem o renomear/);
  assert.match(app, /updateIndexFilenameWarning\(uploadForm\);[\s\S]*submitButton\.disabled = true/);
  assert.doesNotMatch(app, /if \(!validIndexFilename[\s\S]{0,200}return/);
});
