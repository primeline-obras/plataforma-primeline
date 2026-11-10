// Deployment-only orchestrator. Caller supplies the EXISTING authenticated transport.
// No credentials, role impersonation, owner bypass or automatic retry.
async function activateHoursWork({supabase,authorization,receipts,clientsDrained,frontendReady,workId,companyId,requestId,reason}){
 if(authorization?.project!=='znttyadndpkxuekhjamd'||authorization?.productionCutoverApproved!==true||!authorization.reference||!authorization.workIds?.includes(workId))throw Error('EXPLICIT_SCOPED_CUTOVER_AUTHORIZATION_REQUIRED');
 if(clientsDrained!==true||frontendReady!==true||receipts?.daily!=='DAILY_V2_POSTCHECK_PASS_NOT_ACTIVATED'||receipts?.ad15!=='AD15_POSTCHECK_OK'||receipts?.completeChain!==true||receipts?.specialGrantors!==0||receipts?.specialAssignments!==0)throw Error('CUTOVER_PREREQUISITES_NOT_VERIFIED');
 if(!/^[a-f0-9-]{36}$/.test(workId)||!/^[a-f0-9-]{36}$/.test(requestId)||!reason?.trim())throw Error('CUTOVER_ID_AND_REASON_REQUIRED');
 const call=async(name,data)=>{const r=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(data)});const body=await r.json();if(!r.ok)throw Error(body?.message||'CUTOVER_RPC_REFUSED');return body;};
 const identity=await call('fn_folha_rh_permissoes_contexto_v1',{});
 if(identity?.version!==1||identity.company_id!==companyId||!identity.actor_id||identity.can_assign_special!==false)throw Error('MANAGEMENT_IDENTITY_OR_DISABLED_SPECIAL_POWER_NOT_VERIFIED');
 const context=await call('fn_folha_piloto_contexto_v3',{p_obra_id:workId});
 if(context?.version!==3||context.work_id!==workId||context.mode!=='legado'||context.revision!==0)throw Error('WORK_ALREADY_CONFIGURED_REVIEW_BEFORE_CUTOVER');
 const data={version:3,request_id:requestId,work_id:workId,state:'ativo',expected_revision:context.revision,reason:reason.trim()};
 const preview=await call('fn_folha_piloto_configurar_v3',{p_dados:data,p_confirmar:false,p_versao:null});
 if(preview?.version!==3||preview.committed!==false||!preview.versao)throw Error('INVALID_CUTOVER_PREVIEW');
 let result;
 try{
  result=await call('fn_folha_piloto_configurar_v3',{p_dados:data,p_confirmar:true,p_versao:preview.versao});
  if(result?.version!==3||result.committed!==true||result.work_id!==workId||result.request_id!==requestId||result.state!=='ativo'||result.revision!==1)throw Error('INVALID_CUTOVER_COMMIT_RECEIPT');
 }catch(e){throw Object.assign(Error('CUTOVER_OUTCOME_UNCERTAIN_STOP_NO_RETRY: '+e.message),{requestId});}
 const after=await call('fn_folha_piloto_contexto_v3',{p_obra_id:workId});
 if(after?.mode!=='piloto'||after.revision!==1||after.work_id!==workId)throw Error('CUTOVER_POSTCHECK_FAILED_KEEP_WRITERS_PAUSED');
 return {project:authorization.project,companyId,workId,actorId:identity.actor_id,requestId,result,after,specialPowerDisabled:true,syntheticHoursCreated:false};
}

function activationGate({manifest,ledger,manifestSha256,authPreflight,frontendEvidence,clientsDrained}){
 if(!ledger?.complete||ledger.manifestSha256!==manifestSha256||ledger.units.length!==7||manifest.units.some(u=>!ledger.units.some(e=>e.id===u.id&&e.sha256===u.sha256&&e.state==='CONFIRMED')))throw Error('ACTUAL_TECHNICAL_RECEIPTS_REQUIRED');
 const final=ledger.units.find(e=>e.id==='FINAL').result;
 if(final.special_grantors!==0||final.special_assignments!==0||!authPreflight?.verified||authPreflight.companyId!==manifest.companyId||authPreflight.canAssignSpecial!==false||!authPreflight.authUserVerified)throw Error('REAL_AUTH_PREFLIGHT_REQUIRED');
 if(clientsDrained!==true||frontendEvidence?.verified!==true||!frontendEvidence.commit||!frontendEvidence.deployment||frontendEvidence.changedFiles!==4||!frontendEvidence.configPreserved||!frontendEvidence.cacheVerified)throw Error('FRONTEND_AND_DRAINAGE_PROOF_REQUIRED');
 return {cohort:final.cohort,receipts:{daily:'DAILY_V2_POSTCHECK_PASS_NOT_ACTIVATED',ad15:'AD15_POSTCHECK_OK',completeChain:true,specialGrantors:0,specialAssignments:0},readyForScopedPilotAuthorization:true};
}

async function activateFrozenHoursCohort({manifest,manifestSha256,ledger,authorization,authPreflight,frontendEvidence,clientsDrained,supabase,newRequestId,loadWorkReceipt,validateWorkStillInScope,saveReceipt,reason}){
 const gate=activationGate({manifest,ledger,manifestSha256,authPreflight,frontendEvidence,clientsDrained});
 const ids=gate.cohort.works.map(w=>w.id);
 if(authorization?.activationApproved!==true||authorization.project!==manifest.project||!authorization.reference||JSON.stringify(authorization.workIds)!==JSON.stringify(ids))throw Error('EXACT_FROZEN_COHORT_AUTHORIZATION_REQUIRED');
 if(typeof loadWorkReceipt!=='function'||typeof validateWorkStillInScope!=='function')throw Error('DURABLE_RECEIPT_AND_LIVE_WORK_SCOPE_CHECK_REQUIRED');
 const results=[];for(const workId of ids){if(await loadWorkReceipt(workId))throw Error('EXISTING_WORK_ATTEMPT_STOP_NO_RETRY');if(await validateWorkStillInScope(workId,manifest.companyId)!==true)throw Error('WORK_LEFT_AUTHORIZED_COHORT_STOP');const requestId=newRequestId();await saveReceipt({workId,requestId,state:'DISPATCH_STARTED_NO_RETRY'});
  try{const receipt=await activateHoursWork({supabase,authorization:{...authorization,productionCutoverApproved:true},receipts:gate.receipts,clientsDrained,frontendReady:true,workId,companyId:manifest.companyId,requestId,reason});results.push(receipt);await saveReceipt({workId,requestId,state:'CONFIRMED',receipt});}
  catch(e){await saveReceipt({workId,requestId,state:'STOP_OUTCOME_REQUIRES_REVIEW',error:String(e.message)});throw e;}
 }return {confirmed:true,works:results,realHoursWritten:false};
}

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
async function hoursReadOnlyOperationalSmoke({supabase,verifyAuthUser,expectedActorId,workId,date,personId=null,month,profile}){
 const auth=await verifyAuthUser();if(!auth?.id||auth.verifiedByServer!==true)throw Error('REAL_AUTH_SERVER_IDENTITY_REQUIRED');
 const calls=[];const call=async(name,body)=>{const r=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(body)}),d=await r.json();if(!r.ok)throw Error('READ_ONLY_SMOKE_REFUSED: '+name);calls.push(name);return d;};
 const actor=await call('fn_utilizador_atual_id',{});if(!actor||expectedActorId&&actor!==expectedActorId)throw Error('ACTOR_IDENTITY_MISMATCH');
 const work=await call('fn_folha_piloto_contexto_v3',{p_obra_id:workId});if(work.mode!=='piloto'||work.work_id!==workId||work.revision<1)throw Error('ACTIVE_WORK_NOT_VERIFIED');
 const team=await call('fn_folha_equipa_horas_contexto_v3',{p_data:date,p_obra_id:workId});if(team.version!==3||team.work_id!==workId||!Array.isArray(team.people))throw Error('TEAM_READ_CONTRACT_INVALID');
 if(personId){const day=await call('fn_folha_dia_contexto_v3',{p_data:date,p_obra_id:workId,p_person_id:personId,p_kind:'primeline'});if(day.version!==3||day.work_id!==workId||day.person_id!==personId||!Array.isArray(day.records)||!day.rh_workflow)throw Error('DAY_RH_READ_CONTRACT_INVALID');}
 if(profile==='management'){
  await call('fn_folha_obra_mensal_factual_v1',{p_obra_id:workId,p_competencia:month});
  await call('fn_folha_fecho_obra_contexto_v1',{p_obra_id:workId,p_mes:month});
 }
 return {verified:true,profile,actorId:actor,workId,calls,readOnly:true,syntheticRecordsCreated:false};
}


// Adapter only: approved RPC conductors above are unchanged; no request on load.
const DATA={"manifest":{"project":"znttyadndpkxuekhjamd","companyId":"73fb13c8-d29f-4192-a506-4ca243343add","requiredWork120":"7c2a0c29-5eca-40d9-aff0-3e1b00d8e973","units":[{"id":"21","sha256":"57d3d5182d7b4c68acea2e92019770459f2c3b4982660d10b6b4c7275974e0f9"},{"id":"22","sha256":"e51001ff224c5dc46614225f3f1f66fd3026744073f7e5f6995125524822f6e4"},{"id":"23","sha256":"8d894f65b676be33d735c86435880eefb32733033bef75739267c0f66ea4469c"},{"id":"24","sha256":"142e0beee96d777bc418adc16e03d01cb277d2d1e84eaaeded754f76fac0b4e3"},{"id":"25","sha256":"107ec397e3162619b93428eee5f07ac3ca80b7a9dc62b9b5551fdaaf1f72d84a"},{"id":"RH","sha256":"0dd6d76f4877cad71a5639d3e787d351963a82edfc45f93e7b93bc83574bc292"},{"id":"FINAL","sha256":"0da62018587f4d401393a588efe7a8387aa798b555f9d7da4813bc33ba85c406"}]},"ledger":{"manifestSha256":"469108c16cfa5d8d3622f7d42bebd5c0b346ee702d820e9d0e3728933b211fbc","project":"znttyadndpkxuekhjamd","complete":true,"units":[{"id":"21","sha256":"57d3d5182d7b4c68acea2e92019770459f2c3b4982660d10b6b4c7275974e0f9","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_21_CONFIRMED_NOT_ACTIVATED"}},{"id":"22","sha256":"e51001ff224c5dc46614225f3f1f66fd3026744073f7e5f6995125524822f6e4","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_22_CONFIRMED_NOT_ACTIVATED"}},{"id":"23","sha256":"8d894f65b676be33d735c86435880eefb32733033bef75739267c0f66ea4469c","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_23_CONFIRMED_NOT_ACTIVATED"}},{"id":"24","sha256":"142e0beee96d777bc418adc16e03d01cb277d2d1e84eaaeded754f76fac0b4e3","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_24_CONFIRMED_NOT_ACTIVATED"}},{"id":"25","sha256":"107ec397e3162619b93428eee5f07ac3ca80b7a9dc62b9b5551fdaaf1f72d84a","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_25_CONFIRMED_NOT_ACTIVATED"}},{"id":"RH","sha256":"0dd6d76f4877cad71a5639d3e787d351963a82edfc45f93e7b93bc83574bc292","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_RH_CONFIRMED_NOT_ACTIVATED"}},{"id":"FINAL","sha256":"0da62018587f4d401393a588efe7a8387aa798b555f9d7da4813bc33ba85c406","state":"CONFIRMED","result":{"release_marker":"P0_REMAINING_FINAL_CONFIRMED_NOT_ACTIVATED","special_grantors":0,"special_assignments":0,"rh_assignments":0,"cohort":{"works":[{"id":"d22390df-25d7-444e-b281-eebbbee80c29","state":"em_curso","number":32},{"id":"75579b62-44a6-41f4-95bd-f9968e39afc3","state":"em_curso","number":79},{"id":"11b8f830-35d6-48f3-b303-3684d55e652c","state":"em_curso","number":85},{"id":"0cb8eea5-c2ee-4784-9c2e-aa1622616543","state":"em_curso","number":114},{"id":"5222b4c4-5255-4269-bd76-72b5227989c0","state":"em_curso","number":118},{"id":"7c2a0c29-5eca-40d9-aff0-3e1b00d8e973","state":"em_curso","number":120},{"id":"127a4443-931b-49b8-a7eb-48e7099d452c","state":"em_curso","number":121},{"id":"7d49b650-0730-4455-a3c2-647193708eb7","state":"em_curso","number":122},{"id":"459fc319-a57a-4d2a-8b2b-4679af948478","state":"em_curso","number":127},{"id":"d3f0e9bd-3fb4-4a10-9f23-253071516745","state":"em_curso","number":128}],"format":"HOURS_RELEASE_WORK_COHORT_V1","company_id":"73fb13c8-d29f-4192-a506-4ca243343add","observed_at":"2026-11-09T16:54:42.286977+00:00"}}}]},"frontend":{"verified":true,"commit":"f5dcce4057a28245e2528dd161c634d67d020671","deployment":"6ef07719-8399-43e9-8b46-3ffd0391702d","changedFiles":4,"configPreserved":true,"cacheVerified":true},"assets":[{"file":"src/hours-runtime-config.js","sha256":"fa9b5dab17318a5fef8205aa2ecd55af99afec40c05a3104726f463f7750fabc"},{"file":"src/attendance-runtime.js","sha256":"b61eb3ae8356a146e7394ffd1fd4f246f6160dda62943a762f5547bbbe9cb6fb"},{"file":"src/app.js","sha256":"817bcdeaaa91fc5ec9f2189b4d30fcbdd0e3e756b12d1ba9ffd6cca02d1c3c5d"},{"file":"index.html","sha256":"8dda5bdee96b15fcc802f8690590ebe03adec02708becccd5cd609aca8209626"},{"file":"config.js","sha256":"3860b84e635e6b7b5bf69825fb38399205e62f579a687bc3bdcb934197c03378"}],"manifestSha256":"469108c16cfa5d8d3622f7d42bebd5c0b346ee702d820e9d0e3728933b211fbc"};
const activate=document.getElementById('activate');
const start=document.getElementById('start'),confirm=document.getElementById('confirm'),download=document.getElementById('download'),status=document.getElementById('status');
const works=DATA.ledger.units.find(x=>x.id==='FINAL').result.cohort.works;
const workIds=works.map(x=>x.id),previousPrefix='primeline_p0_cohort_f5dcce4_20261110',prefix=previousPrefix+':recovery_v2_ff0668ac',expectedPreviousHash='ff0668ac699cfecf5fe7b277e6c2f215b7d76da46b6b74856d03175c26a1b7da';
let attempted=false,approve=null,resume=null,events=[],transport=null,phase="not_started",currentAsset=null,lastRequest=null;
function show(s){status.textContent=s;}

async function verifyPreviousStop(){
 const first=JSON.parse(localStorage.getItem(previousPrefix+':snapshot:0001')||'null');
 const second=JSON.parse(localStorage.getItem(previousPrefix+':snapshot:0002')||'null');
 if(localStorage.getItem(previousPrefix+':started')!=='started'||!Array.isArray(first)||first.length!==1||!Array.isArray(second)||second.length!==2||first[0].type!=='start'||second[0].type!=='start'||second[1].type!=='stop'||second[1].state!=='STOP_NO_RETRY_KEEP_MAINTENANCE'||JSON.stringify(first[0])!==JSON.stringify(second[0]))throw Error('PREVIOUS_STOP_BINDING_STOP');
 for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(k?.startsWith(previousPrefix+':snapshot:')&&![previousPrefix+':snapshot:0001',previousPrefix+':snapshot:0002'].includes(k))throw Error('PREVIOUS_EXTRA_EVIDENCE_STOP');}
 const original=JSON.stringify({format:'HOURS_COHORT_ASSISTED_RECEIPT_V1',events:second,credentialsRecorded:false,operationalGo:false},null,2);
 const sha=[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(original)))].map(x=>x.toString(16).padStart(2,'0')).join('');
 if(sha!==expectedPreviousHash)throw Error('PREVIOUS_RECEIPT_HASH_STOP');
}
function safeErrorCode(e){
 const known=new Set(['PREVIOUS_STOP_BINDING_STOP','PREVIOUS_EXTRA_EVIDENCE_STOP','PREVIOUS_RECEIPT_HASH_STOP','FRONTEND_READ_STOP','FRONTEND_HASH_STOP','LIVE_WORK_STATE_NOT_LEGACY_ZERO_STOP','LIVE_WORK_SCOPE_STOP','PRIOR_OR_CONCURRENT_ATTEMPT_STOP','STORAGE_STOP','EXISTING_SNAPSHOT_STOP','DURABLE_RECEIPT_STOP','SESSION_CHANGED_BEFORE_REQUEST_STOP','SESSION_CHANGED_AFTER_REQUEST_STOP','READ_ONLY_MODE_STOP','OFFICIAL_CONTEXT_STOP','SESSION_IDENTITY_STOP','OFFICIAL_PUBLIC_CONFIGURATION_REQUIRED','EXISTING_AUTHENTICATED_SESSION_REQUIRED','AUTH_SERVER_REFUSED_NO_RETRY','READ_SCOPE_STOP','RPC_SCOPE_STOP','WORK_SCOPE_STOP','WRITE_SCOPE_STOP','PREVIEW_REPLAY_STOP','CONFIRMATION_REPLAY_OR_TOKEN_STOP','CONFIRMATION_FLAG_STOP','COHORT_POSTCHECK_STOP']);
 if(known.has(e?.message))return e.message;
 if(e?.name==='TimeoutError'||e?.name==='AbortError')return 'REQUEST_TIMEOUT_OR_ABORT';
 if(e?.name==='TypeError')return 'FETCH_OR_LOCAL_TYPE_ERROR';
 if(e?.name==='QuotaExceededError'||e?.name==='SecurityError')return 'STORAGE_OR_BROWSER_POLICY_STOP';
 return 'RPC_OR_GUARD_STOP';
}
activate.addEventListener('click',()=>{if(!resume||activate.disabled)return;const resolve=resume;resume=null;activate.disabled=true;resolve();});

function append(entry){
 const clean={at:new Date().toISOString(),...entry};events.push(clean);
 const text=JSON.stringify(events),key=prefix+':snapshot:'+String(events.length).padStart(4,'0');
 if(localStorage.getItem(key)!==null)throw Error('EXISTING_SNAPSHOT_STOP');
 localStorage.setItem(key,text);if(localStorage.getItem(key)!==text)throw Error('DURABLE_RECEIPT_STOP');download.disabled=false;
}
function saveWork(e){
 const r=e.receipt;
 append({type:'work',workId:e.workId,requestId:e.requestId,state:e.state, ...(e.error?{error:'RPC_OR_GUARD_STOP'}:{}),...(r?{receipt:{project:r.project,companyId:r.companyId,workId:r.workId,actorId:r.actorId,requestId:r.requestId,result:{version:r.result.version,committed:r.result.committed,work_id:r.result.work_id,request_id:r.result.request_id,state:r.result.state,revision:r.result.revision},after:{work_id:r.after.work_id,mode:r.after.mode,revision:r.after.revision},specialPowerDisabled:r.specialPowerDisabled,syntheticHoursCreated:false}}:{})});
}
async function verifyAssets(){phase='assets';for(const a of DATA.assets){currentAsset=a.file;lastRequest={phase:'asset',http_status:null};const path=a.file==='index.html'?'/':'/'+a.file;const r=await fetch(location.origin+path,{cache:'no-store',redirect:'error',signal:AbortSignal.timeout(30000)});lastRequest.http_status=r.status;if(!r.ok)throw Error('FRONTEND_READ_STOP');const b=await r.arrayBuffer();const h=[...new Uint8Array(await crypto.subtle.digest('SHA-256',b))].map(x=>x.toString(16).padStart(2,'0')).join('');if(h!==a.sha256)throw Error('FRONTEND_HASH_STOP');append({type:'asset_verified',file:a.file,canonical_path:path,sha256:h});}currentAsset=null;lastRequest=null;}
confirm.addEventListener('click',()=>{if(!approve||confirm.disabled)return;const resolve=approve;approve=null;confirm.disabled=true;resolve();});
start.addEventListener('click',async()=>{
 if(attempted)return;attempted=true;start.disabled=true;
 try{
  if(location.origin!=='https://plataforma-primeline.pages.dev'||window.top!==window.self||!navigator.locks)throw Error('OFFICIAL_CONTEXT_STOP');
  await navigator.locks.request(previousPrefix,{mode:'exclusive',ifAvailable:true},async lock=>{
   if(!lock||localStorage.getItem(prefix+':started')!==null)throw Error('PRIOR_OR_CONCURRENT_ATTEMPT_STOP');
   phase='recovery_binding';await verifyPreviousStop();
   localStorage.setItem(prefix+':started','started');if(localStorage.getItem(prefix+':started')!=='started')throw Error('STORAGE_STOP');
   append({type:'start',recovery:'V2_FROM_STOP_ff0668ac',previous_receipt_sha256:expectedPreviousHash,commit:DATA.frontend.commit,maintenanceActive:true,operationalGo:false});
   show('Conferindo frontend e sessão. Nenhuma obra habilitada por este passo.');await verifyAssets();
   phase='session_configuration';
   const getSession=()=>{try{return JSON.parse(sessionStorage.getItem('primeline_supabase_session'));}catch{return null;}};
   const frozenToken=getSession()?.access_token,frozenUser=getSession()?.user?.id;
   const getPaths=new Set(['https://znttyadndpkxuekhjamd.supabase.co/auth/v1/user',...workIds.map(id=>'https://znttyadndpkxuekhjamd.supabase.co/rest/v1/obras?select=id,empresa_id,situacao&id=eq.'+id)]);
   const rpcNames=new Set(['fn_utilizador_atual_id','fn_folha_rh_permissoes_contexto_v1','fn_folha_piloto_contexto_v3','fn_folha_piloto_configurar_v3']);
   let allowWrites=false;const previews=new Map(),commits=new Set();
   const boundedFetch=async(url,opts)=>{
    const u=String(url),method=opts.method||'GET';currentAsset=null;phase='initial_or_cohort_read';lastRequest={phase:u.endsWith('/auth/v1/user')?'auth_user':u.includes('/obras?')?'work_scope':'rpc_read',http_status:null};
    if(method==='GET'){if(!getPaths.has(u)||opts.body!==undefined)throw Error('READ_SCOPE_STOP');}
    else if(method==='POST'){
     const name=u.replace('https://znttyadndpkxuekhjamd.supabase.co/rest/v1/rpc/','');if(!rpcNames.has(name))throw Error('RPC_SCOPE_STOP');
     const b=JSON.parse(opts.body);
     if(name==='fn_folha_piloto_contexto_v3'&&!workIds.includes(b.p_obra_id))throw Error('WORK_SCOPE_STOP');
     if(name==='fn_folha_piloto_configurar_v3'){
      if(!allowWrites)throw Error('READ_ONLY_MODE_STOP');phase='activation';lastRequest.phase=b.p_confirmar?'pilot_confirmation':'pilot_preview';
      const d=b.p_dados,attempt=events.find(e=>e.type==='work'&&e.workId===d?.work_id&&e.state==='DISPATCH_STARTED_NO_RETRY');
      if(!attempt||d.request_id!==attempt.requestId||!workIds.includes(d.work_id)||d.version!==3||d.state!=='ativo'||d.expected_revision!==0||d.reason!=='Publicação P0 autorizada; manutenção mantida até GO funcional.')throw Error('WRITE_SCOPE_STOP');
      if(b.p_confirmar===false){if(previews.has(d.work_id))throw Error('PREVIEW_REPLAY_STOP');previews.set(d.work_id,null);}
      else if(b.p_confirmar===true){
       if(commits.has(d.work_id)||!previews.get(d.work_id)||b.p_versao!==previews.get(d.work_id))throw Error('CONFIRMATION_REPLAY_OR_TOKEN_STOP');
       const w=works.find(x=>x.id===d.work_id);append({type:'preview',workId:w.id,requestId:d.request_id,number:w.number,state:'VALIDATED_AWAITING_HUMAN_CONFIRMATION'});
       show('Prévia validada: habilitar somente Obra '+w.number+'. Sem lançamentos de horas. Confirme para enviar UMA confirmação auditada.');
       confirm.textContent='Confirmar habilitação da Obra '+w.number;confirm.disabled=false;await new Promise(resolve=>{approve=resolve;});
       commits.add(d.work_id);append({type:'confirmation',workId:w.id,requestId:d.request_id,state:'CONFIRM_DISPATCH_STARTED_NO_RETRY'});
      }else throw Error('CONFIRMATION_FLAG_STOP');
     }
    }else throw Error('METHOD_SCOPE_STOP');
    if(getSession()?.access_token!==frozenToken||getSession()?.user?.id!==frozenUser)throw Error('SESSION_CHANGED_BEFORE_REQUEST_STOP');
    const response=await fetch(u,{...opts,credentials:'omit',cache:'no-store',redirect:'error',signal:AbortSignal.timeout(60000)});
    if(getSession()?.access_token!==frozenToken||getSession()?.user?.id!==frozenUser)throw Error('SESSION_CHANGED_AFTER_REQUEST_STOP');
    lastRequest.http_status=response.status;
    if(method==='POST'&&u.endsWith('/fn_folha_piloto_configurar_v3')){const b=JSON.parse(opts.body);if(b.p_confirmar===false&&response.ok){const p=await response.clone().json();if(p.committed!==false||!p.versao)throw Error('PREVIEW_FORMAT_STOP');previews.set(b.p_dados.work_id,p.versao);}}
    return response;
   };
   transport=createSingleAttemptHoursTransport({getSession,config:window.PRIMELINE_CONFIG,fetchImpl:boundedFetch});
   const auth=await hoursReadOnlyPreflight({supabase:transport.supabase,verifyAuthUser:async()=>{const u=await transport.verifyAuthUser();if(u.id!==getSession()?.user?.id)throw Error('SESSION_IDENTITY_STOP');return u;},expectedCompanyId:DATA.manifest.companyId,workId:DATA.manifest.requiredWork120});
   append({type:'auth',verified:auth.verified,companyId:auth.companyId,actorId:auth.actorId,specialPowerDisabled:auth.canAssignSpecial===false});
   phase='cohort_state_read_only';
   for(const w of works){
    const live=await transport.readWork(w.id);if(live.id!==w.id||live.empresa_id!==DATA.manifest.companyId||live.situacao!=='em_curso')throw Error('LIVE_WORK_SCOPE_STOP');
    const response=await transport.supabase('rpc/fn_folha_piloto_contexto_v3',{method:'POST',body:JSON.stringify({p_obra_id:w.id})});if(!response.ok)throw Error('LIVE_WORK_STATE_NOT_LEGACY_ZERO_STOP');
    const c=await response.json();append({type:'read_only_work_state',workId:w.id,number:w.number,mode:['legado','piloto','suspenso'].includes(c.mode)?c.mode:'invalid',revision:Number.isSafeInteger(c.revision)&&c.revision>=0?c.revision:null});
    if(c.version!==3||c.work_id!==w.id||c.mode!=='legado'||c.revision!==0)throw Error('LIVE_WORK_STATE_NOT_LEGACY_ZERO_STOP');
   }
   append({type:'read_only_audit_complete',unconfiguredWorks:10,configuredWorks:0,activationRequests:0});phase='awaiting_explicit_recovery_start';
   show('Leitura concluída: dez obras em legado/revisão0. Nenhuma prévia ou confirmação enviada. Guarde o recibo de leitura. Iniciar recuperação exige a autorização específica V2; manutenção permanece ativa.');
   activate.disabled=false;await new Promise(resolve=>{resume=resolve;});allowWrites=true;phase='activation';
   const result=await activateFrozenHoursCohort({manifest:DATA.manifest,manifestSha256:DATA.manifestSha256,ledger:DATA.ledger,authorization:{activationApproved:true,project:DATA.manifest.project,reference:'RECOVERY_V2_FROM_STOP_ff0668ac: requires explicit versioned recovery authorization; original A/B/C/D and exact FINAL cohort preserved; operational GO reserved',workIds},authPreflight:auth,frontendEvidence:DATA.frontend,clientsDrained:true,supabase:transport.supabase,newRequestId:()=>crypto.randomUUID(),loadWorkReceipt:async id=>events.find(e=>e.type==='work'&&e.workId===id)||null,validateWorkStillInScope:async(id,company)=>{const w=await transport.readWork(id);return w.id===id&&w.empresa_id===company&&w.situacao==='em_curso';},saveReceipt:async e=>saveWork(e),reason:'Publicação P0 autorizada; manutenção mantida até GO funcional.'});
   if(!result.confirmed||result.works.length!==10)throw Error('COHORT_POSTCHECK_STOP');
   append({type:'complete',confirmedWorks:10,realHoursWritten:false,operationalGo:false});show('Dez obras confirmadas. Guarde o recibo. Manutenção permanece ativa; smoke e GO ainda pendentes.');
  });
 }catch(error){confirm.disabled=true;activate.disabled=true;approve=null;resume=null;const record={type:'stop',state:'STOP_NO_RETRY_KEEP_MAINTENANCE',phase,code:safeErrorCode(error),asset:currentAsset,request:lastRequest,previous_receipt_sha256:expectedPreviousHash};try{append(record);}catch{}download.disabled=events.length===0;show(JSON.stringify(record,null,2)+'\nSTOP. Não repita, não recarregue e não apague armazenamento. Guarde o recibo; mantenha papel e manutenção.');}
});
download.addEventListener('click',()=>{if(!events.length)return;const b=new Blob([JSON.stringify({format:'HOURS_COHORT_RECOVERY_V2_RECEIPT_V1',events,credentialsRecorded:false,operationalGo:false},null,2)],{type:'application/json'}),u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download='PRIMELINE-COHORT-RECOVERY-V2-RECEIPT.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);});
