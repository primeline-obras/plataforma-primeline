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
 if(reference?.origin==='individual'&&reference.confirmed===true&&UUID.test(reference.version_id||'')&&reference.effective_from<=date&&(!reference.effective_to||date<reference.effective_to))day=reference.day||reference.week?.[new Date(date+'T12:00:00Z').getUTCDay()||7];
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
 const identity=destinationIdentity(x.destination,{activeWorks});const i={start:x.start,end:x.end??null,mode:x.mode,period:x.period,...(x.registration_origin?{registration_origin:x.registration_origin}:{})};facts.push(i);
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
  if(d.type==='escritorio'){if(day.kind==='external'||day.office_available!==true)throw Error('Escritório não autorizado neste contexto.');const r=day.records.find(x=>x.obra_id===null&&x.tipo_local==='escritorio');return {type:'escritorio',expected_revision:r?.revision||0,intervals:group.intervals};}
  if(!['garantia','outra'].includes(d.type))throw Error('Destino não suportado.');
  const id=d.reference_id||requestId(),r=day.references.find(x=>x.id===id);
  return {type:'reference',id,reference_type:r?.tipo||d.type,origin_work_id:r?.origem_obra_id||day.work_id,original_reference:r?.referencia_original||d.reference,original_work_id:r?.obra_original_id||d.original_work_id||null,expected_revision:r?.revision||0,intervals:group.intervals};
 });
}
// FP-28/FP-29: presentation over factual intervals; never rounds or alters the daily reference.
export function quickEntryModel(intervals){
 if(!Array.isArray(intervals)||!intervals.length||intervals.length>2||intervals.some(i=>!i.start||!i.end))return null;
 const xs=[...intervals].sort((a,b)=>a.start.localeCompare(b.start));intervalFacts(xs);
 if(xs.length===2&&xs[0].end>=xs[1].start)return null;
 return {start:xs[0].start,end:xs.at(-1).end,breakStart:xs.length===2?xs[0].end:null,breakEnd:xs.length===2?xs[1].start:null};
}
export function quickEntryIntervals({start,end,breakStart=null,breakEnd=null,source='quick_entry',periodHint=null}){
 const clock=x=>{if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(x||''))throw Error('Indique entrada e saída válidas.');return Number(x.slice(0,2))*60+Number(x.slice(3));};
 const from=clock(start),to=clock(end);if(to<=from)throw Error('A saída deve ser posterior à entrada.');
 let xs;if(breakStart||breakEnd){const a=clock(breakStart),b=clock(breakEnd);if(b<=a)throw Error('O fim do almoço deve ser posterior ao início.');if(from<=a&&to>=b)xs=[{start,end:breakStart,period:'manha',mode:'normal'},{start:breakEnd,end,period:'tarde',mode:'normal'}];else if(to<=a||from>=b)xs=[{start,end,period:to<=a?'manha':'tarde',mode:'normal'}];else throw Error('A pausa não está inteiramente abrangida. Ajuste ou remova o almoço conforme os factos.');}
 else xs=[{start,end,period:periodHint,mode:periodHint?'normal':'personalizado'}];
 xs=xs.filter(x=>x.start<x.end);if(!xs.length)throw Error('O intervalo contém apenas a pausa. Introduza tempo de trabalho factual.');return xs.map(x=>({...x,registration_origin:source}));
}
export function operationalDeviation(day){
 const xs=[...(day.records||[]).flatMap(r=>r.intervals||[]),...(day.references||[]).flatMap(r=>r.intervals||[])];let facts;
 try{facts=intervalFacts(xs);}catch{return {conflict:true,minutes:null,expected:null,difference:null,tolerance:0,withinTolerance:false,alert:false};}
 const base={...facts,expected:null,difference:null,tolerance:0,withinTolerance:false,alert:false};
 const eligible=day.kind==='primeline'&&day.operational_internal===true&&!day.hidden_record_count&&!day.has_absence&&facts.started&&!facts.open;
 const ref=day.reference;let validDate=false;try{assertDate(day.date);assertDate(ref?.effective_from);if(ref?.effective_to)assertDate(ref.effective_to);validDate=ref.effective_from<=day.date&&(!ref.effective_to||day.date<ref.effective_to);}catch{}
 const proven=validDate&&ref?.confirmed===true&&ref.day?.day_type==='prevista'&&Number.isInteger(ref.day.expected_minutes)&&ref.day.expected_minutes>0;
 const r=day.operational_deviation;
 if(r!==undefined){
  const valid=r?.version===1&&r.rule==='FP-29'&&r.person_id===day.person_id&&r.kind===day.kind&&r.work_id===day.work_id&&r.date===day.date&&r.daily_revision===day.expected_daily_revision&&r.rh_effect===false&&r.financial_effect===false&&r.minutes===facts.minutes&&r.open===facts.open&&r.conflict===false&&typeof r.applicable==='boolean'&&typeof r.alert==='boolean'&&typeof r.withinTolerance==='boolean'&&
   (r.applicable?eligible&&proven&&UUID.test(r.source_jornada_id||'')&&r.expected===ref.day.expected_minutes&&r.difference===facts.minutes-r.expected&&r.tolerance===10&&r.withinTolerance===(Math.abs(r.difference)<=10)&&r.alert===(Math.abs(r.difference)>10):r.tolerance===0&&!r.withinTolerance&&!r.alert);
  return valid?{...r,server:true,unavailable:r.reason==='jornada_individual_por_confirmar'}:{...base,unavailable:true,invalid:true};
 }
 // Compatibility for explicitly evidenced individual references only. A numeric
 // legacy/work schedule is not proof of an individual journey for this date.
 const applicable=eligible&&proven&&ref.origin==='individual'&&UUID.test(ref.version_id||'');
 const expected=applicable?ref.day.expected_minutes:null,difference=applicable?facts.minutes-expected:null;
 return {...base,expected,difference,tolerance:applicable?10:0,withinTolerance:applicable&&Math.abs(difference)<=10,alert:applicable&&Math.abs(difference)>10,unavailable:eligible&&!applicable};
}

export function normalTeamPreview(context){
 const included=[],excluded=[];for(const p of context?.people||[]){let reason=null;
 if(p.annulled_records?.length)reason='Registo anulado; sem reintrodução automática';else if(p.has_absence)reason='Falta ou ausência registada';else if(p.temporary_help)reason='Apoio temporário: registe individualmente no destino';else if(p.hidden_record_count)reason='Existem registos noutro âmbito';else if(p.records?.length||p.references?.length)reason='Já existem horas, registo personalizado ou referência';else if(!p.can_write)reason=p.kind==='external'&&p.operational_reference?.reason||'Sem autorização ou fora da janela';
 if(!reason&&p.rh_workflow){if(p.rh_workflow.requests.some(x=>x.state==='pending'))reason='Pedido pendente de RH; use a conferência individual';else if(p.rh_workflow.monthly_state==='closed')reason='Mês fechado; exige regularização formal';else if(p.rh_workflow.daily_state==='conferred')reason='Dia conferido; exige correção controlada';else if(p.date!==p.server_date)reason='Dia passado ou futuro; use o percurso individual';}
 const external=p.kind==='external',operational=external?externalNormalReference(p):null;const intervals=reason?null:external?(context.base?.special_day===false?operational?.intervals:null):referenceSuggestions({date:p.date,reference:individualReference(p),mode:'dia_inteiro',specialDay:context.base?.special_day!==false});if(!reason&&!intervals)reason=external?(p.operational_reference?.reason||'Referência operacional externa indisponível ou dia especial'):'Jornada válida indisponível ou dia especial';
 if(reason)excluded.push({person_id:p.person_id,kind:p.kind,name:p.name,reason});else included.push({person_id:p.person_id,kind:p.kind,name:p.name,expected_daily_revision:p.expected_daily_revision,...(external?{operational_reference_token:operational.token,reference_origin:operational.origin}:{}),intervals:intervals.map(x=>({...x,registration_origin:'normal_team'}))});}
 return {included,excluded};
}

// FP-29 already proves the source journey against the individual/date in PostgreSQL.
// A work's legacy reference must never become an individual schedule suggestion.
export function individualReference(day){const r=day?.operational_deviation,ref=day?.reference;if(r!==undefined){return r?.version===1&&r.rule==='FP-29'&&r.person_id===day.person_id&&r.kind===day.kind&&r.work_id===day.work_id&&r.date===day.date&&r.daily_revision===day.expected_daily_revision&&UUID.test(r.source_jornada_id||'')&&r.expected===ref?.day?.expected_minutes?{...ref,origin:'individual',version_id:r.source_jornada_id}:null;}return ref?.origin==='individual'?ref:null;}

export function externalNormalReference(day){const r=day?.operational_reference;return day?.kind==='external'&&r?.version===1&&r.policy==='FP32_EXTERNAL_OPERATIONAL_20261023'&&r.origin==='approved_external_operational'&&r.kind==='external'&&r.person_id===day.person_id&&r.work_id===day.work_id&&r.date===day.date&&r.eligible===true&&r.verified_by_clock===false&&r.rh_effect===false&&r.financial_effect===false&&r.expected_minutes===480&&/^[0-9a-f]{64}$/.test(r.token||'')&&Array.isArray(r.assignment_sources)&&r.assignment_sources.length>0&&Array.isArray(r.intervals)&&r.intervals.length===2&&[['08:00','12:00','manha'],['13:00','17:00','tarde']].every(([start,end,period],n)=>r.intervals[n]?.start===start&&r.intervals[n]?.end===end&&r.intervals[n]?.period===period&&r.intervals[n]?.mode==='normal')?r:null;}

// Suggestions use the already authorised source for this person/date; never a visited work by inference.
export function operationalSuggestions(day,mode='dia_inteiro'){
 if(day.kind!=='external')return referenceSuggestions({date:day.date,reference:individualReference(day),mode});
 if(mode==='personalizado')return referenceSuggestions({date:day.date,mode});
 if(!['dia_inteiro','manha','tarde'].includes(mode))throw Error('Modo inválido.');
 const reference=externalNormalReference(day);if(!reference)return null;
 return reference.intervals.filter(x=>mode==='dia_inteiro'||x.period===mode).map(x=>({...x}));
}
