import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { accessFor } from "../src/access-control.js";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const moduleSource = readFileSync(new URL("../src/meeting-rooms.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/bloco_12_salas_reuniao.sql", import.meta.url), "utf8");
const participantsMigration = readFileSync(new URL("../supabase/salas_reuniao_participantes_alertas.sql", import.meta.url), "utf8");

for (const role of ["gerencia", "administrativo", "financeiro", "diretor_obra", "adjunto", "preparador"]) {
  assert(accessFor({ role }).views.includes("rooms"), `${role} deve ver Salas de Reunião`);
}
assert(!accessFor({ role: "encarregado" }).views.includes("rooms"), "Encarregado não deve ver Salas de Reunião");

assert.match(app, /data-view="rooms"/);
assert.match(app, /createMeetingRoomsModule/);
assert.match(moduleSource, /HORÁRIOS OCUPADOS/);
assert.match(moduleSource, /overlaps\(fields\.data, fields\.hora_inicio, fields\.hora_fim\)/);
assert.match(moduleSource, /Este horário sobrepõe-se a uma reserva existente/);
assert.match(moduleSource, /criado_por: getProfile\(\)\?\.id \|\| null/);
assert.doesNotMatch(moduleSource, /name="sala_id"/);
assert.match(moduleSource, /name="participantes"/);
assert.match(moduleSource, /rpc\/fn_criar_reserva_sala/);
assert.match(migration, /create trigger trg_bloquear_reserva_sobreposta/i);
assert.match(migration, /overlaps \(r\.hora_inicio, r\.hora_fim\)/i);
assert.match(migration, /create policy reservas_salas_insert/i);
assert.match(participantsMigration, /create table if not exists public\.reservas_salas_participantes/i);
assert.match(participantsMigration, /destinatario_utilizador_id/i);
assert.match(participantsMigration, /expira_em > now\(\)/i);
assert.match(participantsMigration, /v_atual\.funcao = 'encarregado'/i);

console.log("Bloco 12 de Salas de Reunião validado.");
