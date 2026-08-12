import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { isApprovedTee, isPendingTee, teeClientState } from "../src/production-dashboard.js";

assert.equal(teeClientState("Aprovado"), "aprovado");
assert.equal(teeClientState("Em elaboração"), "em_elaboracao");
assert.equal(teeClientState("AGUARDA RESPOSTA"), "aguarda_resposta");
assert.equal(isApprovedTee({ estado_aprovacao_cliente: "APROVADO" }), true);
assert.equal(isPendingTee({ estado_aprovacao_cliente: "em_elaboracao" }), true);
assert.equal(isPendingTee({ estado_aprovacao_cliente: "aguarda resposta" }), true);
assert.equal(isPendingTee({ estado_aprovacao_cliente: "pendente" }), true);
assert.equal(isPendingTee({ estado_aprovacao_cliente: "recusado" }), false);

const dashboard = await readFile(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
assert.match(dashboard, /alteracoes_tee\?select=\*&obra_id=eq\.\$\{encoded\}/);
assert.match(dashboard, /data\.tees\.filter\(isApprovedTee\)/);
assert.match(dashboard, /data\.tees\.filter\(isPendingTee\)/);

const migration = await readFile(new URL("../supabase/corrigir_tees_rsp.sql", import.meta.url), "utf8");
assert.match(migration, /public\.fn_e_admin\(\)/);
assert.match(migration, /public\.fn_pode_ver_obra\(obra_id\)/);
assert.doesNotMatch(migration, /fn_e_financeiro/);

console.log("TEEs aprovados e em elaboração ligados e classificados corretamente na RSP.");
