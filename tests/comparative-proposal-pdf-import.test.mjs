import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { normalizeSupplierName, rankSupplierMatches, parsePortugueseAmount, parseProposalText } from "../src/proposal-pdf-import.js";
import { calculateBestPrices } from "../src/comparative-map.js";

test("normaliza sociedades e sugere fornecedores existentes sem criar duplicados", () => {
  assert.equal(normalizeSupplierName("  Mourelec, Lda. "), "mourelec");
  const ranked = rankSupplierMatches("SILVAS - Carpintaria, Unipessoal Lda", [
    { id: "1", nome: "Silvas Carpintaria, Lda" }, { id: "2", nome: "Outro Fornecedor" },
  ]);
  assert.equal(ranked[0].supplier.id, "1");
  assert.ok(ranked[0].score > .6);
});

test("interpreta valores portugueses e preserva total oficial e condições", () => {
  assert.equal(parsePortugueseAmount("14.757,20 €"), 14757.2);
  const parsed = parseProposalText(`SILVAS CARPINTARIA, LDA\nOrçamento nº 2329\nData 10/07/2025\nTOTAL 14.757,20 €\nValidade do orçamento: 30 dias\nCondições de pagamento: 40% adjudicação, restante na entrega\nPrazo de entrega: 8 semanas\nLED não incluído`, "silvas.pdf");
  assert.equal(parsed.reference, "2329");
  assert.equal(parsed.proposalDate, "2025-07-10");
  assert.equal(parsed.officialTotal, 14757.2);
  assert.equal(parsed.validityDays, 30);
  assert.match(parsed.paymentTerms, /40% adjudicação/);
  assert.match(parsed.exclusions, /LED não incluído/i);
});

test("melhor preço ignora alternativas, exclusões e linhas marcadas não comparáveis", () => {
  const items = [{ id: "i1" }, { id: "i2" }];
  const prices = [
    { item_id: "i1", proposta_id: "p1", preco_total: 100, comparavel: true, estado_ambito: "incluido" },
    { item_id: "i1", proposta_id: "p2", preco_total: 50, comparavel: false, estado_ambito: "alternativa" },
    { item_id: "i2", proposta_id: "p1", preco_total: 20, comparavel: true, estado_ambito: "parcial" },
  ];
  const result = calculateBestPrices(items, [], prices);
  assert.equal(result.soma_dos_menores, 100);
  assert.equal(result.itens_sem_cotacao, 1);
});

test("migração autoriza cadastro controlado e importação atómica com evidência", () => {
  const sql = fs.readFileSync(new URL("../supabase/mapa_comparativo_importacao_pdf.sql", import.meta.url), "utf8");
  assert.match(sql, /fn_criar_fornecedor_comparativo\(p_mapa_id uuid, p_nome text\)/i);
  assert.match(sql, /fn_pode_editar_obra\(v_obra_id\)/i);
  assert.match(sql, /tipo_entidade,estado_confianca/i);
  assert.match(sql, /fn_importar_proposta_comparativo/i);
  assert.match(sql, /preco_total_original/i);
  assert.match(sql, /p\.comparavel and p\.estado_ambito='incluido'/i);
});

test("interface liga à lista de subempreiteiros e usa o arquivo documental da obra", () => {
  const frontend = fs.readFileSync(new URL("../src/comparative-map.js", import.meta.url), "utf8");
  const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
  assert.match(frontend, /\["subempreiteiro",\s*"ambos"\]\.includes\(row\.tipo_entidade\)/);
  assert.match(frontend, /fn_criar_fornecedor_comparativo/);
  assert.match(frontend, /data-add-import-line/);
  assert.match(frontend, /ABRIR PDF ORIGINAL/);
  assert.match(app, /uploadProposalPdf: uploadWorkDocument/);
  assert.match(app, /downloadProposalPdf: downloadWorkDocument/);
  assert.match(app, /deleteProposalPdf: deleteWorkDocument/);
  assert.match(frontend, /PDF original arquivado/);
});
