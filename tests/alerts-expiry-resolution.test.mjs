import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/alertas_vencimentos_resolucao.sql", import.meta.url), "utf8");

assert.match(app, /id="notification-button"/);
assert.match(dashboard, /data-resolve-alert/);
assert.match(dashboard, /rpc\/fn_resolver_alerta/);
assert.doesNotMatch(dashboard, /alertas\?id=.*method:\s*["']PATCH/);
assert.match(migration, /create or replace function public\.fn_resolver_alerta/);
assert.match(migration, /set estado = 'resolvido'/);
assert.match(migration, /data_inspecao_proxima - 15 <= current_date/);
assert.match(migration, /data_proxima_consulta - 30 <= current_date/);
assert.match(migration, /e\.data_validade - 30 <= current_date/);
assert.match(migration, /cross join \(values \(15\), \(7\), \(3\)\)/);
assert.match(migration, /fn_executar_rotinas_diarias/);
assert.match(migration, /Substitui a versão do Bloco 1/);
assert.match(migration, /primeline-congelar-baselines-diario/);
assert.match(migration, /cron\.unschedule/);
assert.match(migration, /'auto_medicao'::text[\s\S]*'faturacao'::text/);

console.log("Alert expiry and explicit resolution checks passed.");
