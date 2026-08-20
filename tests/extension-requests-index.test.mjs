import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const pdf = await readFile(new URL("../src/document-index-pdf.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/pedidos_prorrogacao_indice_pdf.sql", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");

test("pedidos de prorrogação têm schema aditivo, estados controlados e ligação opcional ao TEE", () => {
  assert.match(migration, /create table if not exists public\.pedidos_prorrogacao/);
  for (const column of ["id", "obra_id", "tee_id", "numero", "motivo", "dias_solicitados", "data_pedido", "data_resposta", "estado", "notas"]) {
    assert.match(migration, new RegExp(`\\b${column}\\b`));
  }
  assert.match(migration, /obra_id uuid not null references public\.obras/);
  assert.match(migration, /tee_id uuid references public\.alteracoes_tee\(id\) on delete set null/);
  assert.match(migration, /motivo text not null check \(btrim\(motivo\) <> ''\)/);
  assert.match(migration, /check \(estado in \('pendente', 'aprovado', 'recusado'\)\)/);
  assert.match(migration, /t\.id = new\.tee_id and t\.obra_id = new\.obra_id/);
  assert.match(migration, /create policy pl_pedidos_prorrogacao_select/);
  assert.match(migration, /create policy pl_pedidos_prorrogacao_write/);
});

test("o quinto índice carrega por obra e mostra TEE de origem ou travessão", () => {
  assert.match(app, /pedidos_prorrogacao\?select=\*&obra_id=eq\./);
  assert.match(app, /kind: "prorrogacoes"/);
  for (const heading of ["Número", "Motivo", "Dias Solicitados", "TEE de Origem", "Data do Pedido", "Data de Resposta", "Estado", "Notas"]) {
    assert.match(app, new RegExp(heading));
  }
  assert.match(app, /request\.tee_id \? teeNumbers\.get\(request\.tee_id\) \|\| "TEE não disponível" : "—"/);
  assert.match(app, /kind === "tees" \? teeIndexRows\(\)[\s\S]*?: extensionRequestIndexRows\(\)/);
});

test("a exportação PDF de prorrogações replica os oito cabeçalhos e as cores de estado", () => {
  assert.match(pdf, /prorrogacoes: \{/);
  assert.match(pdf, /title: "ÍNDICE DE PEDIDOS DE PRORROGAÇÃO"/);
  for (const heading of ["Número", "Motivo", "Dias Solicitados", "TEE de Origem", "Data do Pedido", "Data de Resposta", "Estado", "Notas"]) {
    assert.match(pdf, new RegExp(`"${heading}"`));
  }
  assert.match(pdf, /definition\.columns\.forEach[\s\S]*?pdf\.setFillColor\(52, 59, 63\)[\s\S]*?pdf\.setTextColor\(255\)/);
  assert.match(styles, /\.index-state\.pendente/);
  assert.match(styles, /\.index-state\.aprovado/);
  assert.match(styles, /\.index-state\.recusado/);
});
