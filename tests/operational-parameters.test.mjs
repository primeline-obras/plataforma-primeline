import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sql = await readFile(new URL("../supabase/parametros_operacionais.sql", import.meta.url), "utf8");
const settings = await readFile(new URL("../src/settings.js", import.meta.url), "utf8");

const expected = [
  ["valor_minimo_contrato_subempreitada", "5000"],
  ["antecedencias_alerta_contrato_rh", "60,45,30"],
  ["antecedencia_alerta_documento_colaborador", "30"],
  ["antecedencia_alerta_epi", "30"],
  ["antecedencia_alerta_medicina", "30"],
  ["antecedencia_alerta_viatura_inspecao", "15"],
  ["antecedencia_alerta_viatura_seguro", "15"],
  ["antecedencias_alerta_documento_empresa", "15,7,3"],
  ["antecedencias_alerta_pedido_orcamento", "15,7,3"],
  ["antecedencia_alerta_reuniao_condominio", "7"],
];

test("migration seeds all operational parameters with established defaults", () => {
  for (const [key, value] of expected) {
    assert.match(sql, new RegExp(`'${key}'[\\s\\S]{0,180}'${value}'`));
  }
});

test("business functions read dynamic operational parameters", () => {
  assert.match(sql, /fn_limite_contrato_subempreitada\(\)[\s\S]*fn_parametro_operacional_numero\([\s\S]*valor_minimo_contrato_subempreitada/);
  assert.doesNotMatch(sql, /fn_limite_contrato_subempreitada\(\)[\s\S]{0,180}select\s+5000::numeric/);
  for (const [key] of expected.slice(1)) assert.match(sql, new RegExp(key));
});

test("only administrators can view and update parameter values", () => {
  assert.match(sql, /parametros_operacionais_select_admin[\s\S]*using \(public\.fn_e_admin\(\)\)/);
  assert.match(sql, /parametros_operacionais_update_admin[\s\S]*with check \(public\.fn_e_admin\(\)\)/);
  assert.match(sql, /grant update \(valor\)/);
  assert.match(sql, /new\.atualizado_por := public\.fn_utilizador_atual_id\(\)/);
  assert.match(sql, /new\.atualizado_em := now\(\)/);
});

test("settings exposes an admin parameters editor and persists edits", () => {
  assert.match(settings, /data-settings-admin-tab="parameters"/);
  assert.match(settings, /parametros_operacionais\?select=chave,descricao,valor,atualizado_por,atualizado_em/);
  assert.match(settings, /data-parameter-form/);
  assert.match(settings, /method: "PATCH"/);
  assert.match(settings, /Prefer: "return=representation"/);
});

test("migration documents a reversible live-value test at 6000 euros", () => {
  assert.match(sql, /set valor = '6000'[\s\S]*deve_ser_6000[\s\S]*rollback/);
});
