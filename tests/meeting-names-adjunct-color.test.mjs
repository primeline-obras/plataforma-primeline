import assert from "node:assert/strict";
import fs from "node:fs";

const rooms = fs.readFileSync(new URL("../src/meeting-rooms.js", import.meta.url), "utf8");
const roomSql = fs.readFileSync(new URL("../supabase/salas_reuniao_listar_participantes.sql", import.meta.url), "utf8");
const namesSql = fs.readFileSync(new URL("../supabase/nomes_reais_utilizadores_reunioes.sql", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const calendar = fs.readFileSync(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");

assert.match(roomSql, /select u\.id, u\.nome, u\.funcao/);
assert.match(rooms, /show:\s*\(\)\s*=>\s*load\(true\)/);
assert.doesNotMatch(rooms, /Administrativo Geral|Financeiro Primeline/);
assert.match(namesSql, /geral@primeline\.pt'[\s\S]*Belmira Maria Godinho Quental/);
assert.match(namesSql, /financeiro@primeline\.pt'[\s\S]*Natércia da Conceição Santos I\. Rosa Oliveira/);
assert.match(app, /role\.includes\("adjunto"\)\) return "function-adjunct"/);
assert.match(app, /"function-adjunct": "rgba\(61, 90, 158, \.18\)"/);
assert.match(calendar, /vacation-map-row\.function-adjunct[^}]*rgba\(61, 90, 158, \.18\)/);
assert.match(calendar, /vacation-map-row\.function-adjunct > strong[^}]*#3d5a9e/);
assert.match(calendar, /workforce-magnet\.function-adjunct[^}]*#3d5a9e/);

console.log("Nomes das salas sem cache e cor de Adjunto validados.");
