import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(new URL("../supabase/classificacao_especialidades_lote_inicial.sql", import.meta.url), "utf8");

test("o lote contém apenas Alta/Média e valida as contagens do PDF", () => {
  assert.doesNotMatch(sql, /'Baixa'|'Não identificado'/);
  assert.match(sql, /<> 97/);
  assert.match(sql, /<> 99/);
  assert.match(sql, /check \(confianca in \('Alta', 'Média'\)\)/);
});

test("os dois pares de possíveis duplicados ficam excluídos", () => {
  const values = sql.slice(sql.indexOf("insert into lote_classificacao_especialidades"), sql.indexOf("do $$"));
  for (const name of [
    "Ruben Ramos - Transp. Especiais, Lda",
    "Ruben Ramos Tranp Especiais, Lda",
    "Loja do Campo, Lda (WeGarden)",
    "WeGarden (Loja do Campo, Lda)",
  ]) assert.doesNotMatch(values, new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

test("a carga é transacional, idempotente e aborta nomes não resolvidos", () => {
  assert.match(sql, /^begin;/m);
  assert.match(sql, /on conflict \(fornecedor_id, especialidade_id\) do nothing/);
  assert.match(sql, /Fornecedor não encontrado/);
  assert.match(sql, /Especialidade não encontrada/);
  assert.match(sql, /raise exception/);
  assert.match(sql, /commit;/);
});
