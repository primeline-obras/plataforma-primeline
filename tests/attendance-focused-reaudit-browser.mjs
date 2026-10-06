import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url));
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/'){res.setHeader('Content-Type','text/html');return res.end('<meta charset="utf-8"><div id="root"></div>');}
  const p=new URL(req.url,'http://local').pathname;
  if(!p.startsWith('/src/')){res.writeHead(404);return res.end();}
  res.setHeader('Content-Type','text/javascript');res.end(await readFile(path.join(repo,p)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:true});let observations=0;const errors=[];
try{
 for(const width of [1440,820,390]){
  const page=await browser.newPage({viewport:{width,height:900}});
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.evaluate(async()=>{
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');
   window.calls=[];window.rows=[];
   window.module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:()=>{},now:()=>new Date('2026-09-24T12:00:00Z'),supabase:async(name,options)=>{
    calls.push(name);if(!name.endsWith('fn_folha_contexto_v2'))throw Error('Unexpected RPC');
    const b=JSON.parse(options.body);
    return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Synthetic'}],rows,external_rows:[],permissions:{write:false,allocation_write:false,external_write:false},schedule:null});
   }});await module.show();
  });
  assert.equal(await page.locator('[data-sheet-history]').count(),0);
  assert.equal(await page.evaluate(()=>calls.some(n=>n.endsWith('fn_folha_historico_v2'))),false);observations++;
  await page.evaluate(async()=>{rows=[{person_id:'p',name:'Synthetic',role:'Synthetic',sheet:null,absence:{tipo:'falta_injustificada',estado:'ausente_pendente'},expected_minutes:480,revision:0,can_write:false}];await module.refresh();});
  const body=await page.locator('#root').innerText();
  assert.match(body,/Ausência/);assert.match(body,/0 pendentes.*DIA COMPLETO/);
  assert.doesNotMatch(body,/Justificação pendente|ausente_pendente/);observations++;
  await page.close();
 }
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({observations,fail:0,pageErrors:0,meaning:'Reproduces two P2 findings; successful evidence assertions do not mean product acceptance. MOCK ONLY.'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
