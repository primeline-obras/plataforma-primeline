import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = await readFile(new URL('../src/supabase-browser.js', import.meta.url),'utf8');
const storage = () => { const m=new Map(); return {getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,v),removeItem:k=>m.delete(k)}; };
let sequence=0;
async function fixture(fetcher) {
  const sessionStorage=storage();
  sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:'A',refresh_token:'refresh-A',user:{id:'A'}}));
  globalThis.window={sessionStorage,localStorage:storage(),PRIMELINE_CONFIG:{supabaseUrl:'https://synthetic.test',supabaseAnonKey:'anon'},dispatchEvent(){}};
  globalThis.fetch=fetcher;
  return {auth:await import('data:text/javascript;base64,'+Buffer.from(source+'\n//'+sequence++).toString('base64')),sessionStorage};
}
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
test('logout quarantines synchronously before a slow remote logout finishes',async()=>{
  const pending=deferred(),events=[];const {auth}=await fixture(()=>pending.promise);
  auth.onSessionReset(reason=>events.push(reason));
  const logout=auth.signOut();
  assert.deepEqual(events,['session-cleared']);assert.equal(auth.getSession(),null);
  pending.resolve(new Response('{}'));await logout;
});
test('old REST response cannot populate a new identity, including a delayed body',async()=>{
  const pending=deferred();const {auth}=await fixture(()=>pending.promise);
  const request=auth.supabase('obras');auth.clearSession();
  pending.resolve(Response.json([{id:'private-A'}]));await assert.rejects(request,{name:'AbortError'});
  const body=deferred();globalThis.fetch=async()=>({status:200,json:()=>body.promise,text:async()=>'',blob:async()=>null,arrayBuffer:async()=>null,formData:async()=>null,clone(){return this;}});
  const response=await auth.supabase('obras');const parsed=response.json();auth.clearSession();body.resolve([{id:'private-A'}]);await assert.rejects(parsed,{name:'AbortError'});
});
test('late refresh cannot restore A after login B or clear B on failure',async()=>{
  for(const status of [200,400]) {
    const pending=deferred();const {auth}=await fixture(url=>url.includes('refresh_token')?pending.promise:Promise.resolve(Response.json({access_token:'B',user:{id:'B'}})));
    const refresh=auth.refreshSession();await auth.signIn('synthetic@invalid.test','synthetic');
    pending.resolve(Response.json({access_token:'A',user:{id:'A'}},{status}));await assert.rejects(refresh,{name:'AbortError'});
    assert.equal(auth.getSession().user.id,'B');
  }
});
test('identity replacement is detected, but token renewal of the same user is not a reset',async()=>{
  const {auth,sessionStorage}=await fixture(async()=>Response.json({access_token:'renewed',user:{id:'A'}}));const events=[];
  auth.onSessionReset(x=>events.push(x));await auth.refreshSession();assert.deepEqual(events,[]);
  sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:'B',user:{id:'B'}}));auth.getSession();
  assert.deepEqual(events,['identity-changed']);await assert.rejects(auth.supabase('obras'),{name:'AbortError'});
});
test('new login resets before credentials are sent and prevents an older concurrent login winning',async()=>{
  const pending=deferred();const {auth}=await fixture(url=>pending.promise);const events=[];auth.onSessionReset(x=>events.push(x));
  const login=auth.signIn('a@invalid.test','synthetic');assert.deepEqual(events,['login-start']);auth.clearSession();
  pending.resolve(Response.json({access_token:'A',user:{id:'A'}}));await assert.rejects(login,{name:'AbortError'});assert.equal(auth.getSession(),null);
});
test('401 without refresh credentials clears the protected session; 403 does not log out',async()=>{
  const {auth,sessionStorage}=await fixture(async()=>Response.json({message:'expired'},{status:401}));
  sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:'A',user:{id:'A'}}));
  await assert.rejects(auth.supabase('obras'),{name:'AbortError'});assert.equal(auth.getSession(),null);
  const next=await fixture(async()=>Response.json({message:'not allowed'},{status:403}));
  assert.equal((await next.auth.supabase('obras')).status,403);assert.equal(next.auth.getSession().user.id,'A');
});
test('a delayed private Storage download cannot be returned to the next session',async()=>{
  const pending=deferred();const {auth}=await fixture(()=>pending.promise);
  const download=auth.downloadWorkDocument('synthetic/private.pdf');auth.clearSession();
  pending.resolve(new Response('synthetic-private-bytes'));await assert.rejects(download,{name:'AbortError'});
});
