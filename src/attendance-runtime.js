import {createHoursAttemptJournal} from './attendance-hours-attempts.js?v=hours-module-5a03c3b2a65f';
import {createAttendanceModule as createLegacyAttendanceModule} from './attendance-sheet.js?v=hours-module-33b5d5854983';
import {HOURS_RUNTIME_RELEASE} from './hours-runtime-config.js?v=hours-activated-20261106';
export function hoursReleaseState(release){
 if(release?.version!==1||typeof release.enabled!=='boolean')return 'blocked';
 if(release.enabled===false)return 'legacy';
 return release.activationApproved===true&&release.backend?.stage6Postcheck==='DAILY_V2_POSTCHECK_PASS_NOT_ACTIVATED'&&release.backend?.ad15Postcheck==='AD15_POSTCHECK_OK'&&release.backend?.remainingV3ChainVerified===true?'v3':'blocked';
}
// The existing Folha entrypoint is preserved. Tests inject synthetic release data
// through the constructor; the application never reads activation from browser storage.
export function createAttendanceModule(options){
 const release=structuredClone(options.hoursRuntimeRelease??HOURS_RUNTIME_RELEASE);
 const mode=hoursReleaseState(release),root=options.root;
 const attemptJournal=options.isConfigured?createHoursAttemptJournal({storage:()=>{if(!globalThis.window?.localStorage)throw Error('CHECKPOINT_STORAGE_UNAVAILABLE');return window.localStorage;},identity:()=>{const v=options.getIdentity?.();return Array.isArray(v)?{actor_id:v[0],company_id:v[1]}:v;}}):createHoursAttemptJournal();
 let controller=null,initializing=null,generation=0,dead=false;
 function reset(){generation++;controller?.reset?.();controller=null;initializing=null;root.replaceChildren();}
 const unsubscribe=options.onSessionReset?.(()=>reset());
 function blocked(){root.replaceChildren();const panel=document.createElement('section');panel.className='sheet-v2';const p=document.createElement('p');p.setAttribute('role','status');p.textContent='Gestão de Horas V3 indisponível: aguarda instalação verificada e aprovação de ativação.';panel.append(p);root.append(panel);}
 async function initialize(){
  if(controller)return controller;if(initializing)return initializing;const token=generation;
  initializing=(async()=>{
   if(mode==='blocked'){blocked();return null;}
   let factory=createLegacyAttendanceModule;
   if(mode==='v3'){
    const module=await import('./attendance-sheet-v3.js?v=hours-module-b38552af2c51');if(dead||token!==generation)return null;factory=module.createAttendanceModule;
    for(const file of ['attendance-hours-editor.css','attendance-hours-review.css']){
     const href=new URL('./'+file+'?v='+(file==='attendance-hours-review.css'?'hours-module-6b8ac73313d6':'hv3d-6'),import.meta.url).href;
     if(![...document.querySelectorAll('link[data-hours-runtime-style]')].some(l=>l.href===href)){const link=document.createElement('link');link.rel='stylesheet';link.href=href;link.dataset.hoursRuntimeStyle='';document.head.append(link);}
    }
   }
   if(dead||token!==generation)return null;
   const host=document.createElement('div');host.dataset.hoursRuntime=mode;root.replaceChildren(host);
   const current=()=>{if(dead||token!==generation){const e=Error('Sessão alterada. Reabra a Folha de Ponto.');e.code='42501';throw e;}};
   const transport=async(...args)=>{current();const r=await options.supabase(...args);current();return {ok:r.ok,status:r.status,json:async()=>{const j=await r.json();current();return j;}};};
   controller=factory({...options,attemptJournal,root:host,supabase:transport,integratedHours:mode==='v3'});return controller;
  })();
  try{return await initializing;}finally{if(token===generation)initializing=null;}
 }
 async function show(context={}){if(dead)return;const token=generation;try{const c=await initialize();if(c&&token===generation&&!dead)return await c.show(context);}catch(e){if(token===generation&&!dead){root.replaceChildren();const p=document.createElement('p');p.setAttribute('role','alert');p.textContent='A Folha de Ponto não está disponível. Reabra a consulta.';root.append(p);}}}
 return {show,refresh:()=>show(),reset,destroy(){if(dead)return;reset();dead=true;unsubscribe?.();}};
}
