import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("migração consolida PL, misto e compromisso de subempreitada", async () => {
  const sql = await read("supabase/custos_estimados_consolidado.sql");
  assert.match(sql, /add column if not exists executado_por text/);
  assert.match(sql, /add column if not exists custo_estado text/);
  assert.match(sql, /add column if not exists valor_estimado numeric/);
  assert.match(sql, /add column if not exists compromisso_confirmado boolean/);
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
  assert.match(source, /Array\.isArray\(componentPayload\)/);
  assert.match(source, /row\.valor_orca_pl \?\? row\.valor_orcamentado/);
  assert.doesNotMatch(source, /rpc\/fn_resumo_componentes_custo_obra/);
  assert.match(source, /ORÇAMENTO DE CUSTO AINDA NÃO CARREGADO/);
});

test("migração histórica do orçamento é limitada e idempotente", async () => {
  const migration = await read("supabase/migrar_itens_orcamento_para_fases.sql");
  assert.match(migration, /o\.numero in \(118, 120, 128\)/i);
  assert.match(migration, /coalesce\(io\.custo_materiais, 0\)/i);
  assert.match(migration, /coalesce\(io\.custo_mao_obra, 0\)/i);
  assert.match(migration, /on conflict \(fase_id\) do nothing/i);
  assert.match(migration, /Recuperação de itens_orcamento históricos/i);
});

test("importador separa custo PL dos valores subcontratados", async () => {
  const importer = await read("src/xlsx-operational-import.js");
  assert.match(importer, /const plComponents = \["deslocacoes", "mao_obra", "maquinas", "materiais"\]/);
  assert.match(importer, /const total = hasPlBreakdown \? plComponents/);
});

test("planeamento aceita tarefas mistas e remete confirmação para o card", async () => {
  const source = await read("src/planning.js");
  assert.match(source, /value="misto"/);
  assert.match(source, /VALOR ORÇA PL/);
  assert.match(source, /CONFIRMAÇÃO PENDENTE NO CARD/);
  assert.doesNotMatch(source, /data-confirm-subcontract-cost/);
});
