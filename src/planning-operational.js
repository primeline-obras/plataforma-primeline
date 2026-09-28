// Pure operational rules. No database writes or inferred historical values.
export const WEIGHT_TOLERANCE = 0.01;
const DAY = 86400000;
const present = value => value !== null && value !== undefined && String(value).trim() !== "";
const percentage = value => present(value) && Number.isFinite(Number(value)) && Number(value) >= 0 && Number(value) <= 100;
export const activeTask = item => !item.arquivado_em && !item._archive;

export function weightSummary(items) {
  const active = items.filter(activeTask);
  const invalid = active.filter(item => !percentage(item.peso_percentual));
  const assigned = active.reduce((sum, item) => sum + (percentage(item.peso_percentual) ? Number(item.peso_percentual) : 0), 0);
  return { assigned, missing: Math.max(0, 100 - assigned), excess: Math.max(0, assigned - 100),
    valid: active.length > 0 && !invalid.length && Math.abs(assigned - 100) <= WEIGHT_TOLERANCE + 1e-9,
    invalidIds: invalid.map(item => item.id), count: active.length };
}

export function phaseProgress(items) {
  if (!weightSummary(items).valid) return null;
  const active = items.filter(activeTask);
  if (active.some(item => !percentage(item.percentual_executado))) return null;
  return active.reduce((sum, item) => sum + Number(item.peso_percentual) * Number(item.percentual_executado) / 100, 0);
}

export function workProgress(phases, items) {
  const active = phases.filter(activeTask);
  if (!weightSummary(active).valid) return null;
  let total = 0;
  for (const phase of active) {
    const progress = phaseProgress(items.filter(item => item.fase_id === phase.id));
    if (progress === null) return null;
    total += Number(phase.peso_percentual) * progress / 100;
  }
  return total;
}

// Explicit user action only. Largest remainders preserve exactly 100.00%.
export function redistributeWeights(items) {
  const active = items.filter(activeTask);
  if (!active.length || active.some(item => !percentage(item.peso_percentual))) throw new Error("Indique pesos válidos antes de redistribuir.");
  const total = active.reduce((sum, item) => sum + Number(item.peso_percentual), 0);
  if (total <= 0) throw new Error("Não é possível redistribuir pesos nulos.");
  const portions = active.map((item, index) => {
    const exact = Number(item.peso_percentual) / total * 10000;
    return { id: item.id, index, units: Math.floor(exact), remainder: exact - Math.floor(exact) };
  });
  const missing = 10000 - portions.reduce((sum, row) => sum + row.units, 0);
  [...portions].sort((a, b) => b.remainder - a.remainder || a.index - b.index).slice(0, missing).forEach(row => row.units++);
  const weights = new Map(portions.map(row => [row.id, row.units / 100]));
  return items.map(item => weights.has(item.id) ? { ...item, peso_percentual: weights.get(item.id) } : { ...item });
}

export function dateDay(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const timestamp = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(timestamp) && new Date(timestamp).toISOString().slice(0, 10) === value ? timestamp / DAY : null;
}
const dayDate = day => new Date(day * DAY).toISOString().slice(0, 10);

export function workDates(work, progress, today) {
  const start = dateDay(work.data_inicio), end = dateDay(work.data_fim_contratual_atual);
  const operational = dateDay(work.data_fim_prevista), now = dateDay(today);
  const consumed = start !== null && end !== null && end > start && now !== null ? Math.max(0, (now - start) / (end - start) * 100) : null;
  return { progress, consumed, difference: progress !== null && consumed !== null ? progress - consumed : null,
    contractualEnd: work.data_fim_contratual_atual || null, operationalEnd: work.data_fim_prevista || null,
    delayDays: end !== null && operational !== null ? operational - end : null };
}

// The preview never mutates the source. Only an atomic server RPC can commit it.
export function previewPlanningBatch({ items, changes = [], dependencies = [], phases = [] }) {
  const original = new Map(items.map(item => [item.id, item]));
  const rows = new Map(items.map(item => [item.id, { ...item }]));
  const conflicts = [], edited = [], created = [], archived = [], automatic = [];
  const manualDates = new Set(), seen = new Set();
  for (const change of changes) {
    if (!change.id || seen.has(change.id)) { conflicts.push({ type: "duplicate_id", id: change.id }); continue; }
    seen.add(change.id);
    const previous = rows.get(change.id);
    if (!previous && !change._new) { conflicts.push({ type: "missing_task", id: change.id }); continue; }
    const row = { ...previous, ...change };
    rows.set(row.id, row);
    if (["data_inicio_prevista", "data_fim_prevista", "data_inicio_real", "data_fim_real"].some(key => Object.hasOwn(change, key) && change[key] !== previous?.[key])) manualDates.add(row.id);
    if (row._archive) {
      if (row._new) rows.delete(row.id);
      else archived.push(row.id);
    } else if (!previous) created.push(row.id);
    else edited.push(row.id);
  }
  const incoming = new Map(), outgoing = new Map(), degree = new Map();
  for (const row of rows.values()) {
    degree.set(row.id, 0); incoming.set(row.id, []); outgoing.set(row.id, []);
    if (!activeTask(row)) continue;
    if (!String(row.descricao || "").trim()) conflicts.push({ type: "description", id: row.id });
    if (!percentage(row.percentual_executado)) conflicts.push({ type: "progress", id: row.id });
    for (const key of ["data_inicio_prevista", "data_fim_prevista", "data_inicio_real", "data_fim_real"]) {
      if (present(row[key]) && dateDay(row[key]) === null) conflicts.push({ type: "date", id: row.id, field: key });
    }
    if (row.data_inicio_prevista && row.data_fim_prevista && row.data_inicio_prevista > row.data_fim_prevista) conflicts.push({ type: "date_order", id: row.id });
  }
  for (const dependency of dependencies) {
    const target = rows.get(dependency.item_id), source = rows.get(dependency.depende_de_item_id);
    if (!target || !source) { conflicts.push({ type: "missing_dependency", dependency }); continue; }
    if (!activeTask(target)) continue;
    if (!activeTask(source)) { conflicts.push({ type: "archived_dependency", id: target.id, predecessor: source.id }); continue; }
    if (dependency.tipo !== "fim_inicio" || !Number.isInteger(Number(dependency.atraso_dias ?? 0))) { conflicts.push({ type: "unsupported_dependency", dependency }); continue; }
    incoming.get(target.id).push(dependency); outgoing.get(source.id).push(target.id);
    degree.set(target.id, degree.get(target.id) + 1);
  }
  const queue = [...rows.keys()].filter(id => degree.get(id) === 0);
  for (let i = 0; i < queue.length; i++) {
    const row = rows.get(queue[i]);
    let required = null;
    for (const dependency of incoming.get(row.id)) {
      const predecessor = rows.get(dependency.depende_de_item_id);
      const end = dateDay(predecessor.data_fim_real || predecessor.data_fim_prevista);
      if (end !== null) required = Math.max(required ?? -Infinity, end + Number(dependency.atraso_dias ?? 0));
    }
    const start = dateDay(row.data_inicio_prevista);
    if (activeTask(row) && !row.data_fim_real && required !== null && start !== null && required > start) {
      if (manualDates.has(row.id)) conflicts.push({ type: "manual_date_collision", id: row.id, requiredStart: dayDate(required) });
      else {
        const end = dateDay(row.data_fim_prevista);
        const duration = end !== null ? end - start : Number(row.duracao_dias ?? 0);
        if (!Number.isFinite(duration) || duration < 0) conflicts.push({ type: "duration", id: row.id });
        else {
          row.data_inicio_prevista = dayDate(required); row.data_fim_prevista = dayDate(required + Math.ceil(duration));
          automatic.push({ id: row.id, before: original.get(row.id), after: { ...row } });
        }
      }
    }
    for (const id of outgoing.get(row.id)) {
      degree.set(id, degree.get(id) - 1);
      if (degree.get(id) === 0) queue.push(id);
    }
  }
  if (queue.length !== rows.size) conflicts.push({ type: "dependency_cycle" });
  const result = [...rows.values()];
  const phaseIds = new Set(phases.map(phase => phase.id));
  for (const row of result.filter(activeTask)) if (!phaseIds.has(row.fase_id)) conflicts.push({ type: "phase", id: row.id });
  for (const phase of phases.filter(activeTask)) {
    const summary = weightSummary(result.filter(item => item.fase_id === phase.id));
    if (summary.count && !summary.valid) conflicts.push({ type: "phase_weights", id: phase.id, ...summary });
  }
  return { items: result, edited, created, archived, automatic, conflicts, valid: conflicts.length === 0 };
}
