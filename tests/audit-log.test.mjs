import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL("../supabase/ativar_log_auditoria.sql", import.meta.url), "utf8");

test("auditoria preserva a tabela existente e regista alterações por campo", () => {
  assert.doesNotMatch(migration, /create table\s+(?:if not exists\s+)?public\.log_auditoria/i);
  assert.match(migration, /create or replace function public\.fn_registar_log_auditoria/i);
  assert.match(migration, /v_anterior\s*->\s*campo\s+is distinct from\s+v_novo\s*->\s*campo/i);
  assert.match(migration, /'__INSERT__'/i);
  assert.match(migration, /'__DELETE__'/i);
});

test("auditoria identifica o utilizador e protege escrita direta", () => {
  assert.match(migration, /public\.fn_utilizador_atual_id\(\)/i);
  assert.match(migration, /security definer/i);
  assert.match(migration, /revoke insert, update, delete, truncate[\s\S]*from authenticated/i);
  assert.match(migration, /using \(public\.fn_e_admin\(\)\)/i);
});

test("auditoria cobre tarefas, dinheiro, permissões e equipa", () => {
  for (const table of [
    "planeamento_itens", "faturas", "faturacao", "pagamentos_subempreitada",
    "debitos_diretos", "utilizadores", "obra_responsaveis", "quadro_pessoal_alocacao",
  ]) assert.match(migration, new RegExp(`'${table}'`, "i"));
});

test("campos sensíveis são excluídos", () => {
  for (const field of ["password", "access_token", "refresh_token", "service_role_key"])
    assert.match(migration, new RegExp(`'${field}'`, "i"));
});
