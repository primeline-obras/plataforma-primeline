import { csvRows, normalizedHeader, parsedDate, parsedNumber, parsedState } from "./planning-import.js?v=1";

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

export function createPlanningModule({ supabase, isSupabaseConfigured, getWorks, toast }) {
  const state = {
    workId: "", work: null, phases: [], items: [], dependencies: [], specialties: [],
    expanded: new Set(), loaded: false, view: "effective",
    importOpen: false, importRows: [], importErrors: [], saving: new Set(), controlMode: "baseline-planned",
  };

  const workSelect = document.querySelector("#planning-work");
  const content = document.querySelector("#planning-content");

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

  function phaseProgress(items) {
    if (!items.length) return null;
    const weighted = items.filter(item => item.peso_percentual !== null && item.peso_percentual !== "" && Number.isFinite(Number(item.peso_percentual)));
    const totalWeight = weighted.reduce((sum, item) => sum + Number(item.peso_percentual), 0);
    if (weighted.length === items.length && totalWeight > 0) {
      return Math.round(weighted.reduce((sum, item) => sum + Number(item.peso_percentual) * Number(item.percentual_executado || 0), 0) / totalWeight);
    }
    return Math.round(items.reduce((sum, item) => sum + Number(item.percentual_executado || 0), 0) / items.length);
  }

  function windowFor(items, dateGetter) {
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
    return state.items.filter(candidate => candidate.id !== item.id && !linked.has(candidate.id) && !String(candidate.id).startsWith("draft-"))
      .map(candidate => `<option value="${candidate.id}">${escapeHtml(candidate.codigo || "—")} · ${escapeHtml(candidate.descricao)}</option>`).join("");
  }

  function renderDependencies(item) {
    const rows = state.dependencies.filter(row => row.item_id === item.id);
    return `<div class="planning-dependency-editor"><div>${rows.map(row => {
      const predecessor = state.items.find(candidate => candidate.id === row.depende_de_item_id);
      return `<span>${escapeHtml(predecessor?.codigo || "Tarefa")}<button type="button" data-remove-dependency="${row.id}" title="Remover dependência">×</button></span>`;
    }).join("") || `<small>SEM PREDECESSORAS</small>`}</div>
      ${item._new ? "" : `<label><select data-dependency-choice><option value="">Esta tarefa depende de…</option>${dependencyOptions(item)}</select><button type="button" data-add-dependency="${item.id}">LIGAR</button></label>`}</div>`;
  }

  function renderEditor() {
    return `<div class="planning-editor-wrap"><div class="planning-editor-head">
      <span>FASE</span><span>CÓDIGO</span><span>DESCRIÇÃO</span><span>RESPONSÁVEL</span><span>ESPECIALIDADE</span><span>EXECUTADO POR</span><span>INÍCIO PREV.</span><span>FIM PREV.</span><span>INÍCIO REAL</span><span>FIM REAL</span><span>PESO %</span><span>EXEC. %</span><span>ESTADO</span><span>AÇÕES</span>
    </div>${state.items.map(item => `<article class="planning-editor-row ${item._new ? "new" : ""}" data-edit-item="${item.id}">
      <select name="fase_id">${phaseOptions(item.fase_id)}</select>
      <input name="codigo" value="${escapeHtml(item.codigo || "")}" placeholder="F01.1">
      <input name="descricao" value="${escapeHtml(item.descricao || "")}" placeholder="Descrição da tarefa">
      <input name="responsavel" value="${escapeHtml(item.responsavel || "")}" placeholder="Responsável">
      <select name="especialidade_id">${specialtyOptions(item.especialidade_id)}</select>
      <select name="executado_por"><option value="">Por definir</option><option value="PL" ${item.executado_por === "PL" ? "selected" : ""}>Primeline</option><option value="subempreitada" ${item.executado_por === "subempreitada" ? "selected" : ""}>Subempreitada</option></select>
      <input name="data_inicio_prevista" type="date" value="${isoDate(item.data_inicio_prevista)}">
      <input name="data_fim_prevista" type="date" value="${isoDate(item.data_fim_prevista)}">
      <input name="data_inicio_real" type="date" value="${isoDate(item.data_inicio_real)}">
      <input name="data_fim_real" type="date" value="${isoDate(item.data_fim_real)}">
      <input name="peso_percentual" type="number" min="0" step="0.01" value="${item.peso_percentual ?? ""}">
      <input name="percentual_executado" type="number" min="0" max="100" step="1" value="${item.percentual_executado ?? 0}">
      <select name="estado"><option value="por_iniciar" ${item.estado === "por_iniciar" ? "selected" : ""}>Por iniciar</option><option value="em_execucao" ${item.estado === "em_execucao" ? "selected" : ""}>Em execução</option><option value="concluido" ${item.estado === "concluido" ? "selected" : ""}>Concluído</option></select>
      <div><button type="button" data-save-task="${item.id}" ${state.saving.has(item.id) ? "disabled" : ""}>${state.saving.has(item.id) ? "A GUARDAR…" : "GUARDAR"}</button><button type="button" class="remove" data-remove-task="${item.id}">${item._new ? "CANCELAR" : "REMOVER"}</button></div>
      <section>${renderDependencies(item)}</section>
    </article>`).join("")}</div>`;
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
    return `<div class="planning-effective-toolbar"><div><button type="button" data-open-import>⇧ IMPORTAR TAREFAS</button><button type="button" class="primary" data-new-task>＋ NOVA TAREFA</button></div><span>${state.items.filter(item => !item._new).length} TAREFAS</span></div>
    ${renderImportPanel()}${renderEditor()}
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
    };
    const positions = Object.fromEntries(Object.entries(aliases).map(([field, names]) => [field, headers.findIndex(header => names.includes(header))]));
    if (positions.codigo < 0 || positions.descricao < 0) errors.push("Os cabeçalhos Código e Descrição são obrigatórios.");
    const seen = new Set();
    const rows = matrix.slice(1).filter(row => row.some(value => String(value ?? "").trim())).map((row, index) => {
      const get = field => positions[field] >= 0 ? row[positions[field]] : "";
      const codigo = String(get("codigo") || "").trim();
      const descricao = String(get("descricao") || "").trim();
      const phase = phaseForCode(codigo, get("fase"));
      const progress = Math.max(0, Math.min(100, parsedNumber(get("percentual_executado"), 0)));
      const item = {
        fase_id: phase?.id, codigo, descricao, responsavel: String(get("responsavel") || "").trim() || null,
        data_inicio_prevista: parsedDate(get("data_inicio_prevista")), data_fim_prevista: parsedDate(get("data_fim_prevista")),
        data_inicio_real: parsedDate(get("data_inicio_real")), data_fim_real: parsedDate(get("data_fim_real")), peso_percentual: parsedNumber(get("peso_percentual")),
        percentual_executado: progress, estado: parsedState(get("estado"), progress),
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

  async function saveTask(itemId) {
    const row = content.querySelector(`[data-edit-item="${itemId}"]`);
    const item = state.items.find(candidate => candidate.id === itemId);
    if (!row || !item) return;
    const value = name => row.querySelector(`[name="${name}"]`)?.value ?? "";
    const payload = {
      fase_id: value("fase_id"), codigo: value("codigo").trim() || null, descricao: value("descricao").trim(),
      responsavel: value("responsavel").trim() || null, especialidade_id: value("especialidade_id") || null,
      executado_por: value("executado_por") || null, data_inicio_prevista: value("data_inicio_prevista") || null,
      data_fim_prevista: value("data_fim_prevista") || null, data_inicio_real: value("data_inicio_real") || null, data_fim_real: value("data_fim_real") || null,
      peso_percentual: parsedNumber(value("peso_percentual")), percentual_executado: parsedNumber(value("percentual_executado"), 0),
      estado: value("estado"),
    };
    if (!payload.descricao) return toast("A descrição da tarefa é obrigatória.", "error");
    if (payload.data_inicio_prevista && payload.data_fim_prevista && payload.data_fim_prevista < payload.data_inicio_prevista) return toast("O fim previsto não pode ser anterior ao início.", "error");
    state.saving.add(itemId); render();
    const response = await supabase(item._new ? "planeamento_itens?select=*" : `planeamento_itens?id=eq.${encodeURIComponent(item.id)}&select=*`, {
      method: item._new ? "POST" : "PATCH", body: JSON.stringify(payload),
    });
    state.saving.delete(itemId);
    if (!response.ok) { render(); return toast(`Não foi possível guardar a tarefa: ${await response.text()}`, "error"); }
    toast(item._new ? "Tarefa criada." : "Tarefa atualizada.");
    await load(state.workId);
  }

  async function removeTask(itemId) {
    const item = state.items.find(candidate => candidate.id === itemId);
    if (!item) return;
    if (item._new) { state.items = state.items.filter(candidate => candidate.id !== itemId); render(); return; }
    if (!confirm(`Remover a tarefa ${item.codigo || item.descricao}? As dependências associadas também serão removidas.`)) return;
    const response = await supabase(`planeamento_itens?id=eq.${encodeURIComponent(itemId)}`, { method: "DELETE" });
    if (!response.ok) return toast(`Não foi possível remover a tarefa: ${await response.text()}`, "error");
    toast("Tarefa removida."); await load(state.workId);
  }

  async function addDependency(itemId, select) {
    if (!select?.value) return toast("Escolha a tarefa predecessora.", "error");
    const response = await supabase("planeamento_itens_dependencias", { method: "POST", body: JSON.stringify({ item_id: itemId, depende_de_item_id: select.value, tipo: "fim_inicio", atraso_dias: 0 }) });
    if (!response.ok) return toast(`Não foi possível criar a dependência: ${await response.text()}`, "error");
    toast("Dependência criada."); await load(state.workId);
  }

  async function removeDependency(dependencyId) {
    if (!confirm("Remover esta dependência?")) return;
    const response = await supabase(`planeamento_itens_dependencias?id=eq.${encodeURIComponent(dependencyId)}`, { method: "DELETE" });
    if (!response.ok) return toast(`Não foi possível remover a dependência: ${await response.text()}`, "error");
    toast("Dependência removida."); await load(state.workId);
  }

  async function confirmImport(button) {
    const valid = state.importRows.filter(row => !row._error);
    button.disabled = true; button.textContent = "A IMPORTAR…";
    const creates = valid.filter(row => !row._existing).map(({ _existing, _error, ...row }) => row);
    if (creates.length) {
      const response = await supabase("planeamento_itens", { method: "POST", body: JSON.stringify(creates) });
      if (!response.ok) { button.disabled = false; return toast(`A importação foi interrompida: ${await response.text()}`, "error"); }
    }
    for (const row of valid.filter(item => item._existing)) {
      const { _existing, _error, ...payload } = row;
      const response = await supabase(`planeamento_itens?id=eq.${encodeURIComponent(_existing.id)}`, { method: "PATCH", body: JSON.stringify(payload) });
      if (!response.ok) { button.disabled = false; return toast(`A atualização de ${row.codigo} falhou: ${await response.text()}`, "error"); }
    }
    toast(`${creates.length} tarefas criadas e ${valid.length - creates.length} atualizadas.`);
    state.importOpen = false; state.importRows = []; state.importErrors = []; await load(state.workId);
  }

  function render() {
    if (!state.loaded) {
      content.innerHTML = `<div class="empty-state"><strong>A CARREGAR PLANEAMENTO…</strong></div>`;
      return;
    }
    if (!state.phases.length) {
      content.innerHTML = `<div class="empty-state"><strong>SEM FASES</strong><span>Esta obra ainda não possui fases configuradas.</span></div>`;
      return;
    }
    const [title, description] = viewMeta();
    const body = state.view === "baseline" ? renderBaseline() : state.view === "summary" ? renderSummary() : state.view === "control" ? renderControl() : renderEffective();
    content.innerHTML = `<div class="planning-module-shell">
      <aside class="planning-layer-nav" aria-label="Camadas do planeamento">
        <span>CAMADAS</span>
        <button type="button" data-planning-view="baseline" class="${state.view === "baseline" ? "active" : ""}"><b>01</b><span>PLANEAMENTO INICIAL<small>Baseline original</small></span></button>
        <button type="button" data-planning-view="effective" class="${state.view === "effective" ? "active" : ""}"><b>02</b><span>PLANEAMENTO EFETIVO<small>Execução atual</small></span></button>
        <button type="button" data-planning-view="summary" class="${state.view === "summary" ? "active" : ""}"><b>03</b><span>RESUMO POR FASE<small>Desvios agregados</small></span></button>
        <button type="button" data-planning-view="control" class="${state.view === "control" ? "active" : ""}"><b>04</b><span>CONTROLO<small>Classificação dos desvios</small></span></button>
      </aside>
      <section class="planning-layer-content"><header><div><p class="eyebrow">${title}</p><h2>${description}</h2></div>${state.view === "effective" ? `<div class="planning-legend"><span><i class="done"></i>CONCLUÍDO</span><span><i class="doing"></i>EM EXECUÇÃO</span><span><i class="todo"></i>POR INICIAR</span><span><i class="late"></i>EM ATRASO</span></div>` : ""}</header>${body}</section>
    </div>`;

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
    content.querySelectorAll("[data-planning-view]").forEach(button => {
      button.addEventListener("click", event => {
        event.stopPropagation();
        state.view = button.dataset.planningView;
        render();
      });
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
    state.items.unshift({ id: `draft-${crypto.randomUUID()}`, fase_id: firstPhase?.id, codigo: "", descricao: "", responsavel: "", especialidade_id: null, executado_por: "", percentual_executado: 0, estado: "por_iniciar", _new: true });
    render();
    content.querySelector("[data-edit-item] input[name='codigo']")?.focus();
  }

  async function load(workId = state.workId) {
    renderWorkOptions();
    state.workId = workId || workSelect.value;
    state.work = getWorks().find(work => work.id === state.workId) || null;
    if (!state.workId) { state.loaded = true; state.phases = []; render(); return; }
    workSelect.value = state.workId;
    state.loaded = false;
    render();
    if (!isSupabaseConfigured) {
      state.phases = []; state.items = []; state.dependencies = []; state.loaded = true; render(); return;
    }
    const encoded = encodeURIComponent(state.workId);
    const [phaseResponse, specialtiesResponse] = await Promise.all([
      supabase(`fases?select=id,obra_id,codigo,descricao&obra_id=eq.${encoded}&order=codigo`),
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
      state.items = []; state.dependencies = [];
    } else {
      const ids = phaseIds.map(encodeURIComponent).join(",");
      const itemsResponse = await supabase(`planeamento_itens?select=*&fase_id=in.(${ids})&order=codigo,criado_em`);
      if (!itemsResponse.ok) {
        toast(`Não foi possível carregar as tarefas: ${await itemsResponse.text()}`, "error");
        state.items = []; state.dependencies = [];
      } else {
        state.items = await itemsResponse.json();
        const itemIds = state.items.map(item => item.id);
        if (itemIds.length) {
          const dependencyResponse = await supabase(`planeamento_itens_dependencias?select=id,item_id,depende_de_item_id,tipo,atraso_dias&item_id=in.(${itemIds.map(encodeURIComponent).join(",")})&order=criado_em`);
          state.dependencies = dependencyResponse.ok ? await dependencyResponse.json() : [];
        } else state.dependencies = [];
      }
    }
    state.loaded = true;
    render();
  }

  workSelect.addEventListener("change", () => { state.expanded.clear(); load(workSelect.value); });
  content.addEventListener("click", event => {
    if (event.target.closest("[data-open-import]")) { openImportPanel(); return; }
    if (event.target.closest("[data-close-import]")) { state.importOpen = false; state.importRows = []; state.importErrors = []; render(); return; }
    if (event.target.closest("[data-new-task]")) {
      addNewTask(); return;
    }
    const save = event.target.closest("[data-save-task]"); if (save) { saveTask(save.dataset.saveTask); return; }
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
    if (event.target.matches("[data-import-paste]")) prepareImport(csvRows(event.target.value));
  });
  content.addEventListener("change", async event => {
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
    show(options = {}) {
      if (options.workId) state.workId = options.workId;
      if (["baseline", "effective", "summary", "control"].includes(options.view)) state.view = options.view;
      renderWorkOptions(); load(state.workId || workSelect.value);
    },
    refresh: load,
  };
}
