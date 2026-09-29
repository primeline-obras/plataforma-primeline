import { csvRows, normalizedHeader, parsedDate, parsedNumber, parsedState } from "./planning-import.js?v=1";
import { platformConfirm } from "./platform-dialogs.js?v=1";
import { activeTask, phaseProgress, workProgress, workDates, weightSummary, redistributeWeights } from "./planning-operational.js?v=1";
import { planningChanges, batchPreview, requestPlanningBatch } from "./planning-batch.js?v=1";
import { planningFinancialSummary } from "./monthly-api.js?v=1";

const DAY_MS = 86400000;

export function isoDate(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? "" : value.toISOString().slice(0, 10);
  }
  return value ? String(value).slice(0, 10) : "";
}

function dateValue(value) {
  const iso = isoDate(value);
  return iso ? new Date(`${iso}T00:00:00Z`) : null;
}

function addMonths(date, count) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + count, 1));
}

function daysBetween(start, end) {
  return Math.round((end - start) / DAY_MS);
}

function monthLabel(date) {
  return new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit", timeZone: "UTC" })
    .format(date).replace(".", "").toUpperCase();
}

function displayDate(value) {
  const date = dateValue(value);
  return date ? new Intl.DateTimeFormat("pt-PT", { dateStyle: "medium", timeZone: "UTC" }).format(date) : "—";
}

const euro = new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" });

function costStateLabel(value) {
  return {
    orcamentado: "Orçamentado / Não Comprometido",
    em_consulta: "Em Consulta",
    adjudicado: "Adjudicado",
    em_execucao: "Em Execução",
    concluido: "Concluído",
    cancelado: "Cancelado",
  }[value] || "Orçamentado / Não Comprometido";
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  })[character]);
}

function stateLabel(state) {
  return {
    concluido: "CONCLUÍDO",
    em_execucao: "EM EXECUÇÃO",
    por_iniciar: "POR INICIAR",
    em_atraso: "EM ATRASO",
  }[state] || "SEM ESTADO";
}

function visualState(item, today = new Date()) {
  if (item.estado === "concluido") return "concluido";
  const plannedEnd = dateValue(item.data_fim_prevista);
  const currentDay = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
  return plannedEnd && plannedEnd < currentDay ? "em_atraso" : (item.estado || "por_iniciar");
}

function isPastDay(date, today = new Date()) {
  const currentDay = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
  return Boolean(date && date < currentDay);
}

export function createPlanningModule({ supabase, isSupabaseConfigured, getWorks, getRole = () => "", toast, onCommitted = () => {} }) {
  const state = {
    workId: "", work: null, phases: [], items: [], dependencies: [], dependenciesLoaded: false, specialties: [],
    expanded: new Set(), expandedTasks: new Set(), collapsedEditorPhases: new Set(), loaded: false, view: "effective", costs: new Map(), costSummary: {}, budgetItems: [],
    importOpen: false, importRows: [], importErrors: [], saving: new Set(), controlMode: "baseline-planned",
    original: [], originalDependencies: [], batchSaving: false, preview: null, workDataOpen: false,
  };

  const workSelect = document.querySelector("#planning-work");
  const content = document.querySelector("#planning-content");
  const dependencyError = "As dependências não foram carregadas. Pode consultar e editar localmente, mas o preview e a gravação estão bloqueados até recarregar com sucesso.";
  const readOnly = () => getRole() === "encarregado";

  function renderWorkOptions() {
    const works = getWorks().slice().sort((a, b) =>
      String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
    workSelect.innerHTML = works.map(work =>
      `<option value="${work.id}">OBRA ${escapeHtml(work.numero || "—")} · ${escapeHtml(work.nome || "Sem designação")}</option>`
    ).join("");
    if (!state.workId && works[0]) state.workId = works[0].id;
    workSelect.value = state.workId;
    state.work = works.find(work => work.id === state.workId) || null;
  }

  function baselineDate(item, type) {
    const baselineField = type === "start" ? "data_inicio_baseline" : "data_fim_baseline";
    const currentField = type === "start" ? "data_inicio_prevista" : "data_fim_prevista";
    return state.work?.planeamento_baseline_congelado ? item[baselineField] : item[currentField];
  }

  function effectiveDate(item, type) {
    if (type === "start") return item.data_inicio_real || item.data_inicio_prevista;
    return item.data_fim_real || item.data_fim_prevista;
  }

  function scaleFor(mode) {
    const values = [];
    state.items.forEach(item => {
      if (mode !== "effective") values.push(baselineDate(item, "start"), baselineDate(item, "end"));
      if (mode !== "baseline") values.push(effectiveDate(item, "start"), effectiveDate(item, "end"));
    });
    const dates = values.map(dateValue).filter(Boolean);
    const today = new Date();
    const selectedStart = dateValue(state.work?.data_inicio);
    const selectedEnd = dateValue(state.work?.data_fim_prevista);
    const startCandidate = selectedStart || (dates.length ? new Date(Math.min(...dates)) : today);
    const endCandidate = selectedEnd || (dates.length ? new Date(Math.max(...dates)) : addMonths(today, 5));
    const start = new Date(Date.UTC(startCandidate.getUTCFullYear(), startCandidate.getUTCMonth(), 1));
    let end = addMonths(new Date(Date.UTC(endCandidate.getUTCFullYear(), endCandidate.getUTCMonth(), 1)), 1);
    if (end <= start) end = addMonths(start, 6);
    const totalDays = Math.max(daysBetween(start, end), 1);
    const months = [];
    for (let current = start; current < end; current = addMonths(current, 1)) {
      const next = addMonths(current, 1);
      months.push({ label: monthLabel(current), width: daysBetween(current, next) / totalDays * 100 });
    }
    return { start, end, totalDays, months };
  }

  function position(startValue, endValue, scale) {
    const start = dateValue(startValue);
    const end = dateValue(endValue) || start;
    if (!start || !end) return null;
    const left = Math.max(0, Math.min(100, daysBetween(scale.start, start) / scale.totalDays * 100));
    const rawWidth = Math.max(1.4, daysBetween(start, end) / scale.totalDays * 100);
    return { left, width: Math.min(rawWidth, Math.max(0, 100 - left)) };
  }

  function windowFor(items, dateGetter) {
    items = items.filter(activeTask);
    const starts = items.map(item => dateValue(dateGetter(item, "start"))).filter(Boolean);
    const ends = items.map(item => dateValue(dateGetter(item, "end"))).filter(Boolean);
    return starts.length && ends.length
      ? { start: new Date(Math.min(...starts)), end: new Date(Math.max(...ends)) }
      : null;
  }

  function monthHead(scale) {
    return `<div class="planning-months">${scale.months.map(month =>
      `<span style="width:${month.width}%">${month.label}</span>`).join("")}</div>`;
  }

  function todayLine(scale) {
    const today = new Date();
    if (today < scale.start || today > scale.end) return "";
    const left = Math.max(0, Math.min(100, daysBetween(scale.start, today) / scale.totalDays * 100));
    return `<i class="planning-today" style="left:${left}%"></i>`;
  }

  function effectiveTaskBar(item, scale) {
    const bar = position(effectiveDate(item, "start"), effectiveDate(item, "end"), scale);
    if (!bar) return `<span class="planning-no-dates">DATAS NÃO DEFINIDAS</span>`;
    const progress = Math.max(0, Math.min(100, Number(item.percentual_executado || 0)));
    return `<div class="planning-bar ${escapeHtml(visualState(item))} ${item.impedido ? "impedido" : ""}" style="left:${bar.left}%;width:${bar.width}%">
      <i style="width:${progress}%"></i><span>${progress}%</span>
    </div>`;
  }

  function effectivePhaseBar(items, scale) {
    const window = windowFor(items, effectiveDate);
    if (!window) return `<span class="planning-no-dates">DATAS NÃO DEFINIDAS</span>`;
    const bar = position(window.start, window.end, scale);
    const progress = phaseProgress(items) || 0;
    const phaseState = progress >= 100 ? "concluido" : isPastDay(window.end) ? "em_atraso" : progress > 0 ? "em_execucao" : "por_iniciar";
    return `${todayLine(scale)}<div class="planning-phase-bar ${phaseState}" style="left:${bar.left}%;width:${bar.width}%"><i style="width:${progress}%"></i></div>`;
  }

  function phaseOptions(selected) {
    return state.phases.map(phase => `<option value="${phase.id}" ${phase.id === selected ? "selected" : ""}>${escapeHtml(phase.codigo || "—")} · ${escapeHtml(phase.descricao || "Fase")}</option>`).join("");
  }

  function specialtyOptions(selected) {
    return `<option value="">Sem especialidade</option>${state.specialties.map(specialty =>
      `<option value="${specialty.id}" ${specialty.id === selected ? "selected" : ""}>${escapeHtml(specialty.nome)}</option>`
    ).join("")}`;
  }

  function dependencyOptions(item) {
    const linked = new Set(state.dependencies.filter(row => row.item_id === item.id).map(row => row.depende_de_item_id));
    return state.items.filter(candidate => activeTask(candidate) && candidate.id !== item.id && !linked.has(candidate.id) && !String(candidate.id).startsWith("draft-"))
      .map(candidate => `<option value="${candidate.id}">${escapeHtml(candidate.codigo || "—")} · ${escapeHtml(candidate.descricao)}</option>`).join("");
  }

  function renderDependencies(item) {
    if (!state.dependenciesLoaded) return `<div class="planning-dependency-editor"><small>DEPENDÊNCIAS NÃO CARREGADAS</small></div>`;
    const rows = state.dependencies.filter(row => row.item_id === item.id);
    return `<div class="planning-dependency-editor"><div>${rows.map(row => {
      const predecessor = state.items.find(candidate => candidate.id === row.depende_de_item_id);
      return `<span>${escapeHtml(predecessor?.codigo || "Tarefa")}${readOnly() ? "" : `<button type="button" data-remove-dependency="${row.id}" title="Remover dependência">×</button>`}</span>`;
    }).join("") || `<small>SEM PREDECESSORAS</small>`}</div>
      ${item._new || readOnly() ? "" : `<label><select data-dependency-choice><option value="">Esta tarefa depende de…</option>${dependencyOptions(item)}</select><button type="button" data-add-dependency="${item.id}">LIGAR</button></label>`}</div>`;
  }

  function taskDeviation(item) {
    const baselineStart = dateValue(baselineDate(item, "start"));
    const baselineEnd = dateValue(baselineDate(item, "end"));
    const currentStart = dateValue(item.data_inicio_prevista);
    const currentEnd = dateValue(item.data_fim_real || item.data_fim_prevista);
    const startDays = baselineStart && currentStart ? daysBetween(baselineStart, currentStart) : null;
    const endDays = baselineEnd && currentEnd ? daysBetween(baselineEnd, currentEnd) : null;
    const worstDays = startDays === null && endDays === null ? null : Math.max(startDays ?? -Infinity, endDays ?? -Infinity);
    const classification = controlClassification(worstDays);
    const comparison = worstDays === null ? "Sem dados para comparação"
      : worstDays < 0 ? `Adiantado — ${Math.abs(worstDays)} dias`
      : worstDays === 0 ? "Sem alteração"
      : `${classification.label.charAt(0)}${classification.label.slice(1).toLocaleLowerCase("pt-PT")} — ${worstDays} dias`;
    return { startDays, endDays, worstDays, classification, comparison };
  }

  function dayDeviation(value) {
    return value === null ? "—" : `${value > 0 ? "+" : ""}${value}`;
  }

  function renderEditor() {
    const locked = readOnly() || state.batchSaving ? "disabled" : "";
    return `<div class="planning-editor-wrap"><div class="planning-editor-head">
      <span>CÓDIGO</span><span>DESCRIÇÃO / TRABALHOS</span><span>RESPONSÁVEL</span><span>DATA INÍCIO</span><span>FIM PREV.</span><span>FIM REAL</span><span>PESO %</span><span>EXEC. %</span><span>% PONDERADA</span><span>ESTADO</span><span>AÇÕES</span>
    </div>${state.phases.map(phase => {
      const phaseItems = state.items.filter(item => item.fase_id === phase.id && !item.arquivado_em);
      const collapsed = state.collapsedEditorPhases.has(phase.id);
      const progress = phaseProgress(phaseItems);
      return `<section class="planning-editor-phase ${collapsed ? "collapsed" : ""}"><button class="planning-editor-phase-toggle" type="button" data-toggle-editor-phase="${phase.id}" aria-expanded="${!collapsed}"><i>${collapsed ? "+" : "−"}</i><strong>${escapeHtml(phase.codigo || "—")}</strong><span>${escapeHtml(phase.descricao || "FASE")}</span><em>${progress === null ? "—" : `${progress}%`}</em><b>${phaseItems.length} ${phaseItems.length === 1 ? "TAREFA" : "TAREFAS"}</b></button><div class="planning-editor-phase-rows" ${collapsed ? "hidden" : ""}>${phaseItems.map(item => {
      const cost = state.costs.get(String(item.id));
      const weighted = Number(item.peso_percentual || 0) * Number(item.percentual_executado || 0) / 100;
      const progressValue = Number(item.percentual_executado || 0);
      const status = progressValue >= 100 ? "concluido" : progressValue > 0 ? "em_execucao" : "por_iniciar";
      const detailsOpen = state.expandedTasks.has(item.id);
      return `<article class="planning-editor-row ${item._new ? "new" : ""} ${planningChanges(state.original, [item]).length ? "dirty" : ""} ${item._archive ? "archiving" : ""} ${detailsOpen ? "details-open" : ""}" data-edit-item="${item.id}">
      <input name="codigo" value="${escapeHtml(item.codigo || "")}" placeholder="F01.1" ${locked}>
      <textarea name="descricao" rows="2" placeholder="Descrição da tarefa" ${locked}>${escapeHtml(item.descricao || "")}</textarea>
      <input name="responsavel" value="${escapeHtml(item.responsavel || "")}" placeholder="Responsável" ${locked}>
      <input name="data_inicio_prevista" type="date" value="${isoDate(item.data_inicio_prevista)}" ${locked}>
      <input name="data_fim_prevista" type="date" value="${isoDate(item.data_fim_prevista)}" ${locked}>
      <input name="data_fim_real" type="date" value="${isoDate(item.data_fim_real)}" ${locked}>
      <input name="peso_percentual" type="number" min="0" step="0.01" value="${item.peso_percentual ?? ""}" ${locked}>
      <input name="percentual_executado" type="number" min="0" max="100" step="1" value="${item.percentual_executado ?? 0}" ${locked}>
      <output data-weighted>${weighted.toFixed(2)}%</output>
      <input name="estado" type="hidden" value="${escapeHtml(status)}"><output data-derived-state><span class="planning-state ${escapeHtml(status)}">${stateLabel(status)}</span></output>
      <div class="planning-row-actions ${readOnly() ? "readonly" : ""}"><button type="button" class="details" data-toggle-task="${item.id}" aria-expanded="${detailsOpen}">${detailsOpen ? "FECHAR" : "DETALHES"}</button>${readOnly() ? "" : `<button type="button" class="remove" data-remove-task="${item.id}" ${state.batchSaving ? "disabled" : ""}>${item._new ? "CANCELAR" : item._archive ? "DESFAZER RETIRADA" : "RETIRAR"}</button>${item._archive ? "<strong>A REMOVER</strong>" : ""}`}</div>
      <section class="planning-editor-details" ${detailsOpen ? "" : "hidden"}><label>FASE<select name="fase_id" ${locked}>${phaseOptions(item.fase_id)}</select></label><label>ESPECIALIDADE<select name="especialidade_id" ${locked}>${specialtyOptions(item.especialidade_id)}</select></label><label>EXECUTADO POR<select name="executado_por" ${locked}><option value="">Por definir</option><option value="PL" ${item.executado_por === "PL" ? "selected" : ""}>Primeline</option><option value="subempreitada" ${item.executado_por === "subempreitada" ? "selected" : ""}>Subempreitada</option><option value="misto" ${item.executado_por === "misto" ? "selected" : ""}>Misto · PL + Subempreitada</option></select></label><label>INÍCIO REAL<input name="data_inicio_real" type="date" value="${isoDate(item.data_inicio_real)}" ${locked}></label><label>ESTADO CUSTO<select name="custo_estado" ${locked}>${["orcamentado","em_consulta","adjudicado","em_execucao","concluido","cancelado"].map(value => `<option value="${value}" ${String(item.custo_estado || "orcamentado") === value ? "selected" : ""}>${costStateLabel(value)}</option>`).join("")}</select></label><label>DETALHE ORÇAMENTO<select name="item_orcamento_id" ${locked}><option value="">PACOTE / ESPECIALIDADE</option>${state.budgetItems.filter(row => row.fase_id === item.fase_id).map(row => `<option value="${row.id}" ${row.id === item.item_orcamento_id ? "selected" : ""}>${escapeHtml(row.codigo || row.designacao || row.descricao || "Linha do orçamento")}</option>`).join("")}</select></label><label>VALOR ORÇA PL €<input name="valor_orca_pl" type="number" min="0" step="0.01" value="${item.valor_orca_pl ?? item.valor_estimado ?? ""}" placeholder="0,00" ${locked}></label><div class="planning-cost-reference">${cost ? `<b>ADJ. ${euro.format(cost.valor_adjudicado)}</b><span>REAL ${euro.format(cost.custo_real)}</span><span>COMP. ${euro.format(cost.compromisso_remanescente)}</span><span>FAT. ${cost.percentual_faturado == null ? "—" : `${cost.percentual_faturado.toFixed(1)}%`} · PAGO ${cost.percentual_pago == null ? "—" : `${cost.percentual_pago.toFixed(1)}%`}</span>${cost.confirmacao_pendente ? `<small>CONFIRMAÇÃO PENDENTE NO CARD “COMPOSIÇÃO AUDITÁVEL DO CUSTO” DA OBRA</small>` : ""}` : `<span>${state.costSummary ? "SEM COMPONENTES DE CUSTO ASSOCIADOS À TAREFA" : "CUSTOS INDISPONÍVEIS"}</span>`}</div><label class="planning-detail-wide">CAUSA DO ATRASO<textarea name="causa_atraso" rows="2" placeholder="Sem causa registada" ${locked}>${escapeHtml(item.causa_atraso || "")}</textarea></label><label class="planning-detail-wide">IMPACTO<textarea name="impacto" rows="2" placeholder="Sem impacto registado" ${locked}>${escapeHtml(item.impacto || "")}</textarea></label>${renderDependencies(item)}</section>
    </article>`; }).join("") || `<div class="planning-phase-empty">SEM TAREFAS NESTA FASE</div>`}</div></section>`;
    }).join("")}</div>`;
  }

  function renderCostSummary() {
    if (!state.costSummary) return '<div class="planning-cost-summary">CUSTOS INDISPONÍVEIS</div>';
    const real = state.costSummary.real || {};
    const remaining = state.costSummary.por_concluir || {};
    const componentsPayload = state.costSummary.componentes;
    const components = Array.isArray(componentsPayload) ? componentsPayload : componentsPayload?.pacotes || [];
    const availableTotal = field => {
      const rows = components.filter(row => row.fonte === "0_Orçamento" && row[field] != null && Number.isFinite(Number(row[field])));
      return rows.length ? rows.reduce((total, row) => total + Number(row[field]), 0) : null;
    };
    const materials = availableTotal("materiais");
    const labor = availableTotal("mao_obra");
    return `<div class="planning-cost-summary"><article><span>CUSTO REAL</span><strong>${euro.format(Number(real.total || 0))}</strong></article><article><span>CUSTOS ESTIMADOS</span><strong>${euro.format(Number(remaining.pl || 0) + Number(remaining.sub_orcamento_aguarda_confirmacao || 0))}</strong></article>${materials === null ? "" : `<article><span>MATERIAIS · ORÇAMENTO</span><strong>${euro.format(materials)}</strong></article>`}${labor === null ? "" : `<article><span>MÃO DE OBRA · ORÇAMENTO</span><strong>${euro.format(labor)}</strong></article>`}<article><span>SUBEMPREITADAS · COMPROMISSO</span><strong>${euro.format(Number(remaining.sub_compromisso_remanescente || 0))}</strong></article><article><span>ESTIMATIVA FINAL</span><strong>${euro.format(Number(state.costSummary.estimativa_terminus_total || 0))}</strong></article></div>`;
  }

  function renderImportPanel() {
    if (!state.importOpen) return "";
    const creates = state.importRows.filter(row => !row._existing && !row._error).length;
    const updates = state.importRows.filter(row => row._existing && !row._error).length;
    return `<section class="planning-import-panel"><header><div><strong>IMPORTAR TAREFAS</strong><span>Cole uma tabela do Excel/Sheets ou selecione um ficheiro .xlsx/.csv.</span></div><button type="button" data-close-import>×</button></header>
      <div class="planning-import-inputs"><label>COLAR CÉLULAS<textarea data-import-paste rows="6" placeholder="Código&#9;Descrição&#9;Responsável&#9;Data Início&#9;Data Fim Prevista…"></textarea></label><label class="planning-import-file">FICHEIRO<input data-import-file type="file" accept=".xlsx,.xls,.csv,.tsv"><span>SELECIONAR .XLSX OU .CSV</span></label></div>
      <p>Colunas reconhecidas: Código, Descrição, Responsável, Data Início, Data Fim Prevista, Data Início Real, Data Fim Real, Peso (%), % Executado e Estado. A fase é identificada pelo prefixo do código.</p>
      ${state.importRows.length || state.importErrors.length ? `<div class="planning-import-preview"><div><article><span>LINHAS VÁLIDAS</span><strong>${creates + updates}</strong></article><article><span>A CRIAR</span><strong>${creates}</strong></article><article><span>A ATUALIZAR</span><strong>${updates}</strong></article><article class="${state.importErrors.length ? "error" : ""}"><span>COM ERRO</span><strong>${state.importErrors.length}</strong></article></div>
        ${state.importErrors.length ? `<ul>${state.importErrors.slice(0, 8).map(error => `<li>${escapeHtml(error)}</li>`).join("")}</ul>` : ""}
        <button type="button" data-confirm-import ${state.importErrors.length || !(creates + updates) ? "disabled" : ""}>CONFIRMAR IMPORTAÇÃO · ${creates + updates} TAREFAS</button></div>` : ""}
    </section>`;
  }

  function renderEffective() {
    const scale = scaleFor("effective");
    const predecessorCount = state.dependencies.reduce((result, dependency) => {
      result[dependency.item_id] = (result[dependency.item_id] || 0) + 1;
      return result;
    }, {});
    return `<div class="planning-effective-toolbar"><div><button type="button" data-open-import>⇧ IMPORTAR TAREFAS</button><button type="button" class="primary" data-new-task>＋ NOVA TAREFA</button></div><span>${state.items.filter(item => !item._new && activeTask(item)).length} TAREFAS</span></div>
    ${renderCostSummary()}${renderImportPanel()}${renderEditor()}
    <div class="planning-gantt-title"><div><strong>GANTT EFETIVO</strong><span>Atualizado a partir da grelha acima</span></div></div>
    <div class="planning-grid planning-grid-head">
      <div>FASE / TAREFA</div><div>RESPONSÁVEL</div>${monthHead(scale)}<div>ESTADO</div>
    </div>${state.phases.map(phase => {
      const items = state.items.filter(item => item.fase_id === phase.id);
      const expanded = state.expanded.has(phase.id);
      const progress = phaseProgress(items);
      return `<section class="planning-phase ${expanded ? "expanded" : ""}">
        <button class="planning-grid planning-phase-row" type="button" data-planning-phase="${phase.id}" aria-expanded="${expanded}">
          <div><b>${expanded ? "−" : "+"}</b><span><strong>${escapeHtml(phase.codigo || "")}</strong>${escapeHtml(phase.descricao || "Fase")}</span></div>
          <div>${items.length} ${items.length === 1 ? "TAREFA" : "TAREFAS"}</div>
          <div class="planning-phase-track" style="--months:${scale.months.length}">${items.length ? effectivePhaseBar(items, scale) : `<span class="planning-no-dates">SEM TAREFAS</span>`}</div>
          <div><em>${progress === null ? "—" : `${progress}%`}</em></div>
        </button>
        <div class="planning-tasks" ${expanded ? "" : "hidden"}>${items.length ? items.map(item =>
          `<article class="planning-grid planning-task-row ${item.impedido ? "planning-task-blocked" : ""}">
            <div><strong>${escapeHtml(item.codigo || "SUB")}</strong><span>${escapeHtml(item.descricao)}</span>
              ${item.recalculado_automaticamente ? `<small>↻ RECALCULADO AUTOMATICAMENTE</small>` : ""}
              ${item.impedido ? `<em class="planning-blocked-note"><b>IMPEDIDA</b>${escapeHtml(item.observacao_impedimento || "Sem observação")}</em>` : ""}</div>
            <div>${escapeHtml(item.responsavel || "Não definido")}<small>${predecessorCount[item.id] || 0} PREDECESSORAS</small></div>
            <div class="planning-track" style="--months:${scale.months.length}">${todayLine(scale)}${effectiveTaskBar(item, scale)}</div>
            <div><span class="planning-state ${item.impedido ? "impedido" : escapeHtml(visualState(item))}">${item.impedido ? "IMPEDIDA" : stateLabel(visualState(item))}</span>
              <small>${isoDate(effectiveDate(item, "start")) || "—"} → ${isoDate(effectiveDate(item, "end")) || "—"}</small></div>
          </article>`).join("") : `<div class="planning-phase-empty">SEM TAREFAS NESTA FASE</div>`}</div>
      </section>`;
    }).join("")}`;
  }

  function renderBaseline() {
    const scale = scaleFor("baseline");
    const frozen = Boolean(state.work?.planeamento_baseline_congelado);
    const notice = frozen
      ? `<div class="planning-baseline-notice frozen"><strong>BASELINE CONGELADA</strong><span>Datas originais preservadas em ${displayDate(state.work?.planeamento_baseline_congelado_em)}.</span></div>`
      : `<div class="planning-baseline-notice pending"><strong>AINDA NÃO CONGELADO</strong><span>Esta vista baseia-se nas datas previstas atuais até ao congelamento automático aos 30 dias.</span></div>`;
    return `${notice}<div class="planning-baseline-table">
      <div class="planning-baseline-head"><div>FASE / TAREFA</div>${monthHead(scale)}<div>PERÍODO ORIGINAL</div></div>
      ${state.phases.map(phase => {
        const items = state.items.filter(item => item.fase_id === phase.id);
        return `<section class="planning-baseline-phase"><header><strong>${escapeHtml(phase.codigo || "—")}</strong><span>${escapeHtml(phase.descricao || "Fase")}</span></header>
          ${items.map(item => {
            const start = baselineDate(item, "start");
            const end = baselineDate(item, "end");
            const bar = position(start, end, scale);
            return `<article class="planning-baseline-row"><div><b>${escapeHtml(item.codigo || "SUB")}</b><span>${escapeHtml(item.descricao)}</span></div>
              <div class="planning-baseline-track" style="--months:${scale.months.length}">${bar ? `<i style="left:${bar.left}%;width:${bar.width}%"></i>` : `<small>SEM DATAS DE BASELINE</small>`}</div>
              <div>${displayDate(start)}<b>→</b>${displayDate(end)}</div></article>`;
          }).join("") || `<div class="planning-phase-empty">SEM TAREFAS NESTA FASE</div>`}
        </section>`;
      }).join("")}</div>`;
  }

  function renderBaselineNotice() {
    return state.work?.planeamento_baseline_congelado
      ? `<div class="planning-baseline-notice frozen"><strong>BASELINE CONGELADA</strong><span>Datas originais preservadas em ${displayDate(state.work?.planeamento_baseline_congelado_em)}.</span></div>`
      : `<div class="planning-baseline-notice pending"><strong>BASELINE AINDA NÃO CONGELADA</strong><span>Até ao congelamento automático aos 30 dias, a comparação usa as datas previstas atuais.</span></div>`;
  }

  function deviation(windowBaseline, windowEffective) {
    if (!windowBaseline || !windowEffective) return { state: "no-data", label: "SEM COMPARAÇÃO", days: null };
    const days = daysBetween(windowBaseline.end, windowEffective.end);
    if (days > 0) return { state: "late", label: "ATRASADA", days };
    if (days < 0) return { state: "ahead", label: "ADIANTADA", days };
    return { state: "on-time", label: "DENTRO DO PRAZO", days: 0 };
  }

  function summaryBar(window, scale, className) {
    if (!window) return "";
    const bar = position(window.start, window.end, scale);
    return `<i class="${className}" style="left:${bar.left}%;width:${bar.width}%"></i>`;
  }

  function renderSummary() {
    const scale = scaleFor("summary");
    const rows = state.phases.map(phase => {
      const items = state.items.filter(item => item.fase_id === phase.id);
      const baseline = windowFor(items, baselineDate);
      const effective = windowFor(items, effectiveDate);
      const status = deviation(baseline, effective);
      return { phase, items, baseline, effective, status, progress: phaseProgress(items) };
    });
    const counts = rows.reduce((result, row) => { result[row.status.state] = (result[row.status.state] || 0) + 1; return result; }, {});
    return `<div class="planning-summary-kpis"><article class="late"><span>ATRASADAS</span><strong>${counts.late || 0}</strong></article><article class="on-time"><span>DENTRO DO PRAZO</span><strong>${counts["on-time"] || 0}</strong></article><article class="ahead"><span>ADIANTADAS</span><strong>${counts.ahead || 0}</strong></article></div>
      <div class="planning-summary-table"><div class="planning-summary-head"><div>FASE</div>${monthHead(scale)}<div>DESVIO</div><div>EXECUÇÃO</div></div>
      ${rows.map(({ phase, baseline, effective, status, progress }) => `<article class="planning-summary-row ${status.state}">
        <div><strong>${escapeHtml(phase.codigo || "—")}</strong><span>${escapeHtml(phase.descricao || "Fase")}</span><em>${status.label}</em></div>
        <div class="planning-summary-track" style="--months:${scale.months.length}">${todayLine(scale)}${summaryBar(baseline, scale, "baseline")}${summaryBar(effective, scale, "effective")}</div>
        <div><strong>${status.days === null ? "—" : status.days === 0 ? "0 dias" : `${status.days > 0 ? "+" : ""}${status.days} dias`}</strong><small>${displayDate(baseline?.end)} → ${displayDate(effective?.end)}</small></div>
        <div><b>${progress === null ? "—" : `${progress}%`}</b></div></article>`).join("")}
      <div class="planning-summary-legend"><span><i class="baseline"></i>BASELINE</span><span><i class="effective"></i>EFETIVO</span><strong>A LINHA VERMELHA MARCA HOJE</strong></div></div>`;
  }

  function controlSource(item, source, type) {
    if (source === "baseline") return baselineDate(item, type);
    if (source === "planned") return item[type === "start" ? "data_inicio_prevista" : "data_fim_prevista"];
    return item[type === "start" ? "data_inicio_real" : "data_fim_real"];
  }

  function controlClassification(days) {
    if (days === null) return { key: "no-data", label: "SEM DADOS" };
    if (days < 0) return { key: "anticipated", label: "ANTECIPADO" };
    if (days === 0) return { key: "unchanged", label: "SEM ALTERAÇÃO" };
    if (days <= 7) return { key: "slight", label: "ATRASO LIGEIRO" };
    if (days <= 15) return { key: "moderate", label: "ATRASO MODERADO" };
    if (days <= 30) return { key: "high", label: "ATRASO ELEVADO" };
    return { key: "critical", label: "ATRASO CRÍTICO" };
  }

  function renderControl() {
    const [from, to] = state.controlMode.split("-");
    const rows = state.phases.map(phase => {
      const items = state.items.filter(item => item.fase_id === phase.id);
      const reference = windowFor(items, (item, type) => controlSource(item, from, type));
      const comparison = windowFor(items, (item, type) => controlSource(item, to, type));
      const startDays = reference && comparison ? daysBetween(reference.start, comparison.start) : null;
      const endDays = reference && comparison ? daysBetween(reference.end, comparison.end) : null;
      const worstDays = startDays === null || endDays === null ? null : Math.max(startDays, endDays);
      return { phase, reference, comparison, startDays, endDays, worstDays, classification: controlClassification(worstDays) };
    });
    const dayText = value => value === null ? "—" : `${value > 0 ? "+" : ""}${value} dias`;
    return `<div class="planning-control-toolbar"><div><strong>COMPARAR DATAS</strong><span>A classificação considera o pior desvio entre o início e o fim.</span></div><select data-control-mode>
      <option value="baseline-planned" ${state.controlMode === "baseline-planned" ? "selected" : ""}>Inicial × Previsto</option>
      <option value="baseline-real" ${state.controlMode === "baseline-real" ? "selected" : ""}>Inicial × Real</option>
      <option value="planned-real" ${state.controlMode === "planned-real" ? "selected" : ""}>Previsto × Real</option>
    </select></div>
    <div class="planning-control-criteria"><span class="anticipated">ANTECIPADO · &lt; 0</span><span class="unchanged">SEM ALTERAÇÃO · 0</span><span class="slight">LIGEIRO · 1–7</span><span class="moderate">MODERADO · 8–15</span><span class="high">ELEVADO · 16–30</span><span class="critical">CRÍTICO · &gt; 30 DIAS</span></div>
    <div class="planning-control-table"><div class="planning-control-head"><span>FASE</span><span>PERÍODO DE REFERÊNCIA</span><span>PERÍODO COMPARADO</span><span>DESVIO INÍCIO</span><span>DESVIO FIM</span><span>CLASSIFICAÇÃO</span></div>
      ${rows.map(row => `<article><div><strong>${escapeHtml(row.phase.codigo || "—")}</strong><span>${escapeHtml(row.phase.descricao || "Fase")}</span></div><div>${displayDate(row.reference?.start)}<b>→</b>${displayDate(row.reference?.end)}</div><div>${displayDate(row.comparison?.start)}<b>→</b>${displayDate(row.comparison?.end)}</div><div>${dayText(row.startDays)}</div><div>${dayText(row.endDays)}</div><div><em class="${row.classification.key}">${row.classification.label}</em></div></article>`).join("")}
    </div>`;
  }

  function renderUnifiedPlanning() {
    return `<section class="planning-unified-detail"><header><div><p class="eyebrow">PLANEAMENTO DA OBRA</p><h3>Tarefas organizadas por fase</h3></div><span>${state.items.filter(item => !item._new && activeTask(item)).length} TAREFAS</span></header>
        <div class="planning-effective-toolbar">${readOnly() ? `<span>CONSULTA · O ENCARREGADO NÃO PODE CRIAR, EDITAR OU APAGAR TAREFAS</span>` : `<div><button type="button" data-open-import>⇧ IMPORTAR TAREFAS</button><button type="button" class="primary" data-new-task>＋ NOVA TAREFA</button></div><button type="button" data-save-batch ${!dirtyCount() || state.batchSaving || !state.dependenciesLoaded ? "disabled" : ""}>GUARDAR ALTERAÇÕES · ${dirtyCount()}</button>`}</div>
        ${!state.dependenciesLoaded ? `<p class="form-error" role="alert">${dependencyError}</p>` : ""}
        ${renderBatchPreview()}${renderWeights()}${renderImportPanel()}${renderEditor()}
      </section>`;
  }

  function renderWorkData() {
    const work = state.work || {};
    const dates = workDates(work, workProgress(state.phases, state.items), new Date().toLocaleDateString("en-CA"));
    const percent = value => value === null ? "—" : `${value.toFixed(1)}%`;
    return `<details class="planning-work-data"><summary>DADOS DA OBRA</summary><dl>
      <div><dt>Início da obra</dt><dd>${displayDate(work.data_inicio)}</dd></div>
      <div><dt>Fim contratual inicial</dt><dd>${displayDate(work.data_fim_contratual_inicial)}</dd></div>
      <div><dt>Fim contratual atual</dt><dd>${displayDate(dates.contractualEnd)}</dd></div>
      <div><dt>Fim operacional previsto</dt><dd>${displayDate(dates.operationalEnd)}</dd></div>
      <div><dt>Execução física ponderada</dt><dd>${percent(dates.progress)}</dd></div>
      <div><dt>Prazo contratual consumido</dt><dd>${percent(dates.consumed)}</dd></div>
      <div><dt>Execução − prazo</dt><dd>${dates.difference === null ? "—" : `${dates.difference.toFixed(1)} p.p.`}</dd></div>
      <div><dt>Desvio do fim operacional face ao contrato</dt><dd>${dates.delayDays === null ? "—" : `${dates.delayDays} dias`}</dd></div>
      </dl>${!weightSummary(state.phases).valid ? '<p>PESOS GLOBAIS DAS FASES NÃO CONFIGURADOS</p>' : ""}
      ${!dates.contractualEnd ? '<p>Prazo contratual não configurado. A previsão operacional é apresentada separadamente.</p>' : ""}</details>`;
  }

  function viewMeta() {
    return {
      baseline: ["PLANEAMENTO INICIAL", "Baseline contratual apenas para consulta"],
      effective: ["PLANEAMENTO EFETIVO", "Tarefas, dependências, progresso e datas atuais"],
      summary: ["RESUMO POR FASE", "Comparação entre o plano original e o efetivo"],
      control: ["CONTROLO DE PLANEAMENTO", "Classificação dos desvios entre datas iniciais, previstas e reais"],
    }[state.view];
  }

  function phaseForCode(code, explicitPhase = "") {
    const target = String(explicitPhase || code || "").trim().toLocaleLowerCase("pt-PT");
    return [...state.phases].sort((a, b) => String(b.codigo || "").length - String(a.codigo || "").length)
      .find(phase => target === String(phase.codigo || "").toLocaleLowerCase("pt-PT") || target.startsWith(`${String(phase.codigo || "").toLocaleLowerCase("pt-PT")}.`) || target.startsWith(`${String(phase.codigo || "").toLocaleLowerCase("pt-PT")}-`));
  }

  function prepareImport(matrix) {
    const errors = [];
    if (!matrix.length) { state.importRows = []; state.importErrors = ["A tabela está vazia."]; render(); return; }
    const headers = matrix[0].map(normalizedHeader);
    const aliases = {
      codigo: ["codigo", "cod"], descricao: ["descricao", "designacao"], responsavel: ["responsavel"],
      data_inicio_prevista: ["data inicio", "inicio", "data inicio prevista"], data_fim_prevista: ["data fim prevista", "fim previsto"],
      data_inicio_real: ["data inicio real", "inicio real"], data_fim_real: ["data fim real", "fim real"], peso_percentual: ["peso %", "peso", "peso percentual"],
      percentual_executado: ["% executado", "executado %", "percentual executado", "execucao %"], estado: ["estado"], fase: ["fase"],
      causa_atraso: ["causa do atraso", "causa atraso"], impacto: ["impacto"],
    };
    const positions = Object.fromEntries(Object.entries(aliases).map(([field, names]) => [field, headers.findIndex(header => names.includes(header))]));
    if (positions.codigo < 0 || positions.descricao < 0) errors.push("Os cabeçalhos Código e Descrição são obrigatórios.");
    const seen = new Set();
    const rows = matrix.slice(1).filter(row => row.some(value => String(value ?? "").trim())).map((row, index) => {
      const get = field => positions[field] >= 0 ? row[positions[field]] : "";
      const codigo = String(get("codigo") || "").trim();
      const descricao = String(get("descricao") || "").trim();
      const phase = phaseForCode(codigo, get("fase"));
      const progress = parsedNumber(get("percentual_executado"), 0);
      const weight = parsedNumber(get("peso_percentual"));
      const item = {
        fase_id: phase?.id, codigo, descricao, responsavel: String(get("responsavel") || "").trim() || null,
        data_inicio_prevista: parsedDate(get("data_inicio_prevista")), data_fim_prevista: parsedDate(get("data_fim_prevista")),
        data_inicio_real: parsedDate(get("data_inicio_real")), data_fim_real: parsedDate(get("data_fim_real")), peso_percentual: weight,
        percentual_executado: progress, percentual_ponderado: weight === null ? null : weight * progress / 100,
        estado: parsedState(get("estado"), progress), causa_atraso: String(get("causa_atraso") || "").trim() || null,
        impacto: String(get("impacto") || "").trim() || null,
      };
      const rowErrors = [];
      if (!codigo) rowErrors.push("Código em falta");
      if (!descricao) rowErrors.push("Descrição em falta");
      if (!phase) rowErrors.push(`fase não identificada pelo código ${codigo || "—"}`);
      if (seen.has(codigo.toLocaleLowerCase("pt-PT"))) rowErrors.push(`código ${codigo} repetido no ficheiro`);
      seen.add(codigo.toLocaleLowerCase("pt-PT"));
      if (item.data_inicio_prevista && item.data_fim_prevista && item.data_fim_prevista < item.data_inicio_prevista) rowErrors.push("fim previsto anterior ao início");
      item._existing = state.items.find(existing => !existing._new && String(existing.codigo || "").trim().toLocaleLowerCase("pt-PT") === codigo.toLocaleLowerCase("pt-PT")) || null;
      if (rowErrors.length) { item._error = true; errors.push(`Linha ${index + 2}: ${rowErrors.join("; ")}.`); }
      return item;
    });
    state.importRows = rows; state.importErrors = errors; render();
  }

  function dirtyCount() {
    return planningChanges(state.original, state.items).length
      + (JSON.stringify(state.dependencies) !== JSON.stringify(state.originalDependencies) ? 1 : 0);
  }

  function renderWeights() {
    const rows = state.phases.map(phase => {
      const weights = weightSummary(state.items.filter(item => item.fase_id === phase.id));
      if (weights.count === 0) return "";
      return `<div><strong>${escapeHtml(phase.codigo)}</strong> · PESO ATRIBUÍDO ${weights.assigned.toFixed(2)}% · FALTA DISTRIBUIR ${weights.missing.toFixed(2)}%${weights.excess ? ` · EXCESSO ${weights.excess.toFixed(2)}%` : ""}${readOnly() ? "" : `<button type="button" data-redistribute="${phase.id}" ${state.batchSaving ? "disabled" : ""}>REDISTRIBUIR PROPORCIONALMENTE</button>`}</div>`;
    }).join("");
    return rows ? `<div class="planning-weights">${rows}</div>` : "";
  }

  function captureInput(input) {
    const row = input.closest("[data-edit-item]");
    const item = state.items.find(candidate => candidate.id === row?.dataset.editItem);
    if (!item || !input.name || readOnly() || state.batchSaving) return;
    const numeric = ["peso_percentual", "percentual_executado", "valor_orca_pl"];
    item[input.name] = numeric.includes(input.name) ? (input.value === "" ? null : Number(input.value)) : input.value || null;
    if (input.name === "valor_orca_pl") item.valor_estimado = item.valor_orca_pl;
    if (input.name === "percentual_executado") item.estado = item.percentual_executado >= 100 ? "concluido" : item.percentual_executado > 0 ? "em_execucao" : "por_iniciar";
    state.preview = null;
    content.querySelector(".planning-batch-preview")?.remove();
    if (input.name === "peso_percentual") {
      const panel = content.querySelector(".planning-weights");
      if (panel) panel.outerHTML = renderWeights();
    }
    row.classList.toggle("dirty", planningChanges(state.original, [item]).length > 0);
    const button = content.querySelector("[data-save-batch]");
    if (button) { button.textContent = `GUARDAR ALTERAÇÕES · ${dirtyCount()}`; button.disabled = !dirtyCount() || !state.dependenciesLoaded; }
  }

  function removeTask(itemId) {
    const item = state.items.find(candidate => candidate.id === itemId);
    if (!item) return;
    if (item._new) {
      state.items = state.items.filter(candidate => candidate.id !== itemId);
      state.dependencies = state.dependencies.filter(row => row.item_id !== itemId && row.depende_de_item_id !== itemId);
    } else { item._archive = !item._archive; }
    state.preview = null; render();
  }

  function addDependency(itemId, select) {
    if (!select?.value) return toast("Escolha a tarefa predecessora.", "error");
    state.dependencies.push({ id: crypto.randomUUID(), item_id: itemId, depende_de_item_id: select.value, tipo: "fim_inicio", atraso_dias: 0 });
    state.preview = null; render();
  }

  function removeDependency(dependencyId) {
    state.dependencies = state.dependencies.filter(row => row.id !== dependencyId);
    state.preview = null; render();
  }

  function confirmImport() {
    if (state.importErrors.length) return;
    for (const row of state.importRows) {
      const { _existing, _error, ...payload } = row;
      if (_existing) Object.assign(state.items.find(item => item.id === _existing.id), payload);
      else state.items.push({ ...payload, id: crypto.randomUUID(), _new: true });
    }
    state.importOpen = false; state.importRows = []; state.importErrors = []; state.preview = null;
    render(); toast("Importação adicionada ao lote local. Reveja e guarde as alterações.");
  }

  function conflictText(conflict) {
    const labels = { phase_weights: "Os pesos ativos da fase têm de totalizar 100%.", manual_date_collision: "A cascata colide com uma data editada manualmente.", archived_dependency: "Uma tarefa ativa depende de uma tarefa a retirar.", dependency_cycle: "Existem dependências circulares.", description: "Descrição obrigatória.", progress: "Percentagem executada inválida.", date: "Data inválida.", date_order: "Fim anterior ao início.", phase: "Fase inválida.", missing_dependency: "Dependência sem tarefa.", unsupported_dependency: "Dependência não suportada.", duplicate_id: "Identificador repetido.", missing_task: "Tarefa inexistente." };
    return `${conflict.id || ""} · ${labels[conflict.type] || conflict.type}`;
  }

  function renderBatchPreview() {
    if (!state.preview || !state.dependenciesLoaded) return "";
    const preview = state.preview;
    const list = (label, ids) => `<div><strong>${label} · ${ids.length}</strong><ul>${ids.map(id => {
      const item = state.items.find(row => row.id === id);
      return `<li>${escapeHtml(item?.codigo || id)} · ${escapeHtml(item?.descricao || "")}</li>`;
    }).join("")}</ul></div>`;
    return `<section class="planning-batch-preview"><h3>REVER ALTERAÇÕES</h3>
      ${list("EDITADAS", preview.edited)}${list("NOVAS", preview.created)}${list("A REMOVER", preview.archived)}
      <div><strong>AFETADAS AUTOMATICAMENTE · ${preview.automatic.length}</strong><ul>${preview.automatic.map(row => `<li>${escapeHtml(row.after.codigo || row.id)} · ${escapeHtml(row.before?.data_inicio_prevista || "—")} → ${escapeHtml(row.after.data_inicio_prevista)} / fim ${escapeHtml(row.after.data_fim_prevista)}</li>`).join("")}</ul></div>
      <ul class="form-error">${preview.conflicts.map(row => `<li>${escapeHtml(conflictText(row))}</li>`).join("")}</ul>
      ${preview.archived.length ? '<label>MOTIVO DA RETIRADA<input data-archive-reason required maxlength="1000"></label>' : ""}
      <button type="button" data-confirm-batch ${!preview.valid || state.batchSaving ? "disabled" : ""}>CONFIRMAR LOTE</button></section>`;
  }

  async function confirmBatch() {
    if (!state.dependenciesLoaded) return toast(dependencyError, "error");
    const preview = batchPreview(state.original, state.items, state.phases, state.dependencies);
    if (!preview.valid) { state.preview = preview; render(); return; }
    const reason = content.querySelector("[data-archive-reason]")?.value.trim() || null;
    if (preview.archived.length && !reason) return toast("Indique o motivo da retirada.", "error");
    const payload = { version: 1, obra_id: state.workId, changes: planningChanges(state.original, state.items),
      expected_items: state.original, dependencies: state.dependencies, expected_dependencies: state.originalDependencies,
      archive_reason: reason, approved_cascade: preview.automatic.map(row => ({ id: row.id, data_inicio_prevista: row.after.data_inicio_prevista, data_fim_prevista: row.after.data_fim_prevista })) };
    state.batchSaving = true; render();
    try {
      const server = await requestPlanningBatch(supabase, payload);
      if (!Array.isArray(server.conflicts) || server.conflicts.length) throw new Error("O servidor detetou conflitos ou devolveu um preview incompleto.");
      if (JSON.stringify(server.approved_cascade) !== JSON.stringify(payload.approved_cascade)) throw new Error("A cascata do servidor difere do preview. Reveja as consequências antes de guardar.");
      if (!await platformConfirm("Confirmar todas as alterações e a cascata apresentada?", { title: "Guardar lote", confirmLabel: "GUARDAR ALTERAÇÕES" })) return;
      const committed = await requestPlanningBatch(supabase, payload, server.confirmation_token);
      let financialSummary = null;
      try { financialSummary = planningFinancialSummary(committed, state.workId); } catch { /* A committed batch must never be retried merely because its summary is missing. */ }
      state.original = structuredClone(state.items); state.originalDependencies = structuredClone(state.dependencies);
      state.preview = null;
      onCommitted({ workId: state.workId, financialSummary });
      await load(state.workId);
      toast(financialSummary ? "Lote guardado e resumo financeiro atualizado." : "Lote confirmado; recálculo financeiro por confirmar no mapa mensal.", financialSummary ? "success" : "warning");
    } catch (error) { toast(error.message, "error"); }
    finally { state.batchSaving = false; render(); }
  }

  function render() {
    if (!state.loaded) {
      content.innerHTML = `<div class="empty-state"><strong>A CARREGAR PLANEAMENTO…</strong></div>`;
      return;
    }
    if (!state.phases.length) {
      content.innerHTML = `${renderWorkData()}<div class="empty-state"><strong>SEM FASES</strong><span>Esta obra ainda não possui fases configuradas.</span></div>`;
      return;
    }
    content.innerHTML = `<div class="planning-module-shell planning-unified"><section class="planning-layer-content"><header><div><p class="eyebrow">PLANEAMENTO</p><h2>Planeamento detalhado da execução</h2></div><span class="planning-sheet-note">Estrutura operacional por fase</span></header>${renderWorkData()}${renderUnifiedPlanning()}</section></div>`;

    // Bind the primary import action directly too. This keeps it reliable in
    // embedded browsers where a delegated toolbar click may be swallowed.
    content.querySelector("[data-open-import]")?.addEventListener("click", event => {
      event.stopPropagation();
      openImportPanel();
    });
    content.querySelector("[data-new-task]")?.addEventListener("click", event => {
      event.stopPropagation();
      addNewTask();
    });
  }

  function openImportPanel() {
    state.importOpen = true;
    state.importRows = [];
    state.importErrors = [];
    render();
    content.querySelector(".planning-import-panel")?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function addNewTask() {
    const firstPhase = state.phases[0];
    const draft = { id: `draft-${crypto.randomUUID()}`, fase_id: firstPhase?.id, codigo: "", descricao: "", responsavel: "", especialidade_id: null, executado_por: "", percentual_executado: 0, estado: "por_iniciar", _new: true };
    state.items.unshift(draft);
    state.preview = null;
    state.expandedTasks.add(draft.id);
    render();
    content.querySelector("[data-edit-item] input[name='codigo']")?.focus();
  }

  async function load(workId = state.workId) {
    if (dirtyCount() && !await platformConfirm("Existem alterações locais por guardar. Descartar e carregar os dados?", { title: "Alterações por guardar", confirmLabel: "DESCARTAR" })) { workSelect.value = state.workId; return; }
    state.preview = null;
    renderWorkOptions();
    state.workId = workId || workSelect.value;
    state.work = getWorks().find(work => work.id === state.workId) || null;
    if (!state.workId) { state.loaded = true; state.phases = []; render(); return; }
    workSelect.value = state.workId;
    state.loaded = false;
    state.dependenciesLoaded = false;
    render();
    if (!isSupabaseConfigured) {
      state.phases = []; state.items = []; state.dependencies = []; state.loaded = true; render(); return;
    }
    const encoded = encodeURIComponent(state.workId);
    const [phaseResponse, specialtiesResponse] = await Promise.all([
      supabase(`fases?select=id,obra_id,codigo,descricao,peso_percentual&obra_id=eq.${encoded}&order=codigo`),
      supabase("especialidades?select=id,nome&order=nome"),
    ]);
    if (!phaseResponse.ok) {
      state.loaded = true; state.phases = []; render();
      toast(`Não foi possível carregar o planeamento: ${await phaseResponse.text()}`, "error"); return;
    }
    state.phases = await phaseResponse.json();
    state.specialties = specialtiesResponse.ok ? await specialtiesResponse.json() : [];
    const phaseIds = state.phases.map(phase => phase.id);
    if (!phaseIds.length) {
      state.items = []; state.dependencies = []; state.costs = new Map(); state.costSummary = {}; state.budgetItems = [];
    } else {
      const ids = phaseIds.map(encodeURIComponent).join(",");
      const itemsResponse = await supabase(`planeamento_itens?select=*&fase_id=in.(${ids})&order=codigo,criado_em`);
      if (!itemsResponse.ok) {
        toast(`Não foi possível carregar as tarefas: ${await itemsResponse.text()}`, "error");
        state.items = []; state.dependencies = [];
      } else {
        state.items = await itemsResponse.json();
        const budgetResponse = await supabase(`itens_orcamento?select=*&fase_id=in.(${ids})`);
        state.budgetItems = budgetResponse.ok ? await budgetResponse.json() : [];
        state.costSummary = null;
        state.costs = new Map();
        try {
          const costsResponse = await supabase("rpc/fn_resumo_custos_obra", { method: "POST", body: JSON.stringify({ p_obra_id: state.workId }) });
          if (!costsResponse.ok) throw new Error("Resumo de custos indisponível");
          const summary = await costsResponse.json();
          if (!summary?.real || !summary?.por_concluir || summary.componentes == null) throw new Error("Resumo de custos inválido");
          const components = Array.isArray(summary.componentes) ? summary.componentes : summary.componentes.pacotes;
          if (!Array.isArray(components)) throw new Error("Componentes de custo inválidos");
          const costs = new Map();
          for (const row of components) {
            if (!row.planeamento_item_id) continue;
            const key = String(row.planeamento_item_id);
            const cost = costs.get(key) || { valor_adjudicado: 0, custo_real: 0, compromisso_remanescente: 0, pago: 0, faturado: 0, faturadoDisponivel: true, confirmacao_pendente: false };
            const subcontract = row.tipo === "subempreitada";
            const actual = Number(row.valor_real ?? row.valor_real_pl ?? 0);
            cost.custo_real += subcontract || row.estado_custo === "concluido" ? actual : 0;
            cost.compromisso_remanescente += Number(row.compromisso_remanescente || 0);
            if (subcontract) {
              const contract = Number(row.total_aprovado ?? row.valor_adjudicado ?? 0);
              cost.valor_adjudicado += contract;
              cost.pago += actual;
              if (row.percentual_faturado == null) cost.faturadoDisponivel = false;
              else cost.faturado += contract * Number(row.percentual_faturado) / 100;
            }
            cost.confirmacao_pendente ||= Boolean(row.pl_confirmacao_pendente || row.sub_confirmacao_pendente || (subcontract && !row.remocao_confirmada && row.estado_custo !== "cancelado"));
            costs.set(key, cost);
          }
          for (const cost of costs.values()) {
            cost.percentual_pago = cost.valor_adjudicado > 0 ? cost.pago * 100 / cost.valor_adjudicado : null;
            cost.percentual_faturado = cost.valor_adjudicado > 0 && cost.faturadoDisponivel ? cost.faturado * 100 / cost.valor_adjudicado : null;
          }
          state.costSummary = summary;
          state.costs = costs;
        } catch {
          toast("Não foi possível carregar os custos da obra. Os valores estão indisponíveis.", "error");
        }
        const itemIds = state.items.map(item => item.id);
        state.dependencies = [];
        if (itemIds.length) {
          try {
            const dependencyResponse = await supabase(`planeamento_itens_dependencias?select=id,item_id,depende_de_item_id,tipo,atraso_dias&item_id=in.(${itemIds.map(encodeURIComponent).join(",")})&order=criado_em`);
            if (!dependencyResponse.ok) throw new Error(dependencyError);
            const dependencies = await dependencyResponse.json();
            if (!Array.isArray(dependencies)) throw new Error(dependencyError);
            state.dependencies = dependencies;
            state.dependenciesLoaded = true;
          } catch {
            toast(dependencyError, "error");
          }
        } else state.dependenciesLoaded = true;
      }
    }
    state.original = structuredClone(state.items);
    state.originalDependencies = structuredClone(state.dependencies);
    state.loaded = true;
    render();
  }

  window.addEventListener("beforeunload", event => { if (dirtyCount()) { event.preventDefault(); event.returnValue = ""; } });
  workSelect.addEventListener("change", () => { if (state.batchSaving) { workSelect.value = state.workId; return; } load(workSelect.value); });
  content.addEventListener("click", event => {
    if (state.batchSaving) return;
    if (readOnly() && event.target.closest("[data-open-import],[data-new-task],[data-save-batch],[data-confirm-batch],[data-redistribute],[data-remove-task],[data-add-dependency],[data-remove-dependency],[data-confirm-import]")) return;
    if (event.target.closest("[data-open-import]")) { openImportPanel(); return; }
    if (event.target.closest("[data-close-import]")) { state.importOpen = false; state.importRows = []; state.importErrors = []; render(); return; }
    if (event.target.closest("[data-new-task]")) {
      addNewTask(); return;
    }
    const toggleTask = event.target.closest("[data-toggle-task]");
    if (toggleTask) {
      const itemId = toggleTask.dataset.toggleTask;
      const row = toggleTask.closest("[data-edit-item]");
      const details = row?.querySelector(".planning-editor-details");
      const opening = Boolean(details?.hidden);
      if (opening) state.expandedTasks.add(itemId); else state.expandedTasks.delete(itemId);
      if (details) details.hidden = !opening;
      row?.classList.toggle("details-open", opening);
      toggleTask.setAttribute("aria-expanded", String(opening));
      toggleTask.textContent = opening ? "FECHAR" : "DETALHES";
      return;
    }
    const toggleEditorPhase = event.target.closest("[data-toggle-editor-phase]");
    if (toggleEditorPhase) {
      const phaseId = toggleEditorPhase.dataset.toggleEditorPhase;
      if (state.collapsedEditorPhases.has(phaseId)) state.collapsedEditorPhases.delete(phaseId);
      else state.collapsedEditorPhases.add(phaseId);
      render();
      return;
    }
    if (event.target.closest("[data-save-batch]")) { if (!state.dependenciesLoaded) return toast(dependencyError, "error"); state.preview = batchPreview(state.original, state.items, state.phases, state.dependencies); render(); return; }
    if (event.target.closest("[data-confirm-batch]")) { confirmBatch(); return; }
    const redistribute = event.target.closest("[data-redistribute]");
    if (redistribute) {
      try {
        const weights = new Map(redistributeWeights(state.items.filter(item => item.fase_id === redistribute.dataset.redistribute)).map(item => [item.id, item.peso_percentual]));
        state.items.forEach(item => { if (weights.has(item.id)) item.peso_percentual = weights.get(item.id); }); state.preview = null; render();
      } catch (error) { toast(error.message, "error"); }
      return;
    }
    const remove = event.target.closest("[data-remove-task]"); if (remove) { removeTask(remove.dataset.removeTask); return; }
    const addDep = event.target.closest("[data-add-dependency]"); if (addDep) { addDependency(addDep.dataset.addDependency, addDep.closest("label")?.querySelector("select")); return; }
    const removeDep = event.target.closest("[data-remove-dependency]"); if (removeDep) { removeDependency(removeDep.dataset.removeDependency); return; }
    const confirmButton = event.target.closest("[data-confirm-import]"); if (confirmButton) { confirmImport(confirmButton); return; }
    const viewButton = event.target.closest("[data-planning-view]");
    if (viewButton) { state.view = viewButton.dataset.planningView; render(); return; }
    const phaseButton = event.target.closest("[data-planning-phase]");
    if (!phaseButton) return;
    const phaseId = phaseButton.dataset.planningPhase;
    if (state.expanded.has(phaseId)) state.expanded.delete(phaseId); else state.expanded.add(phaseId);
    render();
  });
  content.addEventListener("input", event => {
    captureInput(event.target);
    if (event.target.matches("[data-import-paste]")) prepareImport(csvRows(event.target.value));
    const row = event.target.closest("[data-edit-item]");
    if (row && event.target.matches('[name="peso_percentual"],[name="percentual_executado"]')) {
      const weight = Number(row.querySelector('[name="peso_percentual"]')?.value || 0);
      const progress = Math.max(0, Math.min(100, Number(row.querySelector('[name="percentual_executado"]')?.value || 0)));
      const stateValue = progress >= 100 ? "concluido" : progress > 0 ? "em_execucao" : "por_iniciar";
      const stateInput = row.querySelector('[name="estado"]');
      const stateOutput = row.querySelector("[data-derived-state]");
      if (row.querySelector("[data-weighted]")) row.querySelector("[data-weighted]").textContent = `${(weight * progress / 100).toFixed(2)}%`;
      if (stateInput) stateInput.value = stateValue;
      if (stateOutput) stateOutput.innerHTML = `<span class="planning-state ${stateValue}">${stateLabel(stateValue)}</span>`;
    }
  });
  content.addEventListener("change", async event => {
    captureInput(event.target);
    if (event.target.matches("[data-control-mode]")) {
      state.controlMode = event.target.value;
      render();
      return;
    }
    if (!event.target.matches("[data-import-file]")) return;
    const file = event.target.files?.[0]; if (!file) return;
    try {
      if (/\.csv$|\.tsv$/i.test(file.name)) prepareImport(csvRows(await file.text()));
      else {
        if (!window.XLSX) throw new Error("O leitor de Excel não ficou disponível. Atualize a página e tente novamente.");
        const workbook = window.XLSX.read(await file.arrayBuffer(), { type: "array", cellDates: true });
        const sheet = workbook.Sheets[workbook.SheetNames[0]];
        prepareImport(window.XLSX.utils.sheet_to_json(sheet, { header: 1, defval: "", raw: false, dateNF: "dd/mm/yyyy" }));
      }
    } catch (error) { toast(error.message || "Não foi possível ler o ficheiro.", "error"); }
  });

  return {
    hasUnsavedChanges: () => dirtyCount() > 0,
    canLeave: () => state.batchSaving ? Promise.resolve(false) : !dirtyCount() ? Promise.resolve(true) : platformConfirm("Existem alterações por guardar. Continuar para outra área mantendo o lote local?", { title: "Alterações por guardar", confirmLabel: "CONTINUAR" }),
    show(options = {}) {
      const targetWorkId = options.workId || state.workId;
      if (dirtyCount() && targetWorkId === state.workId) { render(); return; }
      if (["baseline", "effective", "summary", "control"].includes(options.view)) state.view = options.view;
      load(targetWorkId || workSelect.value);
    },
    refresh: load,
  };
}
