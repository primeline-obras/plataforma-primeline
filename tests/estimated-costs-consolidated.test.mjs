import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("migração consolida PL, misto e compromisso de subempreitada", async () => {
  const sql = await read("supabase/custos_estimados_consolidado.sql");
  assert.match(sql, /executado_por in \('PL','subempreitada','misto'\)/);
  assert.match(sql, /fn_confirmar_custo_real_pl/);
  assert.match(sql, /v_item\.estado<>'concluido'/);
  assert.match(sql, /pagamentos_subempreitada/);
  assert.match(sql, /compromisso.*adjudicado confirmado/si);
  assert.match(sql, /Custos Estimados = PL por concluir \+ adjudicações por confirmar/);
});

test("card da obra confirma custos e RSP reutiliza-o em leitura", async () => {
  const source = await read("src/production-dashboard.js");
  assert.match(source, /FÓRMULA APLICADA/);
  assert.match(source, /data-confirm-pl-cost/);
  assert.match(source, /data-confirm-sub-cost/);
  assert.match(source, /renderCostTrace\(projection, false\)/);
  assert.match(source, /const canEdit = editable && canAdjustWorkCosts\(\)/);
});

test("planeamento aceita tarefas mistas e remete confirmação para o card", async () => {
  const source = await read("src/planning.js");
  assert.match(source, /value="misto"/);
  assert.match(source, /VALOR ORÇA PL/);
  assert.match(source, /CONFIRMAÇÃO PENDENTE NO CARD/);
  assert.doesNotMatch(source, /data-confirm-subcontract-cost/);
});
