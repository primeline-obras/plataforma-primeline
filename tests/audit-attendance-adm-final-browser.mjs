// Contract/UI audit, local mocks matching independently verified PostgreSQL projections.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const screenshots=path.join(tmpdir(),'primeline-audit-adm-final');await mkdir(screenshots,{recursive:true});
const server=createServer(async(req,res)=>{try{const p=new URL(req.url,'http://local').pathname;if(p==='/'){res.setHeader('Content-Type','text/html');return res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div>');}if(!p.startsWith('/src/'))throw Error('Forbidden');res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(process.cwd(),p)));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const browser=await chromium.launch({channel:'msedge',headless:true});const checks=[],errors=[];
const check=(name,fn)=>{try{fn();checks.push({name,pass:true});}catch(e){checks.push({name,pass:false,reason:e.message});}};
try{for(const width of [1440,820,390]){
 const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());await page.goto('http://127.0.0.1:'+server.address().port);
 await page.evaluate(async()=>{const {createAttendanceModule}=await import('/src/attendance-sheet.js');const row={person_id:'p',name:'Synthetic reviewed day',role:'Pedreiro',special_day:true,special_review_pending:false,expected_minutes:480,revision:2,can_write:false,can_remove:false,sheet:{state:'registered',intervals:[{start:'09:00',end:'17:00'}]},overtime:{estado:'pending_rule'}};
 const module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:()=>{},now:()=>new Date('2026-10-06T19:00:00Z'),supabase:async(name,options)=>{const b=JSON.parse(options.body);return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Synthetic'}],rows:[row],external_rows:[],permissions:{write:false,allocation_write:false,external_write:false},admin:false,office_available:false,correction_days:1,special_day:true,management:false});}});await module.show();});
 await page.locator('[data-sheet-date]').fill('2026-09-12');await page.locator('[data-sheet-work]').selectOption('own');await page.waitForFunction(()=>document.querySelector('[data-sheet-summary]'));
 const text=await page.locator('#root').innerText();check(width+': reviewed summary complete',()=>assert.match(text,/0 pendentes.*DIA COMPLETO/));check(width+': reviewed day does not claim pending review',()=>assert.doesNotMatch(text,/REQUER REVISÃO/));
 await page.screenshot({path:path.join(screenshots,'reviewed-'+width+'.png'),fullPage:true});
 for(const role of ['diretor_obra','adjunto']){
  await page.evaluate(async()=>{const {createAttendanceManagementModule}=await import('/src/attendance-management.js');const root=document.querySelector('#root');root.replaceChildren();const m=createAttendanceManagementModule({toast:()=>{},supabase:async()=>Response.json({version:2,permissions:{admin:false,adm:false,he_review:true,task_report:false,task_review:true},tasks:[],task_reports:[],history:[],overtime:[{id:'h',estado:'validated_pending_rule',minutes:60,folha_id:'f',folha_revision:1,processado_em:'2026-10-06T12:00:00Z',processado_por:'actor',prazo_processamento:'2026-10-06',sheet:{date:'2026-09-01',intervals:[]},person_name:'Synthetic'}]})});await m.show(root,{workId:'own',date:'2026-09-01'});});
  const he=await page.locator('#root').innerText(),processButtons=await page.locator('[data-management-action=he_process]').count();check(width+': '+role+' no write process action',()=>assert.equal(processButtons,0));
  check(width+': '+role+' administrative process details not displayed',()=>assert.doesNotMatch(he,/Pago \/ processado|Prazo: 2026-10-06/));
  await page.screenshot({path:path.join(screenshots,role+'-'+width+'.png'),fullPage:true});
 }
 await page.close();
}
check('console clean',()=>assert.deepEqual(errors,[]));console.log(JSON.stringify({pass:checks.filter(x=>x.pass).length,fail:checks.filter(x=>!x.pass).length,checks,pageErrors:errors.length,screenshots}));if(checks.some(x=>!x.pass))process.exitCode=1;
}finally{await browser.close();await new Promise(r=>server.close(r));}
