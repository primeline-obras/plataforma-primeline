// Local preparation only: not imported by app.js until the operational interface is approved.
// Authority, reference freezing, permissions and money remain server-side.
import {assertDate,intervalFacts,activeOn,localClock} from './attendance-domain.js?v=9';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function durationLabel(minutes){if(!Number.isInteger(minutes)||minutes<0)throw Error('Duração inválida.');if(!minutes)return '0h';if(minutes<60)return minutes+'min';return Math.floor(minutes/60)+'h'+(minutes%60?String(minutes%60).padStart(2,'0'):'');}
export function referenceSuggestions({date,reference=null,external=false,mode='dia_inteiro',specialDay=false}){
 assertDate(date);if(!['dia_inteiro','manha','tarde','personalizado'].includes(mode))throw Error('Modo inválido.');
 if(mode==='personalizado')return [{start:null,end:null,period:null,mode:'personalizado'},{start:null,end:null,period:null,mode:'personalizado'}];
 if(specialDay)return null;
 let day;
 if(external&&[0,6].includes(new Date(date+'T12:00:00Z').getUTCDay()))return null;
 if(external)day={day_type:'prevista',expected_minutes:480,intervals:[{start:'08:00',end:'12:00',period:'manha'},{start:'13:00',end:'17:00',period:'tarde'}]};
 else if(reference?.confirmed===true&&reference.version_id&&reference.effective_from<=date&&(!reference.effective_to||date<reference.effective_to))day=reference.day||reference.week?.[new Date(date+'T12:00:00Z').getUTCDay()||7];
 if(!day||day.day_type!=='prevista')return null;
 const xs=day.intervals.filter(x=>mode==='dia_inteiro'||x.period===mode).map(x=>({start:x.start,end:x.end,period:x.period,mode:'normal'}));
 if(!xs.length)return null;intervalFacts(xs);return xs;
}
export function destinationIdentity(destination,{activeWorks=[]}={}){
 if(!destination||!['obra','garantia','outra','escritorio'].includes(destination.type))throw Error('Destino inválido.');
 if(destination.type==='obra'||destination.type==='outra'&&destination.work_id){if(!UUID.test(destination.work_id||'')||!activeWorks.some(w=>w.id===destination.work_id))throw Error('Selecione uma obra ativa autorizada.');return 'obra:'+destination.work_id;}
 if(destination.type==='escritorio'){if(destination.work_id||destination.reference_id||destination.reference)throw Error('Escritório não representa uma referência livre.');return 'escritorio';}
 if(!UUID.test(destination.reference_id||'')||typeof destination.reference!=='string'||!destination.reference.trim()||destination.reference.length>1000||destination.work_id)throw Error('Indique uma identidade e a referência original do destino.');
 return destination.type+':'+destination.reference_id;
}
export function prepareIntervals({personId,date,intervals,activeWorks=[],now,expectedDailyRevision=0,external=false}){
 if(!UUID.test(personId||''))throw Error('Colaborador inválido.');assertDate(date);
 if(!Array.isArray(intervals)||intervals.length<1||intervals.length>16)throw Error('Limite de 16 intervalos.');
 if(!Number.isInteger(expectedDailyRevision)||expectedDailyRevision<0)throw Error('Revisão diária inválida.');
 const groups=new Map();const facts=[];
 for(const x of intervals){if(!['normal','personalizado'].includes(x.mode))throw Error('Modo do período inválido.');
 if(x.mode==='personalizado'&&x.period!==null||x.mode==='normal'&&!['manha','tarde'].includes(x.period))throw Error('Classificação factual inválida.');
 const identity=destinationIdentity(x.destination,{activeWorks});const i={start:x.start,end:x.end??null,mode:x.mode,period:x.period};facts.push(i);
 if(!groups.has(identity))groups.set(identity,{identity,destination:structuredClone(x.destination),intervals:[]});
 if(JSON.stringify(groups.get(identity).destination)!==JSON.stringify(x.destination))throw Error('A referência original do mesmo destino diverge.');groups.get(identity).intervals.push(i);
 }
 if(groups.size>4)throw Error('Limite de 4 destinos.');
 const total=intervalFacts(facts,{date,now});
 // Do not repurpose the internal periods_save endpoint for external workers or free references.
 return {person_id:personId,date,kind:external?'external':'primeline',expected_daily_revision:expectedDailyRevision,destinations:[...groups.values()],minutes:total.minutes,open:total.open,requires_destination_contract:[...groups.values()].some(x=>['garantia','outra'].includes(x.destination.type)&&!x.destination.work_id)};
}
export function factualReport(records){
 const keys=new Set(),days=new Map();
 for(const r of records){if(!r.id||keys.has(r.id))throw Error('Registo factual duplicado ou sem identidade.');keys.add(r.id);assertDate(r.date);
 const f=intervalFacts(r.intervals);const key=r.kind+':'+r.person_id+':'+r.date;
 if(!days.has(key))days.set(key,{kind:r.kind,person_id:r.person_id,date:r.date,records:[],minutes:0,open:false});
 const day=days.get(key);day.records.push(r);day.minutes+=f.minutes;day.open ||= f.open;
 }
 for(const day of days.values())intervalFacts(day.records.flatMap(r=>r.intervals));
 return [...days.values()].sort((a,b)=>a.date.localeCompare(b.date)||a.person_id.localeCompare(b.person_id));
}
export function integrationPending({evaluations=[],absences=[],unassociatedReferences=[],missingDays=[],legacyDays=[],conferenceConfirmed=false}){
 const pending=[];if(!conferenceConfirmed)pending.push('conferencia_mensal_pendente');
 for(const e of evaluations){if(e.active===false)continue;
 const reasons=(e.pending||[]).filter(p=>!(p==='he_validada_aguarda_processamento'&&e.he_state==='validada'));
 if(e.reference_state!=='capturada')reasons.push('referencia_diaria_pendente');if(e.he_state==='pendente')reasons.push('he_por_classificar');
 if(e.missing_minutes>0)reasons.push('horas_em_falta');if(e.open)reasons.push('intervalo_aberto');
 pending.push(...reasons.map(reason=>({date:e.date,reason})));
 }
 pending.push(...absences.filter(x=>x.state==='ausente_pendente').map(x=>({date:x.date,reason:'ausencia_por_classificar'})),...unassociatedReferences.map(x=>({id:x.id,reason:'referencia_por_associar'})),...missingDays.map(date=>({date,reason:'ponto_por_regularizar'})),...legacyDays.map(date=>({date,reason:'legado_por_reconciliar'})));
 return pending;
}
export function nextConferenceState({validatedFingerprint=null,currentFingerprint,closed=false}){if(typeof currentFingerprint!=='string'||!/^[0-9a-f]{64}$/.test(currentFingerprint))throw Error('Fingerprint mensal inválido.');if(closed&&validatedFingerprint!==currentFingerprint)throw Error('Reabra a competência antes de corrigir os factos.');return validatedFingerprint===currentFingerprint?'validada_para_integracao':validatedFingerprint?'requer_revalidacao':'por_conferir';}
export function canReportFaltou({role,workAuthorized,member,person,date,today,hasHours=false,external=false}){assertDate(date);assertDate(today);const yesterday=new Date(Date.parse(today+'T12:00:00Z')-86400000).toISOString().slice(0,10);return role==='encarregado'&&workAuthorized===true&&member===true&&!external&&activeOn(person,date)&&[today,yesterday].includes(date)&&!hasHours;}
export function financialAvailability({external=false,approvedRate=null,date,hasExcess=false}){
 assertDate(date);
 // Only a contract availability result. No hourly rate is inferred from pay, role or visited work.
 if(!approvedRate||approvedRate.approved!==true||!UUID.test(approvedRate.approved_by||'')||!approvedRate.approved_at||!UUID.test(approvedRate.id||'')||!Number.isInteger(approvedRate.revision)||approvedRate.revision<1||!Number.isFinite(approvedRate.hourly_rate)||approvedRate.hourly_rate<0||!/^\d{4}-\d{2}-\d{2}$/.test(approvedRate.effective_from||'')||approvedRate.effective_from>date||approvedRate.effective_to&&date>=approvedRate.effective_to)return {hoursOnly:true,reason:external?'preco_externo_pendente':'custo_hora_rh_pendente'};
 if(hasExcess)return {hoursOnly:true,reason:'pendente_de_valorizacao_hr31',valuationPending:true,cost:null,blocksRhValidation:false};
 return {hoursOnly:false,rateIdentity:{id:approvedRate.id,revision:approvedRate.revision},financialEffect:false};
}export function planSitesFromIntervals({day,intervals,works,now={date:day.server_date||localClock().date},requestId=()=>crypto.randomUUID()}){
 const actual=intervals.filter(x=>x.start||x.end);if(!actual.length)throw Error('Indique pelo menos um intervalo.');
 const allowed=works.filter(w=>w.status==='em_curso'||day.records.some(r=>r.obra_id===w.id));
 const plan=prepareIntervals({personId:day.person_id,date:day.date,intervals:actual,activeWorks:allowed,now,expectedDailyRevision:day.expected_daily_revision,external:day.kind==='external'});
 return plan.destinations.map(group=>{const d=group.destination;
  if(d.type==='obra'||d.type==='outra'&&d.work_id){const r=day.records.find(x=>x.obra_id===d.work_id);return {type:'obra',work_id:d.work_id,expected_revision:r?.revision||0,intervals:group.intervals};}
  if(!['garantia','outra'].includes(d.type))throw Error('Este formulário conserva o registo de Escritório no fluxo existente.');
  const id=d.reference_id||requestId(),r=day.references.find(x=>x.id===id);
  return {type:'reference',id,reference_type:r?.tipo||d.type,origin_work_id:r?.origem_obra_id||day.work_id,original_reference:r?.referencia_original||d.reference,original_work_id:r?.obra_original_id||d.original_work_id||null,expected_revision:r?.revision||0,intervals:group.intervals};
 });
}
