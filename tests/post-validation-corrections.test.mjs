import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const rooms = readFileSync(new URL("../src/meeting-rooms.js", import.meta.url), "utf8");
const roomsSql = readFileSync(new URL("../supabase/salas_reuniao_listar_participantes.sql", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/correcoes_pos_validacao_encarregado_utilizadores.sql", import.meta.url), "utf8");

test("Rastreio de Faturas usa reticências UTF-8 corretas", () => {
  assert.match(app, /placeholder="Pesquisar fornecedor, documento ou obra…"/);
  assert.doesNotMatch(app, /obraâ€¦/);
});

test("sidebar e cartões das Salas mostram apenas primeiro e último nome", () => {
  assert.match(app, /const displayName = shortPersonName\(label\)/);
  assert.match(app, /\#user-name"\)\.title = label/);
  assert.match(rooms, /shortPersonName\(user\.nome\)/);
  assert.match(rooms, /title="\$\{esc\(user\.nome\)\}"/);
});

test("listas operacionais excluem sempre utilizadores inativos", () => {
  assert.match(app, /utilizadores\?select=id,nome,funcao,auth_user_id,ativo&ativo=eq\.true/);
  assert.match(roomsSql, /utilizadores\.ativo is true/);
  assert.match(roomsSql, /u\.ativo is true/);
  assert.match(migration, /u\.ativo is true/);
});
