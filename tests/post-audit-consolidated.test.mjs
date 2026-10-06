import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { runInNewContext } from "node:vm";

const root = new URL("../", import.meta.url);
const read = path => readFile(new URL(path, root), "utf8");
const [app, planning, dashboard, documents, access, sql] = await Promise.all([
  read("src/app.js"), read("src/planning.js"), read("src/production-dashboard.js"),
  read("src/documents.js"), read("src/access-control.js"), read("supabase/correcoes_pos_auditoria_custos_faturas.sql"),
]);

test("Reunião Semanal é sempre só leitura e a edição de custos vive no Resumo", () => {
  const meeting = dashboard.slice(dashboard.indexOf('async function openMeeting('), dashboard.indexOf('async function openMeeting(') + 10000);
  assert.match(meeting, /costEditMode = false/);
  assert.match(meeting, /renderCostTrace\(projection, false\)/);
  assert.match(dashboard, /data-work-cost-card/);
  assert.match(dashboard, /async function showWorkCosts/);
  // Delegated listeners remain, but every mutation handler checks the edit context.
  for (const name of ['saveCostAdjustment','deleteCostAdjustment','confirmPlCost','confirmSubcontractCost']) {
    const body = dashboard.slice(dashboard.indexOf(`async function ${name}(`));
    assert.match(body.slice(0,600), /!canAdjustWorkCosts\(\)/);
  }
});

test("Planeamento usa o modelo único e o Encarregado recebe uma grelha só de consulta", () => {
  assert.match(planning, /rpc\/fn_resumo_custos_obra/);
  assert.match(planning, /requestPlanningBatch\(supabase, payload, server.confirmation_token\)/);
  assert.doesNotMatch(planning, /rpc\/fn_concluir_custos_pl_tarefa/);
  assert.doesNotMatch(planning, /fn_resumo_custos_estimados_obra|fn_confirmar_compromisso_subempreitada/);
  assert.match(planning, /O ENCARREGADO NÃO PODE CRIAR, EDITAR OU APAGAR TAREFAS/);
  assert.match(sql, /'PL','subempreitada','misto'/);
});

test("Custos filtram pagamentos e faturação ao cliente e protegem a venda por TEE", () => {
  assert.match(sql, /pagamentos_subempreitada[\s\S]*estado_pagamento[\s\S]*estado_aprovacao/);
  assert.match(sql, /public\.faturacao/);
  assert.match(sql, /trg_bloquear_venda_contrato_direta/);
  assert.match(sql, /trg_recalcular_venda_contrato_tee/);
  assert.match(sql, /p_item_orcamento_id/);
});

test("Faturas expõem e operam os cinco estados e permitem apagar guias/anexos", () => {
  for (const state of ["recebida", "em_validacao", "aprovada_tecnicamente", "enviada_financeiro", "paga"]) {
    assert.match(app, new RegExp(state)); assert.match(sql, new RegExp(state));
  }
  assert.match(app, /fn_avancar_estado_fluxo_fatura/);
  assert.match(app, /data-delete-invoice-guide/);
  assert.match(app, /data-delete-invoice-attachment/);
  assert.match(sql, /fn_apagar_guia_fatura/);
  assert.match(sql, /fn_apagar_anexo_fatura/);
});

test("Arranque falha fechado antes de carregar dados; diálogos nativos não são usados", async () => {
  // An unused import is not a login fallback. Execute the actual fail-closed branch.
  const guard = app.slice(app.indexOf('async function loadData() {') + 'async function loadData() {'.length, app.indexOf('  await loadAccessContext();', app.indexOf('async function loadData() {')));
  const controls = [{disabled:false}, {disabled:false}];
  const nodes = {'#login-form':{querySelectorAll:()=>controls}, '#auth-error':{textContent:''}, '#auth-screen':{hidden:true}};
  runInNewContext(`(function(){${guard}})()`, {isSupabaseConfigured:false, $:selector=>nodes[selector], getSession:()=>{throw Error('não deve consultar a sessão');}});
  assert.ok(controls.every(c=>c.disabled)); assert.equal(nodes['#auth-screen'].hidden,false);
  assert.match(nodes['#auth-error'].textContent, /acesso foi bloqueado/);
  assert.equal((app.match(/\bdemo(?:Invoices|Works|Suppliers|Subcontracts)\b/g)||[]).length,4,'constantes importadas não alimentam dados');
  assert.match(app, /Configuração segura indisponível[\s\S]*acesso foi bloqueado/);
  const names = (await readdir(new URL("src/", root))).filter(name => name.endsWith(".js"));
  const sources = await Promise.all(names.map(name => read(`src/${name}`)));
  for (const source of sources) {
    assert.doesNotMatch(source, /\bwindow\.(?:prompt|alert|confirm)\s*\(/);
    // The Folha client intentionally accepts an injected asynchronous confirm adapter.
    if (!/export function \w+\(\{[^)]*\bconfirm\b/.test(source)) assert.doesNotMatch(source, /(?<![.\w])(?:prompt|alert|confirm)\s*\(/);
  }
});

test("Definições e Planeamento respeitam a matriz de papéis", () => {
  assert.match(access, /encarregado:[\s\S]*?planning/);
  assert.match(app, /isAdmin: \(\) => hasFullAccess\(\) \|\| isAdministrative\(\)/);
  assert.match(access, /const NO_ACCESS[\s\S]*views: \["settings"\]/);
});

test("CRUD pós-auditoria tem caminhos restritos e auditados", () => {
  for (const rpc of ["fn_cancelar_rnc", "fn_editar_rnc_base", "fn_apagar_anexo_rnc", "fn_gerir_registo_frota", "fn_apagar_anexo_imovel", "fn_apagar_anexo_pedido_orcamento"]) assert.match(sql, new RegExp(rpc));
  for (const table of ["viaturas_eventos", "viaturas_sinistros", "multas", "imoveis_anexos", "pedidos_orcamento_anexos"]) assert.match(sql, new RegExp(table));
  assert.match(sql, /fn_registar_log_auditoria/);
});

test("Documentos mostram todas as revisões e destinatários nos dois contextos", () => {
  assert.doesNotMatch(documents, /latestByDocumentNumber/);
  assert.match(documents, /HISTÓRICO COMPLETO DOS DESENHOS/);
  assert.match(documents, /ENVIADO PARA/);
  assert.match(documents, /destinatarios/);
});
