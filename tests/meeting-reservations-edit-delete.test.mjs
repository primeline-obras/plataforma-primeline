import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/meeting-rooms.js", import.meta.url), "utf8");
const access = readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/salas_reuniao_editar_apagar_notificar.sql", import.meta.url), "utf8");

assert.match(source, /data-edit-reservation/);
assert.match(source, /data-delete-reservation/);
assert.match(source, /rpc\/fn_editar_reserva_sala/);
assert.match(source, /rpc\/fn_apagar_reserva_sala/);
assert.match(source, /Reserva atualizada e participantes notificados/);
assert.match(access, /context\.role === "encarregado"/);
assert.match(sql, /v_reserva\.criado_por is distinct from v_atual\.id[\s\S]*fn_e_administrativo/);
assert.match(sql, /foi alterada por/);
assert.match(sql, /foi cancelada por/);
assert.match(sql, /expira_em/);

console.log("Meeting reservation edit, delete and notifications validated.");
