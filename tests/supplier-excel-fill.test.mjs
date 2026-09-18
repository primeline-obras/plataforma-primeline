import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Excel enrichment never creates suppliers or overwrites populated contacts", async () => {
  const sql = await read("supabase/preencher_fornecedores_fontes_excel.sql");
  assert.doesNotMatch(sql, /insert\s+into\s+public\.fornecedores\s*\(/i);
  assert.match(sql, /case when a\.preencher_email then nullif\(a\.email,''\) else f\.email end/i);
  assert.match(sql, /case when a\.preencher_telefone then nullif\(a\.telefone,''\) else f\.telefone end/i);
  assert.match(sql, /f\.repeticoes_nome=1/i);
  assert.match(sql, /s\.repeticoes_base_fonte=1/i);
});

test("Excel enrichment supports legal suffix matching and skips unsafe source names", async () => {
  const sql = await read("supabase/preencher_fornecedores_fontes_excel.sql");
  assert.match(sql, /unipessoal\|unip\|lda\|ltd/i);
  assert.match(sql, /join fontes s on s\.elegivel/i);
  assert.match(sql, /length\(s\.nome_base\)>=6/i);
});

test("Excel enrichment adds only known zones and historical specialties", async () => {
  const sql = await read("supabase/preencher_fornecedores_fontes_excel.sql");
  assert.match(sql, /z\.zona in \('lisboa_cascais','algarve'\)/i);
  assert.match(sql, /select distinct a\.fornecedor_id,e\.id,'historico'/i);
  assert.match(sql, /on conflict\(fornecedor_id,zona\) do nothing/i);
});
