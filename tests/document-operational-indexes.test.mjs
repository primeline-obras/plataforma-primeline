import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const pdf = await readFile(new URL("../src/document-index-pdf.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/indices_pdes_desenhos_pames_pdf.sql", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/workforce-calendar.css", import.meta.url), "utf8");
const identity = await readFile(new URL("../src/visual-identity-final.css", import.meta.url), "utf8");

test("a migração completa PDEs e Desenhos sem restringir estados livres", () => {
  assert.match(migration, /alter table public\.rfis[\s\S]*?revisao text[\s\S]*?data_emissao date[\s\S]*?notas text/);
  assert.match(migration, /alter table public\.desenhos[\s\S]*?data_envio_do date[\s\S]*?data_resposta_do date[\s\S]*?notas text/);
  assert.doesNotMatch(migration, /check\s*\(\s*estado\s+in/i);
  assert.match(migration, /cada documento\/revisão é uma linha própria/i);
});

test("PAME tem schema, RLS e sincronização a partir de documentos da obra", () => {
  for (const column of ["id", "obra_id", "numero", "descricao", "revisao", "data_emissao", "data_envio", "data_resposta", "estado", "notas"]) {
    assert.match(migration, new RegExp(`\\b${column}\\b`));
  }
  assert.match(migration, /create policy pl_pames_select/);
  assert.match(migration, /create policy pl_pames_write/);
  assert.match(migration, /new\.tipo = 'pames'/);
});

test("cada revisão de desenho permanece uma linha e não é agrupada pela versão mais recente", () => {
  assert.doesNotMatch(app, /function latestDrawingRows/);
  assert.match(app, /const drawings = sortedIndexRows\(workDetails\.drawings\)/);
  assert.match(app, /numero\.asc,revisao\.desc/);
});

test("os quatro índices expõem as colunas operacionais e Exportar PDF", () => {
  for (const kind of ["pdes", "desenhos", "pames", "tees"]) {
    assert.match(app, new RegExp(`kind: "${kind}"`));
    assert.match(pdf, new RegExp(`\\b${kind}: \\{`));
  }
  assert.match(app, /data-export-index-pdf/);
  assert.match(app, /data_resposta", label: "Data de Aprovação"/);
  assert.match(app, /Data Envio DO/);
  assert.match(app, /Resposta DO\/Fiscalização/);
  assert.match(app, /Valor \(s\/IVA\)/);
  assert.match(app, /Aprovado \(S\/N\)/);
  assert.match(app, /tee\.estado_aprovacao_cliente === "aprovado" \? "Sim" : "Não"/);
  assert.doesNotMatch(app, /tee\.estado_aprovacao_gerencia/);
  assert.equal((pdf.match(/\["data_resposta", "Data de Aprovação"/g) || []).length, 2);
  assert.match(pdf, /\["data_resposta", "Data Resposta", 27/);
  assert.match(pdf, /\["data_resposta_do", "Resposta DO\/Fisc\."/);
});

test("os cinco índices têm um separador próprio e deixam de estar escondidos em Documentos", () => {
  assert.match(app, /data-work-tab="indexes"[^>]*>ÍNDICES<\/button>/);
  assert.match(app, /selectedWorkTab === "indexes"\) return renderDocumentIndexes\(\)/);

  const documentsTab = app.slice(
    app.indexOf("function renderWorkDocumentsTab()"),
    app.indexOf("function renderWorkTab(work)"),
  );
  assert.doesNotMatch(documentsTab, /renderDocumentIndexes\(\)/);
  assert.equal((app.match(/kind: "(?:pdes|desenhos|pames|tees|prorrogacoes)"/g) || []).length, 5);
});

test("o PDF é standalone, paginado e mantém cores de estado", () => {
  assert.match(pdf, /orientation: "landscape"/);
  assert.match(pdf, /Data de referência/);
  assert.match(pdf, /pdf\.addPage/);
  assert.match(pdf, /STATUS_COLORS/);
  assert.match(pdf, /definition\.columns\.forEach[\s\S]*?pdf\.setFillColor\(52, 59, 63\)[\s\S]*?pdf\.rect/);
  assert.match(pdf, /pdf\.save/);
  assert.match(styles, /\.document-index-table-wrap/);
});

test("as linhas do índice de TEEs usam a aprovação do cliente e a paleta existente", () => {
  assert.match(app, /tee-index-row \$\{indexStateClass\(item\.estado_aprovacao_cliente \|\| "pendente"\)\}/);
  assert.match(identity, /tee-index-row\.aprovado > td \{ background: rgba\(63, 98, 72, \.15\)/);
  assert.match(identity, /tee-index-row\.pendente > td \{ background: rgba\(138, 100, 32, \.15\)/);
  assert.match(identity, /tee-index-row\.recusado > td \{ background: rgba\(140, 74, 64, \.15\)/);
  assert.match(pdf, /TEE_APPROVAL_ROW_COLORS/);
  assert.match(pdf, /aprovado: \[226, 232, 227\]/);
  assert.match(pdf, /pendente: \[237, 232, 222\]/);
  assert.match(pdf, /recusado: \[238, 227, 226\]/);
  assert.match(pdf, /kind === "tees" \? TEE_APPROVAL_ROW_COLORS\[row\.estado_aprovacao_cliente\]/);
});
