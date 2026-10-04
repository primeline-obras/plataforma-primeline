// Só servidor local e respostas sintéticas; nenhum acesso à plataforma real.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const server=createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/'){res.setHeader('Content-Type','text/html');return res.end('<main id="rnc"></main>');}
 if(!/^\/src\/[a-z0-9-]+\.js$/.test(url.pathname)){res.statusCode=404;return res.end();}
 try{res.setHeader('Content-Type','text/javascript');res.end(await readFile(new URL('..'+url.pathname,import.meta.url)));}catch{res.statusCode=404;res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({channel:'msedge',headless:true});
try{
 for(const role of ['encarregado','administrativo','gerencia','diretor_obra','adjunto','preparador']){
  const page=await browser.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>route.request().url().startsWith(origin)?route.continue():route.abort());
  await page.goto(origin);
  const result=await page.evaluate(async role=>{
   const {createRncModule}=await import('/src/rnc.js');const calls=[],messages=[];
   const api=async(path,options={})=>{
    calls.push({path,method:options.method||'GET',body:options.body?JSON.parse(options.body):null});
    let value=[];
    if(path==='rpc/fn_pode_editar_obra')value=false;
    if(path==='rpc/fn_subempreitadas_operacionais_obra'||path.startsWith('subempreitadas?'))value=[{id:'s1',obra_id:'w120',fornecedor_id:'f1',especialidade:'Sintética'}];
    return new Response(JSON.stringify(value),{status:200});
   };
   const module=createRncModule({root:document.querySelector('#rnc'),supabase:api,isConfigured:true,getWorks:()=>[{id:'w120',numero:120,nome:'Obra sintética'}],getRole:()=>role,toast:m=>messages.push(m)});
   await module.show('w120');return {calls,messages,text:document.body.textContent};
  },role);
  assert.deepEqual(errors,[]);assert.deepEqual(result.messages,[]);
  assert.ok(result.text.includes('RNC'));
  const rpc=result.calls.filter(c=>c.path==='rpc/fn_subempreitadas_operacionais_obra');
  if(role==='encarregado'){
   assert.deepEqual(rpc,[{path:'rpc/fn_subempreitadas_operacionais_obra',method:'POST',body:{p_obra_id:'w120'}}]);
   assert.ok(!result.calls.some(c=>c.path.startsWith('subempreitadas?')));
  }else{assert.equal(rpc.length,0);assert.ok(result.calls.some(c=>c.path.startsWith('subempreitadas?')));}
  assert.ok(result.calls.every(c=>c.method==='GET'||c.path.startsWith('rpc/fn_')));
  await page.close();console.log('PASS RNC '+role);
 }
 const page=await browser.newPage();await page.goto(origin);
 const failed=await page.evaluate(async()=>{
  const {createRncModule}=await import('/src/rnc.js');const calls=[],messages=[];
  const api=async(path)=>{calls.push(path);return new Response(JSON.stringify(path==='rpc/fn_subempreitadas_operacionais_obra'?{message:'RPC indisponível'}:path==='rpc/fn_pode_editar_obra'?false:[]),{status:path==='rpc/fn_subempreitadas_operacionais_obra'?404:200});};
  const m=createRncModule({root:document.querySelector('#rnc'),supabase:api,isConfigured:true,getWorks:()=>[{id:'w120',numero:120,nome:'Sintética'}],getRole:()=>'encarregado',toast:m=>messages.push(m)});
  await m.show('w120');return {calls,messages};
 });
 assert.deepEqual(failed.messages,['RPC indisponível']);assert.ok(!failed.calls.some(c=>c.startsWith('subempreitadas?')));
 console.log('PASS RPC ausente: erro explícito, sem fallback direto');
}finally{await browser.close();await new Promise(r=>server.close(r));}
