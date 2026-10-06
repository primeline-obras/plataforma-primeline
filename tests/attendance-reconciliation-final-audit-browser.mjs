import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const scenes=JSON.parse(await readFile(path.join(tmpdir(),'primeline-reconciliation-final-audit','synthetic-contexts.json'),'utf8'));
assert.equal(scenes.length,12,'Run attendance-backend-v2.test.mjs on this audit branch first.');
const repo=fileURLToPath(new URL('../',import.meta.url)),errors=[];let pass=0;
const labels={registered:'Registado',regularization:'Regularização',missing:'Horas em falta',open:'Em aberto'};
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/favicon.ico'){res.writeHead(204);return res.end();}
  if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<html data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div></html>');}
  const p=new URL(req.url,'http://local').pathname;if(!p.startsWith('/src/'))throw Error('denied');
  res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(repo,p)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:true});
try{
 for(const width of [1440,820,390])for(const scene of scenes){
  const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.evaluate(async scene=>{
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');window.rpcNames=[];
   window.sheet=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:()=>{},now:()=>new Date(scene.context.date+'T18:00:00Z'),supabase:async(name,options)=>{
    const b=JSON.parse(options.body);rpcNames.push(name);
    if(name.endsWith('fn_folha_contexto_v2'))return Response.json(b.p_obra_id?scene.context:{...scene.context,work_id:null,rows:[],external_rows:[]});
    if(name.endsWith('fn_folha_gestao_contexto_v2'))return Response.json({version:2,permissions:{admin:false,he_review:false,task_report:false,task_review:false},tasks:[],task_reports:[],overtime:[],history:[]});
    throw Error('Audit browser forbids every write RPC: '+name);
   }});await sheet.show();
  },scene);
  await page.locator('[data-sheet-work]').selectOption(scene.context.work_id);
  await page.waitForFunction(()=>!!document.querySelector('.sheet-person b'));
  assert.equal(await page.locator('.sheet-person b').innerText(),labels[scene.state],`${width} ${scene.label}`);
  const text=await page.locator('[data-sheet-summary]').innerText();assert.match(text,new RegExp(`${scene.context.summary.pending} pendentes`));
  assert.equal(text.includes('DIA COMPLETO'),scene.context.summary.complete);
  assert.equal(await page.evaluate(()=>rpcNames.some(n=>n.endsWith('fn_folha_operar_v2')||n.endsWith('fn_folha_gestao_v2'))),false);
  pass++;await page.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({pass,fail:0,pageErrors:errors.length,viewports:3,source:'Independent PostgreSQL synthetic contexts rendered by unchanged candidate UI; no real backend/write'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
