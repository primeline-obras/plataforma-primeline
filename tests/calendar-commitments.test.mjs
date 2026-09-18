import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { accessFor } from "../src/access-control.js";

const [app, calendar, dashboard, sql, styles, html] = await Promise.all([
  readFile(new URL("../src/app.js", import.meta.url), "utf8"),
  readFile(new URL("../src/calendar.js", import.meta.url), "utf8"),
  readFile(new URL("../src/production-dashboard.js", import.meta.url), "utf8"),
  readFile(new URL("../supabase/calendario_compromissos.sql", import.meta.url), "utf8"),
  readFile(new URL("../src/styles.css", import.meta.url), "utf8"),
  readFile(new URL("../index.html", import.meta.url), "utf8"),
]);

for (const role of ["gestao_plataforma", "gerencia", "administrativo", "financeiro", "diretor_obra", "adjunto", "preparador", "encarregado"]) {
  assert(accessFor({ role }).views.includes("calendar"), `${role} deve ter acesso à Agenda`);
}

assert.match(app, /createCalendarModule/);
assert.match(app, /data-view="calendar"[^>]*>[\s\S]*?Agenda/);
assert.match(app, /id="calendar-view"/);
assert.match(app, /view === "calendar"\) calendarModule\.show\(\)/);

assert.match(calendar, /rpc\/fn_listar_colegas_agenda/);
assert.match(calendar, /MARCAR COLEGAS/);
assert.match(calendar, /data\.getAll\("participantes"\)/);
assert.match(calendar, /p_participantes:participants/);
assert.match(calendar, /data-edit-calendar/);
assert.match(calendar, /data-delete-calendar/);
assert.match(calendar, /platformConfirm/);

assert.match(sql, /create table if not exists public\.compromissos\s*\(/i);
assert.match(sql, /create table if not exists public\.compromissos_participantes/i);
assert.match(sql, /references public\.compromissos\(id\) on delete cascade/i);
assert.match(sql, /fn_pode_ver_compromisso/i);
assert.match(sql, /create or replace function public\.fn_listar_colegas_agenda\(\)/i);
assert.match(sql, /u\.empresa_id=atual\.empresa_id/i);
assert.match(sql, /coalesce\(u\.ativo,true\)/i);
assert.match(sql, /'compromisso_agenda'/);
assert.match(sql, /destinatario_utilizador_id/);
assert.match(sql, /trg_auditoria_compromissos/i);

assert.match(dashboard, /calendar:\s*"AGENDA"/);
assert.match(dashboard, /alert\.tipo === "compromisso_agenda"[\s\S]*?view: "calendar"/);
assert.match(styles, /\.agenda-layout/);
assert.match(styles, /\.agenda-participants/);
assert.match(html, /styles\.css\?v=98/);
assert.match(html, /app\.js\?v=144/);

console.log("Agenda: permissões, marcação de colegas, alertas pessoais, edição, eliminação e interface validados.");
