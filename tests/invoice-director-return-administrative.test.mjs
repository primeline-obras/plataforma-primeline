import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/faturas_devolucao_diretor_administrativo.sql", import.meta.url), "utf8");

test("Diretor e Adjunto têm devolução explícita com nota obrigatória", () => {
  assert.match(app, /function canReturnInvoiceToAdministrative/);
  assert.match(app, /\["diretor_obra", "adjunto", "gestao_plataforma", "gerencia"\]/);
  assert.doesNotMatch(app.slice(app.indexOf("function canReturnInvoiceToAdministrative"), app.indexOf("function canDeleteInvoiceFiles")), /preparador/);
  assert.match(app, /data-return-administrative/);
  assert.match(app, /data-detail-return-administrative/);
  assert.match(app, /platformPrompt[\s\S]*NOTA OBRIGATÓRIA/);
  assert.match(app, /rpc\/fn_devolver_fatura_administrativo/);
  assert.match(styles, /\.invoice-return-administrative/);
});

test("A fatura devolvida fica numa fila própria até o Administrativo corrigir", () => {
  assert.match(app, /devolvida_administrativo/);
  assert.match(app, /estado_fluxo=in\.\(recebida,em_validacao,aprovada_tecnicamente,devolvida_administrativo\)/);
  assert.match(app, /DEVOLVIDA AO ADMINISTRATIVO/);
  assert.match(app, /Corrija a fatura e guarde as alterações para a reenviar ao Diretor/);
  assert.match(sql, /fn_proteger_fatura_devolvida_administrativo/);
  assert.match(sql, /A fatura aguarda correção do Administrativo e não pode ser aprovada/);
  assert.match(sql, /v_foi_devolvida or \(v_fatura\.criado_por/);
  assert.match(sql, /estado_fluxo = case when v_foi_devolvida then 'recebida'/);
});

test("A devolução e a correção ficam no histórico, sem prompts nativos", () => {
  assert.match(sql, /'devolvida_administrativo'/);
  assert.match(sql, /'corrigida_reenviada'/);
  assert.match(sql, /insert into public\.faturas_eventos/);
  assert.match(app, /devolvida_administrativo: "DEVOLVIDA AO ADMINISTRATIVO"/);
  assert.match(app, /corrigida_reenviada: "CORRIGIDA E REENVIADA"/);
  assert.match(app, /import \{ platformConfirm, platformPrompt \} from "\.\/platform-dialogs\.js\?v=2"/);
  assert.doesNotMatch(app, /window\.confirm\(/);
  assert.doesNotMatch(app, /window\.prompt\(/);
});

console.log("Fluxo Diretor → Administrativo → Diretor validado.");
