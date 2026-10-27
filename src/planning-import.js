export function normalizedHeader(value) {
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9%]+/g, " ").trim();
}

export function csvRows(text, delimiter = null) {
  const source = String(text || "").replace(/^\uFEFF/, "");
  const firstLine = source.split("\n")[0] || "";
  const separator = delimiter || (firstLine.includes("\t") ? "\t" : firstLine.includes(";") ? ";" : ",");
  const rows = []; let row = []; let cell = ""; let quoted = false;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (character === '"') {
      if (quoted && source[index + 1] === '"') { cell += '"'; index += 1; }
      else quoted = !quoted;
    } else if (character === separator && !quoted) { row.push(cell); cell = ""; }
    else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && source[index + 1] === "\n") index += 1;
      row.push(cell); if (row.some(value => String(value).trim())) rows.push(row); row = []; cell = "";
    } else cell += character;
  }
  row.push(cell); if (row.some(value => String(value).trim())) rows.push(row);
  return rows;
}

export function parsedDate(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0, 10);
  const text = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(text)) return text.slice(0, 10);
  const match = text.match(/^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})$/);
  if (!match) return null;
  return `${match[3].length === 2 ? `20${match[3]}` : match[3]}-${match[2].padStart(2, "0")}-${match[1].padStart(2, "0")}`;
}

export function parsedNumber(value, fallback = null) {
  if (value === null || value === undefined || value === "") return fallback;
  const number = Number(String(value).replace("%", "").replace(/\s/g, "").replace(",", "."));
  return Number.isFinite(number) ? number : fallback;
}

export function parsedState(value, progress = 0) {
  const text = normalizedHeader(value).replaceAll(" ", "_");
  if (["concluido", "concluida"].includes(text) || progress >= 100) return "concluido";
  if (["em_execucao", "execucao", "em_curso"].includes(text) || progress > 0) return "em_execucao";
  return "por_iniciar";
}
