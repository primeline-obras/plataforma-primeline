import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/corrigir_alertas_resolvido_por.sql", import.meta.url), "utf8");
const dashboard = await readFile(new URL("../src/production-dashboard.js", import.meta.url), "utf8");

assert.match(sql, /foreign key \(resolvido_por\)[\s\S]*references public\.utilizadores\(id\)/i);
assert.doesNotMatch(sql, /references public\.colaboradores\(id\)/i);
assert.match(sql, /v_utilizador_id := public\.fn_utilizador_atual_id\(\)/i);
assert.match(sql, /resolvido_por = v_utilizador_id/i);
assert.match(sql, /resolvido_em = now\(\)/i);
assert.match(sql, /on delete set null/i);
assert.match(dashboard, /rpc\/fn_resolver_alerta/);
assert.doesNotMatch(dashboard, /resolvido_por\s*:/);

console.log("Resolução de alertas usa utilizadores.id e não colaboradores.id.");
