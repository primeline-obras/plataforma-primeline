import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/classificacao_especialidades_lote_2.sql", import.meta.url), "utf8");
const values = sql.slice(sql.indexOf("insert into lote_2_classificacao"), sql.indexOf("do $$"));

test("o lote 2 contém exatamente as 18 classificações confirmadas", () => {
  assert.equal((values.match(/^  \('/gm) || []).length, 18);
  assert.match(sql, /<> 18/);
  assert.match(values, /'Desafio Ótimo, Lda', 'MUDANÇAS'/);
});

test("Domintegra permanece pendente e fora da carga", () => {
  assert.doesNotMatch(values, /Domintegra/);
  assert.match(sql, /Domintegra deve permanecer pendente/);
});

test("a carga cria a categoria nova e é transacional e idempotente", () => {
  assert.match(sql, /insert into public\.especialidades/);
  assert.match(sql, /aplicavel_subempreiteiro = true/);
  assert.match(sql, /on conflict \(fornecedor_id, especialidade_id\) do nothing/);
  assert.match(sql, /^begin;/m);
  assert.match(sql, /commit;/);
});
