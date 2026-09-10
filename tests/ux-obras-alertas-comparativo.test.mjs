import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { alertTopic, groupAlertsByTopic } from "../src/production-dashboard.js";
import { managementFilterWorks } from "../src/management-map.js";

const read = path => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("alertas são agrupados por tema e mantêm prioridade dentro do grupo", () => {
  const groups = groupAlertsByTopic([
    { tipo: "aniversario", titulo: "Aniversário", data_gatilho: "2026-09-10" },
    { tipo: "seguro_viatura", titulo: "Seguro", data_gatilho: "2026-09-12" },
    { tipo: "consulta_medicina", titulo: "Consulta", data_gatilho: "2026-09-11" },
    { tipo: "pagamento_fatura", titulo: "Pagamento", data_gatilho: "2026-09-10" },
    { tipo: "rnc_obra", titulo: "RNC", obra_id: "obra-1", data_gatilho: "2026-09-10" },
  ]);
  assert.deepEqual(groups.map(group => group.topic), ["safety", "people", "finance", "production"]);
  assert.equal(alertTopic({ tipo: "seguro_viatura" }), "safety");
  assert.deepEqual(groups.find(group => group.topic === "people").alerts.map(alert => alert.tipo), ["consulta_medicina", "aniversario"]);
});

test("obras usam seletor recolhível e detalhe a toda a largura", async () => {
  const app = await read("src/app.js");
  const css = await read("src/visual-identity-final.css");
  assert.match(app, /id="work-picker-toggle"/);
  assert.match(app, /id="works-picker-panel" hidden/);
  assert.match(css, /\.works-layout\s*\{\s*display:\s*block/);
  assert.match(css, /\.works-list\s*\{[^}]*grid-template-columns:\s*repeat\(3/);
});

test("comparativo e MGO apresentam matrizes orientadas à leitura", async () => {
  const comparison = await read("src/comparative-map.js");
  const management = await read("src/management-map.js");
  const css = await read("src/visual-identity-final.css");
  const migration = await read("supabase/mgo_grelha_excel_leitura_tecnica.sql");
  assert.match(comparison, /comparison-price-best/);
  assert.match(css, /\.comparison-table thead th\s*\{[^}]*position:\s*sticky/);
  assert.match(css, /\.comparison-col-description[^}]*position:\s*sticky/);
  assert.match(management, /fn_mapa_gestao_obras_excel/);
  assert.match(management, /response\.status === 404/);
  assert.match(migration, /fn_pode_ver_mapa_gestao_obras/);
  assert.match(migration, /'gestao_plataforma','administrativo','diretor_obra','adjunto','preparador'/);
  assert.match(migration, /unidade_medida text, quantidade numeric/);
  assert.match(management, /DATA[\s\S]*OBRA[\s\S]*FORNECEDOR \/ COLABORADOR[\s\S]*DESCRIÇÃO[\s\S]*UN\. MEDIDA[\s\S]*QUANTIDADE[\s\S]*VALOR UNITÁRIO[\s\S]*VALOR TOTAL[\s\S]*DATA DE PAGAMENTO[\s\S]*CATEGORIA[\s\S]*DOCUMENTO/);
});

test("filtro do MGO inclui obras históricas presentes nos lançamentos", () => {
  const works = managementFilterWorks(
    [{ id: "obra-118", numero: "118", nome: "Saboia 37" }],
    [
      { obra_id: "obra-118", obra_numero: "118", obra_nome: "Saboia 37" },
      { obra_id: "obra-114", obra_numero: "114", obra_nome: "Bairro do Rosário" },
      { obra_id: "obra-122", obra_numero: "122", obra_nome: "Av Bombeiros Voluntários" },
    ],
  );
  assert.deepEqual(works.map(work => work.numero), ["114", "118", "122"]);
  assert.equal(works.filter(work => work.numero === "118").length, 1);
});
