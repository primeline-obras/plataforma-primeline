import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
test('collaborator filter is default; opt-out is explicit, boolean and GET-only',async()=>{
 const source=await readFile(new URL('../src/supabase-browser.js',import.meta.url),'utf8');
 const oldWindow=globalThis.window,oldFetch=globalThis.fetch;
 try{
  globalThis.window={PRIMELINE_CONFIG:{supabaseUrl:'https://example.test',supabaseAnonKey:'anon'},sessionStorage:{getItem:()=>null},localStorage:{removeItem(){}}};
  const calls=[];globalThis.fetch=async(url,options)=>{calls.push({url:new URL(url),options});return Response.json([]);};
  const {supabase}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const path of ['colaboradores?select=id','colaboradores?id=eq.test','colaboradores?data_saida=not.is.null&includeInactiveCollaborators=true','colaboradores?or=(data_saida.not.is.null)']){
   await supabase(path);assert.equal(calls.at(-1).url.searchParams.get('data_saida'),'is.null');
  }
  await supabase('colaboradores?id=eq.test',{includeInactiveCollaborators:true});assert.equal(calls.at(-1).url.searchParams.has('data_saida'),false);assert.equal(Object.hasOwn(calls.at(-1).options,'includeInactiveCollaborators'),false);
  await supabase('colaboradores?data_saida=not.is.null',{includeInactiveCollaborators:true});assert.equal(calls.at(-1).url.searchParams.get('data_saida'),'not.is.null');
  for(const options of [{includeInactiveCollaborators:'true'},{includeInactiveCollaborators:true,method:'PATCH'}]){await supabase('colaboradores?id=eq.test',options);assert.equal(calls.at(-1).url.searchParams.get('data_saida'),'is.null');}
  await supabase('viaturas?select=*',{headers:{Prefer:'return=representation'}});assert.equal(calls.at(-1).url.search,'?select=*');assert.equal(calls.at(-1).options.headers.Prefer,'return=representation');
 }finally{globalThis.window=oldWindow;globalThis.fetch=oldFetch;}
});
