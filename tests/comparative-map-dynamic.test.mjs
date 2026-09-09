import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { calculateBestPrices, calculateCosting } from "../src/comparative-map.js";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("schema relacional aceita N propostas e contém os quatro blocos pedidos", async () => {
  const sql = await read("supabase/mapa_comparativo_dinamico.sql");
  for (const table of ["mapas_comparativos", "comparativo_propostas", "comparativo_itens", "comparativo_itens_precos", "comparativo_ajustes"]) assert.match(sql, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(sql, /nota_primeline text/);
  assert.match(sql, /preco_unitario\*v_quantidade/);
  assert.match(sql, /min\(p\.preco_total\)/);
  assert.match(sql, /valor_adjudicado_real - melhor_preco_comparativo/);
  assert.match(sql, /preco_venda - valor_adjudicado_real/);
  assert.doesNotMatch(sql, /preco_venda - melhor_preco_comparativo/);
  assert.match(sql, /valor_adjudicado[\s\S]*v_mapa\.valor_adjudicado_real/);
});

test("melhor preço ignora proposta sem cotação para um item", () => {
  const items = [{ id: "i1" }, { id: "i2" }];
  const proposals = [{ id: "a" }, { id: "b" }, { id: "c" }];
  const prices = [
    { item_id: "i1", proposta_id: "a", preco_total: 100 },
    { item_id: "i1", proposta_id: "b", preco_total: 90 },
    // A proposta C não cotou i1 e deve ser ignorada, não tratada como zero.
    { item_id: "i2", proposta_id: "a", preco_total: 60 },
    { item_id: "i2", proposta_id: "c", preco_total: 70 },
  ];
  const result = calculateBestPrices(items, proposals, prices);
  assert.deepEqual(result.winners, [
    { item_id: "i1", proposta_id: "b", melhor_preco: 90 },
    { item_id: "i2", proposta_id: "a", melhor_preco: 60 },
  ]);
  assert.equal(result.soma_dos_menores, 150);
});

test("margem real usa o adjudicado e nunca o melhor preço", () => {
  const result = calculateCosting({ melhor_preco: 80, custo_estimado: 95, valor_adjudicado: 100, preco_venda: 140 });
  assert.equal(result.negotiation, 20);
  assert.equal(result.budgetDeviation, 5);
  assert.equal(result.margin, 40);
  assert.equal(result.marginPct, 40 / 140 * 100);
  assert.notEqual(result.margin, 140 - 80);
});

test("editar abre itens e propostas com os valores existentes", async () => {
  const frontend = await read("src/comparative-map.js");
  assert.match(frontend, /data-item-field="numero" value="\$\{esc\(item\.numero\)\}"/);
  assert.match(frontend, /data-item-field="designacao" value="\$\{esc\(item\.designacao\)\}"/);
  assert.match(frontend, /supplierOptions\(proposal\.fornecedor_id\)/);
  for (const field of ["data_proposta", "prazo_validade", "contacto", "telemovel", "condicoes_pagamento", "exclusoes_ambito", "outras_informacoes", "nota_primeline"]) {
    assert.match(frontend, new RegExp(`proposal\\.${field}`), `${field} deve ser pré-preenchido.`);
  }
  assert.match(frontend, /Proposta atualizada sem perder preços ou ajustes/);
});

test("eliminar exige confirmação e usa RPCs que verificam a cascata", async () => {
  const frontend = await read("src/comparative-map.js");
  const deletion = await read("supabase/mapa_comparativo_editar_eliminar.sql");
  const cascadeTest = await read("supabase/teste_mapa_comparativo_editar_eliminar.sql");
  assert.match(frontend, /CONFIRMAR\?/);
  assert.match(frontend, /data-confirm-delete-\$\{type\}/);
  assert.match(frontend, /\[data-confirm-delete-\$\{type\}\]/);
  assert.match(frontend, /fn_eliminar_item_comparativo/);
  assert.match(frontend, /fn_eliminar_proposta_comparativo/);
  assert.match(deletion, /precos_restantes[\s\S]*v_precos_depois/);
  assert.match(deletion, /ajustes_restantes[\s\S]*v_ajustes_depois/);
  assert.match(cascadeTest, /Ajuste de escopo temporário/);
  assert.match(cascadeTest, /rollback;/i);
  assert.match(cascadeTest, /v_precos_depois <> 0 or v_ajustes_depois <> 0/);
});

test("eliminar o mapa completo preserva adjudicações e verifica todos os descendentes", async () => {
  const frontend = await read("src/comparative-map.js");
  const deletion = await read("supabase/eliminar_mapa_comparativo.sql");
  assert.match(frontend, /deleteActions\("map", map\.id\)/);
  assert.match(frontend, /fn_eliminar_mapa_comparativo/);
  assert.match(frontend, /mapas_restantes/);
  assert.match(deletion, /subempreitadas where mapa_comparativo_id = p_mapa_id/);
  assert.match(deletion, /histórico da adjudicação deve ser preservado/);
  for (const field of ["mapas_restantes", "itens_restantes", "propostas_restantes", "precos_restantes", "ajustes_restantes"]) {
    assert.match(deletion, new RegExp(`'${field}'`));
  }
});
