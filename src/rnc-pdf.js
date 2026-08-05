const label = value => String(value || "—").replaceAll("_", " ").replace(/\b\w/g, letter => letter.toUpperCase());

async function imageData(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

export async function generateRncPdf({ rnc, work, phase, subcontract, reporter, verifier, annexes, download }) {
  const JsPdf = window.jspdf?.jsPDF;
  if (!JsPdf) throw new Error("O gerador de PDF ainda não terminou de carregar. Tente novamente.");
  const pdf = new JsPdf({ unit: "mm", format: "a4" });
  const width = 210, margin = 16;
  let y = 16;
  const ensure = height => { if (y + height > 280) { pdf.addPage(); y = 18; } };
  const heading = (title) => {
    ensure(15); pdf.setFillColor(32, 36, 43); pdf.roundedRect(margin, y, width - margin * 2, 10, 2, 2, "F");
    pdf.setTextColor(255); pdf.setFont("helvetica", "bold"); pdf.setFontSize(9); pdf.text(title.toUpperCase(), margin + 4, y + 6.5);
    pdf.setTextColor(20); y += 14;
  };
  const field = (name, value) => {
    ensure(13); pdf.setFontSize(7); pdf.setTextColor(110); pdf.setFont("helvetica", "bold"); pdf.text(name.toUpperCase(), margin, y);
    pdf.setFontSize(10); pdf.setTextColor(25); pdf.setFont("helvetica", "normal");
    const lines = pdf.splitTextToSize(String(value || "—"), width - margin * 2); pdf.text(lines, margin, y + 5); y += Math.max(12, lines.length * 5 + 6);
  };

  pdf.setFillColor(23, 26, 31); pdf.rect(0, 0, width, 30, "F");
  pdf.setTextColor(255); pdf.setFont("helvetica", "bold"); pdf.setFontSize(18); pdf.text("/// PRIMELINE", margin, 13);
  pdf.setFontSize(8); pdf.text("RELATÓRIO DE NÃO CONFORMIDADE", margin, 21);
  pdf.setFontSize(12); pdf.text(`RNC ${String(rnc.numero).padStart(3, "0")}`, 194, 17, { align: "right" });
  y = 40;
  heading("Identificação");
  field("Obra", `${work.numero} · ${work.nome}`); field("Data de deteção", rnc.data_deteccao); field("Fase", phase ? `${phase.codigo || ""} · ${phase.descricao}` : "Sem fase");
  field("Local", rnc.local_ocorrencia); field("Origem", label(rnc.origem)); field("Gravidade", label(rnc.gravidade));
  if (subcontract) field("Subempreitada", subcontract.especialidade || subcontract.id);
  field("Reportado por", reporter);
  heading("Não conformidade"); field("Descrição", rnc.descricao);
  heading("Tratamento"); field("Estado", label(rnc.estado)); field("Ação corretiva", rnc.acao_corretiva); field("Responsável pela correção", rnc.responsavel_correcao); field("Prazo", rnc.prazo_correcao);
  field("Observação da verificação", rnc.observacao_verificacao); field("Verificado por", verifier); field("Data de fecho", rnc.data_fecho);

  if (annexes.length) {
    heading("Evidências");
    for (const annex of annexes) {
      if (!/\.(png|jpe?g|webp)$/i.test(annex.nome_arquivo || annex.arquivo_url)) { field("Anexo", annex.nome_arquivo); continue; }
      try {
        const blob = await download(annex.arquivo_url);
        const data = await imageData(blob);
        ensure(70); pdf.setFontSize(8); pdf.text(annex.nome_arquivo, margin, y); y += 3;
        const format = blob.type.includes("png") ? "PNG" : "JPEG";
        pdf.addImage(data, format, margin, y, 80, 60, undefined, "FAST"); y += 66;
      } catch { field("Anexo", `${annex.nome_arquivo} (não foi possível incorporar a imagem)`); }
    }
  }
  const pages = pdf.getNumberOfPages();
  for (let page = 1; page <= pages; page++) { pdf.setPage(page); pdf.setFontSize(7); pdf.setTextColor(120); pdf.text(`PRIMELINE · Página ${page}/${pages}`, 194, 291, { align: "right" }); }
  pdf.save(`RNC_${work.numero}_${String(rnc.numero).padStart(3, "0")}.pdf`);
}
