// Prepared map contract; not connected to legacy cost ledgers or the mounted UI.
import {factualReport} from './attendance-hours-domain.js';
export function workHoursMap({records,conferences=[]}){
 const source=factualReport(records),approvals=new Map();
 for(const c of conferences){const key=c.person_id+':'+c.month;if(approvals.has(key))throw Error('Competência duplicada.');approvals.set(key,c);}
 const works=new Map();
 for(const day of source)for(const r of day.records){
  if(!Number.isInteger(r.revision)||r.revision<1)throw Error('Revisão factual inválida.');
  const key=r.work_id||'referencia:'+r.reference_id;
  if(!r.work_id&&!r.reference_id)throw Error('Destino sem identidade; não inferir Escritório.');
  if(!works.has(key))works.set(key,{work_id:r.work_id||null,reference_id:r.work_id?null:r.reference_id,provisional_minutes:0,consolidated_minutes:0,external_minutes:0,records:[],financial_effect:false,existing_costs_included:false});
  const map=works.get(key),month=r.date.slice(0,7)+'-01',c=approvals.get(r.person_id+':'+month);
  // Revision-specific approval: a monthly state alone cannot approve facts edited afterwards.
  const approved=r.kind==='primeline'&&!!r.work_id&&c?.state==='validada_para_integracao'&&typeof c.facts_fingerprint==='string'&&/^[0-9a-f]{64}$/.test(c.facts_fingerprint)&&c.facts_fingerprint===c.validated_fingerprint&&c.records?.some(x=>x.id===r.id&&x.revision===r.revision)&&!day.open;
  const minutes=r.intervals.reduce((n,x)=>n+(x.end?time(x.end)-time(x.start):0),0);
  if(r.kind==='external')map.external_minutes+=minutes;else if(approved)map.consolidated_minutes+=minutes;else map.provisional_minutes+=minutes;
  map.records.push({id:r.id,revision:r.revision,minutes,status:r.kind==='external'?'external':approved?'consolidated':'provisional'});
 }
 return [...works.values()];
}
function time(s){const [h,m]=s.split(':').map(Number);return h*60+m;}
// HR-31 is assessed at worker/day, never allocated to an arbitrary destination.
export function dayValuationContract({records,expectedMinutes,approvedRate=null,date}){
 const days=factualReport(records);if(days.length!==1||days[0].date!==date)throw Error('Valorização exige um trabalhador/dia.');
 const day=days[0];if(day.kind==='external')return {minutes:day.minutes,cost:null,status:'horas_apenas',reason:'preco_externo_pendente',blocksRhValidation:false};
 if(day.open||!Number.isInteger(expectedMinutes)||expectedMinutes<0)return {minutes:day.minutes,cost:null,status:'pendente',reason:day.open?'intervalo_aberto':'referencia_diaria_pendente',blocksRhValidation:false};
 if(day.minutes>expectedMinutes)return {minutes:day.minutes,cost:null,status:'pendente_de_valorizacao',reason:'HR-31',blocksRhValidation:false,destinations:day.records.map(r=>({id:r.id,work_id:r.work_id||null,reference_id:r.reference_id||null}))};
 // A tariff must come from an authorized, versioned RH source. This module performs no approval.
 if(!approvedRate||approvedRate.person_id!==day.person_id||approvedRate.approved!==true||!approvedRate.approved_by||!approvedRate.approved_at||!approvedRate.id||!Number.isInteger(approvedRate.revision)||approvedRate.revision<1||!Number.isFinite(approvedRate.hourly_rate)||approvedRate.hourly_rate<0||!/^\d{4}-\d{2}-\d{2}$/.test(approvedRate.effective_from||'')||approvedRate.effective_from>date||approvedRate.effective_to&&date>=approvedRate.effective_to)return {minutes:day.minutes,cost:null,status:'pendente',reason:'custo_hora_rh_pendente',blocksRhValidation:false};
 return {minutes:day.minutes,cost:null,status:'tarifa_comprovada',rate_identity:{id:approvedRate.id,revision:approvedRate.revision},blocksRhValidation:false,existing_costs_included:false};
}
