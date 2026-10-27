const PDFJS_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs";
const PDFJS_WORKER_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs";

export function normalizeSupplierName(value) {
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("pt-PT").replace(/\b(unipessoal|unip|lda|sa|ltda)\b\.?/g, " ")
    .replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
}

function tokenSet(value) {
  return new Set(normalizeSupplierName(value).split(" ").filter(token => token.length > 1));
}

export function rankSupplierMatches(extractedName, suppliers) {
  const target = normalizeSupplierName(extractedName);
  if (!target) return [];
  const targetTokens = tokenSet(target);
  return (suppliers || []).map(supplier => {
    const candidate = normalizeSupplierName(supplier.nome);
    const candidateTokens = tokenSet(candidate);
    const shared = [...targetTokens].filter(token => candidateTokens.has(token)).length;
    const union = new Set([...targetTokens, ...candidateTokens]).size || 1;
    const contains = target.includes(candidate) || candidate.includes(target);
    const score = target === candidate ? 1 : Math.min(.99, shared / union + (contains ? .25 : 0));
    return { supplier, score };
  }).filter(row => row.score >= .35).sort((a, b) => b.score - a.score
    || String(a.supplier.nome).localeCompare(String(b.supplier.nome), "pt-PT"));
}

export function parsePortugueseAmount(value) {
  const clean = String(value || "").replace(/[^\d,.-]/g, "");
  if (!clean || !/\d/.test(clean)) return null;
  let normalized = clean;
  if (clean.includes(",")) normalized = clean.replace(/\./g, "").replace(",", ".");
  else if ((clean.match(/\./g) || []).length > 1) normalized = clean.replace(/\./g, "");
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
}

function isoDate(value) {
  const match = String(value || "").match(/\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b/);
  return match ? `${match[3]}-${match[2].padStart(2, "0")}-${match[1].padStart(2, "0")}` : "";
}

function linesOf(text) {
  return String(text || "").split(/\r?\n/).map(line => line.replace(/\s+/g, " ").trim()).filter(Boolean);
}

function context(lines, pattern, length = 3) {
  const index = lines.findIndex(line => pattern.test(line));
  return index < 0 ? "" : lines.slice(index, index + length).join(" ").slice(0, 1000);
}

function supplierCandidate(lines) {
  const legal = lines.find(line => /\b(?:unip(?:essoal)?\.?[- ]?lda|l(?:da)?\.?|s\.?a\.?)\b/i.test(line)
    && !/cliente|primeline|morada|nif|condi[cç][oõ]es/i.test(line));
  if (legal) return legal.replace(/^(fornecedor|empresa)\s*[:.-]?\s*/i, "").trim();
  const counts = new Map();
  lines.slice(0, 180).forEach(line => {
    if (!/^[A-ZÀ-Ý][A-ZÀ-Ý0-9 .&'-]{2,35}$/.test(line) || /CLIENTE|TOTAL|OR[ÇC]AMENTO|PROPOSTA|P[ÁA]GINA|TERMOS|CONDI[ÇC][ÕO]ES/.test(line)) return;
    const key = line.trim(); counts.set(key, (counts.get(key) || 0) + 1);
  });
  return [...counts].sort((a, b) => b[1] - a[1] || a[0].length - b[0].length)[0]?.[0] || "";
}

function officialTotal(lines) {
  const priorities = [
    /total\s+(?:roupeiros?|il[ií]quido|s\/?iva)[^\d]{0,30}([\d .]+,\d{2})\s*€/i,
    /(?:total|valor\s+da\s+cota[cç][aã]o)[^\d]{0,30}([\d .]+,\d{2})\s*€/i,
  ];
  for (const pattern of priorities) {
    for (const line of lines) {
      const match = line.match(pattern); const value = parsePortugueseAmount(match?.[1]);
      if (value != null) return value;
    }
  }
  const values = lines.flatMap(line => [...line.matchAll(/([\d .]+,\d{2})\s*€/g)]
    .map(match => parsePortugueseAmount(match[1])).filter(value => value != null));
  return values.length ? Math.max(...values) : null;
}

function proposalReference(lines) {
  const patterns = [
    /(?:or[cç]amento|proposta)\s*(?:n[.ºo°]*)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9./-]{2,})/i,
    /refer[eê]ncia\s*[:#-]?\s*([A-Z0-9][A-Z0-9./-]{2,})/i,
  ];
  for (const line of lines.slice(0, 80)) for (const pattern of patterns) {
    const match = line.match(pattern); if (match?.[1]) return match[1];
  }
  return "";
}

function proposalDate(lines) {
  const preferred = lines.find(line => /\b(data|lisboa|or[cç]amento|proposta)\b/i.test(line)
    && /\d{1,2}[./-]\d{1,2}[./-]\d{4}/.test(line));
  return isoDate(preferred || lines.slice(0, 80).join(" "));
}

function validityDays(text) {
  const match = String(text).match(/valid(?:ade|o)(?:\s+do\s+or[cç]amento)?[^\d]{0,30}(\d{1,3})\s*dias/i);
  return match ? Number(match[1]) : null;
}

function notableExclusions(lines) {
  return lines.filter(line => /\b(n[aã]o\s+(?:inclu[ií]d[ao]|contempla|executa|fornece|realiza)|acresce[mr]?\s+\d|a\s+cargo\s+do\s+cliente|responsabilidade\s+do\s+cliente)\b/i.test(line))
    .filter((line, index, rows) => rows.indexOf(line) === index).slice(0, 10).join("\n");
}

export function parseProposalText(text, fileName = "") {
  const lines = linesOf(text);
  const validity = validityDays(text);
  const date = proposalDate(lines);
  const validityDate = date && validity != null
    ? new Date(`${date}T12:00:00`) : null;
  if (validityDate) validityDate.setDate(validityDate.getDate() + validity);
  const supplier = supplierCandidate(lines);
  return {
    fileName,
    supplierName: supplier,
    reference: proposalReference(lines),
    proposalDate: date,
    validityDays: validity,
    validityDate: validityDate ? validityDate.toISOString().slice(0, 10) : "",
    officialTotal: officialTotal(lines),
    paymentTerms: context(lines, /condi[cç][oõ]es?\s+(?:de\s+)?pagamento/i, 5),
    deliveryTerms: context(lines, /prazo\s+de\s+entrega/i, 3),
    assemblyTerms: context(lines, /prazo\s+de\s+montagem|montagem\/instala[cç][aã]o/i, 3),
    warranty: context(lines, /\bgarantia\b/i, 3),
    exclusions: notableExclusions(lines),
    fullText: lines.join("\n"),
  };
}

function pdfRows(items, pageNumber) {
  const positioned = items.filter(item => String(item.str || "").trim()).map(item => ({
    text: String(item.str).replace(/\s+/g, " ").trim(),
    x: Number(item.transform?.[4] || 0), y: Number(item.transform?.[5] || 0),
    width: Number(item.width || 0),
  })).sort((a, b) => Math.abs(b.y - a.y) > 2 ? b.y - a.y : a.x - b.x);
  const rows = [];
  for (const item of positioned) {
    let row = rows.find(candidate => Math.abs(candidate.y - item.y) <= 2);
    if (!row) { row = { pageNumber, y: item.y, items: [] }; rows.push(row); }
    row.items.push(item);
  }
  return rows.map(row => {
    row.items.sort((a, b) => a.x - b.x);
    row.text = row.items.map(item => item.text).join(" ").replace(/\s+/g, " ").trim();
    return row;
  }).sort((a, b) => a.pageNumber - b.pageNumber || b.y - a.y);
}

function amountTokens(row) {
  const tokens = [];
  for (const item of row.items) for (const match of item.text.matchAll(/(?:\d{1,3}(?:[.\s]\d{3})*|\d+),\d{2,4}\s*€?/g)) {
    const value = parsePortugueseAmount(match[0]);
    if (value != null) tokens.push({ value, x: item.x, raw: match[0] });
  }
  return tokens.sort((a, b) => a.x - b.x);
}

function isTotalRow(text) {
  return /\b(total|iva|incid[eê]ncia|desconto|pagamento\s+por|iban|nib)\b/i.test(text);
}

function looksLikeHeading(text) {
  return /\b(hall|quarto|suite|su[ií]te|roupeiro|arm[aá]rio|cozinha|porta|pavimento|revestimento|carpintaria)\b/i.test(text)
    && !/condi[cç][oõ]es|prazo|cliente|morada/i.test(text);
}

function cleanDescription(text) {
  return String(text || "").replace(/^(?:\d+(?:\.\d+)*|\d+(?:,\s*\d+)?\s*[-–])\s*/, "")
    .replace(/\s+(?:\d+[.,]\d{2,4}\s*€?\s*){1,3}$/g, "").trim();
}

export function extractProposalLineCandidates(rows) {
  const candidates = [];
  const recentHeadings = new Map();
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index];
    if (looksLikeHeading(row.text) && !isTotalRow(row.text)) recentHeadings.set(row.pageNumber, row.text);
    const amounts = amountTokens(row);
    if (!amounts.length || isTotalRow(row.text)) continue;
    let description = cleanDescription(row.items.filter(item => item.x < amounts[0].x - 2).map(item => item.text).join(" "));
    if (!looksLikeHeading(description)) description = recentHeadings.get(row.pageNumber) || description;
    if (!looksLikeHeading(description)) continue;
    let quantity = 1;
    const beforePrice = row.items.filter(item => item.x < amounts[0].x).map(item => item.text).join(" ");
    const quantityMatch = beforePrice.match(/(?:^|\s)(\d+(?:[.,]\d+)?)\s*(?:un|vg|cj|ml|m2|m²)?\s*$/i);
    if (quantityMatch) quantity = parsePortugueseAmount(quantityMatch[1]) || 1;
    const unitMatch = beforePrice.match(/\b(un|vg|cj|ml|m2|m²)\b/i);
    const unitPrice = amounts.length > 1 ? amounts.at(-2).value : amounts[0].value;
    let total = amounts.at(-1).value;
    const next = rows[index + 1];
    if (amounts.length === 1 && next?.pageNumber === row.pageNumber && Math.abs(row.y - next.y) < 28) {
      const nextAmounts = amountTokens(next);
      if (nextAmounts.length && !isTotalRow(next.text)) total = nextAmounts.at(-1).value;
    }
    candidates.push({
      sourcePage: row.pageNumber,
      originalDescription: cleanDescription(description).slice(0, 1000),
      normalizedDescription: cleanDescription(description).slice(0, 240),
      originalQuantity: quantity,
      normalizedQuantity: 1,
      unit: unitMatch?.[1]?.toLowerCase() || "un",
      unitPrice,
      originalTotal: total,
      scopeStatus: /\bop(?:[cç][aã]o)?\s*\d|\balternativa\b/i.test(description) ? "alternativa" : "incluido",
      comparable: !/\bop(?:[cç][aã]o)?\s*\d|\balternativa\b/i.test(description),
      confidence: amounts.length > 1 ? .8 : .55,
    });
  }
  const unique = new Map();
  candidates.forEach(row => {
    const key = `${normalizeSupplierName(row.normalizedDescription)}|${row.unitPrice}|${row.sourcePage}`;
    if (!unique.has(key)) unique.set(key, row);
  });
  return [...unique.values()].slice(0, 100);
}

export async function extractComparativeProposalPdf(file) {
  if (!file || (file.type !== "application/pdf" && !/\.pdf$/i.test(file.name))) throw new Error("Selecione um ficheiro PDF.");
  if (file.size > 10 * 1024 * 1024) throw new Error("O PDF excede o limite de 10 MB.");
  const pdfjs = await import(PDFJS_URL);
  pdfjs.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_URL;
  const pdf = await pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
  const rows = [];
  for (let pageNumber = 1; pageNumber <= Math.min(pdf.numPages, 30); pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    const content = await page.getTextContent();
    rows.push(...pdfRows(content.items, pageNumber));
  }
  const text = rows.map(row => row.text).join("\n");
  if (text.replace(/\s/g, "").length < 30) throw new Error("O PDF não contém texto pesquisável. Este documento precisa de OCR ou preenchimento manual.");
  return { ...parseProposalText(text, file.name), pageCount: pdf.numPages, lines: extractProposalLineCandidates(rows) };
}
