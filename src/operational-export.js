// Encoding and source metadata only; no business calculations or additional reads.
export function csvCell(value){if(value==null)return '"Não devolvido"';if(typeof value==='number'){if(!Number.isFinite(value))throw Error('Número não finito na origem.');return '"'+value+'"';}let s=String(value);if(/^[\t\r\n]|^\s*[=+@-]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
export function operationalCsv({kind,companyId,workId=null,from=null,to=null,revision=null,state='consulta',sourceHash=null,capturedAt=new Date().toISOString(),rows,columns}){
 if(!kind||!Array.isArray(rows)||!Array.isArray(columns)||!columns.length||columns.some(c=>!c.key||!c.label||/salari|tarifa|remuneracao|custo_hora/i.test(c.key)))throw Error('Contrato de exportação operacional inválido.');
 const meta=[['RELATÓRIO',kind],['EMPRESA',companyId??'Não devolvida pela origem'],['OBRA',workId??'Sem obra / âmbito explícito da consulta'],['INÍCIO',from],['FIM',to],['ESTADO DA ORIGEM',state],['REVISÃO DA ORIGEM',revision],['FINGERPRINT DA ORIGEM',sourceHash],['CAPTURADO EM UTC',capturedAt],['REFERÊNCIA TEMPORAL','Retrato da consulta indicada. Não comprova o estado atual após alterações posteriores.']];
 const text='\ufeff'+[...meta,[],columns.map(c=>c.label),...rows.map(r=>columns.map(c=>r[c.key]??null))].map(row=>row.map(csvCell).join(';')).join('\r\n');
 return {text,filename:String(kind).replace(/[^a-z0-9_-]/gi,'-')+'-'+capturedAt.slice(0,10)+'.csv',capturedAt};
}
export function downloadOperationalCsv(report){const url=URL.createObjectURL(new Blob([report.text],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');a.href=url;a.download=report.filename;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
