import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareAttendanceReport,exportAttendanceExcel,exportAttendancePdf} from '../src/attendance-report.js';
const work={id:'120',numero:'120',nome:'Casa R'};
const row={obra_id:'120',colaborador_id:'p1',colaborador:'Zélia',funcao:'Pedreiro',data:'2026-09-01',horas:'8',estado:'presente',entrada_manha:'08:00:00',saida_manha:'12:00:00',entrada_tarde:'13:00:00',saida_tarde:'17:00:00',observacao:'Nota',justificacao_estado:null};
test('relatório por obra/mês, ordem alfabética, tempos e totais por ID',()=>{
 const r=prepareAttendanceReport([row,{...row,colaborador_id:'p2',colaborador:'Ana',horas:4},{...row,data:'2026-09-02',horas:3.5}],work,'2026-09');
 assert.equal(r.lines[0][0],'Ana');assert.equal(r.lines[0][4],'08:00');assert.deepEqual(r.totals,[['Ana',4],['Zélia',11.5]]);assert.equal(r.total,15.5);assert.equal(r.filename,'folha-ponto-obra-120-2026-09');
});
test('vazio, obra/mês ausentes, respostas mistas e horas inválidas nunca exportam',()=>{
 for(const [rows,w,m] of [[[],work,'2026-09'],[[row],null,'2026-09'],[[row],work,'2026-13'],[[{...row,obra_id:'118'}],work,'2026-09'],[[{...row,data:'2026-10-01'}],work,'2026-09'],[[{...row,horas:'x'}],work,'2026-09']]) assert.throws(()=>prepareAttendanceReport(rows,w,m));
});
test('Excel contém registos e totais; PDF pagina textos longos sem truncar',()=>{
 const r=prepareAttendanceReport([{...row,observacao:'nota '.repeat(3000)}],work,'2026-09');
 let filename;const sheets=[];
 exportAttendanceExcel(r,{utils:{book_new:()=>({}),aoa_to_sheet:lines=>({lines}),book_append_sheet:(b,s,n)=>sheets.push([n,s])},writeFile:(b,f)=>filename=f});
 assert.equal(filename,`${r.filename}.xlsx`);assert.equal(sheets.length,2);assert.equal(sheets[1][1].lines.at(-1)[1],8);
 let pages=1;const printed=[];
 class PDF {setFontSize(){} splitTextToSize(s){return String(s).match(/.{1,40}/g)||[''];} text(s,x,y){assert(y<=190);printed.push(s);} addPage(){pages++;} save(f){filename=f;}}
 exportAttendancePdf(r,PDF);assert(pages>1);assert.equal(filename,`${r.filename}.pdf`);assert(printed.flat().join('').includes('TOTAL MENSAL DA OBRA'));
 assert.throws(()=>exportAttendanceExcel(r,null));assert.throws(()=>exportAttendancePdf(r,null));
});
