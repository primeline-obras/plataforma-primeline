// Local modules, synthetic responses only; all external traffic blocked.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const screenshots=path.join(tmpdir(),'primeline-security-visibility-browser');await mkdir(screenshots,{recursive:true});
const server=createServer(async(req,res)=>{try{const p=new URL(req.url,'http://local').pathname;
 if(p==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div>');}
 if(!p.startsWith('/src/'))throw Error('Forbidden');res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(process.cwd(),p)));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({channel:'msedge',headless:true});let groups=0;const errors=[];
try {for(const width of [1440,820,390]) {
 const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.fulfill({status:200,body:'',contentType:'text/css'}));await page.goto(url);
 for(const reviewed of [false,true,false]){
  await page.evaluate(async reviewed=>{const {createAttendanceModule}=await import('/src/attendance-sheet.js');
   document.querySelector('#root').replaceChildren();window.calls=[];const row={person_id:'p',name:'Pessoa sintética',role:'Pedreiro',special_day:true,special_reviewed:reviewed,special_review_pending:!reviewed,expected_minutes:480,revision:reviewed?2:3,can_write:false,can_remove:false,sheet:{state:'registered',intervals:[{start:'09:00',end:'17:00'}]},overtime:{estado:reviewed?'none':'pending_rule'}};
   const module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:()=>{},now:()=>new Date('2026-10-06T19:00:00Z'),supabase:async(name,o)=>{calls.push(name);const b=JSON.parse(o.body);return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Sintética'}],rows:b.p_obra_id?[row]:[],external_rows:[],permissions:{write:false,allocation_write:false,external_write:false},admin:false,office_available:false,correction_days:1,special_day:true});}});await module.show();
  },reviewed);
  await page.locator('[data-sheet-work]').selectOption('own');await page.waitForSelector('.sheet-person');const text=await page.locator('#root').textContent(),summary=await page.locator('[data-sheet-summary]').textContent();
  if(reviewed){assert.match(text,/DIA ESPECIAL · REVISTO/);assert.doesNotMatch(text,/REQUER REVISÃO/);assert.match(summary,/0 pendentes.*DIA COMPLETO/);}else{assert.match(text,/REQUER REVISÃO/);assert.doesNotMatch(text,/· REVISTO/);assert.match(summary,/1 pendentes/);assert.doesNotMatch(summary,/DIA COMPLETO/);}
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2));assert.ok(await page.evaluate(()=>calls.every(n=>n==='rpc/fn_folha_contexto_v2')));groups++;
 }
 for(const role of ['diretor_obra','adjunto','encarregado','administrativo','gestao_plataforma','gerencia']){
  await page.evaluate(async role=>{const {createAttendanceManagementModule}=await import('/src/attendance-management.js');document.querySelector('#root').replaceChildren();const admin=['administrativo','gestao_plataforma','gerencia'].includes(role),adm=role==='administrativo',he_review=['diretor_obra','adjunto'].includes(role);
   // Deliberately broad old response: UI protection is tested separately from SQL minimization.
   window.module=createAttendanceManagementModule({toast:()=>{},confirm:async()=>true,supabase:async()=>Response.json({version:2,permissions:{admin,adm,he_review,task_report:false,task_review:false},overtime:role==='encarregado'?[]:[{id:'h',folha_id:'f',folha_revision:1,revision:3,minutes:60,estado:'validated_pending_rule',processado_em:'ADMIN_DATE_SENTINEL',processado_por:'ADMIN_ACTOR_SENTINEL',prazo_processamento:'ADMIN_DEADLINE_SENTINEL',person_name:'Pessoa sintética',sheet:{date:'2026-09-18',intervals:[]}}],history:[{action:'he_approve',dominio:'he',antes:{minutes:60,processado_em:'ADMIN_HISTORY_SENTINEL'},depois:{estado:'pending_validation',prazo_processamento:'ADMIN_HISTORY_SENTINEL'}},{action:'he_process',dominio:'administrativo',antes:null,depois:{processado:true}}],tasks:[],task_reports:[],people:[],vacations:[],entitlements:[],vacation_revision:0,payroll:[],live_facts:{sheets:[]},config:{calendar_complete:true,calendar_validated_years:[2026]}})});await module.show(document.querySelector('#root'),{workId:'own',date:'2026-10-06'});
  },role);
  const admin=['administrativo','gestao_plataforma','gerencia'].includes(role),text=await page.locator('#root').textContent();
  if(admin){assert.match(text,/Pago \/ processado/);assert.match(text,/ADMIN_DEADLINE_SENTINEL/);}else{assert.doesNotMatch(text,/Pago \/ processado|Prazo|ADMIN_/);assert.equal(await page.locator('[data-management-action=he_validate],[data-management-action=he_process]').count(),0);}
  if(role==='encarregado')assert.equal(await page.locator('[data-management-tab=he]').count(),0);groups++;
  await page.locator('[data-management-tab=tasks]').click();if(!admin)assert.doesNotMatch(await page.locator('#root').textContent(),/ADMIN_|he_process|processado_em|prazo_processamento/);groups++;
 }
 for(const reviewed of [false,true,false]){
  await page.evaluate(async reviewed=>{const {createAttendanceManagementModule}=await import('/src/attendance-management.js');document.querySelector('#root').replaceChildren();window.module=createAttendanceManagementModule({toast:()=>{},confirm:async()=>true,supabase:async()=>Response.json({version:2,permissions:{admin:true,adm:true,he_review:false,task_report:false,task_review:false},overtime:[],history:[],tasks:[],task_reports:[],people:[{id:'p',name:'Sintético'}],vacations:[],entitlements:[],vacation_revision:0,payroll:[],config:{calendar_complete:true,calendar_validated_years:[2026]},live_facts:{sheets:[{id:'f',date:'2026-10-03',minutes:480,state:'registered',special_day:true,special_reviewed:reviewed}],absences:[],pending_days:[],legacy_days:[]}})});await module.show(document.querySelector('#root'),{date:'2026-10-06',workId:null});},reviewed);
  await page.locator('[data-management-tab=payroll]').click();await page.locator('[data-management-person]').selectOption('p');await page.waitForSelector('[data-management-payroll]');const text=await page.locator('#root').textContent();
  if(reviewed){assert.match(text,/DIA ESPECIAL · REVISTO/);assert.doesNotMatch(text,/REQUER REVISÃO/);assert.match(text,/2 factos pendentes/);assert.equal(await page.locator('[data-management-special]').count(),0);}else{assert.match(text,/REQUER REVISÃO/);assert.match(text,/3 factos pendentes/);assert.equal(await page.locator('[data-management-special]').count(),1);}groups++;
 }
 await page.screenshot({path:path.join(screenshots,`payroll-${width}.png`),fullPage:true});await page.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({groups,fail:0,viewports:3,profiles:6,errors,screenshots}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
