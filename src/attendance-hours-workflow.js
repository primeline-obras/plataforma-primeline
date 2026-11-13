// Presentation/contract validation only. Server authorization must be independent.
export const RH_POLICY='P0_RH_REVIEW_20261103';
export const RH_CAPABILITIES=['write_direct','request_correction','request_retroactive','request_regularization','confer_daily','decide_requests','decide_regularizations','close_month'];
export const RH_STATES={pending:'Pendente de conferência diária',conferred:'Conferido pelo RH',closed:'Mês fechado',regularization:'Regularização formal',requested:'Pedido pendente de decisão RH'};
export function validateRhContext(c,scope){
 if(c?.version!==1||c.policy!==RH_POLICY||!['pending','conferred'].includes(c.daily_state)||!['open','closed'].includes(c.monthly_state)||!Number.isInteger(c.revision)||c.revision<0||!Number.isInteger(c.fact_revision)||c.fact_revision<0||!Array.isArray(c.requests)||!Array.isArray(c.history)||!RH_CAPABILITIES.every(k=>typeof c.capabilities?.[k]==='boolean')||!['work_id','person_id','date','kind'].every(k=>c[k]===scope[k])||c.financial_effect!==false)throw Error('Contrato de conferência diária incompleto ou fora do âmbito.');
 if(c.monthly_state==='closed'&&(c.capabilities.write_direct||c.capabilities.request_correction||c.capabilities.request_retroactive||c.capabilities.confer_daily))throw Error('Mês fechado com capacidades incompatíveis.');
 if(c.daily_state==='conferred'&&c.capabilities.write_direct)throw Error('Dia conferido não permite edição direta.');
 if(!/^[0-9a-f]{64}$/.test(c.month_fingerprint||''))throw Error('Fotografia mensal não confirmada.');
 const ids=new Set();for(const r of c.requests){if(!r.id||ids.has(r.id)||!['correction','retroactive','regularization'].includes(r.type)||!['pending','approved','rejected'].includes(r.state)||!Number.isInteger(r.fact_revision)||!Array.isArray(r.sites))throw Error('Pedidos de conferência inválidos.');ids.add(r.id);}
 if(c.exception_policy!==undefined){if(c.exception_policy!=='H_P1_EXACT_PROPOSAL_V1'||!Array.isArray(c.regularization_authorizations)||c.regularization_authorizations.some(a=>!a.id||!a.executor_id||!Number.isInteger(a.revision)||a.revision<1||a.scope!=='exact_proposal'||!Array.isArray(a.allowed_actions)||!a.allowed_actions.length||a.allowed_actions.some(x=>!['approve_request','reject_request'].includes(x))||a.month!==c.date.slice(0,7)+'-01'||!c.requests.some(r=>r.id===a.proposal_id&&r.type==='regularization'&&r.state==='pending')))throw Error('Autorizações delimitadas fora do contrato.');}
 return c;
}
export function rhWriteRoute(day){
 if(!Object.hasOwn(day,'rh_workflow'))return null; // Existing contract remains intact until new server capability is present.
 const c=validateRhContext(day.rh_workflow,day);
 if(c.requests.some(r=>r.state==='pending'))return 'pending';
 if(c.capabilities.correct_direct===true)return 'rh_direct';
 if(c.monthly_state==='closed')return c.capabilities.request_regularization?'regularization':'readonly';
 if(c.daily_state==='conferred')return c.capabilities.request_correction?'correction':'readonly';
 if(c.fact_revision===0&&day.date<day.server_date)return c.capabilities.request_retroactive?'retroactive':'readonly';
 return c.capabilities.write_direct?'direct':'readonly';
}
export const rhRouteLabel=route=>({direct:'GUARDAR HORÁRIOS',rh_direct:'CORRIGIR E CONFERIR',correction:'PEDIR CORREÇÃO AO RH',retroactive:'PEDIR REGISTO RETROATIVO',regularization:'PEDIR REGULARIZAÇÃO FORMAL',pending:'PEDIDO PENDENTE DE RH',readonly:'SOMENTE CONSULTA'})[route];
export function rhScope(day){return{work_id:day.work_id,person_id:day.person_id,date:day.date,kind:day.kind};}
