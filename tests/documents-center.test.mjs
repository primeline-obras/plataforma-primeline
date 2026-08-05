import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const moduleSource = fs.readFileSync(new URL("../src/documents.js", import.meta.url), "utf8");
const appSource = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/centro_documentos_encarregado.sql", import.meta.url), "utf8");

test("centro documental disponibiliza os quatro grupos operacionais", () => {
  for (const label of ["Articulado", "Desenhos", "PDEs / PAMEs", "Atas"]) {
    assert.match(moduleSource, new RegExp(`label: \\"${label.replace("/", "\\/")}\\"`));
  }
  assert.match(moduleSource, /CARREGAR FICHEIRO/);
  assert.match(moduleSource, /documents-center-upload/);
});

test("encarregado não recebe o arquivo geral", () => {
  assert.match(moduleSource, /getRole\(\) === "encarregado" \? PRIMARY_SECTIONS/);
  assert.match(migration, /fn_e_encarregado_da_obra\(obra_id\)/);
  assert.match(migration, /'articulado_original'/);
  assert.doesNotMatch(migration.match(/and tipo in \([\s\S]*?\n    \)/)?.[0] || "", /'contrato'/);
});

test("rota lateral Documentos usa um ecrã real", () => {
  assert.match(appSource, /id="documents-view"/);
  assert.match(appSource, /if \(view === "documents"\) documentsModule\.show\(\)/);
});
