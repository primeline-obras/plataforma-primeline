const numericPattern = /^[+\-−]?\s*(?:€\s*)?[\d\s.]+(?:,\d+)?\s*(?:€|%|dias?|meses?|h)?$/iu;

const positiveStates = new Set([
  "adjudicado", "aprovado", "concluido", "concluído", "pago", "fechado", "verificado", "ativo", "válido", "valido"
]);
const negativeStates = new Set([
  "recusado", "atrasado", "cancelado", "bloqueado", "urgente", "vencido", "não recomendado", "nao recomendado"
]);
const progressStates = new Set([
  "em comparação", "em comparacao", "em curso", "em execução", "em execucao", "pendente", "por iniciar", "aberto"
]);
const decisionStates = new Set([
  "requer decisão", "requer decisao", "prioritário", "prioritario"
]);
const waitingStates = new Set([
  "em análise", "em analise", "aguarda resposta", "não avaliado", "nao avaliado", "inativo"
]);

function normalizedText(node) {
  return String(node.textContent || "").trim().replace(/\s+/g, " ").toLocaleLowerCase("pt-PT");
}

function decorateTable(table) {
  table.querySelectorAll("tbody tr, tr:not(:has(th))").forEach(row => {
    const cells = [...row.children].filter(cell => cell.matches("td"));
    cells.forEach(cell => {
      const value = String(cell.textContent || "").trim();
      if (value && numericPattern.test(value)) cell.classList.add("ui-number-cell");
    });
    const identifier = cells.find(cell => !cell.classList.contains("ui-number-cell"));
    if (identifier) identifier.classList.add("ui-identifier-cell");
  });
}

function decorateBadge(node) {
  const state = normalizedText(node);
  if (!state || state.length > 45) return;
  const exact = [...positiveStates, ...negativeStates, ...progressStates, ...decisionStates, ...waitingStates].some(item => state === item || state.startsWith(`${item} `));
  if (!exact) return;
  node.classList.add("ui-state-badge");
  if ([...positiveStates].some(item => state === item || state.startsWith(`${item} `))) node.classList.add("ui-state-positive");
  else if ([...negativeStates].some(item => state === item || state.startsWith(`${item} `))) node.classList.add("ui-state-negative");
  else if ([...decisionStates].some(item => state === item || state.startsWith(`${item} `))) node.classList.add("ui-state-decision");
  else if ([...waitingStates].some(item => state === item || state.startsWith(`${item} `))) node.classList.add("ui-state-waiting");
  else node.classList.add("ui-state-progress");
}

function decorate(root = document) {
  root.querySelectorAll?.("table").forEach(decorateTable);
  root.querySelectorAll?.("span, em, b, strong").forEach(decorateBadge);
}

decorate();
new MutationObserver(records => {
  records.forEach(record => record.addedNodes.forEach(node => {
    if (node.nodeType === Node.ELEMENT_NODE) decorate(node);
  }));
}).observe(document.documentElement, { childList: true, subtree: true });
