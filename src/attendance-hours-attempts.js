// Own-key operational checkpoint only. Never stores bodies, tokens, cookies, names or hours.
const prefix='primeline.hours.attempt.v1:',active=new Set(['IN_FLIGHT','PREVIEW_CONFIRMED','UNCERTAIN']);
export const hoursUncertainError=()=>Object.assign(Error('Resultado incerto. Não repita a operação. Consulte os dados atuais, o histórico e o recibo para reconciliação.'),{code:'HOURS_RESULT_UNCERTAIN'});
export function createHoursAttemptJournal({storage=null,identity=()=>({company_id:'local',actor_id:'local'}),now=()=>new Date().toISOString()}={}){
 const memory=new Map(),fallback={getItem:k=>memory.get(k)??null,setItem:(k,v)=>memory.set(k,v)};let unavailable=false;
 const store=()=>{const s=typeof storage==='function'?storage():storage;return s||fallback;};
 function key(){const i=identity();if(!i?.company_id||!i?.actor_id||![i.company_id,i.actor_id].every(v=>typeof v==='string'&&/^[A-Za-z0-9_.-]{1,128}$/.test(v)))throw Object.assign(Error('Confirme a sessão e o utilizador interno antes de gravar.'),{code:'HOURS_IDENTITY_REQUIRED'});return prefix+i.company_id+':'+i.actor_id;}
 function read(k){try{const raw=store().getItem(k);if(raw===null)return null;if(raw.length>64000)throw Error();const r=JSON.parse(raw);if(r?.format!=='P0_HOURS_ATTEMPT_V1'||typeof r.observed_at!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(r.observed_at)||!Number.isFinite(Date.parse(r.observed_at))||!['IN_FLIGHT','PREVIEW_CONFIRMED','UNCERTAIN','CONFIRMED','REJECTED','CANCELLED_NO_CONFIRMATION'].includes(r.state)||!['preview','confirm'].includes(r.phase)||!/^fn_[a-z0-9_]+$/.test(r.rpc)||!Array.isArray(r.request_ids)||!r.request_ids.length||!r.request_ids.every(x=>typeof x==='string'&&/^[A-Za-z0-9_.:-]{1,160}$/.test(x)))throw Error();return{format:r.format,state:r.state,phase:r.phase,rpc:r.rpc,request_ids:r.request_ids,observed_at:r.observed_at};}catch{unavailable=true;throw hoursUncertainError();}}
 function write(k,r){try{store().setItem(k,JSON.stringify(r));}catch{unavailable=true;throw Object.assign(Error('Não foi possível preservar o checkpoint. Nenhuma nova gravação deve ser enviada.'),{code:'HOURS_CHECKPOINT_UNAVAILABLE'});}}
 const same=(a,b)=>a?.rpc===b.rpc&&JSON.stringify(a.request_ids)===JSON.stringify(b.request_ids);
 function update(t,state){if(!t)return;const r=read(t.key);if(!same(r,t)){if(state==='CANCELLED_NO_CONFIRMATION')return;throw hoursUncertainError();}if(['CONFIRMED','REJECTED','CANCELLED_NO_CONFIRMATION','UNCERTAIN'].includes(r.state))return;if(state==='CANCELLED_NO_CONFIRMATION'&&r.state!=='PREVIEW_CONFIRMED')return;write(t.key,{...r,state,observed_at:now()});}
 return{
  begin({rpc,request_ids,phase}){if(unavailable)throw hoursUncertainError();const k=key(),old=read(k),ticket={key:k,rpc,request_ids};if(!Array.isArray(request_ids)||!request_ids.length||!request_ids.every(x=>typeof x==='string'&&/^[A-Za-z0-9_.:-]{1,160}$/.test(x)))throw Error('Identificador de operação inválido.');if(active.has(old?.state)&&!(phase==='confirm'&&old.state==='PREVIEW_CONFIRMED'&&same(old,ticket)))throw hoursUncertainError();if(phase==='confirm'&&(!same(old,ticket)||old.state!=='PREVIEW_CONFIRMED'))throw hoursUncertainError();write(k,{format:'P0_HOURS_ATTEMPT_V1',state:'IN_FLIGHT',phase,rpc,request_ids,observed_at:now()});return ticket;},
  preview:t=>update(t,'PREVIEW_CONFIRMED'),complete:t=>update(t,'CONFIRMED'),reject:t=>update(t,'REJECTED'),uncertain:t=>update(t,'UNCERTAIN'),cancel:t=>update(t,'CANCELLED_NO_CONFIRMATION'),
  receipt(){try{return read(key());}catch{return{format:'P0_HOURS_ATTEMPT_V1',state:'UNCERTAIN',reason:'CHECKPOINT_UNREADABLE'};}},
  isBlocked(){try{return unavailable||active.has(read(key())?.state);}catch{return true;}}
 };
}

// Optional bridge for legacy P0 clients. Other modules keep their existing transport when no journal is supplied.
export function createHoursAttemptTransport({supabase,journal,missingMessage='O contrato ainda não está disponível.'}){
 let ticket=null;
 async function call(name,body){const writer=journal&&typeof body.p_confirmar==='boolean';if(writer)ticket=journal.begin({rpc:name,phase:body.p_confirmar?'confirm':'preview',request_ids:[body.p_dados.request_id]});
  try{const response=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(body)}),data=await response.json().catch(()=>null);
   if(!response.ok){if(writer&&(response.status>=500||response.status===408)){journal.uncertain(ticket);throw hoursUncertainError();}if(writer)journal.reject(ticket);throw Object.assign(Error(response.status===404?missingMessage:data?.message||'Operação recusada.'),{code:data?.code||String(response.status),httpStatus:response.status});}
   if(writer&&!data){journal.uncertain(ticket);throw hoursUncertainError();}return data;
  }catch(error){if(writer&&(!error.code||error.code==='HOURS_RESULT_UNCERTAIN')){journal.uncertain(ticket);throw hoursUncertainError();}throw error;}
 }
 call.preview=()=>journal?.preview(ticket);call.cancel=()=>journal?.cancel(ticket);call.complete=()=>journal?.complete(ticket);
 call.fail=error=>{if(journal&&(!error.code||error.code==='HOURS_RESULT_UNCERTAIN'||error.httpStatus>=500)){journal.uncertain(ticket);error.code='HOURS_RESULT_UNCERTAIN';error.message=hoursUncertainError().message;}};
 call.receipt=()=>journal?.receipt();return call;
}
