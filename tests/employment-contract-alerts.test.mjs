import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sql = await readFile(
  new URL("../supabase/bloco_07_contratos_trabalho.sql", import.meta.url),
  "utf8",
);

assert.match(sql, /array array\[60, 45, 30\]/);
assert.match(sql, /cc\.tipo_contrato = 'a_prazo'/);
assert.match(sql, /cc\.estado = 'ativo'/);
assert.match(sql, /c\.data_saida is null/);
assert.match(sql, /data_evento_referencia/);
assert.match(sql, /antecedencia_dias/);
assert.match(sql, /on conflict do nothing/);
assert.match(sql, /drop trigger if exists trg_alerta_fim_contrato/);
assert.match(sql, /perform public\.fn_verificar_alertas_fim_contrato\(\)/);
assert.doesNotMatch(sql, /alter table public\.colaboradores_contratos/);

console.log("Alertas escalonados de contratos de trabalho validados.");
