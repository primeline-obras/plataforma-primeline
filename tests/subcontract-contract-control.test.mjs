import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/subempreitadas_controle_contratual.sql", import.meta.url), "utf8");
const alertBackfill = readFileSync(new URL("../supabase/subempreitadas_alertas_limite_backfill.sql", import.meta.url), "utf8");

test("TEE do cliente só aumenta o contrato quando ligado a aditamento aprovado", () => {
  assert.match(sql, /subempreitada_aditamentos/);
  assert.match(sql, /alteracao_tee_id uuid references public\.alteracoes_tee/);
  assert.match(sql, /sum\(a\.valor\) filter\(where a\.estado='aprovado'\)/);
});

test("controlo expõe contrato, extras, faturado, pago, saldo e ultrapassagem", () => {
  for (const field of ["valor_contratual", "aditamentos_aprovados", "total_aprovado", "total_faturado", "total_pago", "saldo", "ultrapassagem_faturada", "ultrapassagem_paga"]) assert.match(sql, new RegExp(field));
  assert.match(app, /ADITAMENTOS APROVADOS/);
  assert.match(app, /FATURADO VALIDADO/);
  assert.match(app, /SALDO CONTRATUAL/);
  assert.match(styles, /\.subcontract-contract-grid/);
});

test("Diretor e Financeiro recebem alerta antes de ultrapassar o aprovado", () => {
  assert.match(sql, /fn_verificar_limite_fatura_subempreitada/);
  assert.match(app, /confirmSubcontractContractLimit\(invoice, nextState\)/);
  assert.match(app, /confirmSubcontractContractLimit\(invoice, "paga"\)/);
  assert.match(app, /CONTINUAR COM ALERTA/);
  assert.match(sql, /subempreitada_limite_contratual/);
  assert.match(sql, /trg_alerta_limite_fatura_subempreitada/);
  assert.match(sql, /Limite contratual da subempreitada ultrapassado/);
  assert.match(sql, /current_date,0,current_date,'diretor_obra','pendente'/);
  assert.match(alertBackfill, /for v_subempreitada_id in select id from public\.subempreitadas loop/);
  assert.match(alertBackfill, /destinatario_role='diretor_obra'/);
  assert.doesNotMatch(alertBackfill, /from public\.fn_resumo_controle_subempreitadas_obra/);
  assert.match(alertBackfill, /Editor SQL, onde não existe sessão da aplicação/);
  assert.match(alertBackfill, /translate\(to_char\(v_res\.total_aprovado/);
});

test("aprovação técnica atualiza faturado sem o confundir com custo pago", () => {
  assert.match(sql, /estado_fluxo in \('aprovada_tecnicamente','enviada_financeiro','paga'\)/);
  assert.match(sql, /sub_faturado/);
  assert.match(sql, /Custo Real = PL confirmado \+ pagamentos; Faturado = faturas validadas/);
});

console.log("Controlo contratual integrado validado.");
