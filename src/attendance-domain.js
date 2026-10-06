// Administrative rules are explicit; monetary rates and unverified calendars are not inferred.
export const SHEET_STATES = Object.freeze({ none: 'Não registado', open: 'Em aberto', registered: 'Registado', legacy: 'REGISTO LEGADO', missing: 'HORAS EM FALTA — REQUER REGULARIZAÇÃO', vacation: 'Férias', absence: 'Ausência', absence_pending: 'Ausência · JUSTIFICAÇÃO PENDENTE', regularization: 'Regularização' });
export function assertDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || '') || new Date(`${value}T12:00:00Z`).toISOString().slice(0,10) !== value) throw new Error('Data inválida.');
  return value;
}
export function localClock(now = new Date()) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Lisbon', year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hourCycle:'h23' }).formatToParts(now).map(x => [x.type,x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}
export function minutes(value) {
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(value || '')) throw new Error('Hora inválida.');
  return Number(value.slice(0,2))*60+Number(value.slice(3,5));
}
export function intervalFacts(intervals = [], { date, now } = {}) {
  const ranges = [];
  let open = false;
  for (const x of intervals) {
    if (!x.start && !x.end) continue;
    if (!x.start) throw new Error('Registe a entrada antes da saída.');
    const start = minutes(x.start), end = x.end ? minutes(x.end) : null;
    if (end != null && end <= start) throw new Error('A saída deve ser posterior à entrada.');
    if (date && now && (date > now.date || date === now.date && Math.max(start,end ?? start) > minutes(now.time))) throw new Error('Não pode registar uma hora futura como realizada.');
    ranges.push({start,end});
    if (end == null) open = true;
  }
  ranges.sort((a,b)=>a.start-b.start);
  if (ranges.some((x,i)=>i && (ranges[i-1].end == null || x.start < ranges[i-1].end))) throw new Error('Os intervalos de trabalho sobrepõem-se.');
  return { minutes: ranges.reduce((sum,x)=>sum+(x.end == null ? 0 : x.end-x.start),0), open, started:ranges.length>0 };
}
export function analyseSheet({ sheet = null, absence = null, legacy = false, expectedMinutes = null, workType = 'obra', specialDay = false }) {
  const facts = intervalFacts(sheet?.intervals || []);
  // Persisted backend state is authoritative; interval analysis is for unsaved previews.
  if (sheet && ['open','registered','missing','regularization'].includes(sheet.estado ?? sheet.state)) {
    const state=sheet.estado ?? sheet.state;
    const overtime=state==='registered' && specialDay ? 'pending_rule' : state==='registered' && workType==='obra' && expectedMinutes!=null && facts.minutes>expectedMinutes ? 'potential' : 'none';
    return {state,expectedMinutes,...facts,overtime};
  }
  if (legacy && sheet) return {state:'regularization',expectedMinutes,...facts,overtime:'none'};
  if (absence && facts.started) return {state:'regularization',expectedMinutes:absence.tipo==='ferias'?0:expectedMinutes,...facts,overtime:'pending_validation'};
  if (absence) return {state:absence.estado==='ausente_pendente'?'absence_pending':absence.tipo==='ferias'?'vacation':'absence',expectedMinutes:absence.tipo==='ferias'?0:expectedMinutes,...facts,overtime:'none'};
  if (legacy) return {state:'legacy',expectedMinutes,...facts,overtime:'none'};
  const state = !sheet || !facts.started ? 'none' : facts.open ? 'open' : expectedMinutes == null ? 'regularization' : facts.minutes < expectedMinutes ? 'missing' : 'registered';
  const overtime = specialDay && facts.started ? 'pending_rule' : workType==='obra' && expectedMinutes != null && !facts.open && facts.minutes>expectedMinutes ? 'potential' : 'none';
  return {state,expectedMinutes,...facts,overtime};
}
export function exactAllocations(rows, personId, date) {
  assertDate(date);
  return rows.filter(x=>x.colaborador_id===personId && x.data===date); // Never inherit a previous allocation.
}
export function activeOn(person,date) {
  assertDate(date);
  return !!person.data_admissao && person.data_admissao<=date && (!person.data_saida || person.data_saida>date);
}
export function normalIntervals(schedule, period = 'dia_inteiro') {
  if (!schedule || !Array.isArray(schedule.intervals)) throw new Error('Defina primeiro o horário normal da obra.');
  if (!['manha','tarde','dia_inteiro'].includes(period)) throw new Error('Período inválido.');
  const selected = schedule.intervals.filter(x=>period==='dia_inteiro'||x.period===period).map(x=>({start:x.start,end:x.end}));
  if (!selected.length) throw new Error('O horário não contém este período.');
  intervalFacts(selected);
  return selected;
}
export function correctionAllowed({ role, date, today, days = 1 }) {
  assertDate(date);assertDate(today);
  if (date>today) return false;
  if (['administrativo','gestao_plataforma','gerencia'].includes(role)) return true;
  if (role !== 'encarregado') return false;
  if (date===today) return true;
  if (!Number.isInteger(days) || days<0) return false;
  return (Date.parse(`${today}T12:00:00Z`)-Date.parse(`${date}T12:00:00Z`))/86400000<=Math.min(days,1);
}
export function vacationSelection({ selected=[], from, to, remove=[], holidays=[], calendarVerified=false }) {
  const dates=new Set(selected.map(assertDate));
  if (from || to) {
    assertDate(from);assertDate(to);if(to<from)throw new Error('Intervalo inválido.');
    if((Date.parse(to)-Date.parse(from))/86400000>366)throw new Error('Intervalo superior a um ano.');
    for(let d=from;d<=to;d=new Date(Date.parse(`${d}T12:00:00Z`)+86400000).toISOString().slice(0,10)) dates.add(d);
  }
  remove.forEach(d=>dates.delete(assertDate(d)));
  const allDates=[...dates].sort();
  const excluded=allDates.filter(d=>[0,6].includes(new Date(`${d}T12:00:00Z`).getUTCDay())||holidays.includes(d));
  const result=allDates.filter(d=>!excluded.includes(d));
  const calendarPending=!calendarVerified;
  return {dates:result,excluded,pendingRule:false,calendarPending,consumedDays:calendarPending?null:result.length};
}
export function overtimeTransition(state,action,role) {
  const director=['diretor_obra','adjunto'].includes(role), admin=role==='administrativo';
  if(state==='potential' && director && ['approve','reject'].includes(action))return action==='approve'?'pending_validation':'rejected';
  if(state==='pending_validation' && admin && action==='validate')return 'validated_pending_rule';
  throw new Error('Transição de horas extraordinárias não autorizada.');
}
export function payrollFacts(sheets = [], absences = []) {
  return { workedMinutes:sheets.reduce((n,x)=>n+intervalFacts(x.intervals).minutes,0), openDays:sheets.filter(x=>intervalFacts(x.intervals).open).map(x=>x.date), absenceDays:absences.map(x=>({date:x.data,type:x.tipo,sourceId:x.id})), financialEffect:false };
}
export function payrollTransition(state,action,{canAdmin=false,unresolved=0,officialTemplate=false}={}) {
  if(!canAdmin)throw new Error('Operação reservada ao Administrativo.');
  if(state==='draft' && action==='validate' && !unresolved)return 'validated';
  if(['validated','closed'].includes(state) && action==='reopen')return 'draft';
  if(state==='validated' && action==='close' && !unresolved)return 'closed';
  if(state==='closed' && action==='export' && officialTemplate)return 'exported';
  throw new Error('Resolva as pendências e confirme o modelo antes de fechar/exportar.');
}
export function activePlanningTasks(items) {return items.filter(x=>x.estado!=='concluido' && !x.arquivado_em);}
export function daySummary(rows, options={}) {
  const states=rows.map(row=>row.conflict&&!row.sheet?.state&&!row.sheet?.estado?'regularization':analyseSheet({sheet:row.sheet,absence:row.absence,legacy:row.legacy,expectedMinutes:row.expected_minutes,...options}).state);
  const pending=states.filter((s,i)=>!['registered','vacation','absence','legacy'].includes(s)||rows[i].special_review_pending===true).length;
  return {people:states.length,registered:states.filter(s=>s==='registered').length,open:states.filter(s=>s==='open').length,pending,complete:pending===0};
}
export function normalDaySelection(rows,{schedule,date,now,admin=false,correctionDays=1,specialDay=false}={}) {
 const eligible=[],excluded=[];
 let scheduleError=null;try{intervalFacts(normalIntervals(schedule),{date,now});}catch(e){scheduleError=e.message;}
 for(const row of rows){let reason=null,intervals;
   if([0,6].includes(new Date(`${date}T12:00:00Z`).getUTCDay())||row.special_day||schedule?.holiday_dates?.includes(date)||specialDay)reason='Dia especial — registe horários reais';else if(row.absence)reason='Férias/ausência';else if(row.conflict)reason='Conflito';else if(row.legacy)reason='Registo legado';else if(row.sheet)reason='Folha já registada';else if(scheduleError)reason=scheduleError;
  else if(!row.can_write)reason='Sem autorização ou fora da janela';
  else if(!admin&&!correctionAllowed({role:'encarregado',date,today:now.date,days:correctionDays}))reason='Fora da janela de correção';
  else {try{intervals=normalIntervals(schedule,row.period||'dia_inteiro');intervalFacts(intervals,{date,now});}catch(e){reason=e.message;}}
  if(reason)excluded.push({person_id:row.person_id,reason});else eligible.push({row,intervals});
 }
 return {eligible,excluded};
}
