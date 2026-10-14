import {durationLabel,factualReport}from './attendance-hours-domain.js';
export function buildExternalWorkbook(c,{XLSX=globalThis.XLSX}={}){
 if(!XLSX?.utils?.aoa_to_sheet||!XLSX?.write)throw Error('O gerador Excel não está disponível. Recarregue; não existe alternativa CSV.');
 const r=c?.report;if(c?.version!==3||c.server_authorized!==true||c.export_format!=='xlsx'||c.confirmed_by_role!=='diretor_obra'||!c.confirmation_id||!c.confirmed_by||!c.confirmed_at||!Number.isInteger(c.revision)||c.revision<1||!/^[0-9a-f]{64}$/.test(c.facts_fingerprint||'')||c.facts_fingerprint!==r?.facts_fingerprint||!Array.isArray(r.records)||!r.work_id||!r.month||!r.provider_id)throw Error('Excel exige confirmação atual do Diretor.');
 if(r.records.some(x=>x.kind!=='external'||x.work_id!==r.work_id||x.provider_id!==r.provider_id||x.date.slice(0,7)!==r.month.slice(0,7)||x.open))throw Error('Relatório externo fora do contrato.');
 factualReport(r.records);const rows=[['Data','Obra ID','Fornecedor ID','Fornecedor','Trabalhador ID','Nome','Entrada','Saída','Duração','Registo ID','Revisão']];let total=0;
 for(const f of r.records){let minutes=0;for(const x of f.intervals){if(!x.end)throw Error('Intervalo aberto não pode ser exportado.');const value=time(x.end)-time(x.start);minutes+=value;rows.push([f.date,f.work_id,f.provider_id,f.provider_name,f.person_id,f.name,x.start,x.end,durationLabel(value),f.id,f.revision]);}if(minutes!==f.minutes)throw Error('Total factual divergente.');total+=minutes;}
 rows.push(['TOTAL','','','','','','','',durationLabel(total),'','']);
 const book=XLSX.utils.book_new();XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet(rows),'Horas');XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet([['Contrato','Externo mensal v3'],['Formato','XLSX'],['Obra ID',r.work_id],['Competência',r.month],['Confirmação ID',c.confirmation_id],['Revisão',c.revision],['Fingerprint',c.facts_fingerprint],['Confirmado por',c.confirmed_by],['Confirmado em',c.confirmed_at],['Total',durationLabel(total)],['Efeito financeiro','Nenhum']]),'Confirmação');
 return {book,filename:'relatorio-externos-'+r.work_id+'-'+r.provider_id+'-'+r.month+'-r'+c.revision+'.xlsx',minutes:total};
}
function time(s){const [h,m]=s.split(':').map(Number);return h*60+m;}
export function externalExcelBytes(c,options={}){const r=buildExternalWorkbook(c,options),XLSX=options.XLSX||globalThis.XLSX;return {...r,bytes:XLSX.write(r.book,{bookType:'xlsx',type:'array'})};}
