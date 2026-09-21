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
    "rpc/fn_guardar_cadastro_fornecedor",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  assert.match(source, /fornecedores\?select=\*&order=nome/);
  assert.doesNotMatch(source, /tipo_entidade=eq\.subempreiteiro/);
});

test("directory supports safe manual review of incomplete profiles", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "supplierProfileStatus", "CADASTROS POR COMPLETAR", "COMPLETUDE DO CADASTRO",
    "data-supplier-profile", "DADOS EM FALTA", "POR COMPLETAR:",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  assert.match(source, /row\.supplier\.nif, row\.supplier\.notas/);

  const { supplierProfileStatus } = await import("../src/subcontractors.js");
  const incomplete = supplierProfileStatus({ nome: "Empresa", email: "geral@empresa.pt" }, {
    zones: ["lisboa_cascais"], specialties: [{ id: "especialidade" }],
  });
  assert.equal(incomplete.complete, false);
  assert.deepEqual(incomplete.missing, ["NIF", "TELEFONE", "REPRESENTANTE", "NOTAS", "TIPO"]);
  const complete = supplierProfileStatus({
    nif: "500000000", email: "geral@empresa.pt", telefone: "210000000",
    representante: "Ana", notas: "Referência validada", tipo_entidade: "ambos",
  }, { zones: ["algarve"], specialties: [{ id: "especialidade" }] });
  assert.deepEqual(complete, { complete: true, missing: [] });
});

test("supplier editing stays above the directory instead of jumping to the page end", async () => {
  const source = await read("src/subcontractors.js");
  const detailPosition = source.indexOf("${renderDetail()}");
  const directoryPosition = source.indexOf('<section class="supplier-directory-panel">');
  assert.ok(detailPosition >= 0 && detailPosition < directoryPosition);
  assert.match(source, /Cadastro completo atualizado/);
});

test("directory distinguishes partner type and accepts an intermediate assessment", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "FORNECEDOR", "SUBEMPREITEIRO", "FORNECEDOR E SUBEMPREITEIRO",
    "RECOMENDADO COM RESSALVAS", "data-supplier-entity", 'name="tipo_entidade"',
    "rpc/fn_guardar_cadastro_fornecedor",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  const comparative = await read("src/comparative-map.js");
  assert.match(comparative, /\["subempreiteiro",\s*"ambos"\]\.includes\(row\.tipo_entidade\)/);
});

test("authorized users save the complete profile and a new specialty once", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "NOVA ESPECIALIDADE", 'name="nova_especialidade"',
    "rpc/fn_guardar_cadastro_fornecedor", 'creating ? "CRIAR PARCEIRO" : "GUARDAR"',
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  assert.doesNotMatch(source, /GUARDAR ZONAS|GUARDAR CLASSIFICAÇÃO|CRIAR E ASSOCIAR/);
  assert.match(source, /state\.selectedSupplierId = null;[\s\S]*Cadastro completo atualizado/);
  const sql = await read("supabase/cadastro_fornecedor_unificado.sql");
  assert.match(sql, /fn_guardar_cadastro_fornecedor/);
  assert.match(sql, /fn_editar_fornecedor_diretorio_v2/);
  assert.match(sql, /fn_definir_zonas_fornecedor/);
  assert.match(sql, /fn_criar_especialidade_fornecedor/);
  assert.match(sql, /delete from public\.fornecedores_especialidades/);
  assert.match(sql, /grant execute[\s\S]+to authenticated/i);
  const classificationSql = await read("supabase/diretorio_tipos_avaliacao_especialidades.sql");
  assert.match(classificationSql, /recomendado_com_ressalvas/);
  assert.match(classificationSql, /set tipo_entidade = 'fornecedor'[\s\S]*where tipo_entidade = 'fornecedor_material'/);
  assert.match(classificationSql, /tipo_entidade[^;]+fornecedor[^;]+subempreiteiro[^;]+ambos/is);
  assert.match(classificationSql, /pg_advisory_xact_lock/);
  assert.match(classificationSql, /on conflict \(fornecedor_id, especialidade_id\) do nothing/i);
});

test("directory creates a new partner and filters every operational-zone combination", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "+ NOVO PARCEIRO", "data-new-supplier", 'data-supplier-mode="create"',
    "Novo parceiro criado.", "data-supplier-zone-filter", 'value="both"',
    "Lisboa / Cascais e Algarve", "Por classificar",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  assert.match(source, /p_fornecedor_id:\s*supplierForm\.dataset\.supplierEditor \|\| null/);
  assert.match(source, /Object\.keys\(OPERATIONAL_ZONES\)\.every\(zone => zones\.includes\(zone\)\)/);

  const sql = await read("supabase/cadastro_fornecedor_unificado.sql");
  assert.match(sql, /if v_fornecedor_id is null then/i);
  assert.match(sql, /insert into public\.fornecedores/i);
  assert.match(sql, /Já existe um cadastro com este nome/i);
  assert.match(sql, /Já existe um cadastro com este NIF/i);
  assert.match(sql, /exception when unique_violation/i);
  assert.match(sql, /criacao_fornecedor_ativa/i);
});

test("duplicate supplier deletion is explicit and refuses records with business history", async () => {
  const source = await read("src/subcontractors.js");
  for (const expected of [
    "ELIMINAR DUPLICADO", "data-delete-supplier", "fn_eliminar_fornecedor_duplicado",
    "window.confirm", "Registo duplicado eliminado",
  ]) assert.ok(source.includes(expected), `missing ${expected}`);
  const sql = await read("supabase/diretorio_tipos_avaliacao_especialidades.sql");
  assert.match(sql, /fn_eliminar_fornecedor_duplicado/);
  assert.match(sql, /Qualquer referência de negócio bloqueia a eliminação/);
  assert.match(sql, /Este registo não pode ser eliminado porque já tem histórico associado/);
  assert.match(sql, /delete from public\.fornecedores_zonas/);
  assert.match(sql, /delete from public\.fornecedores_especialidades/);
  assert.match(sql, /delete from public\.fornecedores where id = p_fornecedor_id/);
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
