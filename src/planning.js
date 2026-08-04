const DAY_MS = 86400000;

function isoDate(value) {
  if (!value) return "";
  return String(value).slice(0, 10);
}

function dateValue(value) {
  const iso = isoDate(value);
  return iso ? new Date(`${iso}T00:00:00Z`) : null;
}

function addMonths(date, count) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + count, 1));
}

function monthLabel(date) {
  return new Intl.DateTimeFormat("pt-PT", { month: "short", year: "2-digit", timeZone: "UTC" })
    .format(date).replace(".", "").toUpperCase();
}

function daysBetween(start, end) {
  return Math.max(0, Math.round((end - start) / DAY_MS));
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
  }[state] || "SEM ESTADO";
}

export function createPlanningModule({ supabase, isSupabaseConfigured, getWorks, toast }) {
  const state = {
    workId: "",
    phases: [],
    items: [],
    dependencies: [],
    expanded: new Set(),
    loaded: false,
  };

  const page = document.querySelector("#planning-view");
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
  }

  function timeline() {
    const datedItems = state.items.filter(item => item.data_inicio_prevista || item.data_fim_prevista);
    const selectedWork = getWorks().find(work => work.id === state.workId);
    const starts = [
      dateValue(selectedWork?.data_inicio),
      ...datedItems.map(item => dateValue(item.data_inicio_prevista)),
    ].filter(Boolean);
    const ends = [
      dateValue(selectedWork?.data_fim_prevista),
      ...datedItems.map(item => dateValue(item.data_fim_prevista)),
    ].filter(Boolean);
    const today = new Date();
    const startCandidate = starts.length ? new Date(Math.min(...starts)) : today;
    const endCandidate = ends.length ? new Date(Math.max(...ends)) : addMonths(today, 5);
    const start = new Date(Date.UTC(startCandidate.getUTCFullYear(), startCandidate.getUTCMonth(), 1));
    const end = addMonths(new Date(Date.UTC(endCandidate.getUTCFullYear(), endCandidate.getUTCMonth(), 1)), 1);
    const totalDays = Math.max(daysBetween(start, end), 1);
    const months = [];
    for (let current = start; current < end; current = addMonths(current, 1)) {
      const next = addMonths(current, 1);
      months.push({
        label: monthLabel(current),
        width: daysBetween(current, next) / totalDays * 100,
      });
    }
    return { start, end, totalDays, months };
  }

  function taskBar(item, scale) {
    const start = dateValue(item.data_inicio_prevista);
    const end = dateValue(item.data_fim_prevista) || start;
    if (!start || !end) return `<span class="planning-no-dates">DATAS NÃO DEFINIDAS</span>`;
    const left = Math.min(100, daysBetween(scale.start, start) / scale.totalDays * 100);
    const width = Math.max(1.4, daysBetween(start, end) / scale.totalDays * 100);
    const progress = Math.max(0, Math.min(100, Number(item.percentual_executado || 0)));
    return `<div class="planning-bar ${escapeHtml(item.estado || "por_iniciar")} ${item.impedido ? "impedido" : ""}" style="left:${left}%;width:${Math.min(width, 100 - left)}%">
      <i style="width:${progress}%"></i><span>${progress}%</span>
    </div>`;
  }

  function phaseProgress(items) {
    if (!items.length) return null;
    const weightedItems = items.filter(item =>
      item.peso_percentual !== null && item.peso_percentual !== "" &&
      Number.isFinite(Number(item.peso_percentual)));
    const totalWeight = weightedItems.reduce(
      (sum, item) => sum + Number(item.peso_percentual), 0);
    if (weightedItems.length === items.length && totalWeight > 0) {
      return Math.round(weightedItems.reduce(
        (sum, item) => sum +
          Number(item.peso_percentual) * Number(item.percentual_executado || 0),
        0,
      ) / totalWeight);
    }
    return Math.round(items.reduce(
      (sum, item) => sum + Number(item.percentual_executado || 0), 0,
    ) / items.length);
  }

  function phaseBar(items, scale, todayPosition) {
    if (!items.length) return `<span class="planning-no-dates">SEM TAREFAS</span>`;
    const starts = items.map(item => dateValue(item.data_inicio_prevista)).filter(Boolean);
    const allCompleted = items.every(item =>
      item.estado === "concluido" || Number(item.percentual_executado || 0) >= 100);
    const allHaveActualEnd = allCompleted && items.every(item => dateValue(item.data_fim_real));
    const ends = items.map(item => dateValue(
      allHaveActualEnd ? item.data_fim_real : item.data_fim_prevista,
    )).filter(Boolean);
    if (!starts.length || !ends.length) {
      return `<span class="planning-no-dates">DATAS NÃO DEFINIDAS</span>`;
    }
    const start = new Date(Math.min(...starts));
    const end = new Date(Math.max(...ends));
    const left = Math.min(100, daysBetween(scale.start, start) / scale.totalDays * 100);
    const width = Math.max(1.4, daysBetween(start, end) / scale.totalDays * 100);
    const progress = phaseProgress(items);
    const phaseState = progress >= 100 ? "concluido" : progress > 0 ? "em_execucao" : "por_iniciar";
    return `
      ${todayPosition === null ? "" : `<i class="planning-today" style="left:${todayPosition}%"></i>`}
      <div class="planning-phase-bar ${phaseState}" style="left:${left}%;width:${Math.min(width, 100 - left)}%">
        <i style="width:${progress}%"></i>
      </div>`;
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
    const scale = timeline();
    const today = new Date();
    const todayPosition = today >= scale.start && today <= scale.end
      ? daysBetween(scale.start, today) / scale.totalDays * 100 : null;
    const predecessorCount = state.dependencies.reduce((result, dependency) => {
      result[dependency.item_id] = (result[dependency.item_id] || 0) + 1;
      return result;
    }, {});
    content.innerHTML = `
      <div class="planning-grid planning-grid-head">
        <div>FASE / TAREFA</div><div>RESPONSÁVEL</div>
        <div class="planning-months">${scale.months.map(month =>
          `<span style="width:${month.width}%">${month.label}</span>`).join("")}</div>
        <div>ESTADO</div>
      </div>
      ${state.phases.map(phase => {
        const items = state.items.filter(item => item.fase_id === phase.id);
        const expanded = state.expanded.has(phase.id);
        const progress = phaseProgress(items);
        return `<section class="planning-phase ${expanded ? "expanded" : ""}">
          <button class="planning-grid planning-phase-row" type="button" data-planning-phase="${phase.id}" aria-expanded="${expanded}">
            <div><b>${expanded ? "−" : "+"}</b><span><strong>${escapeHtml(phase.codigo || "")}</strong>${escapeHtml(phase.descricao || "Fase")}</span></div>
            <div>${items.length} ${items.length === 1 ? "TAREFA" : "TAREFAS"}</div>
            <div class="planning-phase-track" style="--months:${scale.months.length}">
              ${phaseBar(items, scale, todayPosition)}
            </div>
            <div><em>${progress === null ? "—" : `${progress}%`}</em></div>
          </button>
          <div class="planning-tasks" ${expanded ? "" : "hidden"}>
            ${items.length ? items.map(item => `<article class="planning-grid planning-task-row ${item.impedido ? "planning-task-blocked" : ""}">
              <div>
                <strong>${escapeHtml(item.codigo || "SUB")}</strong>
                <span>${escapeHtml(item.descricao)}</span>
                ${item.recalculado_automaticamente ? `<small title="${item.recalculado_em ? `Em ${escapeHtml(item.recalculado_em)}` : ""}">↻ RECALCULADO AUTOMATICAMENTE</small>` : ""}
                ${item.impedido ? `<em class="planning-blocked-note"><b>IMPEDIDA</b>${escapeHtml(item.observacao_impedimento || "Sem observação")}</em>` : ""}
              </div>
              <div>${escapeHtml(item.responsavel || "Não definido")}<small>${predecessorCount[item.id] || 0} PREDECESSORAS</small></div>
              <div class="planning-track" style="--months:${scale.months.length}">
                ${todayPosition === null ? "" : `<i class="planning-today" style="left:${todayPosition}%"></i>`}
                ${taskBar(item, scale)}
              </div>
              <div><span class="planning-state ${item.impedido ? "impedido" : escapeHtml(item.estado || "por_iniciar")}">${item.impedido ? "IMPEDIDA" : stateLabel(item.estado)}</span>
                <small>${isoDate(item.data_inicio_prevista) || "—"} → ${isoDate(item.data_fim_prevista) || "—"}</small>
              </div>
            </article>`).join("") : `<div class="planning-phase-empty">SEM TAREFAS NESTA FASE</div>`}
          </div>
        </section>`;
      }).join("")}`;
  }

  async function load(workId = state.workId) {
    renderWorkOptions();
    state.workId = workId || workSelect.value;
    if (!state.workId) {
      state.loaded = true;
      state.phases = [];
      render();
      return;
    }
    workSelect.value = state.workId;
    state.loaded = false;
    render();
    if (!isSupabaseConfigured) {
      state.phases = [];
      state.items = [];
      state.dependencies = [];
      state.loaded = true;
      render();
      return;
    }
    const encoded = encodeURIComponent(state.workId);
    const phaseResponse = await supabase(`fases?select=id,obra_id,codigo,descricao&obra_id=eq.${encoded}&order=codigo`);
    if (!phaseResponse.ok) {
      state.loaded = true;
      state.phases = [];
      render();
      toast(`Não foi possível carregar o planeamento: ${await phaseResponse.text()}`, "error");
      return;
    }
    state.phases = await phaseResponse.json();
    const phaseIds = state.phases.map(phase => phase.id);
    if (!phaseIds.length) {
      state.items = [];
      state.dependencies = [];
    } else {
      const ids = phaseIds.map(encodeURIComponent).join(",");
      const itemsResponse = await supabase(`planeamento_itens?select=*&fase_id=in.(${ids})&order=codigo,criado_em`);
      if (!itemsResponse.ok) {
        toast(`Execute primeiro o script planeamento_detalhado.sql: ${await itemsResponse.text()}`, "error");
        state.items = [];
        state.dependencies = [];
      } else {
        state.items = await itemsResponse.json();
        const itemIds = state.items.map(item => item.id);
        if (itemIds.length) {
          const dependenciesResponse = await supabase(`planeamento_itens_dependencias?select=id,item_id,depende_de_item_id,tipo,atraso_dias&item_id=in.(${itemIds.map(encodeURIComponent).join(",")})&order=criado_em`);
          state.dependencies = dependenciesResponse.ok ? await dependenciesResponse.json() : [];
        } else state.dependencies = [];
      }
    }
    state.loaded = true;
    render();
  }

  workSelect.addEventListener("change", () => {
    state.expanded.clear();
    load(workSelect.value);
  });
  content.addEventListener("click", event => {
    const button = event.target.closest("[data-planning-phase]");
    if (!button) return;
    const phaseId = button.dataset.planningPhase;
    if (state.expanded.has(phaseId)) state.expanded.delete(phaseId);
    else state.expanded.add(phaseId);
    render();
  });

  return {
    show() {
      renderWorkOptions();
      load(state.workId || workSelect.value);
    },
    refresh: load,
  };
}
