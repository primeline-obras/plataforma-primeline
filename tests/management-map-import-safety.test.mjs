import assert from "node:assert/strict";
import test from "node:test";
import { validateManagementImportRows } from "../src/management-map.js";

test("a pré-visualização bloqueia as obras reservadas ao Saldo de Abertura", () => {
  const errors = validateManagementImportRows([
    { linha: 2, obra_numero: "79" },
    { linha: 3, obra_numero: "085" },
    { linha: 4, obra_numero: 127 },
    { linha: 5, obra_numero: "120" },
  ]);

  assert.equal(errors.length, 3);
  assert.match(errors[0], /Obra 79 não aceita importação/);
  assert.match(errors[1], /Obra 085 não aceita importação/);
  assert.match(errors[2], /Obra 127 não aceita importação/);
  assert.ok(errors.every(error => error.includes("usar Saldo de Abertura")));
});

test("as restantes obras continuam permitidas na validação local", () => {
  assert.deepEqual(validateManagementImportRows([
    { linha: 2, obra_numero: "032" },
    { linha: 3, obra_numero: "118" },
    { linha: 4, obra_numero: "120" },
    { linha: 5, obra_numero: "128" },
  ]), []);
});
