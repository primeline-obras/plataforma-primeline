const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const normalize = value => String(value ?? "").trim().normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-PT");
const number = value => {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const text = String(value ?? "").trim().replace(/\s/g, "");
  if (!text) return null;
  const normalized = text.includes(",") ? text.replace(/\./g, "").replace(",", ".") : text;
  const parsed = Number(normalized.replace(/[^0-9+-.]/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
};

const excelDate = value => {
  if (value == null || value === "") return null;
  if (value instanceof Date && !Number.isNaN(value.valueOf())) return value.toISOString().slice(0, 10);
  if (typeof value === "number" && globalThis.XLSX?.SSF?.parse_date_code) {
    const parsed = globalThis.XLSX.SSF.parse_date_code(value);
    if (parsed) return `${parsed.y}-${String(parsed.m).padStart(2, "0")}-${String(parsed.d).padStart(2, "0")}`;
  }
  const text = String(value).trim();
  const iso = text.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (iso) return `${iso[1]}-${iso[2].padStart(2, "0")}-${iso[3].padStart(2, "0")}`;
  const pt = text.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/);
  if (pt) return `${pt[3].length === 2 ? `20${pt[3]}` : pt[3]}-${pt[2].padStart(2, "0")}-${pt[1].padStart(2, "0")}`;
  return null;
};

const SUBCONTRACT_HEADERS = [
  "Obra (nº)*", "Fase (código)", "Trabalho / Especialidade*", "Fornecedor (nome)", "Custo Direto (€)",
  "Preço de Venda (€)", "Margem Prevista (€)", "Data do Pedido", "Data da Proposta", "Data do Contrato",
  "Valor Adjudicado (€)", "Tipo de Pagamento", "Condição de Pagamento", "Data Início Prevista", "Data Fim Prevista", "Estado*",
];
const TEE_HEADERS = ["Nº TEE*", "Obra (nº)*", "Fase (código)", "Descrição", "Especialidade", "Valor (€)", "Preço de Custo (€)", "Dias de Prorrogação", "Data de Envio", "Data de Resposta", "Estado Aprovação Cliente", "Revisão", "Data Início Execução", "Data Fim Execução"];
const TEE_ITEM_HEADERS = ["Nº TEE*", "Nº Artigo*", "Descrição*", "Unidade", "Quantidade", "Preço Unitário (€)", "Valor Total (€)"];
const MONTH_NAMES = [["jan", "janeiro"], ["fev", "fevereiro"], ["mar", "marco", "março"], ["abr", "abril"], ["mai", "maio"], ["jun", "junho"], ["jul", "julho"], ["ago", "agosto"], ["set", "setembro"], ["out", "outubro"], ["nov", "novembro"], ["dez", "dezembro"]];
const FIXED_LABELS = new Map([
  ["remuneracoes e encargos (sede)", "remuneracoes_sede"], ["remuneracoes e encargos sede", "remuneracoes_sede"],
  ["despesas sede", "despesas_sede"], ["despesas armazem", "despesas_armazem"],
]);

function rowsOf(workbook, sheetName) {
  const sheet = workbook.Sheets[sheetName];
  return sheet ? globalThis.XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: "" }) : [];
}

function exactSheet(workbook, sheetName, headers) {
  const rows = rowsOf(workbook, sheetName);
  if (!rows.length) throw new Error(`A folha “${sheetName}” não existe ou está vazia.`);
  const actual = rows[0].slice(0, headers.length).map(value => String(value).trim());
  const missing = headers.filter((header, index) => actual[index] !== header);
  if (missing.length || actual.length < headers.length) throw new Error(`A folha “${sheetName}” não segue o modelo: confirme os cabeçalhos e a respetiva ordem.`);
  return rows.slice(1).filter(row => row.some(value => String(value ?? "").trim()));
}

function parseSubcontracts(workbook, context) {
  const validStates = new Set(["em_consulta", "recusado", "adjudicado", "em_execucao", "concluido"]);
  const validPayments = new Set(["por_fase", "unico", "mensal", ""]);
  const validConditions = new Set(["imediato", "15_dias", "30_dias", ""]);
  const suppliers = new Map(context.suppliers.map(item => [normalize(item.nome), item]));
  const phases = new Map(context.phases.map(item => [normalize(item.codigo), item]));
  return exactSheet(workbook, "Subempreitadas", SUBCONTRACT_HEADERS).map((row, index) => {
    const errors = []; const warnings = [];
    const workNumber = String(row[0] ?? "").trim(); const specialty = String(row[2] ?? "").trim();
    const supplier = suppliers.get(normalize(row[3])); const phase = phases.get(normalize(row[1]));
    const state = normalize(row[15]).replaceAll(" ", "_"); const payment = normalize(row[11]).replaceAll(" ", "_"); const condition = normalize(row[12]).replaceAll(" ", "_");
    if (!workNumber || Number(workNumber) !== Number(context.work.numero)) errors.push(`A obra tem de ser ${context.work.numero}.`);
    if (!specialty) errors.push("Trabalho / Especialidade obrigatório.");
    if (row[1] && !phase) errors.push(`Fase “${row[1]}” não encontrada nesta obra.`);
    if (row[3] && !supplier) errors.push(`Fornecedor “${row[3]}” não existe; não será criado automaticamente.`);
    if (!validStates.has(state)) errors.push(`Estado inválido: ${row[15] || "vazio"}.`);
    if (!validPayments.has(payment)) errors.push(`Tipo de pagamento inválido: ${row[11]}.`);
    if (!validConditions.has(condition)) errors.push(`Condição de pagamento inválida: ${row[12]}.`);
    const start = excelDate(row[13]); const end = excelDate(row[14]);
    if (row[13] && !start) errors.push("Data de início inválida.");
    if (row[14] && !end) errors.push("Data de fim inválida.");
    if (start && end && end < start) errors.push("A data de fim é anterior à data de início.");
    if (["adjudicado", "em_execucao", "concluido"].includes(state) && !supplier) errors.push("Uma subempreitada adjudicada exige fornecedor existente.");
    if (["adjudicado", "em_execucao", "concluido"].includes(state) && !phase) errors.push("Uma subempreitada adjudicada exige fase.");
    if (["adjudicado", "em_execucao", "concluido"].includes(state) && number(row[10]) == null) errors.push("Uma subempreitada adjudicada exige valor adjudicado.");
    const duplicate = context.consultations.some(item => normalize(item.trabalho) === normalize(specialty) && (!supplier || !item.fornecedor_id || item.fornecedor_id === supplier.id))
      || context.subcontracts.some(item => normalize(item.especialidade) === normalize(specialty) && (!supplier || item.fornecedor_id === supplier.id));
    if (duplicate) warnings.push("Possível duplicado; por omissão será ignorado.");
    return {
      row: index + 2, label: specialty || `Linha ${index + 2}`, errors, warnings, duplicate, selected: !duplicate && !errors.length,
      payload: { obra_id: context.work.id, fase_id: phase?.id || null, trabalho: specialty, fornecedor_id: supplier?.id || null,
        custo_direto: number(row[4]), preco_venda: number(row[5]), margem_prevista: number(row[6]), data_pedido: excelDate(row[7]), data_proposta: excelDate(row[8]), data_contrato: excelDate(row[9]),
        valor_adjudicado: number(row[10]), tipo_pagamento: payment || null, condicao_pagamento: condition || null, data_inicio_prevista: start, data_fim_prevista: end, estado: state },
    };
  });
}

function parseTees(workbook, context) {
  const headers = exactSheet(workbook, "TEE_Cabeçalho", TEE_HEADERS);
  const itemRows = exactSheet(workbook, "TEE_Itens", TEE_ITEM_HEADERS);
  const phases = new Map(context.phases.map(item => [normalize(item.codigo), item]));
  const f01 = phases.get("f01") || context.phases.find(item => normalize(item.descricao).includes("estaleiro"));
  const validApproval = new Set(["pendente", "aprovado", "recusado", ""]);
  const itemsByTee = new Map();
  itemRows.forEach((row, index) => {
    const teeNumber = String(row[0] ?? "").trim();
    if (!itemsByTee.has(normalize(teeNumber))) itemsByTee.set(normalize(teeNumber), []);
    itemsByTee.get(normalize(teeNumber)).push({ linha: index + 2, numero_artigo: String(row[1] ?? "").trim(), descricao: String(row[2] ?? "").trim(), unidade: String(row[3] ?? "").trim() || null, quantidade: number(row[4]), preco_unitario: number(row[5]), valor_total: number(row[6]) });
  });
  const existing = new Set(context.tees.map(item => normalize(item.numero)));
  return headers.map((row, index) => {
    const errors = []; const warnings = [];
    const teeNumber = String(row[0] ?? "").trim(); const workNumber = String(row[1] ?? "").trim();
    const phase = row[2] ? phases.get(normalize(row[2])) : f01;
    const client = normalize(row[10]).replaceAll(" ", "_");
    const items = itemsByTee.get(normalize(teeNumber)) || [];
    if (!teeNumber) errors.push("Nº TEE obrigatório.");
    if (!String(row[3] ?? "").trim()) errors.push("Descrição obrigatória.");
    if (!workNumber || Number(workNumber) !== Number(context.work.numero)) errors.push(`A obra tem de ser ${context.work.numero}.`);
    if (!phase) errors.push(row[2] ? `Fase “${row[2]}” não encontrada.` : "A fase F01 não existe nesta obra.");
    if (!validApproval.has(client)) errors.push(`Estado do cliente inválido: ${row[10]}.`);
    const start = excelDate(row[12]); const end = excelDate(row[13]);
    if (row[12] && !start) errors.push("Data de início inválida.");
    if (row[13] && !end) errors.push("Data de fim inválida.");
    if ((start && !end) || (!start && end)) errors.push("Datas de execução incompletas.");
    if (start && end && end < start) errors.push("A data de fim é anterior à data de início.");
    items.forEach(item => { if (!item.numero_artigo || !item.descricao) errors.push(`Item da linha ${item.linha} sem Nº Artigo ou Descrição.`); });
    if (!items.length) warnings.push("TEE sem itens associados; será importado apenas o cabeçalho.");
    const duplicate = existing.has(normalize(teeNumber));
    if (duplicate) warnings.push("Nº TEE já existente; por omissão será ignorado.");
    return { row: index + 2, label: teeNumber || `Linha ${index + 2}`, errors, warnings, duplicate, selected: !duplicate && !errors.length,
      payload: { obra_id: context.work.id, fase_id: phase?.id || null, numero: teeNumber, descricao: String(row[3] ?? "").trim() || null, especialidade: String(row[4] ?? "").trim() || null,
        valor: number(row[5]), preco_custo: number(row[6]), dias_prorrogacao: number(row[7]) || 0, data_envio: excelDate(row[8]), data_resposta: excelDate(row[9]), estado_aprovacao_cliente: client || "pendente", revisao: String(row[11] ?? "").trim() || "REV00", data_inicio_execucao: start, data_fim_execucao: end, itens: items },
    };
  });
}

function findFinancialGrid(workbook) {
  for (const sheetName of workbook.SheetNames) {
    const rows = rowsOf(workbook, sheetName);
    for (let rowIndex = 0; rowIndex < Math.min(rows.length, 80); rowIndex += 1) {
      const normalized = rows[rowIndex].map(normalize);
      const monthColumns = MONTH_NAMES.map(names => normalized.findIndex(cell => names.includes(cell)));
      const workColumn = normalized.findIndex(cell => cell === "obra" || cell.includes("obra ") || cell === "nº obra" || cell === "numero obra");
      if (workColumn >= 0 && monthColumns.every(column => column >= 0)) return { sheetName, rows, rowIndex, workColumn, monthColumns };
    }
  }
  throw new Error("Não foi encontrada uma grelha com a coluna Obra e os meses Jan–Dez.");
}

function parseFinancial(workbook, context) {
  const grid = findFinancialGrid(workbook); const results = [];
  const works = context.works || [];
  for (let index = grid.rowIndex + 1; index < grid.rows.length; index += 1) {
    const row = grid.rows[index]; const label = String(row[grid.workColumn] ?? "").trim();
    if (!label) continue;
    const normalizedLabel = normalize(label); const fixedCategory = FIXED_LABELS.get(normalizedLabel);
    const monthly = grid.monthColumns.map(column => number(row[column]));
    if (fixedCategory) {
      const debitIds = new Set((context.debits || []).filter(item => item.categoria === fixedCategory && normalize(item.descricao).startsWith("importacao mapa financeiro")).map(item => item.id));
      const duplicate = (context.entries || []).some(item => debitIds.has(item.debito_direto_id) && String(item.data || "").startsWith(`${context.year}-`));
      results.push({ row: index + 1, label, errors: [], warnings: duplicate ? ["Já existem lançamentos importados neste ano; assinale para os substituir."] : [], duplicate, selected: !duplicate, payload: { tipo: "despesa_fixa", categoria: fixedCategory, meses: monthly } });
      continue;
    }
    const numeric = label.match(/\b0*(\d{1,4})\b/)?.[1];
    const work = works.find(item => numeric && Number(item.numero) === Number(numeric)) || works.find(item => normalizedLabel.includes(normalize(item.nome)) || normalize(item.nome).includes(normalizedLabel));
    if (!work) continue;
    const hasExisting = context.adjustments?.some(item => item.obra_id === work.id && item.ano === context.year && monthly[item.mes - 1] != null);
    const warnings = hasExisting ? ["Já existem ajustes neste ano; assinale a linha apenas se pretende substituí-los."] : [];
    results.push({ row: index + 1, label: `${work.numero} · ${work.nome}`, errors: [], warnings, duplicate: hasExisting, selected: !hasExisting, payload: { tipo: "obra", obra_id: work.id, meses: monthly } });
  }
  if (!results.length) throw new Error("A grelha foi encontrada, mas nenhuma obra ou grupo de despesas conhecido pôde ser lido.");
  return results;
}

function parsePhaseBudget(workbook, context) {
  const wantedSheet = workbook.SheetNames.find(name => normalize(name) === "0_orcamento" || normalize(name) === "0 orcamento");
  if (!wantedSheet) throw new Error("A folha “0_Orçamento” não foi encontrada.");
  const rows = rowsOf(workbook, wantedSheet);
  const aliases = {
    fase: ["fase", "codigo fase", "cod fase"], descricao: ["descricao", "designacao"],
    venda_prevista: ["venda prevista", "preco venda", "venda"], custo_total_estimado: ["custo total estimado", "custo total", "custo estimado"],
    margem_prevista: ["margem prevista", "margem"], deslocacoes: ["deslocacoes"], mao_obra: ["mao de obra", "m.o."],
    maquinas: ["maquinas"], materiais: ["materiais"], mao_obra_sub: ["m.o.sub", "mo sub", "mao de obra sub"], subempreitada: ["subempreitada", "subempreitadas"],
  };
  let headerIndex = -1; let columns = {};
  for (let index = 0; index < Math.min(rows.length, 25); index += 1) {
    const normalized = rows[index].map(normalize);
    const found = {};
    Object.entries(aliases).forEach(([key, names]) => { found[key] = normalized.findIndex(value => names.includes(value)); });
    if (found.fase >= 0 && (found.custo_total_estimado >= 0 || found.materiais >= 0)) { headerIndex = index; columns = found; break; }
  }
  if (headerIndex < 0) throw new Error("Não foi possível identificar o cabeçalho por fase na folha “0_Orçamento”.");
  const phases = context.phases || [];
  return rows.slice(headerIndex + 1).map((row, offset) => {
    const phaseText = String(row[columns.fase] ?? "").trim();
    if (!phaseText && row.every(value => String(value ?? "").trim() === "")) return null;
    const phase = phases.find(item => normalize(item.codigo) === normalize(phaseText) || normalize(item.descricao) === normalize(phaseText));
    const amount = key => columns[key] >= 0 ? number(row[columns[key]]) : 0;
    const components = ["deslocacoes", "mao_obra", "maquinas", "materiais", "mao_obra_sub", "subempreitada"].reduce((sum, key) => sum + (amount(key) || 0), 0);
    const total = amount("custo_total_estimado") ?? components;
    const errors = [];
    if (!phase) errors.push(`A fase “${phaseText || "(vazia)"}” não existe nesta obra.`);
    if (total == null || total < 0) errors.push("Custo total estimado inválido.");
    return { row: headerIndex + offset + 2, label: `${phaseText || "Fase"} · ${row[columns.descricao] || phase?.descricao || "Orçamento"}`, errors, warnings: [], selected: !errors.length, payload: {
      fase_id: phase?.id || null, descricao: String(row[columns.descricao] || phase?.descricao || "").trim() || null,
      venda_prevista: amount("venda_prevista") || 0, custo_total_estimado: total || 0, margem_prevista: amount("margem_prevista") || 0,
      deslocacoes: amount("deslocacoes") || 0, mao_obra: amount("mao_obra") || 0, maquinas: amount("maquinas") || 0,
      materiais: amount("materiais") || 0, mao_obra_sub: amount("mao_obra_sub") || 0, subempreitada: amount("subempreitada") || 0,
    } };
  }).filter(Boolean);
}

function status(row) {
  if (row.errors.length) return ["error", "COM ERRO"];
  if (row.duplicate) return ["warning", "POSSÍVEL DUPLICADO"];
  if (row.warnings.length) return ["warning", "COM AVISO"];
  return ["ready", "PRONTA"];
}

export function createOperationalXlsxImport({ supabase, isConfigured, getProfile, toast }) {
  const state = { module: "", title: "", file: null, rows: [], context: null, busy: false };
  let dialog;
  const ensureDialog = () => {
    if (dialog) return dialog;
    dialog = document.createElement("div"); dialog.className = "xlsx-import-overlay"; dialog.hidden = true;
    dialog.innerHTML = '<section class="xlsx-import-dialog" role="dialog" aria-modal="true"><header><div><p class="eyebrow">IMPORTAÇÃO CONTROLADA</p><h2 data-xlsx-title>IMPORTAR EXCEL</h2></div><button type="button" data-xlsx-close>×</button></header><div data-xlsx-content></div></section>';
    document.body.append(dialog);
    dialog.addEventListener("click", event => { if (event.target === dialog || event.target.closest("[data-xlsx-close]")) close(); });
    dialog.addEventListener("change", async event => {
      if (event.target.matches("[data-xlsx-file]")) await readFile(event.target.files?.[0]);
      if (event.target.matches("[data-xlsx-select]")) { const row = state.rows[Number(event.target.dataset.xlsxSelect)]; if (row && !row.errors.length) row.selected = event.target.checked; render(); }
    });
    dialog.addEventListener("click", async event => {
      if (event.target.closest("[data-xlsx-confirm]")) await confirmImport();
      if (event.target.closest("[data-xlsx-reset]")) { state.file = null; state.rows = []; render(); }
    });
    return dialog;
  };
  const api = async (path, options) => {
    const response = await supabase(path, options); const payload = await response.json().catch(() => null);
    if (!response.ok) throw new Error(payload?.message || payload?.details || "Não foi possível confirmar a importação.");
    return payload;
  };
  const close = () => { if (dialog) dialog.hidden = true; };
  const open = (module, title, context) => { Object.assign(state, { module, title, context, file: null, rows: [], busy: false }); ensureDialog().hidden = false; render(); };
  async function readFile(file) {
    if (!file) return;
    if (!/\.xlsx$/i.test(file.name)) return toast("Selecione um ficheiro .xlsx.", "error");
    if (!globalThis.XLSX) return toast("O leitor de Excel ainda não foi carregado. Atualize a página e tente novamente.", "error");
    try {
      const workbook = globalThis.XLSX.read(await file.arrayBuffer(), { type: "array", cellDates: false });
      const parsers = { subempreitadas: parseSubcontracts, tees: parseTees, mapa_financeiro: parseFinancial, orcamento_fases: parsePhaseBudget };
      state.rows = parsers[state.module](workbook, state.context); state.file = file; render();
    } catch (error) { state.file = null; state.rows = []; toast(error.message, "error"); render(error.message); }
  }
  function render(error = "") {
    if (!dialog) return;
    dialog.querySelector("[data-xlsx-title]").textContent = state.title;
    const ready = state.rows.filter(row => row.selected && !row.errors.length).length; const problems = state.rows.filter(row => row.errors.length || row.warnings.length).length;
    dialog.querySelector("[data-xlsx-content]").innerHTML = `${!state.file ? `<div class="xlsx-import-drop"><input type="file" accept=".xlsx" data-xlsx-file><strong>SELECIONAR FICHEIRO .XLSX</strong><span>Nada será gravado antes da pré-visualização e confirmação.</span>${error ? `<p>${esc(error)}</p>` : ""}</div>` : `<div class="xlsx-import-summary"><div><span>FICHEIRO</span><strong>${esc(state.file.name)}</strong></div><div class="ready"><span>PRONTAS</span><strong>${ready}</strong></div><div class="warning"><span>COM AVISO/ERRO</span><strong>${problems}</strong></div><button type="button" data-xlsx-reset>SUBSTITUIR FICHEIRO</button></div><div class="xlsx-import-table-wrap"><table class="xlsx-import-table"><thead><tr><th>IMPORTAR</th><th>LINHA</th><th>REGISTO</th><th>ESTADO</th><th>OBSERVAÇÕES</th></tr></thead><tbody>${state.rows.map((row, index) => { const [kind, label] = status(row); return `<tr class="${kind}"><td><input type="checkbox" data-xlsx-select="${index}" ${row.selected ? "checked" : ""} ${row.errors.length ? "disabled" : ""}></td><td>${row.row}</td><td><strong>${esc(row.label)}</strong></td><td><span>${label}</span></td><td>${[...row.errors, ...row.warnings].map(message => `<p>${esc(message)}</p>`).join("") || "Sem problemas"}</td></tr>`; }).join("")}</tbody></table></div><footer><p><strong>${ready} linhas prontas</strong> · ${state.rows.length - ready} não selecionadas ou bloqueadas</p><button class="primary-button" type="button" data-xlsx-confirm ${!ready || state.busy ? "disabled" : ""}>${state.busy ? "A IMPORTAR…" : "CONFIRMAR IMPORTAÇÃO"} <span>→</span></button></footer>`}`;
  }
  async function confirmImport() {
    const rows = state.rows.filter(row => row.selected && !row.errors.length).map(row => row.payload);
    if (!rows.length || state.busy) return;
    state.busy = true; render();
    try {
      const paths = { subempreitadas: "rpc/fn_importar_subempreitadas_xlsx", tees: "rpc/fn_importar_tees_xlsx", mapa_financeiro: "rpc/fn_importar_mapa_financeiro_xlsx", orcamento_fases: "rpc/fn_importar_orcamento_fases" };
      const body = state.module === "mapa_financeiro"
        ? { p_ano: state.context.year, p_linhas: rows, p_nome_ficheiro: state.file.name }
        : state.module === "orcamento_fases"
          ? { p_obra_id: state.context.work.id, p_linhas: rows, p_nome_ficheiro: state.file.name }
          : { p_linhas: rows, p_nome_ficheiro: state.file.name };
      const result = isConfigured ? await api(paths[state.module], { method: "POST", body: JSON.stringify(body) }) : { importadas: rows.length };
      toast(`${result?.importadas ?? rows.length} linha(s) importada(s) com auditoria registada.`); const callback = state.context.onComplete; close(); await callback?.();
    } catch (error) { toast(error.message, "error"); }
    finally { state.busy = false; render(); }
  }
  return {
    openSubcontracts: context => open("subempreitadas", "IMPORTAR SUBEMPREITADAS", context),
    openTees: context => open("tees", "IMPORTAR TEEs", context),
    openFinancial: context => open("mapa_financeiro", "IMPORTAR MAPA FINANCEIRO", context),
    openPhaseBudget: context => open("orcamento_fases", "IMPORTAR 0_ORÇAMENTO POR FASE", context),
  };
}

export const __test = { normalize, number, excelDate, parseSubcontracts, parseTees, parseFinancial, parsePhaseBudget };
