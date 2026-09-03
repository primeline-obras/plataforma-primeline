const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const CATEGORY_LABELS = { materiais: "Materiais", estaleiro: "Despesas-Estaleiro", subempreitadas: "Subcontratos", mao_obra: "Funcionários-Obra · Mão de Obra", faturacao: "Faturação" };
const SHEETS = { materiais: ["materiais"], estaleiro: ["despesas estaleiro"], subempreitadas: ["subcontratos", "subempreitadas"], mao_obra: ["funcionarios obra"], faturacao: ["faturacao"] };
const OPTIONAL_SHEETS = new Set(["faturacao"]);
const BLOCKED_IMPORT_WORKS = new Set(["79", "85", "127"]);
const IMPORT_BATCH_SIZE = 500;
const norm = value => String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLocaleLowerCase("pt-PT").replace(/\s+/g, " ");
const sheetKey = value => norm(value).replace(/[\s_-]*-[\s_-]*/g, " ").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
const sheetMatches = (name, category, aliases) => {
  const normalized = sheetKey(name);
  if (aliases.includes(normalized)) return true;
  return category === "mao_obra"
    && (normalized.includes("mao de obra") || (normalized.includes("funcionarios") && normalized.includes("obra")));
};
const key = value => norm(value).replace(/[º°ª.()/%_-]/g, "").replace(/\s+/g, "");
const money = value => { if (typeof value === "number") return value; const text = String(value ?? "").trim(); if (!text) return null; const parsed = Number(text.replace(/\s|€/g, "").replace(/\.(?=\d{3}(?:\D|$))/g, "").replace(",", ".")); return Number.isFinite(parsed) ? parsed : null; };
const date = value => {
  if (!value) return null;
  if (typeof value === "number" && globalThis.XLSX?.SSF?.parse_date_code) { const parsed = globalThis.XLSX.SSF.parse_date_code(value); return parsed ? `${parsed.y}-${String(parsed.m).padStart(2, "0")}-${String(parsed.d).padStart(2, "0")}` : null; }
  const text = String(value).trim(); if (/^\d{4}-\d{2}-\d{2}/.test(text)) return text.slice(0, 10);
  const match = text.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{4})$/); return match ? `${match[3]}-${match[2].padStart(2, "0")}-${match[1].padStart(2, "0")}` : null;
};

export function formatManagementDate(value) {
  const match = String(value ?? "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : (value || "—");
}

export function managementRowMatches(row, filters = {}, { mode = "categoria", category = "" } = {}) {
  const requestedValue = String(filters.valor ?? "").trim() === "" ? null : money(filters.valor);
  return (!filters.obra_id || row.obra_id === filters.obra_id)
    && (!category || row.categoria === category)
    && (mode !== "categoria" || !filters.categoria || row.categoria === filters.categoria)
    && (!filters.data_inicio || row.data_lancamento >= filters.data_inicio)
    && (!filters.data_fim || row.data_lancamento <= filters.data_fim)
    && (!norm(filters.entidade) || norm(row.entidade_nome).includes(norm(filters.entidade)))
    && (!norm(filters.descricao) || norm(row.descricao).includes(norm(filters.descricao)))
    && (!norm(filters.documento) || norm(row.documento).includes(norm(filters.documento)))
    && (requestedValue == null || Math.abs(Number(row.valor || 0) - requestedValue) < 0.005);
}

const meaningfulImportValue = value => {
  const text = String(value ?? "").trim();
  return Boolean(text) && !["#N/A", "#VALUE!", "#REF!", "#DIV/0!"].includes(text.toUpperCase());
};
const managementEmployeeName = value => String(value ?? "").replace(/\s*\([^)]*nível\s*\d+[^)]*\)\s*$/i, "").trim();

export function summarizeManagementImportErrors(errors = []) {
  const grouped = new Map();
  errors.forEach(error => {
    const message = String(error).replace(/^Linha\s+\d+:\s*/i, "").trim();
    grouped.set(message, (grouped.get(message) || 0) + 1);
  });
  return [...grouped.entries()].map(([message, count]) => count > 1 ? `${message} (${count} linhas)` : message);
}

export function normalizeManagementRows(category, rows, firstDataLine = 2) {
  return rows.map((row, index) => {
    const values = Object.fromEntries(Object.entries(row).map(([header, value]) => [key(header), value]));
    const common = { categoria: category, linha: index + firstDataLine, obra_numero: String(values.obra ?? values.obran ?? values.numeroobra ?? values.nobra ?? "").trim() };
    if (category === "mao_obra") return { ...common, colaborador: managementEmployeeName(values.colaborador ?? values.nomefuncionario ?? values.funcionario ?? values.nome), data: date(values.data), horas: money(values.horas ?? values.quant ?? values.quantidade), valor_hora: money(values.valorhora ?? values.valorunit ?? values.valorunitario) };
    if (category === "faturacao") return { ...common, numero_fatura: String(values.nfatura ?? values.numerofatura ?? "").trim(), data_emissao: date(values.dataemissao), valor: money(values.valor), data_recebimento: date(values.datarecebimento), valor_recebido: money(values.valorrecebido), estado: String(values.estado ?? "").trim() };
    const quantidade = money(values.quant ?? values.quantidade), valorUnitario = money(values.valorunit ?? values.valorunitario);
    return { ...common, numero_documento: String(values.ndocumento ?? values.numerodocumento ?? values.ndoc ?? values.n ?? "").trim(), data: date(values.data), fornecedor: String(values.fornecedor ?? "").trim(), colaborador: managementEmployeeName(values.colaborador ?? values.reembolso ?? ""), designacao: String(values.designacao ?? values.descricao ?? "").trim(), unidade: String(values.unmedida ?? values.unidade ?? "").trim(), quantidade, valor_unitario: valorUnitario, valor_total: money(values.valortotal) ?? (quantidade != null && valorUnitario != null ? quantidade * valorUnitario : null), data_pagamento: date(values.datapagamento ?? values.datadepagamento) };
  }).filter(row => category === "mao_obra"
    ? [row.obra_numero, row.data, row.colaborador, row.horas].some(meaningfulImportValue)
    : category === "faturacao"
      ? [row.obra_numero, row.numero_fatura, row.data_emissao, row.valor].some(meaningfulImportValue)
      : [row.obra_numero, row.numero_documento, row.data, row.fornecedor, row.designacao, row.quantidade, row.valor_unitario].some(meaningfulImportValue));
}

export function managementSheetTable(matrix) {
  if (!matrix.length) return { rows: [], headerIndex: -1 };
  const headerIndex = matrix.findIndex(row => Array.isArray(row) && row.some(cell => ["obra", "obran", "numeroobra", "nobra"].includes(key(cell))));
  if (headerIndex < 0) return { rows: [], headerIndex };
  const headers = matrix[headerIndex].map((header, index) => String(header ?? `__coluna_${index}`));
  const rows = matrix.slice(headerIndex + 1).map(row => Object.fromEntries(headers.map((header, index) => [header, row[index] ?? null])));
  return { rows, headerIndex };
}

const normalizedWorkNumber = value => String(value ?? "").trim().replace(/^0+(?=\d)/, "");

export function validateManagementImportRows(rows) {
  const blocked = new Map();
  rows.forEach(row => {
    const work = normalizedWorkNumber(row.obra_numero);
    if (!BLOCKED_IMPORT_WORKS.has(work)) return;
    const entry = blocked.get(work) || { count: 0, lines: [] };
    entry.count += 1;
    if (entry.lines.length < 5) entry.lines.push(row.linha);
    blocked.set(work, entry);
  });
  return [...blocked.entries()].map(([work, entry]) => `Obra ${work} não aceita importação por este caminho — usar Saldo de Abertura. ${entry.count} linha(s) afetada(s)${entry.lines.length ? `; primeiras: ${entry.lines.join(", ")}` : ""}.`);
}

function managementImportFingerprint(row) {
  const category = String(row.categoria ?? "").trim();
  const work = normalizedWorkNumber(row.obra_numero);
  let document = row.numero_documento;
  let entity = row.fornecedor;
  let value = money(row.valor_total);
  if (category === "mao_obra") {
    document = row.data;
    entity = row.colaborador;
    const hours = money(row.horas), hourlyValue = money(row.valor_hora);
    value = hours == null || hourlyValue == null ? null : hours * hourlyValue;
  } else if (category === "faturacao") {
    document = row.numero_fatura;
    entity = "Cliente";
    value = money(row.valor_recebido) ?? money(row.valor);
  } else if (category === "estaleiro") {
    document ||= row.data;
    entity ||= row.colaborador;
  }
  if (!category || !work || !String(document ?? "").trim() || !String(entity ?? "").trim() || value == null) return null;
  return [category, work, norm(document), norm(entity), Number(value).toFixed(2)].join("|");
}

export function prepareManagementImportRows(rows) {
  const seen = new Set(), uniqueRows = [];
  let duplicates = 0;
  rows.forEach(row => {
    const fingerprint = managementImportFingerprint(row);
    if (fingerprint && seen.has(fingerprint)) duplicates += 1;
    else {
      if (fingerprint) seen.add(fingerprint);
      uniqueRows.push(row);
    }
  });
  return { rows: uniqueRows, duplicates };
}

export function parseManagementWorkbook(workbook) {
  const result = [], errors = [];
  for (const [category, aliases] of Object.entries(SHEETS)) {
    const sheetName = workbook.SheetNames.find(name => sheetMatches(name, category, aliases));
    if (!sheetName) {
      if (!OPTIONAL_SHEETS.has(category)) errors.push(`Folha em falta: ${CATEGORY_LABELS[category]}.`);
      continue;
    }
    const matrix = globalThis.XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], { header: 1, defval: null, raw: true });
    const table = managementSheetTable(matrix);
    if (matrix.length && table.headerIndex < 0) {
      errors.push(`Não foi possível localizar o cabeçalho com a coluna Obra na folha ${sheetName}.`);
      continue;
    }
    const rows = normalizeManagementRows(category, table.rows, table.headerIndex + 2);
    result.push(...rows);
  }
  errors.push(...validateManagementImportRows(result));
  return { rows: result, errors };
}

export function createManagementMapModule({ root, supabase, isConfigured, getWorks, euro, toast }) {
  const state = { loaded: false, loading: false, error: "", rows: [], mode: "categoria", importOpen: false, importRows: [], importReadyRows: [], importErrors: [], importProgress: "", preview: null, importing: false };
  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render(); state.loading = true; state.error = ""; render();
    try { if (!isConfigured) state.rows = []; else { const response = await supabase("rpc/fn_mapa_gestao_obras", { method: "POST", body: "{}" }); if (!response.ok) { const payload = await response.json().catch(() => ({})); throw new Error(payload.message || payload.details || "Não foi possível consultar o Mapa de Gestão."); } state.rows = await response.json(); } state.loaded = true; }
    catch (error) { state.error = error.message; } finally { state.loading = false; render(); }
  }
  function filters() { const form = root.querySelector("[data-management-map-filters]"); return form ? Object.fromEntries(new FormData(form)) : {}; }
  function filteredRows(category = "") { const value = filters(); return state.rows.filter(row => managementRowMatches(row, value, { mode: state.mode, category })); }
  const rowHtml = row => `<tr><td class="management-date">${esc(formatManagementDate(row.data_lancamento))}</td><td class="management-work"><strong>${esc(row.obra_numero || "—")}</strong><small>${esc(row.obra_nome || "")}</small></td><td><span class="management-category ${esc(row.categoria)}">${esc(CATEGORY_LABELS[row.categoria] || row.categoria)}</span></td><td class="management-wrap management-entity">${esc(row.entidade_nome || "—")}</td><td class="management-wrap management-description">${esc(row.descricao || "—")}</td><td class="management-document">${esc(row.documento || "—")}</td><td class="management-value">${euro.format(Number(row.valor || 0))}</td></tr>`;
  const table = (rows, empty = "SEM LANÇAMENTOS NESTE FILTRO") => `<div class="management-map-scroll"><table><thead><tr><th>DATA</th><th>OBRA</th><th>CATEGORIA</th><th>FORNECEDOR / COLABORADOR</th><th>DESCRIÇÃO</th><th>DOCUMENTO</th><th>VALOR</th></tr></thead><tbody>${rows.length ? rows.map(rowHtml).join("") : `<tr><td colspan="7" class="management-map-empty">${empty}</td></tr>`}</tbody></table></div>`;
  function renderResults() {
    const rows = filteredRows(), total = rows.reduce((sum, row) => sum + Number(row.valor || 0), 0);
    const summary = `<div class="management-map-summary"><span><small>LANÇAMENTOS VISÍVEIS</small><strong>${rows.length}</strong></span><span><small>VALOR VISÍVEL</small><strong>${euro.format(total)}</strong></span></div>`;
    if (state.mode === "obra") { const selected = filters().obra_id; return `<div class="management-map-result">${summary}${selected ? `<div class="management-work-blocks">${Object.entries(CATEGORY_LABELS).map(([category, label]) => { const categoryRows = filteredRows(category); return `<section><header><strong>${esc(label)}</strong><span>${categoryRows.length} registos · ${euro.format(categoryRows.reduce((sum, row) => sum + Number(row.valor || 0), 0))}</span></header>${table(categoryRows, `SEM REGISTOS DE ${label.toLocaleUpperCase("pt-PT")}`)}</section>`; }).join("")}</div>` : '<div class="management-map-empty management-select-work">ESCOLHA UMA OBRA PARA VER AS CINCO CATEGORIAS</div>'}</div>`; }
    return `<div class="management-map-result">${summary}${table(rows)}</div>`;
  }
  function renderImport() {
    if (!state.importOpen) return ""; const preview = state.preview || {};
    return `<section class="management-import"><header><div><strong>IMPORTAR MAPA DE GESTÃO</strong><span>Folhas obrigatórias: Materiais, Despesas-Estaleiro, Subcontratos e Funcionários-Obra. Faturação é opcional.</span></div><button type="button" data-close-management-import>×</button></header><label class="management-file">FICHEIRO .XLSX<input type="file" accept=".xlsx,.xls" data-management-import-file></label>${state.importProgress ? `<div class="work-warning"><strong>PROCESSAMENTO</strong><span>${esc(state.importProgress)}</span></div>` : ""}${state.importErrors.length ? `<div class="work-warning"><strong>VALIDAÇÃO</strong><span>${state.importErrors.map(esc).join(" · ")}</span></div>` : ""}${state.importRows.length ? `<div class="management-import-preview"><span><small>LINHAS LIDAS</small><strong>${state.importRows.length}</strong></span><span><small>A CRIAR</small><strong>${preview.criar ?? "—"}</strong></span><span><small>DUPLICADOS</small><strong>${preview.duplicados ?? "—"}</strong></span><span><small>COM ERRO</small><strong>${preview.erros?.length ?? 0}</strong></span></div>${preview.erros?.length ? `<div class="work-warning"><span>${summarizeManagementImportErrors(preview.erros).map(esc).join(" · ")}</span></div>` : ""}<button type="button" class="primary-action" data-confirm-management-import ${!state.preview || state.importing || preview.erros?.length ? "disabled" : ""}>${state.importing ? "A IMPORTAR…" : `CONFIRMAR IMPORTAÇÃO · ${preview.criar || 0} LINHAS`}</button>` : ""}</section>`;
  }
  function render() {
    const works = [...getWorks()].sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
    root.innerHTML = `<section class="panel management-map"><header><div><p class="eyebrow">CONSOLIDADO DA EMPRESA</p><h2>MAPA DE GESTÃO DE OBRAS</h2><p>Cinco categorias de custos e faturação, consultáveis por categoria ou por obra.</p></div><div class="management-head-actions"><button type="button" class="outline-action" data-open-management-import>IMPORTAR EXCEL</button><button type="button" class="outline-action" data-refresh-management-map>ATUALIZAR</button></div></header>${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)} Confirme se executou o SQL deste módulo.</span></div>` : ""}<div class="management-mode"><button type="button" data-management-mode="categoria" class="${state.mode === "categoria" ? "active" : ""}">POR CATEGORIA · TODAS AS OBRAS</button><button type="button" data-management-mode="obra" class="${state.mode === "obra" ? "active" : ""}">POR OBRA · TODAS AS CATEGORIAS</button></div><form class="management-map-filters" data-management-map-filters><label>OBRA<select name="obra_id"><option value="">${state.mode === "obra" ? "Escolher uma obra" : "Todas as obras"}</option>${works.map(work => `<option value="${work.id}">Obra ${esc(work.numero)} — ${esc(work.nome)}</option>`).join("")}</select></label><label class="${state.mode === "obra" ? "management-filter-disabled" : ""}">CATEGORIA<select name="categoria" ${state.mode === "obra" ? "disabled" : ""}><option value="">Todas as categorias</option>${Object.entries(CATEGORY_LABELS).map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select></label><label>DATA — DE<input type="date" name="data_inicio"></label><label>DATA — ATÉ<input type="date" name="data_fim"></label><label>FORNECEDOR / COLABORADOR<input name="entidade" placeholder="Pesquisar fornecedor ou colaborador"></label><label>DESCRIÇÃO<input name="descricao" placeholder="Pesquisar descrição"></label><label>DOCUMENTO<input name="documento" placeholder="Pesquisar documento"></label><label>VALOR EXATO (€)<input name="valor" type="number" min="0" step="0.01" placeholder="0,00"></label><button type="reset" class="outline-action management-clear-filters">LIMPAR FILTROS</button></form>${renderImport()}${state.loading ? '<div class="fleet-loading">A CARREGAR LANÇAMENTOS…</div>' : renderResults()}</section>`;
  }
  async function runImportBatches(rows, confirmImportRows) {
    const result = { linhas: rows.length, criar: 0, criados: 0, duplicados: 0, erros: [] };
    for (let start = 0; start < rows.length; start += IMPORT_BATCH_SIZE) {
      const batch = rows.slice(start, start + IMPORT_BATCH_SIZE);
      state.importProgress = `${confirmImportRows ? "A importar" : "A validar"} ${Math.min(start + batch.length, rows.length)} de ${rows.length} linhas…`;
      render();
      const response = await supabase("rpc/fn_importar_mapa_gestao", { method: "POST", body: JSON.stringify({ p_linhas: batch, p_confirmar: confirmImportRows }) });
      if (!response.ok) {
        const payload = await response.json().catch(() => ({}));
        throw new Error(payload.message || `${confirmImportRows ? "A importação" : "A validação"} falhou no lote iniciado na linha ${start + 1}.`);
      }
      const batchResult = await response.json();
      result.criar += Number(batchResult.criar || 0);
      result.criados += Number(batchResult.criados || 0);
      result.duplicados += Number(batchResult.duplicados || 0);
      result.erros.push(...(batchResult.erros || []));
    }
    state.importProgress = "";
    return result;
  }
  async function previewImport(rows) {
    const prepared = prepareManagementImportRows(rows);
    state.importReadyRows = prepared.rows;
    const result = await runImportBatches(prepared.rows, false);
    result.linhas = rows.length;
    result.duplicados += prepared.duplicates;
    state.preview = result;
    state.importProgress = "";
    render();
  }
  async function readImportFile(file) { state.importRows = []; state.importReadyRows = []; state.importErrors = []; state.importProgress = ""; state.preview = null; if (!globalThis.XLSX) { state.importErrors = ["O leitor Excel não está disponível."]; return render(); } const workbook = globalThis.XLSX.read(await file.arrayBuffer(), { type: "array", cellDates: false }); const parsed = parseManagementWorkbook(workbook); state.importRows = parsed.rows; state.importErrors = parsed.errors; render(); if (!parsed.errors.length) try { await previewImport(parsed.rows); } catch (error) { state.importProgress = ""; state.importErrors = [error.message]; render(); } }
  async function confirmImport() { if (!state.preview || state.importing) return; if (!confirm(`Importar ${state.preview.criar || 0} linhas? Os ${state.preview.duplicados || 0} duplicados serão ignorados.`)) return; state.importing = true; render(); try { const result = await runImportBatches(state.importReadyRows, true); toast(`${result.criados || 0} lançamentos importados. ${result.duplicados || 0} duplicados ignorados.`); state.importOpen = false; state.importRows = []; state.importReadyRows = []; state.preview = null; await load(true); } catch (error) { state.importProgress = ""; state.importErrors = [`${error.message} Pode repetir a importação em segurança: os lotes já gravados serão reconhecidos como duplicados.`]; } finally { state.importing = false; render(); } }
  root.addEventListener("input", event => { if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderResults())); });
  root.addEventListener("change", event => { if (event.target.matches("[data-management-import-file]")) { const [file] = event.target.files; if (file) readImportFile(file); return; } if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderResults())); });
  root.addEventListener("reset", () => setTimeout(() => root.querySelector(".management-map-result")?.replaceWith(fragment(renderResults())), 0));
  root.addEventListener("click", event => { const mode = event.target.closest("[data-management-mode]"); if (mode) { state.mode = mode.dataset.managementMode; render(); return; } if (event.target.closest("[data-open-management-import]")) { state.importOpen = true; render(); return; } if (event.target.closest("[data-close-management-import]")) { state.importOpen = false; render(); return; } if (event.target.closest("[data-confirm-management-import]")) { confirmImport(); return; } if (event.target.closest("[data-refresh-management-map]")) load(true).catch(error => toast(error.message, "error")); });
  function fragment(html) { const template = document.createElement("template"); template.innerHTML = html.trim(); return template.content.firstElementChild; }
  return { show: () => load(), refresh: () => load(true) };
}
