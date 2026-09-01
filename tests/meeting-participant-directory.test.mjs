import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../src/meeting-rooms.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/salas_reuniao_listar_participantes.sql", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

assert.match(source, /rpc\/fn_listar_participantes_reuniao/);
assert.doesNotMatch(source, /utilizadores\?select=id,nome,funcao,auth_user_id,ativo/);
assert.match(sql, /u\.empresa_id = v_atual\.empresa_id/);
assert.match(sql, /u\.ativo is true/);
assert.match(sql, /u\.auth_user_id is not null/);
assert.doesNotMatch(sql, /obra_responsaveis/);
assert.match(css, /grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
assert.match(css, /@media \(max-width: 1100px\)[\s\S]*grid-template-columns:1fr/);

console.log("Meeting participant directory and pending invoice grid validated.");
