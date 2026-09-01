import { platformPrompt } from "./platform-dialogs.js?v=1";

const DAY_MS = 86400000;

const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

function isoDate(value) {
  return value ? String(value).slice(0, 10) : "";
}

function utcDate(value) {
  const iso = isoDate(value);
  return iso ? new Date(`${iso}T00:00:00Z`) : null;
}

function addDays(date, amount) {
  return new Date(date.getTime() + amount * DAY_MS);
}

function monday(date) {
  const result = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  result.setUTCDate(result.getUTCDate() - ((result.getUTCDay() + 6) % 7));
  return result;
}

function taskDate(item) {
  return utcDate(item.data_inicio_prevista) || utcDate(item.data_fim_prevista);
}

function overlapsDay(item, day) {
  const start = utcDate(item.data_inicio_prevista) || utcDate(item.data_fim_prevista);
  const end = utcDate(item.data_fim_prevista) || start;
  return start && end && day >= start && day <= end;
}

function stateLabel(item) {
  if (item.impedido) return "IMPEDIDA";
  return { concluido: "CONCLUÍDA", em_execucao: "EM EXECUÇÃO", por_iniciar: "POR INICIAR" }[item.estado] || "SEM ESTADO";
}

function calendarTaskLabel(item) {
  const words = String(item.descricao || "Tarefa").trim().split(/\s+/).filter(Boolean);
  return words.slice(0, 4).join(" ") || "Tarefa";
}

export function createActionPlanModule({ root, supabase, isConfigured, getWorks, getRole }) {
  const state = { items: [], phases: [], month: new Date(), loading: false, error: "" };

  function workFor(item) {
    const phase = state.phases.find(row => row.id === item.fase_id);
    return getWorks().find(work => work.id === phase?.obra_id);
  }

  function taskCard(item) {
    const work = workFor(item);
    const completed = item.estado === "concluido";
    return `<article class="action-task ${item.impedido ? "blocked" : ""} ${completed ? "completed" : ""}">
      <span class="action-check" aria-hidden="true">${completed ? "✓" : ""}</span>
      <div><small>OBRA ${escapeHtml(work?.numero || "—")} · ${escapeHtml(item.codigo || "TAREFA")}</small>
        <strong>${escapeHtml(item.descricao || "Tarefa sem descrição")}</strong>
        <span>${isoDate(item.data_inicio_prevista) || "—"} → ${isoDate(item.data_fim_prevista) || "—"}</span>
        ${item.impedido ? `<em>${escapeHtml(item.observacao_impedimento)}</em>` : ""}
      </div>
      <b class="action-state">${stateLabel(item)}</b>
    </article>`;
  }

  function calendar() {
    const year = state.month.getFullYear();
    const month = state.month.getMonth();
    const first = new Date(Date.UTC(year, month, 1));
    const gridStart = addDays(first, -((first.getUTCDay() + 6) % 7));
    const days = Array.from({ length: 42 }, (_, index) => addDays(gridStart, index));
    const title = new Intl.DateTimeFormat("pt-PT", { month: "long", year: "numeric", timeZone: "UTC" }).format(first).toUpperCase();
    return `<section class="panel action-calendar"><header><button type="button" data-action-month="-1">←</button><h2>${title}</h2><button type="button" data-action-month="1">→</button></header>
      <div class="action-weekdays">${["SEG", "TER", "QUA", "QUI", "SEX", "SÁB", "DOM"].map(day => `<b>${day}</b>`).join("")}</div>
      <div class="action-calendar-grid">${days.map(day => {
        const dayItems = state.items.filter(item => overlapsDay(item, day));
        const outside = day.getUTCMonth() !== month;
        return `<div class="action-day ${outside ? "outside" : ""} ${dayItems.some(item => item.impedido) ? "blocked" : ""}"><span>${day.getUTCDate()}</span>
          ${dayItems.slice(0, 3).map(item => {
            const work = workFor(item);
            const context = `Obra ${work?.numero || "—"} · ${item.codigo || "Tarefa"} · ${item.descricao || ""}`;
            if (item.estado === "concluido") return `<i class="action-calendar-task completed" title="${escapeHtml(`${context} · Tarefa concluída`)}"><span>${escapeHtml(calendarTaskLabel(item))}</span><em>✓ CONCLUÍDA</em></i>`;
            return `<i title="${escapeHtml(context)}">${escapeHtml(calendarTaskLabel(item))}</i>`;
          }).join("")}
          ${dayItems.length > 3 ? `<small>+${dayItems.length - 3}</small>` : ""}</div>`;
      }).join("")}</div></section>`;
  }

  function render() {
    if (state.loading) return root.innerHTML = `<div class="empty-state"><strong>A CARREGAR PLANO DE AÇÃO…</strong></div>`;
    if (state.error) return root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">EXECUÇÃO EM OBRA</p><h1>PLANO DE AÇÃO</h1></div></div><div class="overview-warning">${escapeHtml(state.error)}</div>`;
    const now = new Date();
    const today = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
    const weekStart = monday(today);
    const weekEnd = addDays(weekStart, 6);
    const open = state.items.filter(item => item.estado !== "concluido");
    const overdue = open.filter(item => utcDate(item.data_fim_prevista) && utcDate(item.data_fim_prevista) < today)
      .sort((a, b) => String(a.data_fim_prevista).localeCompare(String(b.data_fim_prevista)));
    const weekly = state.items.filter(item => {
      const date = taskDate(item);
      return date && date >= weekStart && date <= weekEnd && !overdue.includes(item);
    }).sort((a, b) => taskDate(a) - taskDate(b));
    root.innerHTML = `<div class="page-heading action-heading"><div><p class="eyebrow">EXECUÇÃO EM OBRA</p><h1>PLANO DE AÇÃO</h1><p>Tarefas das obras sob a sua responsabilidade.</p></div><div class="heading-stat"><span>EM ABERTO</span><strong>${String(open.length).padStart(2, "0")}</strong></div></div>
      <div class="action-priority-grid">
        <section class="panel action-overdue"><header><div><p class="eyebrow">PRIORIDADE</p><h2>ATRASADAS</h2></div><strong>${overdue.length}</strong></header>
          ${overdue.length ? overdue.map(item => taskCard(item)).join("") : `<div class="empty-state"><strong>SEM TAREFAS ATRASADAS</strong></div>`}</section>
        <section class="panel action-week"><header><div><p class="eyebrow">SEMANA ATUAL</p><h2>TAREFAS DA SEMANA</h2></div><span>${isoDate(weekStart)} → ${isoDate(weekEnd)}</span></header>
          ${weekly.length ? weekly.map(item => taskCard(item)).join("") : `<div class="empty-state"><strong>SEM TAREFAS NESTA SEMANA</strong></div>`}</section>
      </div>
      ${calendar()}`;
  }

  async function load() {
    state.loading = true; state.error = ""; render();
    if (!isConfigured) { state.loading = false; state.items = []; state.phases = []; render(); return; }
    const workIds = getWorks().map(work => work.id);
    if (!workIds.length) { state.loading = false; state.items = []; state.phases = []; render(); return; }
    const phasesResponse = await supabase(`fases?select=id,obra_id,codigo,descricao&obra_id=in.(${workIds.map(encodeURIComponent).join(",")})&order=codigo`);
    if (!phasesResponse.ok) { state.loading = false; state.error = `Não foi possível carregar as fases: ${await phasesResponse.text()}`; render(); return; }
    state.phases = await phasesResponse.json();
    const phaseIds = state.phases.map(phase => phase.id);
    if (!phaseIds.length) { state.loading = false; state.items = []; render(); return; }
    const response = await supabase(`planeamento_itens?select=id,fase_id,codigo,descricao,responsavel,data_inicio_prevista,data_fim_prevista,data_fim_real,estado,percentual_executado,impedido,observacao_impedimento&fase_id=in.(${phaseIds.map(encodeURIComponent).join(",")})&order=data_fim_prevista,codigo`);
    state.loading = false;
    if (!response.ok) { state.error = `Execute primeiro plano_acao_encarregado.sql no Supabase: ${await response.text()}`; render(); return; }
    state.items = await response.json(); render();
  }

  root.addEventListener("click", event => {
    const monthButton = event.target.closest("[data-action-month]");
    if (monthButton) { state.month = new Date(state.month.getFullYear(), state.month.getMonth() + Number(monthButton.dataset.actionMonth), 1); render(); return; }
  });

  return { show: load, refresh: load, isForeman: () => getRole() === "encarregado" };
}
