import { extractComparativeProposalPdf, normalizeSupplierName, rankSupplierMatches } from "./proposal-pdf-import.js?v=1";

const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[c]);
const num = value => Number.isFinite(Number(value)) ? Number(value) : 0;
const nullableNumber = value => value === "" || value == null ? null : num(value);

export function calculateBestPrices(items, proposals, prices) {
  const winners = items.map(item => {
    const quoted = prices.filter(row => row.item_id === item.id && row.preco_total != null && row.comparavel !== false && (row.estado_ambito || "incluido") === "incluido");
    if (!quoted.length) return { item_id: item.id, proposta_id: null, melhor_preco: null };
    const winner = quoted.reduce((best, row) => num(row.preco_total) < num(best.preco_total) ? row : best);
    return { item_id: item.id, proposta_id: winner.proposta_id, melhor_preco: num(winner.preco_total) };
  });
  return { winners, soma_dos_menores: winners.reduce((sum, row) => sum + num(row.melhor_preco), 0), itens_sem_cotacao: winners.filter(row => row.proposta_id == null).length };
}

export function calculateCosting({ melhor_preco, custo_estimado, valor_adjudicado, preco_venda }) {
  const negotiation = valor_adjudicado == null ? null : num(valor_adjudicado) - num(melhor_preco);
  const budgetDeviation = valor_adjudicado == null || custo_estimado == null ? null : num(valor_adjudicado) - num(custo_estimado);
  const budgetPct = budgetDeviation == null || !num(custo_estimado) ? null : budgetDeviation / num(custo_estimado) * 100;
  const margin = preco_venda == null || valor_adjudicado == null ? null : num(preco_venda) - num(valor_adjudicado);
  const marginPct = margin == null || !num(preco_venda) ? null : margin / num(preco_venda) * 100;
  return { negotiation, budgetDeviation, budgetPct, margin, marginPct };
}

export function createComparativeMapModule({ host, supabase, isConfigured, getSuppliers, getPhases, euro, toast, onAdjudicated, uploadProposalPdf, downloadProposalPdf, deleteProposalPdf, onSupplierCreated }) {
  const state = { work: null, maps: [], proposals: [], items: [], prices: [], adjustments: [], canEdit: false, expanded: "", newOpen: false, loading: false, editingItemId: "", editingProposalId: "", pendingDelete: "", importMapId: "", importFile: null, importPreview: null, importBusy: false, importNewSupplier: false };
  const root = () => host.querySelector("[data-comparative-map-root]");
  const comparisonSuppliers = () => getSuppliers().filter(row => !row.tipo_entidade || row.tipo_entidade === "subempreiteiro");
  const supplierName = id => getSuppliers().find(row => row.id === id)?.nome || "Fornecedor";
  const proposalsFor = id => state.proposals.filter(row => row.mapa_id === id);
  const itemsFor = id => state.items.filter(row => row.mapa_id === id).sort((a, b) => String(a.numero).localeCompare(String(b.numero), "pt", { numeric: true }));
  const pricesFor = itemId => state.prices.filter(row => row.item_id === itemId);
  const adjustmentsFor = id => state.adjustments.filter(row => row.mapa_id === id);
  const priceFor = (itemId, proposalId) => state.prices.find(row => row.item_id === itemId && row.proposta_id === proposalId);
  const bestFor = item => {
    const quoted = pricesFor(item.id).filter(row => row.preco_unitario != null && row.comparavel !== false && (row.estado_ambito || "incluido") === "incluido");
    return quoted.length ? quoted.reduce((best, row) => num(row.preco_total) < num(best.preco_total) ? row : best) : null;
  };
  const bestSum = mapId => itemsFor(mapId).reduce((sum, item) => sum + num(bestFor(item)?.preco_total), 0);
  const money = value => value == null ? "—" : euro.format(num(value));
  const percent = value => value == null ? "—" : `${num(value).toFixed(1)}%`;

  async function api(path, options = {}, label = "Não foi possível concluir a operação") {
    const response = await supabase(path, options);
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      throw new Error(detail.message || detail.details || label);
    }
    return response.status === 204 ? null : response.json();
  }

  const supplierOptions = selected => comparisonSuppliers().map(row => `<option value="${row.id}" ${row.id === selected ? "selected" : ""}>${esc(row.nome)}</option>`).join("");
  const phaseOptions = () => (getPhases() || []).map(row => `<option value="${row.id}">${esc(row.codigo || "")} · ${esc(row.descricao || "Fase")}</option>`).join("");

  function renderNewMap() {
    if (!state.canEdit) return "";
    return `<div class="comparison-new-wrap"><button class="outline-action" type="button" data-toggle-new-map>${state.newOpen ? "FECHAR" : "＋ NOVO MAPA COMPARATIVO"}</button>
      ${state.newOpen ? `<form class="comparison-new-form" data-new-map><label>ESPECIALIDADE<input name="especialidade" required></label><label>DESCRIÇÃO<input name="descricao"></label><label>CUSTO ESTIMADO (€)<input name="custo_estimado" type="number" min="0" step="0.01"></label><label>PREÇO DE VENDA (€)<input name="preco_venda" type="number" min="0" step="0.01"></label><button class="primary-button" type="submit">CRIAR MAPA</button><p class="form-error"></p></form>` : ""}</div>`;
  }

  const scopeOptions = selected => [
    ["incluido", "Incluído e comparável"], ["parcial", "Âmbito parcial"],
    ["alternativa", "Alternativa"], ["excluido", "Excluído"], ["nao_cotado", "Não cotado"],
  ].map(([value, label]) => `<option value="${value}" ${value === selected ? "selected" : ""}>${label}</option>`).join("");

  function renderPdfImport(map) {
    if (!state.canEdit) return "";
    if (state.importMapId !== map.id) return `<div class="comparison-pdf-entry"><button class="outline-action" type="button" data-open-pdf-import="${map.id}">IMPORTAR PROPOSTA PDF</button><span>Extração assistida: confirme fornecedor, âmbito, quantidades e valores antes de gravar.</span></div>`;
    if (!state.importPreview) return `<section class="comparison-pdf-import"><header><div><strong>IMPORTAR PROPOSTA PDF</strong><span>O documento será apenas analisado nesta etapa. Nada é gravado sem a sua confirmação.</span></div><button type="button" data-close-pdf-import>FECHAR</button></header><form data-read-proposal-pdf="${map.id}" class="comparison-pdf-file"><input name="pdf" type="file" accept="application/pdf,.pdf" required><button class="secondary-button" type="submit">ANALISAR PDF</button><p class="form-error"></p></form></section>`;
    const preview = state.importPreview;
    const matches = rankSupplierMatches(preview.supplierName, comparisonSuppliers()).slice(0, 4);
    const suggested = matches[0]?.score >= .62 ? matches[0].supplier.nome : "";
    const items = itemsFor(map.id);
    return `<section class="comparison-pdf-import reviewing"><header><div><strong>REVER EXTRAÇÃO · ${esc(preview.fileName)}</strong><span>${preview.pageCount} página(s). O PDF original e os valores apresentados pelo fornecedor serão preservados.</span></div><button type="button" data-close-pdf-import>DESCARTAR</button></header>
      <form data-confirm-proposal-pdf="${map.id}">
        <div class="comparison-pdf-metadata">
          <label>FORNECEDOR EXTRAÍDO<input name="supplier_extracted" value="${esc(preview.supplierName)}" readonly></label>
          <label>VINCULAR À LISTA DE SUBEMPREITEIROS<input name="supplier_search" list="comparison-suppliers-${map.id}" value="${esc(suggested)}" placeholder="Pesquisar fornecedor existente"><datalist id="comparison-suppliers-${map.id}">${comparisonSuppliers().map(row => `<option value="${esc(row.nome)}"></option>`).join("")}</datalist></label>
          <label>REFERÊNCIA<input name="reference" value="${esc(preview.reference)}"></label>
          <label>DATA<input name="proposal_date" type="date" value="${esc(preview.proposalDate)}"></label>
          <label>TOTAL ORIGINAL (€)<input name="official_total" type="number" min="0" step="0.01" value="${preview.officialTotal ?? ""}"></label>
          <label>VALIDADE (DIAS)<input name="validity_days" type="number" min="0" value="${preview.validityDays ?? ""}"></label>
        </div>
        <div class="comparison-supplier-resolution">
          <span>Correspondências prováveis: ${matches.length ? matches.map(row => `<b>${esc(row.supplier.nome)} · ${Math.round(row.score * 100)}%</b>`).join(" ") : "nenhuma"}</span>
          <label><input type="checkbox" name="create_supplier" ${state.importNewSupplier ? "checked" : ""}> FORNECEDOR NOVO — CADASTRAR NA LISTA</label>
          <input name="new_supplier_name" value="${state.importNewSupplier ? esc(preview.supplierName) : ""}" placeholder="Nome oficial do novo fornecedor">
          <small>Antes de criar, pesquise a lista acima. O cadastro ficará como subempreiteiro “não avaliado”.</small>
        </div>
        <div class="comparison-pdf-conditions">
          <label>CONDIÇÕES DE PAGAMENTO<textarea name="payment_terms">${esc(preview.paymentTerms)}</textarea></label><label>PRAZO DE ENTREGA<textarea name="delivery_terms">${esc(preview.deliveryTerms)}</textarea></label><label>PRAZO DE MONTAGEM<textarea name="assembly_terms">${esc(preview.assemblyTerms)}</textarea></label><label>GARANTIA<textarea name="warranty">${esc(preview.warranty)}</textarea></label><label>EXCLUSÕES / ÂMBITO<textarea name="exclusions">${esc(preview.exclusions)}</textarea></label><label>NOTA DE REVISÃO<textarea name="review_notes" placeholder="Registe esclarecimentos ou normalizações aplicadas"></textarea></label>
        </div>
        <div class="comparison-pdf-lines"><header><div><strong>ITENS EXTRAÍDOS</strong><span>Linhas não comparáveis permanecem visíveis, mas não vencem o “melhor preço”.</span></div><button type="button" data-add-import-line>＋ LINHA MANUAL</button></header>
          ${preview.lines.length ? preview.lines.map((line, index) => `<article data-import-line="${index}" data-original-description="${esc(line.originalDescription)}" data-original-quantity="${line.originalQuantity ?? ""}" data-original-total="${line.originalTotal ?? ""}" data-source-page="${line.sourcePage ?? ""}" data-confidence="${line.confidence ?? ""}">
            <label class="comparison-line-include"><input type="checkbox" name="include" checked> INCLUIR</label>
            <div class="comparison-source-line"><small>PDF · PÁG. ${line.sourcePage || "—"} · CONFIANÇA ${Math.round(num(line.confidence) * 100)}%</small><span>${esc(line.originalDescription)}</span><b>${money(line.originalTotal)}</b></div>
            <label>ITEM DO MAPA<select name="item_id"><option value="">Criar novo item</option>${items.map(item => `<option value="${item.id}">${esc(item.numero)} · ${esc(item.designacao)}</option>`).join("")}</select></label>
            <label>DESCRIÇÃO NORMALIZADA<input name="description" value="${esc(line.normalizedDescription)}"></label>
            <label>UN.<input name="unit" value="${esc(line.unit || "un")}"></label>
            <label>QTD.<input name="quantity" type="number" min="0.0001" step="0.0001" value="${line.normalizedQuantity || 1}"></label>
            <label>UNITÁRIO NORMALIZADO (€)<input name="unit_price" type="number" min="0" step="0.0001" value="${line.unitPrice ?? ""}"></label>
            <label>ÂMBITO<select name="scope">${scopeOptions(line.scopeStatus)}</select></label>
            <label class="comparison-line-comparable"><input name="comparable" type="checkbox" ${line.comparable ? "checked" : ""}> COMPARÁVEL</label>
          </article>`).join("") : '<p class="procurement-empty">NÃO FOI POSSÍVEL EXTRAIR ITENS AUTOMATICAMENTE. REGISTE A PROPOSTA MANUALMENTE.</p>'}
        </div>
        <footer><p class="form-error"></p><button type="button" data-close-pdf-import>CANCELAR</button><button class="primary-button" type="submit">CONFIRMAR E IMPORTAR ${preview.lines.length} LINHA(S)</button></footer>
      </form></section>`;
  }

  function deleteActions(type, id) {
    const key = `${type}:${id}`;
    if (state.pendingDelete !== key) return `<button class="comparison-delete-button" type="button" data-request-delete-${type}="${id}">ELIMINAR</button>`;
    return `<span class="comparison-delete-confirm"><b>CONFIRMAR?</b><button type="button" data-cancel-delete>CANCELAR</button><button class="comparison-delete-button" type="button" data-confirm-delete-${type}="${id}">SIM, ELIMINAR</button></span>`;
  }

  function renderProposalInfo(map, proposal) {
    const editing = state.editingProposalId === proposal.id;
    if (!editing) return `<article class="comparison-commercial-card"><header><strong>${esc(supplierName(proposal.fornecedor_id))}</strong><span class="comparison-row-actions">${proposal.documento_url ? `<button type="button" data-open-proposal-pdf="${esc(proposal.documento_url)}">ABRIR PDF ORIGINAL</button>` : ""}${state.canEdit ? `<button type="button" data-edit-proposal="${proposal.id}">EDITAR</button>${deleteActions("proposal", proposal.id)}` : ""}</span></header><div class="comparison-proposal-summary"><span>PROPOSTA <strong>${esc(proposal.data_proposta || "—")}</strong></span><span>REFERÊNCIA <strong>${esc(proposal.referencia_proposta || "—")}</strong></span><span>TOTAL ORIGINAL <strong>${money(proposal.total_original)}</strong></span><span>VALIDADE <strong>${esc(proposal.prazo_validade || "—")}</strong></span><span>CONDIÇÕES <strong>${esc(proposal.condicoes_pagamento || "—")}</strong></span><span>ENTREGA / MONTAGEM <strong>${esc([proposal.prazo_entrega, proposal.prazo_montagem].filter(Boolean).join(" · ") || "—")}</strong></span></div></article>`;
    return `<form class="comparison-commercial-card editing" data-proposal-info="${proposal.id}"><header><strong>EDITAR PROPOSTA · ${esc(supplierName(proposal.fornecedor_id))}</strong><button type="button" data-cancel-edit-proposal>CANCELAR</button></header><div class="comparison-commercial-grid">
      <label>FORNECEDOR<select name="fornecedor_id" required>${supplierOptions(proposal.fornecedor_id)}</select></label><label>DATA DA PROPOSTA<input type="date" name="data_proposta" value="${esc(proposal.data_proposta || "")}"></label><label>VALIDADE<input type="date" name="prazo_validade" value="${esc(proposal.prazo_validade || "")}"></label>
      <label>CONTACTO<input name="contacto" value="${esc(proposal.contacto || "")}"></label><label>TELEMÓVEL<input name="telemovel" value="${esc(proposal.telemovel || "")}"></label>
      <label>CONDIÇÕES DE PAGAMENTO<textarea name="condicoes_pagamento">${esc(proposal.condicoes_pagamento || "")}</textarea></label><label>EXCLUSÕES / ÂMBITO<textarea name="exclusoes_ambito">${esc(proposal.exclusoes_ambito || "")}</textarea></label>
      <label>OUTRAS INFORMAÇÕES<textarea name="outras_informacoes">${esc(proposal.outras_informacoes || "")}</textarea></label><label class="primeline-note">NOTA PRIMELINE<textarea name="nota_primeline">${esc(proposal.nota_primeline || "")}</textarea></label>
    </div><div class="comparison-edit-actions"><button type="button" data-cancel-edit-proposal>CANCELAR</button><button class="secondary-button" type="submit">GUARDAR ALTERAÇÕES</button></div><p class="form-error"></p></form>`;
  }

  function renderGrid(map) {
    const proposals = proposalsFor(map.id);
    const items = itemsFor(map.id);
    if (!proposals.length || !items.length) return `<div class="procurement-empty">ADICIONE ITENS E PROPOSTAS PARA COMEÇAR A COMPARAÇÃO.</div>`;
    return `<div class="comparison-table-wrap"><table class="comparison-table"><thead><tr><th class="comparison-col-number">Nº</th><th class="comparison-col-description">DESIGNAÇÃO / DESCRITIVO</th><th>UNID.</th><th>QUANT.</th>${proposals.map(p => `<th class="comparison-supplier-heading"><span>${esc(supplierName(p.fornecedor_id))}</span><small>UNITÁRIO / TOTAL</small></th>`).join("")}<th>MELHOR PREÇO</th><th class="comparison-col-actions">AÇÕES</th></tr></thead><tbody>
      ${items.map(item => { const best = bestFor(item); const editing = state.editingItemId === item.id; return `<tr class="${editing ? "comparison-item-editing" : ""}"><td class="comparison-col-number">${editing ? `<input data-item-field="numero" value="${esc(item.numero)}" required>` : esc(item.numero)}</td><td class="comparison-col-description">${editing ? `<input data-item-field="designacao" value="${esc(item.designacao)}" required>` : `<strong>${esc(item.designacao)}</strong>`}</td><td>${editing ? `<input data-item-field="unidade" value="${esc(item.unidade)}" required>` : esc(item.unidade)}</td><td>${editing ? `<input data-item-field="quantidade" type="number" min="0.0001" step="0.0001" value="${num(item.quantidade)}" required>` : num(item.quantidade)}</td>${proposals.map(proposal => { const price = priceFor(item.id, proposal.id); const comparable = price?.comparavel !== false && (price?.estado_ambito || "incluido") === "incluido"; return `<td class="${price && best?.id === price.id ? "comparison-price-best" : ""} ${price && !comparable ? "comparison-price-not-comparable" : ""}"><form data-save-price data-item="${item.id}" data-proposal="${proposal.id}"><input aria-label="Preço unitário ${esc(supplierName(proposal.fornecedor_id))}" name="preco_unitario" type="number" min="0" step="0.0001" value="${price?.preco_unitario ?? ""}" placeholder="Sem cotação" ${state.canEdit && !editing ? "" : "disabled"}><output>${price ? money(price.preco_total) : "—"}</output>${price?.preco_total_original != null ? `<small>ORIGINAL ${money(price.preco_total_original)}</small>` : ""}<select name="estado_ambito" ${state.canEdit && !editing ? "" : "disabled"}>${scopeOptions(price?.estado_ambito || "incluido")}</select><label class="comparison-price-comparable"><input name="comparavel" type="checkbox" ${comparable ? "checked" : ""} ${state.canEdit && !editing ? "" : "disabled"}> COMPARÁVEL</label><input name="observacoes" value="${esc(price?.observacoes || "")}" placeholder="Inclui / exclui" ${state.canEdit && !editing ? "" : "disabled"}>${state.canEdit && !editing ? '<button type="submit">GUARDAR</button>' : ""}</form></td>`; }).join("")}<td class="comparison-best"><strong>${best ? esc(supplierName(proposals.find(p => p.id === best.proposta_id)?.fornecedor_id)) : "SEM COTAÇÃO COMPARÁVEL"}</strong><span>${best ? money(best.preco_total) : "—"}</span></td><td class="comparison-item-actions comparison-col-actions">${state.canEdit ? editing ? `<button type="button" data-save-item="${item.id}">GUARDAR</button><button type="button" data-cancel-edit-item>CANCELAR</button>` : `<button type="button" data-edit-item="${item.id}">EDITAR</button>${deleteActions("item", item.id)}` : "—"}</td></tr>`; }).join("")}
      <tr class="comparison-total"><td colspan="4">TOTAL NORMALIZADO POR PROPOSTA</td>${proposals.map(p => `<td>${money(pricesForProposal(p.id).reduce((sum,row) => sum+num(row.preco_total),0))}</td>`).join("")}<td><small>REFERENCIAL TEÓRICO · MENORES COMPARÁVEIS</small><strong>${money(bestSum(map.id))}</strong></td><td></td></tr>
    </tbody></table></div>`;
  }

  const pricesForProposal = id => state.prices.filter(row => row.proposta_id === id);

  function renderCosting(map) {
    const best = bestSum(map.id);
    const { negotiation, budgetDeviation, budgetPct, margin, marginPct } = calculateCosting({ melhor_preco: best, custo_estimado: map.custo_estimado_orcamento, valor_adjudicado: map.valor_adjudicado_real, preco_venda: map.preco_venda });
    return `<section class="comparison-costing"><header>CUSTEIO E MARGEM</header><form data-save-costing="${map.id}"><label>CUSTO ESTIMADO · ORÇAMENTO<input name="custo_estimado_orcamento" type="number" min="0" step="0.01" value="${map.custo_estimado_orcamento ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div><span>MELHOR PREÇO NO COMPARATIVO</span><strong>${money(best)}</strong></div><label>VALOR ADJUDICADO REAL<input name="valor_adjudicado_real" type="number" min="0" step="0.01" value="${map.valor_adjudicado_real ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div><span>DIFERENÇA DA NEGOCIAÇÃO</span><strong>${money(negotiation)}</strong></div><div><span>DESVIO FACE AO ORÇAMENTO</span><strong>${money(budgetDeviation)} · ${percent(budgetPct)}</strong></div><label>PREÇO DE VENDA<input name="preco_venda" type="number" min="0" step="0.01" value="${map.preco_venda ?? ""}" ${state.canEdit ? "" : "disabled"}></label><div class="comparison-margin"><span>MARGEM REAL</span><strong>${money(margin)} · ${percent(marginPct)}</strong><small>Calculada exclusivamente sobre o Valor Adjudicado Real.</small></div>${state.canEdit ? '<button class="secondary-button" type="submit">GUARDAR CUSTEIO</button>' : ""}<p class="form-error"></p></form></section>`;
  }

  function renderAdjustments(map) {
    const proposals = proposalsFor(map.id);
    return `<section class="comparison-adjustments"><header><strong>AJUSTES DE ESCOPO / LEITURA TÉCNICA</strong><span>Registe diferenças de âmbito sem alterar os preços apresentados.</span></header>${adjustmentsFor(map.id).map(row => `<article><b>${esc(supplierName(proposals.find(p => p.id === row.proposta_id)?.fornecedor_id))}</b><span>${esc(row.justificacao)}</span><strong>${money(row.valor_ajustado)}</strong></article>`).join("") || '<p class="procurement-empty">SEM AJUSTES</p>'}${state.canEdit && proposals.length ? `<form data-add-adjustment="${map.id}"><select name="proposta_id" required>${proposals.map(p => `<option value="${p.id}">${esc(supplierName(p.fornecedor_id))}</option>`).join("")}</select><input name="valor_ajustado" type="number" step="0.01" required placeholder="Valor ajustado"><input name="justificacao" required placeholder="Justificação técnica"><button type="submit">ADICIONAR AJUSTE</button><p class="form-error"></p></form>` : ""}</section>`;
  }

  function renderMap(map) {
    const expanded = state.expanded === map.id;
    const proposals = proposalsFor(map.id);
    return `<article class="comparison-map ${expanded ? "expanded" : ""}"><button class="comparison-map-head" type="button" data-toggle-map="${map.id}"><span><small>${esc(state.work?.numero)} · ${esc(map.especialidade)}</small><strong>${esc(map.descricao || map.especialidade)}</strong></span><span>${itemsFor(map.id).length} ITENS</span><span>${proposals.length} PROPOSTAS</span><span>${money(bestSum(map.id))}</span><b>${expanded ? "−" : "+"}</b></button>${expanded ? `<div class="comparison-map-body">
      ${state.canEdit ? `<div class="comparison-map-actions"><span>GESTÃO DO MAPA</span>${deleteActions("map", map.id)}</div>` : ""}
      ${renderPdfImport(map)}
      <div class="comparison-entry-forms">${state.canEdit ? `<form data-add-item="${map.id}"><strong>NOVO ITEM</strong><input name="numero" required placeholder="Nº"><input name="designacao" required placeholder="Designação"><input name="unidade" value="un" required><input name="quantidade" type="number" min="0.0001" step="0.0001" value="1" required><button type="submit">ADICIONAR</button><p class="form-error"></p></form><form data-add-proposal="${map.id}"><strong>NOVA PROPOSTA</strong><select name="fornecedor_id" required><option value="">Fornecedor</option>${supplierOptions()}</select><input name="data_proposta" type="date"><button type="submit">ADICIONAR</button><p class="form-error"></p></form>` : ""}</div>
      ${renderGrid(map)}${renderAdjustments(map)}${renderCosting(map)}
      <section class="comparison-commercial"><header>CONDIÇÕES / INFORMAÇÃO COMERCIAL</header>${proposals.map(p => renderProposalInfo(map,p)).join("") || '<p class="procurement-empty">SEM PROPOSTAS</p>'}</section>
      ${state.canEdit && proposals.length && map.valor_adjudicado_real != null ? `<form class="comparison-adjudicate" data-adjudicate-map="${map.id}"><strong>CRIAR SUBEMPREITADA</strong><select name="proposta_id" required>${proposals.map(p => `<option value="${p.id}">${esc(supplierName(p.fornecedor_id))}</option>`).join("")}</select><select name="fase_id" required>${phaseOptions()}</select><input name="data_inicio" type="date" required><input name="data_fim" type="date" required><select name="condicao_pagamento"><option value="">Sem condição definida</option><option value="imediato">Imediato</option><option value="15_dias">15 dias</option><option value="30_dias">30 dias</option></select><button type="submit">CRIAR COM ${money(map.valor_adjudicado_real)}</button><p class="form-error"></p></form>` : ""}
    </div>` : ""}</article>`;
  }

  function render() {
    const container = root(); if (!container) return;
    if (state.loading) return void (container.innerHTML='<div class="empty-state">A CARREGAR MAPAS COMPARATIVOS…</div>');
    container.innerHTML=`<section class="comparison-module"><header><div><p class="eyebrow">MODELO VALIDADO</p><h3>MAPA COMPARATIVO DE SUBEMPREITADAS E FORNECEDORES</h3><span>Propostas dinâmicas, melhor preço por item, ajustes, custeio e margem real.</span></div><b>${state.maps.length}</b></header>${renderNewMap()}<div>${state.maps.length ? state.maps.map(renderMap).join("") : '<div class="procurement-empty">NÃO EXISTEM MAPAS COMPARATIVOS NESTA OBRA.</div>'}</div></section>`;
  }

  async function load(work) {
    state.work=work; state.loading=true; render();
    try {
      if (!isConfigured) { state.canEdit=true; state.maps=[]; state.proposals=[]; state.items=[]; state.prices=[]; state.adjustments=[]; }
      else {
        const [maps,permission]=await Promise.all([api(`mapas_comparativos?select=*&obra_id=eq.${encodeURIComponent(work.id)}&order=criado_em.desc`),api("rpc/fn_pode_editar_obra",{method:"POST",body:JSON.stringify({p_obra_id:work.id})})]);
        state.maps=maps; state.canEdit=Boolean(permission); const ids=maps.map(row=>row.id);
        if (ids.length) {
          const encoded=ids.map(encodeURIComponent).join(",");
          [state.proposals,state.items,state.adjustments]=await Promise.all([api(`comparativo_propostas?select=*&mapa_id=in.(${encoded})&order=criado_em`),api(`comparativo_itens?select=*&mapa_id=in.(${encoded})&order=numero`),api(`comparativo_ajustes?select=*&mapa_id=in.(${encoded})&order=criado_em`)]);
          const itemIds=state.items.map(row=>row.id);
          state.prices=itemIds.length?await api(`comparativo_itens_precos?select=*&item_id=in.(${itemIds.map(encodeURIComponent).join(",")})`):[];
        } else { state.proposals=[];state.items=[];state.prices=[];state.adjustments=[]; }
      }
    } catch(error) { toast(error.message,"error"); }
    finally { state.loading=false;render(); }
  }

  async function submit(form, action) { const button=form.querySelector('button[type="submit"]'); if(button)button.disabled=true; try{await action();}catch(error){const p=form.querySelector('.form-error');if(p)p.textContent=error.message;else toast(error.message,"error");}finally{if(button)button.disabled=false;} }
  const post = (table,payload) => api(table,{method:"POST",headers:{Prefer:"return=representation"},body:JSON.stringify(payload)});
  const patch = (table,id,payload) => api(`${table}?id=eq.${encodeURIComponent(id)}`,{method:"PATCH",headers:{Prefer:"return=representation"},body:JSON.stringify(payload)});

  async function deleteItem(id) {
    const result = await api("rpc/fn_eliminar_item_comparativo", { method: "POST", body: JSON.stringify({ p_item_id: id }) });
    if (num(result?.precos_restantes) !== 0) throw new Error("A eliminação do item deixou preços relacionados na base.");
    state.pendingDelete = ""; state.editingItemId = ""; await load(state.work); toast(`Item eliminado com ${num(result?.precos_eliminados)} preço(s) relacionado(s).`);
  }

  async function deleteProposal(id) {
    const result = await api("rpc/fn_eliminar_proposta_comparativo", { method: "POST", body: JSON.stringify({ p_proposta_id: id }) });
    if (num(result?.precos_restantes) !== 0 || num(result?.ajustes_restantes) !== 0) throw new Error("A eliminação da proposta deixou registos relacionados na base.");
    state.pendingDelete = ""; state.editingProposalId = ""; await load(state.work); toast(`Proposta eliminada com ${num(result?.precos_eliminados)} preço(s) e ${num(result?.ajustes_eliminados)} ajuste(s).`);
  }

  async function deleteMap(id) {
    const result = await api("rpc/fn_eliminar_mapa_comparativo", { method: "POST", body: JSON.stringify({ p_mapa_id: id }) });
    const remaining = ["mapas_restantes", "itens_restantes", "propostas_restantes", "precos_restantes", "ajustes_restantes"];
    if (remaining.some(field => num(result?.[field]) !== 0)) throw new Error("A eliminação do mapa deixou registos relacionados na base.");
    state.pendingDelete = ""; state.expanded = ""; await load(state.work);
    toast(`Mapa eliminado com ${num(result?.itens_eliminados)} item(ns), ${num(result?.propostas_eliminadas)} proposta(s), ${num(result?.precos_eliminados)} preço(s) e ${num(result?.ajustes_eliminados)} ajuste(s).`);
  }

  async function readProposalPdf(form) {
    const file = form.elements.pdf.files?.[0];
    if (!file) throw new Error("Selecione o PDF da proposta.");
    state.importBusy = true;
    try {
      state.importFile = file;
      state.importPreview = await extractComparativeProposalPdf(file);
      const bestSupplierMatch = rankSupplierMatches(state.importPreview.supplierName, comparisonSuppliers())[0];
      state.importNewSupplier = !bestSupplierMatch || bestSupplierMatch.score < .62;
      render();
    } finally { state.importBusy = false; }
  }

  async function confirmProposalPdf(form) {
    const preview = state.importPreview;
    if (!preview || !state.importFile) throw new Error("Volte a analisar o PDF antes de confirmar.");
    const creating = form.elements.create_supplier.checked;
    const searchedName = form.elements.supplier_search.value.trim();
    let supplier = comparisonSuppliers().find(row => normalizeSupplierName(row.nome) === normalizeSupplierName(searchedName));
    if (creating) {
      const newName = form.elements.new_supplier_name.value.trim();
      if (!newName) throw new Error("Indique o nome oficial do novo fornecedor.");
      const similar = rankSupplierMatches(newName, comparisonSuppliers()).find(row => row.score >= .82);
      if (similar && normalizeSupplierName(similar.supplier.nome) !== normalizeSupplierName(newName)) {
        throw new Error(`Já existe um fornecedor muito semelhante: ${similar.supplier.nome}. Se for o mesmo, desmarque “fornecedor novo” e selecione-o na lista.`);
      }
      supplier = await api("rpc/fn_criar_fornecedor_comparativo", { method: "POST", body: JSON.stringify({ p_mapa_id: form.dataset.confirmProposalPdf, p_nome: newName }) });
      onSupplierCreated?.(supplier);
    }
    if (!supplier) throw new Error("Selecione um fornecedor existente da lista ou assinale o cadastro de fornecedor novo.");

    const lines = [...form.querySelectorAll("[data-import-line]")].filter(row => row.querySelector('[name="include"]').checked).map((row, index) => {
      const value = name => row.querySelector(`[name="${name}"]`)?.value.trim() || "";
      const scope = value("scope") || "incluido";
      const itemId = value("item_id") || null;
      if (!itemId && !value("description")) throw new Error(`Preencha a descrição da linha ${index + 1}.`);
      if (num(value("quantity")) <= 0 || value("unit_price") === "") throw new Error(`Confirme quantidade e valor da linha ${index + 1}.`);
      return {
        itemId,
        number: `PDF-${index + 1}`,
        originalDescription: row.dataset.originalDescription,
        normalizedDescription: value("description"),
        originalQuantity: nullableNumber(row.dataset.originalQuantity),
        normalizedQuantity: num(value("quantity")),
        originalUnit: value("unit"), unit: value("unit"),
        unitPrice: num(value("unit_price")),
        originalTotal: nullableNumber(row.dataset.originalTotal),
        scopeStatus: scope,
        comparable: scope === "incluido" && row.querySelector('[name="comparable"]').checked,
        sourcePage: nullableNumber(row.dataset.sourcePage), confidence: nullableNumber(row.dataset.confidence),
      };
    });
    if (!lines.length) throw new Error("Selecione pelo menos uma linha para importar.");
    const data = {
      ...preview,
      fullText: undefined,
      supplierName: form.elements.supplier_extracted.value.trim(), reference: form.elements.reference.value.trim(),
      proposalDate: form.elements.proposal_date.value, officialTotal: nullableNumber(form.elements.official_total.value),
      validityDays: nullableNumber(form.elements.validity_days.value), paymentTerms: form.elements.payment_terms.value.trim(),
      deliveryTerms: form.elements.delivery_terms.value.trim(), assemblyTerms: form.elements.assembly_terms.value.trim(),
      warranty: form.elements.warranty.value.trim(), exclusions: form.elements.exclusions.value.trim(),
      reviewNotes: form.elements.review_notes.value.trim(),
    };
    let uploadedPath = ""; let result;
    try {
      uploadedPath = await uploadProposalPdf(state.importFile, state.work.id, "propostas-comparativo");
      data.documentPath = uploadedPath; data.documentName = state.importFile.name;
      result = await api("rpc/fn_importar_proposta_comparativo", { method: "POST", body: JSON.stringify({ p_mapa_id: form.dataset.confirmProposalPdf, p_fornecedor_id: supplier.id, p_dados: data, p_linhas: lines }) });
    } catch (error) {
      if (uploadedPath && deleteProposalPdf) await deleteProposalPdf(uploadedPath).catch(() => {});
      throw error;
    }
    state.importMapId = ""; state.importFile = null; state.importPreview = null; state.importNewSupplier = false;
    await load(state.work);
    toast(`Proposta importada com ${num(result?.linhas_criadas)} linha(s) e PDF original arquivado.`);
  }

  host.addEventListener("click", event => {
    const toggleNew = event.target.closest("[data-toggle-new-map]");
    if (toggleNew) { state.newOpen = !state.newOpen; render(); return; }
    const openImport = event.target.closest("[data-open-pdf-import]");
    if (openImport) { state.importMapId = openImport.dataset.openPdfImport; state.importFile = null; state.importPreview = null; state.importNewSupplier = false; render(); return; }
    if (event.target.closest("[data-close-pdf-import]")) { state.importMapId = ""; state.importFile = null; state.importPreview = null; state.importNewSupplier = false; render(); return; }
    if (event.target.closest("[data-add-import-line]") && state.importPreview) {
      state.importPreview.lines.push({ sourcePage: null, originalDescription: "Linha acrescentada na revisão", normalizedDescription: "", originalQuantity: 1, normalizedQuantity: 1, unit: "un", unitPrice: null, originalTotal: null, scopeStatus: "incluido", comparable: true, confidence: 1 });
      render(); return;
    }
    const openPdf = event.target.closest("[data-open-proposal-pdf]");
    if (openPdf) return void (async () => {
      try {
        const blob = await downloadProposalPdf(decodeURIComponent(openPdf.dataset.openProposalPdf));
        const url = URL.createObjectURL(blob); window.open(url, "_blank", "noopener"); setTimeout(() => URL.revokeObjectURL(url), 60000);
      } catch (error) { toast(error.message || "Não foi possível abrir o PDF.", "error"); }
    })();
    const editItem = event.target.closest("[data-edit-item]");
    if (editItem) { state.editingItemId = editItem.dataset.editItem; state.pendingDelete = ""; render(); return; }
    if (event.target.closest("[data-cancel-edit-item]")) { state.editingItemId = ""; render(); return; }
    const saveItem = event.target.closest("[data-save-item]");
    if (saveItem) {
      const row = saveItem.closest("tr");
      return void submit(row, async () => {
        const value = name => row.querySelector(`[data-item-field="${name}"]`)?.value.trim() || "";
        const quantity = num(value("quantidade"));
        if (!value("numero") || !value("designacao") || !value("unidade") || quantity <= 0) throw new Error("Preencha os dados válidos do item.");
        await patch("comparativo_itens", saveItem.dataset.saveItem, { numero: value("numero"), designacao: value("designacao"), unidade: value("unidade"), quantidade: quantity });
        state.editingItemId = ""; await load(state.work); toast("Item atualizado sem perder os preços existentes.");
      });
    }
    const editProposal = event.target.closest("[data-edit-proposal]");
    if (editProposal) { state.editingProposalId = editProposal.dataset.editProposal; state.pendingDelete = ""; render(); return; }
    if (event.target.closest("[data-cancel-edit-proposal]")) { state.editingProposalId = ""; render(); return; }
    if (event.target.closest("[data-cancel-delete]")) { state.pendingDelete = ""; render(); return; }
    for (const type of ["item", "proposal", "map"]) {
      const request = event.target.closest(`[data-request-delete-${type}]`);
      if (request) {
        const attribute = type === "item" ? "requestDeleteItem" : type === "proposal" ? "requestDeleteProposal" : "requestDeleteMap";
        state.pendingDelete = `${type}:${request.dataset[attribute]}`; render(); return;
      }
      const confirm = event.target.closest(`[data-confirm-delete-${type}]`);
      if (confirm) {
        const attribute = type === "item" ? "confirmDeleteItem" : type === "proposal" ? "confirmDeleteProposal" : "confirmDeleteMap";
        const id = confirm.dataset[attribute];
        const action = type === "item" ? deleteItem : type === "proposal" ? deleteProposal : deleteMap;
        return void action(id)
          .catch(error => toast(error.message || "Não foi possível eliminar o registo.", "error"));
      }
    }
    const toggle = event.target.closest("[data-toggle-map]");
    if (toggle) { state.expanded = state.expanded === toggle.dataset.toggleMap ? "" : toggle.dataset.toggleMap; render(); }
  });
  host.addEventListener("submit",event=>{const form=event.target;if(!form.closest('[data-comparative-map-root]'))return;event.preventDefault();
    if(form.matches('[data-read-proposal-pdf]'))return submit(form,()=>readProposalPdf(form));
    if(form.matches('[data-confirm-proposal-pdf]'))return submit(form,()=>confirmProposalPdf(form));
    if(form.matches('[data-new-map]'))return submit(form,async()=>{await post('mapas_comparativos',{obra_id:state.work.id,especialidade:form.elements.especialidade.value.trim(),descricao:form.elements.descricao.value.trim()||null,custo_estimado_orcamento:nullableNumber(form.elements.custo_estimado.value),preco_venda:nullableNumber(form.elements.preco_venda.value)});state.newOpen=false;await load(state.work);toast('Mapa comparativo criado.');});
    if(form.matches('[data-add-item]'))return submit(form,async()=>{await post('comparativo_itens',{mapa_id:form.dataset.addItem,numero:form.elements.numero.value.trim(),designacao:form.elements.designacao.value.trim(),unidade:form.elements.unidade.value.trim(),quantidade:num(form.elements.quantidade.value)});await load(state.work);toast('Item adicionado.');});
    if(form.matches('[data-add-proposal]'))return submit(form,async()=>{await post('comparativo_propostas',{mapa_id:form.dataset.addProposal,fornecedor_id:form.elements.fornecedor_id.value,data_proposta:form.elements.data_proposta.value||null});await load(state.work);toast('Proposta adicionada.');});
    if(form.matches('[data-save-price]'))return submit(form,async()=>{if(form.elements.preco_unitario.value==='')throw new Error('Indique um preço ou deixe o item sem cotação.');const scope=form.elements.estado_ambito.value;const payload={item_id:form.dataset.item,proposta_id:form.dataset.proposal,preco_unitario:num(form.elements.preco_unitario.value),estado_ambito:scope,comparavel:scope==='incluido'&&form.elements.comparavel.checked,observacoes:form.elements.observacoes.value.trim()||null};await api('comparativo_itens_precos?on_conflict=item_id,proposta_id',{method:'POST',headers:{Prefer:'resolution=merge-duplicates,return=representation'},body:JSON.stringify(payload)});await load(state.work);toast('Preço e âmbito guardados.');});
    if(form.matches('[data-proposal-info]'))return submit(form,async()=>{const payload={fornecedor_id:form.elements.fornecedor_id.value};['data_proposta','prazo_validade','contacto','telemovel','condicoes_pagamento','exclusoes_ambito','outras_informacoes','nota_primeline'].forEach(k=>payload[k]=form.elements[k].value.trim()||null);await patch('comparativo_propostas',form.dataset.proposalInfo,payload);state.editingProposalId="";await load(state.work);toast('Proposta atualizada sem perder preços ou ajustes.');});
    if(form.matches('[data-add-adjustment]'))return submit(form,async()=>{await post('comparativo_ajustes',{mapa_id:form.dataset.addAdjustment,proposta_id:form.elements.proposta_id.value,valor_ajustado:num(form.elements.valor_ajustado.value),justificacao:form.elements.justificacao.value.trim()});await load(state.work);toast('Ajuste registado.');});
    if(form.matches('[data-save-costing]'))return submit(form,async()=>{await patch('mapas_comparativos',form.dataset.saveCosting,{custo_estimado_orcamento:nullableNumber(form.elements.custo_estimado_orcamento.value),valor_adjudicado_real:nullableNumber(form.elements.valor_adjudicado_real.value),preco_venda:nullableNumber(form.elements.preco_venda.value)});await load(state.work);toast('Custeio guardado.');});
    if(form.matches('[data-adjudicate-map]'))return submit(form,async()=>{const result=await api('rpc/fn_criar_subempreitada_do_comparativo',{method:'POST',body:JSON.stringify({p_mapa_id:form.dataset.adjudicateMap,p_proposta_id:form.elements.proposta_id.value,p_fase_id:form.elements.fase_id.value,p_data_inicio_prevista:form.elements.data_inicio.value,p_data_fim_prevista:form.elements.data_fim.value,p_condicao_pagamento:form.elements.condicao_pagamento.value||null})});await onAdjudicated?.(Array.isArray(result)?result[0]:result);toast('Subempreitada criada com o Valor Adjudicado Real.');});
  });
  return {show:work=>load(work),reload:()=>state.work&&load(state.work)};
}
