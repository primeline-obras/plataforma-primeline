import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sql = await readFile(new URL("../supabase/atualizar_obra_120_planeamento_xlsx_20260910.sql", import.meta.url), "utf8");

test("atualização da Obra 120 é restrita, idempotente e validada", () => {
  assert.match(sql, /where numero::text = '120'/i);
  assert.match(sql, /<> 66/);
  assert.match(sql, /update public\.planeamento_itens/i);
  assert.match(sql, /where not exists/i);
  assert.match(sql, /v_divergentes <> 0/i);
  assert.doesNotMatch(sql, /delete from public\.planeamento_itens/i);
});

test("datas e percentagens críticas seguem a folha recebida", () => {
  assert.match(sql, /'F04\.7'[\s\S]*date '2026-05-07'[\s\S]*date '2026-08-07'[\s\S]*15, 95, 14\.25/);
  assert.match(sql, /'F05\.10'[\s\S]*date '2026-10-26'[\s\S]*date '2026-11-05'[\s\S]*7, 95, 6\.65/);
  assert.match(sql, /'F07\.4'[\s\S]*date '2026-11-26'[\s\S]*date '2026-12-03'[\s\S]*10, 10, 1/);
});
