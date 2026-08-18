import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/controlo_versoes_documentos_alerta_subempreitadas.sql", import.meta.url), "utf8");

test("documentos mostram revisão atual e histórico auditável de envios", () => {
  assert.match(app, /VERSÃO MAIS RECENTE/);
  assert.match(app, /destinatarios/);
  assert.match(app, /enviado_em/);
  assert.match(app, /QUANDO \/ PARA QUEM/);
  assert.match(migration, /idx_documentos_obra_historico_revisoes/);
});

test("execução sem aprovação cria alerta para a gerência e não bloqueia", () => {
  assert.match(migration, /new\.estado = 'em_execucao'/);
  assert.match(migration, /coalesce\(new\.estado_aprovacao_gerencia, ''\) <> 'aprovado'/);
  assert.match(migration, /'gerencia', 'pendente'/);
  assert.match(migration, /after insert or update of estado, estado_aprovacao_gerencia/);
  assert.match(migration, /return new;/);
  assert.doesNotMatch(migration, /raise exception/i);
});
