import assert from "node:assert/strict";
import fs from "node:fs";
import { accessFor } from "../src/access-control.js";

const moduleSource = fs.readFileSync(new URL("../src/company-documents.js", import.meta.url), "utf8");
const appSource = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const storageSource = fs.readFileSync(new URL("../src/supabase-browser.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/documentos_empresa.sql", import.meta.url), "utf8");

for (const type of [
  "certidao_permanente_comercial", "rcbe", "certidao_nao_divida_financas",
  "certidao_nao_divida_seguranca_social", "inpi", "seguro_acidentes_trabalho",
  "seguro_responsabilidade_civil",
]) assert(moduleSource.includes(type), `falta o tipo documental ${type}`);

assert(moduleSource.includes('entidade_tipo: "empresa"'));
assert(moduleSource.includes("data_validade"));
assert(moduleSource.includes("VENCE EM"));
assert(moduleSource.includes("VENCIDO HÁ"));
assert(moduleSource.includes("data-company-document-download"));
assert(moduleSource.includes('accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.xls,.xlsx,.csv,.doc,.docx"'));
assert(appSource.includes('data-view="company-documents"'));
assert(appSource.includes('companyDocumentsModule.show()'));
assert(storageSource.includes('entityType === "empresa" ? `empresa/${entityId}`'));

assert(accessFor({ role: "gerencia" }).views.includes("company-documents"));
assert(accessFor({ role: "administrativo" }).views.includes("company-documents"));
for (const role of ["financeiro", "diretor_obra", "preparador", "encarregado"])
  assert(!accessFor({ role }).views.includes("company-documents"), `${role} não deve ver documentos da empresa`);

assert(migration.includes("pl_documentos_empresa_select"));
assert(migration.includes("pl_documentos_empresa_insert"));
assert(migration.includes("documentos_empresa_storage_select"));
assert(migration.includes("documentos_empresa_storage_insert"));
assert(migration.includes("public.fn_e_administrativo()"));
assert(!migration.includes("alter table public.documentos\n  add column"));

console.log("Arquivo de documentos da empresa, validades e permissões validados.");
