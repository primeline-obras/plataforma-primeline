import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const migration = fs.readFileSync(new URL("../supabase/alertas_vencimentos_resolucao_corrigido.sql", import.meta.url), "utf8");

assert.match(app, /id="notification-button"/);
assert.match(app, /id="notification-drawer"/);
assert.match(dashboard, /data-resolve-alert/);
assert.match(dashboard, /rpc\/fn_resolver_alerta/);
assert.match(dashboard, /openNotificationDrawer/);
assert.match(dashboard, /data-notification-view/);
assert.doesNotMatch(dashboard, /notification-button[^\n]*showView\("overview"\)/);
assert.doesNotMatch(dashboard, /alertas\?id=.*method:\s*["']PATCH/);
assert.match(migration, /create or replace function public\.fn_resolver_alerta/);
assert.match(migration, /resolvido_por = v_utilizador_id/);
assert.match(migration, /resolvido_em = now\(\)/);
assert.match(migration, /drop trigger if exists trg_alerta_validade_documento/);
assert.match(migration, /create unique index if not exists alertas_ocorrencia_unica_idx/);
assert.match(migration, /data_inspecao_proxima - 15 <= current_date/);
assert.match(migration, /data_proxima_consulta - 30 <= current_date/);
assert.match(migration, /e\.data_validade - 30 <= current_date/);
assert.match(migration, /fn_executar_rotinas_diarias/);
assert.doesNotMatch(migration, /cron\.schedule/);

console.log("Alert expiry and explicit resolution checks passed.");
