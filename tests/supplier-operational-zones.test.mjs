import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("migration supports two operational zones with protected writes", async () => {
  const sql = await read("supabase/fornecedores_zonas_operacionais.sql");
  assert.match(sql, /create table if not exists public\.fornecedores_zonas/i);
  assert.match(sql, /zona in \('lisboa_cascais', 'algarve'\)/i);
  assert.match(sql, /unique \(fornecedor_id, zona\)/i);
  assert.match(sql, /fn_definir_zonas_fornecedor/i);
  assert.match(sql, /fn_e_admin\(\) or public\.fn_e_administrativo\(\)/i);
});

test("supplier profile edit is auditable and rejects duplicate NIFs", async () => {
  const sql = await read("supabase/fornecedores_zonas_operacionais.sql");
  assert.match(sql, /add column if not exists nif text/i);
  assert.match(sql, /add column if not exists representante text/i);
  assert.match(sql, /add column if not exists notas text/i);
  assert.match(sql, /fn_editar_fornecedor_diretorio/i);
  assert.match(sql, /Já existe outra empresa com este NIF/i);
  assert.match(sql, /for update of f/i);
});

test("directory exposes region filters and complete supplier form", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "LISBOA / CASCAIS", "ALGARVE", "POR CLASSIFICAR",
    "CADASTRO DA EMPRESA", "name=\"nif\"", "name=\"email\"",
    "name=\"telefone\"", "name=\"representante\"", "name=\"notas\"",
    "rpc/fn_editar_fornecedor_diretorio", "rpc/fn_definir_zonas_fornecedor",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  assert.match(source, /fornecedores\?select=\*&order=nome/);
  assert.doesNotMatch(source, /tipo_entidade=eq\.subempreiteiro/);
});

test("edited supplier propagates to the shared application list", async () => {
  const source = await read("src/app.js");
  assert.match(source, /onSupplierUpdated: updated =>/);
  assert.match(source, /suppliers\[index\] = updated/);
  assert.match(source, /renderSelectors\(\)/);
});

test("page title reflects the combined directory", async () => {
  const source = await read("src/app.js");
  assert.match(source, /FORNECEDORES E SUBEMPREITEIROS/);
  const css = await read("src/specialties.css");
  assert.match(css, /supplier-editor-actions \.primary-button \{ flex: 0 0 auto; width: auto/);
});
