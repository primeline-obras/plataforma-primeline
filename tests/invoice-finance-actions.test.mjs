import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_acoes_financeiro_pos_pagamento.sql", import.meta.url), "utf8");

assert.match(app, /data-unmark-paid/);
assert.match(app, /rpc\/fn_desmarcar_fatura_paga/);
assert.match(app, /data-finance-attachment-input/);
assert.match(app, /rpc\/fn_devolver_fatura_financeiro/);
assert.match(app, /A observação é obrigatória/);
assert.match(app, /observacao_devolucao/);
assert.match(app, /invoiceTraceEvents/);
assert.match(css, /finance-return-note/);

assert.match(sql, /create table if not exists public\.faturas_eventos/i);
assert.match(sql, /create or replace function public\.fn_desmarcar_fatura_paga/i);
assert.match(sql, /create or replace function public\.fn_devolver_fatura_financeiro/i);
assert.match(sql, /estado_aprovacao = 'pendente'/i);
assert.match(sql, /nullif\(btrim\(p_observacao\), ''\) is null/i);
assert.match(sql, /public\.fn_e_financeiro\(\)/i);
assert.match(sql, /or public\.fn_e_financeiro\(\)/i);
assert.match(sql, /trg_evento_anexo_fatura/i);
assert.match(sql, /jsonb_agg/i);

console.log("Ações financeiras pós-pagamento e respetivo rastreio validados.");
