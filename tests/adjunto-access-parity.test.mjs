import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/adjunto_acesso_equipa_tecnica.sql", import.meta.url), "utf8");
const rnc = await readFile(new URL("../src/rnc.js", import.meta.url), "utf8");

test("Adjunto pode ver e editar as obras onde integra a Equipa Técnica", () => {
  assert.match(migration, /u\.funcao in \('diretor_obra', 'adjunto', 'preparador'\)/);
  assert.match(migration, /r\.papel in \('diretor_obra', 'adjunto', 'preparador'\)/);
  assert.match(migration, /create or replace function public\.fn_pode_ver_obra/);
  assert.match(migration, /create or replace function public\.fn_pode_editar_obra/);
});

test("Adjunto conserva a criação de RNC disponível ao Preparador", () => {
  assert.match(rnc, /\["gerencia", "diretor_obra", "adjunto", "preparador", "encarregado"\]\.includes\(getRole\(\)\)/);
});
