// REVIEW BEFORE MANUAL EXECUTION. No imports, installations, activation or SQL.
// Authentication headers remain inside requests to the official Supabase only.
// Do not export Network logs or session storage. No automatic retry or refresh.
export async function runAssistedAuthReadOnly() {
 'use strict';
 let step='origin'; let lastRequest=null;
 try {
  if(window.top!==window.self)throw Error('STOP');
  if(location.origin!=='https://plataforma-primeline.pages.dev')throw Error('STOP');
  const base='https://znttyadndpkxuekhjamd.supabase.co';
  const company='73fb13c8-d29f-4192-a506-4ca243343add';
  const work='7c2a0c29-5eca-40d9-aff0-3e1b00d8e973';
  const getSession=()=>{try{return JSON.parse(sessionStorage.getItem('primeline_supabase_session'));}catch{return null;}};
  step='existing_session';
  const session=getSession();
  if(!session?.access_token||!/^[a-f0-9-]{36}$/i.test(session.user?.id||''))throw Error('STOP');
  const sessionUserId=session.user.id;
  const allowed=new Map([
   ['GET '+base+'/auth/v1/user',null],
   ['POST '+base+'/rest/v1/rpc/fn_utilizador_atual_id',{}],
   ['POST '+base+'/rest/v1/rpc/fn_folha_rh_permissoes_contexto_v1',{}],
   ['POST '+base+'/rest/v1/rpc/fn_folha_piloto_contexto_v3',{p_obra_id:work}],
   ['GET '+base+'/rest/v1/obras?select=id,empresa_id,situacao&id=eq.'+work,null],
   ['GET '+base+'/rest/v1/utilizadores?select=id,empresa_id,funcao,ativo,auth_user_id&auth_user_id=eq.'+sessionUserId,null]
  ]);
  const dispatched=new Set();
  const requestLabels=['auth_user','internal_actor_rpc','management_context_rpc','pilot_context_rpc','work120_rls','internal_profile_rls'];
  const safeFetch=async(url,options={})=>{
   const key=(options.method||'GET')+' '+String(url);
   if(!allowed.has(key)||dispatched.has(key))throw Error('STOP');
   const body=allowed.get(key);
   if(body!==null&&JSON.stringify(JSON.parse(options.body||'null'))!==JSON.stringify(body))throw Error('STOP');
   if(body===null&&options.body!==undefined)throw Error('STOP');
   if(getSession()?.access_token!==session.access_token||getSession()?.user?.id!==sessionUserId)throw Error('STOP');
   dispatched.add(key);
   lastRequest={phase:requestLabels[[...allowed.keys()].indexOf(key)],http_status:null};
   const response=await fetch(url,{...options,credentials:'omit',redirect:'error',cache:'no-store',signal:AbortSignal.timeout(60000)});
   lastRequest.http_status=response.status;
   return response;
  };
// Existing browser session and public configuration only. Never log/persist secrets.
// Unlike the normal app transport, this release transport never refreshes/replays a 401.
function createSingleAttemptHoursTransport({getSession,config,fetchImpl=globalThis.fetch}){
 const base=config?.supabaseUrl?.replace(/\/$/,'');if(base!=='https://znttyadndpkxuekhjamd.supabase.co'||!config.supabaseAnonKey)throw Error('OFFICIAL_PUBLIC_CONFIGURATION_REQUIRED');
 const session=getSession();if(!session?.access_token)throw Error('EXISTING_AUTHENTICATED_SESSION_REQUIRED');const token=session.access_token;
 const current=()=>{if(getSession()?.access_token!==token)throw Error('SESSION_CHANGED_STOP');};
 const allowed=new Set(['fn_utilizador_atual_id','fn_folha_rh_permissoes_contexto_v1','fn_folha_piloto_contexto_v3','fn_folha_piloto_configurar_v3','fn_folha_equipa_horas_contexto_v3','fn_folha_dia_contexto_v3','fn_folha_obra_mensal_factual_v1','fn_folha_fecho_obra_contexto_v1']);
 const request=async(url,opts)=>{current();const r=await fetchImpl(url,{...opts,headers:{apikey:config.supabaseAnonKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},cache:'no-store'});current();return r;};
 return {supabase:async(path,opts)=>{const name=path.replace(/^rpc\//,'');if(path!=='rpc/'+name||!allowed.has(name)||opts?.method!=='POST')throw Error('RPC_OUTSIDE_CUTOVER_SCOPE');return request(base+'/rest/v1/'+path,opts);},readWork:async id=>{if(!/^[a-f0-9-]{36}$/.test(id))throw Error('WORK_ID_INVALID');const r=await request(base+'/rest/v1/obras?select=id,empresa_id,situacao&id=eq.'+id,{method:'GET'});if(!r.ok)throw Error('WORK_SCOPE_READ_REFUSED');const rows=await r.json();current();if(!Array.isArray(rows)||rows.length!==1||rows[0].id!==id)throw Error('WORK_SCOPE_NOT_UNIQUE');return rows[0];},verifyAuthUser:async()=>{const r=await request(base+'/auth/v1/user',{method:'GET'});if(!r.ok)throw Error('AUTH_SERVER_REFUSED_NO_RETRY');const user=await r.json();current();if(!user.id)throw Error('AUTH_SERVER_IDENTITY_MISSING');return {id:user.id,verifiedByServer:true};}};
}

// Existing authenticated browser/API transport only. No sign-in, credentials or writes.
async function hoursReadOnlyPreflight({supabase,verifyAuthUser,expectedCompanyId,expectedActorId,workId}){
 const auth=await verifyAuthUser();if(!auth?.id||auth.verifiedByServer!==true)throw Error('REAL_AUTH_SERVER_IDENTITY_REQUIRED');
 const call=async(name,body)=>{const r=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(body)});const data=await r.json();if(!r.ok)throw Error('READ_ONLY_RPC_REFUSED: '+name);return data;};
 const actor=await call('fn_utilizador_atual_id',{});if(!actor||expectedActorId&&actor!==expectedActorId)throw Error('ACTOR_IDENTITY_MISMATCH');
 const management=await call('fn_folha_rh_permissoes_contexto_v1',{});
 if(management.company_id!==expectedCompanyId||management.actor_id!==actor||management.can_assign_special!==false)throw Error('MANAGEMENT_OR_DISABLED_SPECIAL_POWER_MISMATCH');
 const work=await call('fn_folha_piloto_contexto_v3',{p_obra_id:workId});if(work.version!==3||work.work_id!==workId||work.mode!=='legado'||work.revision!==0)throw Error('WORK_NOT_UNCONFIGURED_STOP');
 return {verified:true,companyId:expectedCompanyId,actorId:actor,authUserVerified:true,canAssignSpecial:false,workId,mode:work.mode,credentialsRecorded:false};
}

  step='public_configuration';
  const config=window.PRIMELINE_CONFIG;
  const t=createSingleAttemptHoursTransport({getSession,config,fetchImpl:safeFetch});
  let selfRoleVerified=false;
  const readRpc=async(path,opts)=>{
   const response=await t.supabase(path,opts);
   if(path==='rpc/fn_folha_rh_permissoes_contexto_v1'&&response.ok){
    const data=await response.clone().json();
    const self=data.users?.filter(x=>x.id===data.actor_id);
    selfRoleVerified=Array.isArray(self)&&self.length===1&&self[0].active===true&&self[0].role==='gestao_plataforma';
    if(!selfRoleVerified)throw Error('STOP');
   }
   return response;
  };
  step='auth_postgrest_rpc';
  const result=await hoursReadOnlyPreflight({supabase:readRpc,verifyAuthUser:async()=>{
   const auth=await t.verifyAuthUser();if(auth.id!==sessionUserId)throw Error('STOP');return auth;
  },expectedCompanyId:company,workId:work});
  step='internal_identity_rls';
  const profileResponse=await safeFetch(base+'/rest/v1/utilizadores?select=id,empresa_id,funcao,ativo,auth_user_id&auth_user_id=eq.'+sessionUserId,{method:'GET',headers:{apikey:config.supabaseAnonKey,Authorization:'Bearer '+session.access_token}});
  if(!profileResponse.ok)throw Error('STOP');
  const profiles=await profileResponse.json();
  if(!Array.isArray(profiles)||profiles.length!==1)throw Error('STOP');
  const p=profiles[0];
  if(p.id!==result.actorId||p.auth_user_id!==sessionUserId||p.empresa_id!==company||p.funcao!=='gestao_plataforma'||p.ativo!==true)throw Error('STOP');
  step='work_rls';
  const row=await t.readWork(work);
  if(row.empresa_id!==company||row.situacao!=='em_curso')throw Error('STOP');
  if(dispatched.size!==6||getSession()?.access_token!==session.access_token||getSession()?.user?.id!==sessionUserId)throw Error('STOP');
  return {format:'HOURS_ASSISTED_AUTH_READONLY_V1',status:'PASS',observed_at:new Date().toISOString(),official_origin:true,official_supabase:true,auth_server_verified:true,session_identity_matches:true,internal_identity_matches:true,management_profile_verified:selfRoleVerified,company_matches:true,postgrest_verified:true,read_rpc_count:3,rls_self_profile_read:true,rls_work120_read:true,work120_in_progress:true,work120_mode:result.mode,work120_revision:0,current_actor_can_assign_special:result.canAssignSpecial,global_special_counts_checked_here:false,requests:dispatched.size,operational_writes:0,activation_performed:false,credentials_in_output:false};
 } catch {
  return {format:'HOURS_ASSISTED_AUTH_READONLY_V1',status:'STOP',observed_at:new Date().toISOString(),failed_check:step,request:lastRequest,no_automatic_retry:true,activation_performed:false,credentials_in_output:false};
 }
}
// UI: no requests on page load, no globals holding session or response bodies.
const start=document.getElementById('start');
const result=document.getElementById('result');
const download=document.getElementById('download');
let attempted=false,receipt=null;
start.addEventListener('click',async()=>{
 if(attempted)return;
 attempted=true;start.disabled=true;result.textContent='Verificação de leitura em curso. Não recarregue nem repita.';
 try{receipt=await runAssistedAuthReadOnly();}
 catch{receipt={format:'HOURS_ASSISTED_AUTH_READONLY_V1',status:'STOP',failed_check:'unexpected_local_error',no_automatic_retry:true};}
 result.textContent=JSON.stringify(receipt,null,2);download.disabled=false;
});
download.addEventListener('click',()=>{
 if(!receipt)return;
 const blob=new Blob([JSON.stringify(receipt,null,2)+'\n'],{type:'application/json'});
 const url=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=url;a.download='PRIMELINE-AUTH-READONLY-RECEIPT.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(url),1000);
});
