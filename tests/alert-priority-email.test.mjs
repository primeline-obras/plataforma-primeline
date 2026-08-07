import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { alertPriority, sortAlertsByPriority } from "../src/production-dashboard.js";

const dashboard = await readFile(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const sql = await readFile(
  new URL("../supabase/bloco_09_alertas_prioridade_email.sql", import.meta.url),
  "utf8",
);

const ordered = sortAlertsByPriority([
  { tipo: "aniversario", data_gatilho: "2026-08-01" },
  { tipo: "fim_contrato_rh", data_gatilho: "2026-08-01" },
  { tipo: "consulta_medicina", data_gatilho: "2026-08-01" },
  { tipo: "seguro_viatura", data_gatilho: "2026-08-01" },
  { tipo: "geral", data_gatilho: "2026-08-01" },
]);
assert.deepEqual(ordered.map(row => alertPriority(row)), [0, 1, 2, 3, 4]);
assert.match(dashboard, /PLATAFORMA \+ EMAIL/);
assert.match(dashboard, /sortAlertsByPriority\(alerts\)/);

assert.match(sql, /add column if not exists enviar_email boolean not null default false/);
assert.match(sql, /'pedido_semanal_horas'/);
assert.match(sql, /'informacao_reuniao_semanal'/);
assert.match(sql, /extract\(isodow from p_data\) <> 5/);
assert.match(sql, /v_pedidos_horas := public\.fn_criar_pedidos_horas_semanais\(current_date\)/);
assert.match(sql, /SMTP NÃO é configurado/);
assert.doesNotMatch(sql, /smtp_host|smtp_password|send_email|net\.http_post/);

console.log("Prioridade e canal dos alertas validados.");
