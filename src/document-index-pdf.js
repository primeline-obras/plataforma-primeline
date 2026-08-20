const STATUS_COLORS = {
  positive: { fill: [229, 242, 233], text: [37, 98, 59] },
  warning: { fill: [249, 239, 211], text: [138, 91, 19] },
  negative: { fill: [246, 226, 224], text: [140, 58, 51] },
  neutral: { fill: [235, 237, 237], text: [70, 78, 82] },
  info: { fill: [226, 235, 246], text: [61, 90, 158] },
};

const plain = value => String(value ?? "—").replaceAll("_", " ");
const safeFilename = value => plain(value).normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "");

function stateTone(value) {
  const state = plain(value).toLocaleLowerCase("pt-PT");
  if (/aprovado|respondido|emitido|apresentado|^sim$/.test(state)) return STATUS_COLORS.positive;
  if (/cancelado|recusado/.test(state)) return STATUS_COLORS.negative;
  if (/enviado|discutido|analisado|reunião|reuniao/.test(state)) return STATUS_COLORS.info;
  if (/elaboração|elaboracao|revisão|revisao|pendente|não enviado|nao enviado/.test(state)) return STATUS_COLORS.warning;
  return STATUS_COLORS.neutral;
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(`${String(value).slice(0, 10)}T12:00:00`);
  return Number.isNaN(date.getTime()) ? plain(value) : new Intl.DateTimeFormat("pt-PT").format(date);
}

function formatValue(value) {
  return new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" }).format(Number(value || 0));
}

export const INDEX_PDF_DEFINITIONS = {
  pdes: {
    title: "ÍNDICE DE PDEs",
    filename: "Indice-PDEs",
    columns: [
      ["numero", "Número", 19], ["descricao", "Descrição", 53], ["revisao", "Revisão", 18],
      ["data_emissao", "Data Emissão", 23, formatDate], ["data_envio", "Data Envio", 22, formatDate],
      ["data_resposta", "Data de Aprovação", 24, formatDate], ["estado", "Estado", 33], ["notas", "Notas", 58],
    ],
  },
  desenhos: {
    title: "ÍNDICE DE DESENHOS DE PREPARAÇÃO",
    filename: "Indice-Desenhos-Preparacao",
    columns: [
      ["numero", "Número", 19], ["descricao", "Descrição", 50], ["revisao", "Revisão", 18],
      ["data_emissao", "Data Emissão", 23, formatDate], ["data_envio_do", "Data Envio DO", 24, formatDate],
      ["data_resposta_do", "Resposta DO/Fisc.", 27, formatDate], ["estado", "Estado", 34], ["notas", "Notas", 54],
    ],
  },
  pames: {
    title: "ÍNDICE DE PAME",
    filename: "Indice-PAME",
    columns: [
      ["numero", "Número", 19], ["descricao", "Descrição", 53], ["revisao", "Revisão", 18],
      ["data_emissao", "Data Emissão", 23, formatDate], ["data_envio", "Data Envio", 22, formatDate],
      ["data_resposta", "Data de Aprovação", 24, formatDate], ["estado", "Estado", 33], ["notas", "Notas", 58],
    ],
  },
  tees: {
    title: "ÍNDICE DE TEEs",
    filename: "Indice-TEEs",
    columns: [
      ["fase", "Fase", 28], ["numero", "Número", 22], ["descricao", "Descrição", 72],
      ["data_envio", "Data Envio", 25, formatDate], ["data_resposta", "Data Resposta", 27, formatDate],
      ["valor", "Valor (s/IVA)", 31, formatValue], ["dias_prorrogacao", "Prorrogação", 25, value => `${Number(value || 0)} dias`],
      ["aprovado", "Aprovado", 24],
    ],
  },
  prorrogacoes: {
    title: "ÍNDICE DE PEDIDOS DE PRORROGAÇÃO",
    filename: "Indice-Pedidos-Prorrogacao",
    columns: [
      ["numero", "Número", 20], ["motivo", "Motivo", 63], ["dias_solicitados", "Dias Solicitados", 24],
      ["tee_origem", "TEE de Origem", 32], ["data_pedido", "Data do Pedido", 27, formatDate],
      ["data_resposta", "Data de Resposta", 27, formatDate], ["estado", "Estado", 25], ["notas", "Notas", 55],
    ],
  },
};

export function buildDocumentIndexPdf({ kind, work, rows, referenceDate = new Date() }) {
  const JsPdf = window.jspdf?.jsPDF;
  if (!JsPdf) throw new Error("O gerador de PDF ainda não terminou de carregar. Tente novamente.");
  const definition = INDEX_PDF_DEFINITIONS[kind];
  if (!definition) throw new Error("Índice PDF desconhecido.");

  const pdf = new JsPdf({ orientation: "landscape", unit: "mm", format: "a4" });
  const pageWidth = 297;
  const margin = 12;
  const tableWidth = definition.columns.reduce((sum, column) => sum + column[2], 0);
  const scale = (pageWidth - margin * 2) / tableWidth;
  const widths = definition.columns.map(column => column[2] * scale);
  let y = 42;
  let page = 1;

  const pageHeader = () => {
    pdf.setFillColor(32, 36, 43); pdf.rect(0, 0, pageWidth, 27, "F");
    pdf.setTextColor(255); pdf.setFont("helvetica", "bold"); pdf.setFontSize(17); pdf.text("/// PRIMELINE", margin, 11);
    pdf.setFontSize(8); pdf.text("ENGENHARIA E CONSTRUÇÃO", margin, 18);
    pdf.setFontSize(13); pdf.text(definition.title, pageWidth - margin, 11, { align: "right" });
    pdf.setFont("helvetica", "normal"); pdf.setFontSize(8);
    pdf.text(`${plain(work?.numero)} · ${plain(work?.nome)}`, pageWidth - margin, 18, { align: "right" });
    pdf.setTextColor(65); pdf.setFontSize(7);
    pdf.text(`Data de referência: ${formatDate(referenceDate.toISOString())}`, margin, 34);
    pdf.text(`Página ${page}`, pageWidth - margin, 34, { align: "right" });
    y = 39;
  };

  const tableHeader = () => {
    let x = margin;
    pdf.setFillColor(52, 59, 63); pdf.setTextColor(255); pdf.setFont("helvetica", "bold"); pdf.setFontSize(6.7);
    definition.columns.forEach((column, index) => {
      pdf.setFillColor(52, 59, 63);
      pdf.rect(x, y, widths[index], 9, "F");
      pdf.setTextColor(255);
      pdf.text(column[1].toUpperCase(), x + 2, y + 5.7, { maxWidth: widths[index] - 4 });
      x += widths[index];
    });
    y += 9;
  };

  const addPage = () => { pdf.addPage("a4", "landscape"); page += 1; pageHeader(); tableHeader(); };
  pageHeader(); tableHeader();

  if (!rows.length) {
    pdf.setTextColor(100); pdf.setFont("helvetica", "bold"); pdf.setFontSize(10);
    pdf.text("SEM REGISTOS NESTE ÍNDICE", pageWidth / 2, y + 18, { align: "center" });
  }

  rows.forEach((row, rowIndex) => {
    const cells = definition.columns.map(column => {
      const raw = row[column[0]];
      const formatted = column[3] ? column[3](raw) : plain(raw);
      return pdf.splitTextToSize(formatted, widths[definition.columns.indexOf(column)] - 4);
    });
    const rowHeight = Math.max(9, ...cells.map(lines => lines.length * 3.5 + 4));
    if (y + rowHeight > 196) addPage();
    let x = margin;
    definition.columns.forEach((column, index) => {
      const isState = column[0] === "estado" || column[0] === "aprovado";
      const tone = isState ? stateTone(row[column[0]]) : null;
      if (tone) pdf.setFillColor(...tone.fill);
      else if (rowIndex % 2) pdf.setFillColor(247, 247, 245);
      else pdf.setFillColor(255, 255, 255);
      pdf.setDrawColor(218, 220, 217); pdf.rect(x, y, widths[index], rowHeight, "FD");
      pdf.setTextColor(...(tone ? tone.text : [45, 50, 53]));
      pdf.setFont("helvetica", isState ? "bold" : "normal"); pdf.setFontSize(6.7);
      pdf.text(cells[index], x + 2, y + 4.4, { lineHeightFactor: 1.25 });
      x += widths[index];
    });
    y += rowHeight;
  });

  const pages = pdf.getNumberOfPages();
  for (let number = 1; number <= pages; number += 1) {
    pdf.setPage(number); pdf.setTextColor(110); pdf.setFont("helvetica", "normal"); pdf.setFontSize(6.5);
    pdf.text(`PRIMELINE · ${definition.title} · ${plain(work?.numero)} · ${number}/${pages}`, pageWidth - margin, 205, { align: "right" });
  }
  return { pdf, filename: `${definition.filename}-${safeFilename(work?.numero || work?.nome || "Obra")}.pdf` };
}

export function generateDocumentIndexPdf(options) {
  const result = buildDocumentIndexPdf(options);
  result.pdf.save(result.filename);
  return result;
}
