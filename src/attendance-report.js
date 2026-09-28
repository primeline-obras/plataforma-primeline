const labels = {presente:'Presente',falta_com_justificacao:'Falta com justificação',falta_sem_justificacao:'Falta sem justificação'};
const time = value => value ? String(value).slice(0,5) : '';
const headers = ['Colaborador','Função','Data','Estado','Entrada manhã','Saída manhã','Entrada tarde','Saída tarde','Horas','Observação','Justificação'];
export function prepareAttendanceReport(rows, work, month) {
  if (!work?.id || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new Error('Selecione uma obra e um mês válidos.');
  if(!Array.isArray(rows)) throw new Error('Resposta mensal inválida.');
  if(!rows.length) throw new Error('Não existem registos neste mês e obra.');
  if(rows.some(r=>r.obra_id!==work.id || !String(r.data).startsWith(`${month}-`) || r.horas==null || !Number.isFinite(Number(r.horas)))) throw new Error('O relatório contém dados incompatíveis com a obra/mês selecionados.');
  const sorted = [...rows].sort((a,b)=>String(a.colaborador).localeCompare(String(b.colaborador),'pt') || String(a.data).localeCompare(String(b.data)));
  const totals = new Map();
  for(const row of sorted) {
    const item=totals.get(row.colaborador_id) || {nome:row.colaborador,horas:0};
    item.horas+=Number(row.horas);totals.set(row.colaborador_id,item);
  }
  const round = n=>Math.round((n+Number.EPSILON)*100)/100;
  return {title:`Obra ${work.numero} · ${work.nome}`,month,
    filename:`folha-ponto-obra-${String(work.numero).replace(/[^\w-]/g,'_')}-${month}`,
    headers,lines:sorted.map(r=>[r.colaborador,r.funcao||'',r.data,labels[r.estado]||r.estado,time(r.entrada_manha),time(r.saida_manha),time(r.entrada_tarde),time(r.saida_tarde),Number(r.horas),r.observacao||'',r.justificacao_estado||'']),
    totals:[...totals.values()].map(t=>[t.nome,round(t.horas)]),total:round(sorted.reduce((n,r)=>n+Number(r.horas),0))};
}
export function exportAttendanceExcel(report, XLSX) {
  if(!XLSX?.utils) throw new Error('Biblioteca Excel indisponível. Atualize a página e tente novamente.');
  const book=XLSX.utils.book_new();
  const sheet=XLSX.utils.aoa_to_sheet([[report.title],[report.month],[],report.headers,...report.lines]);
  sheet['!cols']=[30,23,12,28,15,15,15,15,10,50,20].map(wch=>({wch}));
  XLSX.utils.book_append_sheet(book,sheet,'Registos');
  XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet([[report.title],[report.month],[],['Colaborador','Total horas'],...report.totals,['TOTAL MENSAL DA OBRA',report.total]]),'Totais');
  XLSX.writeFile(book,`${report.filename}.xlsx`);
}
export function exportAttendancePdf(report, JsPDF) {
  if(!JsPDF) throw new Error('Biblioteca PDF indisponível. Atualize a página e tente novamente.');
  const pdf=new JsPDF({orientation:'landscape',unit:'mm',format:'a4'});
  const widths=[35,25,21,29,17,17,17,17,12,62,25];
  let y=10;
  function page() {
    pdf.setFontSize(12);pdf.text('FOLHA DE PONTO MENSAL',10,10);pdf.setFontSize(9);
    const title = pdf.splitTextToSize(`${report.title} · ${report.month}`,277);
    pdf.text(title,10,16);y=22+title.length*4;
  }
  function tableRow(values) {
    pdf.setFontSize(7);
    const cells=values.map((v,i)=>pdf.splitTextToSize(String(v ?? ''),widths[i]-3));
    const max=Math.max(1,...cells.map(c=>c.length));
    for(let start=0;start<max;) {
      if(y>185) {pdf.addPage();page();}
      const count=Math.min(max-start,Math.max(1,Math.floor((190-y)/3.5)));
      let x=10;
      cells.forEach((lines,i)=>{const part=lines.slice(start,start+count);if(part.length)pdf.text(part,x,y);x+=widths[i];});
      y+=count*3.5+2;start+=count;
      if(start<max){pdf.addPage();page();}
    }
  }
  page();tableRow(report.headers);
  for(const row of report.lines) {if(y>180){pdf.addPage();page();tableRow(report.headers);}tableRow(row);}
  y+=5;
  for(const row of [...report.totals,['TOTAL MENSAL DA OBRA',report.total]]) {
    if(y>185){pdf.addPage();page();}
    pdf.setFontSize(9);const lines=pdf.splitTextToSize(`${row[0]}: ${row[1]} h`,270);
    for(const line of lines){if(y>185){pdf.addPage();page();}pdf.text(line,10,y);y+=5;}
  }
  pdf.save(`${report.filename}.pdf`);
}
