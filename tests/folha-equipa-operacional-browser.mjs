import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url)),shots=path.join(os.tmpdir(),'primeline-folha-equipa-20261010');await mkdir(shots,{recursive:true});
const server=createServer(async(req,res)=>{try{const pathname=new URL(req.url,'http://localhost').pathname;if(pathname==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><link rel="stylesheet" href="/src/workforce-calendar.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><style>body{margin:0;font:16px Arial}#root{max-width:100%}button{min-height:48px}.action-task{display:flex;flex-wrap:wrap;gap:8px}.action-calendar-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr))}.action-calendar-grid>*{min-width:0;overflow-wrap:anywhere}</style><div id="root"></div>');}const f=path.resolve(repo,'.'+pathname);if(!f.startsWith(repo))throw Error('path');res.setHeader('Content-Type',pathname.endsWith('.js')?'text/javascript':'text/css');res.end(await readFile(f));}catch{res.statusCode=404;res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({headless:true,...(process.env.PLANNING_CHROMIUM_EXE?{executablePath:process.env.PLANNING_CHROMIUM_EXE}:{})});let pass=0;const errors=[];
const appSource=await readFile(path.join(repo,'src/app.js'),'utf8');
const vacationRenderer=appSource.slice(appSource.indexOf('function renderVacationMap('),appSource.indexOf('\nfunction entityDocuments('));
async function setup(page){await page.goto(base);await page.evaluate(async()=>{
 const {createAttendanceModule}=await import('/src/attendance-sheet.js');window.calls=[];window.messages=[];window.team=[{id:'p',name:'Operacional sintético',role:'Pedreiro',delegation:null,start:'2026-10-01'}];window.facts={};window.externals=[];
 const row=p=>({person_id:p.id,name:p.name,role:p.role,delegation:p.delegation,can_write:true,can_remove:!window.facts[p.id],team_revision:1,revision:window.facts[p.id]?1:0,period:'dia_inteiro',expected_minutes:480,sheet:window.facts[p.id]||null});
 window.transport=async(name,opts)=>{const b=JSON.parse(opts.body);calls.push({name,b});
  if(name.endsWith('fn_folha_contexto_v2'))return Response.json({version:2,team_contract:1,date:b.p_data,work_id:b.p_obra_id,works:[{id:'work',name:'Obra sintética',number:120}],rows:team.filter(p=>p.start<=b.p_data&&(!p.end||p.end>b.p_data)).map(row),external_rows:externals.filter(x=>x.date===b.p_data).map(x=>({...row(x),provider_name:'Fornecedor sintético',sheet:x.sheet})),permissions:{write:true,external_write:true,allocation_write:true},providers:[{id:'provider',name:'Fornecedor sintético'}],external_people:[],office_available:false,admin:false,management:false,schedule:null,calendar_verified:false,overtime_generation:'disabled_pending_compatibility',delegation:'lisboa'});
  if(name.endsWith('fn_folha_pessoas_v2'))return Response.json({version:2,people:[{person_id:'p2',name:'Pessoa disponível',role:'Servente',delegation:null,can_allocate:true,team_revision:0},{person_id:'p3',name:'Pessoa Algarve',role:'Pedreiro',delegation:'algarve',can_allocate:true,team_revision:0}]});
  if(name.endsWith('fn_folha_historico_v2'))return Response.json({version:2,events:[{action:'save',reason:'Histórico preservado'}],legacy:[],legacy_interpretation:'original'});
  if(name.endsWith('fn_equipa_operar_v2')||name.endsWith('fn_folha_operar_v2')){
   if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'preview',summary:'Confirmar?'});
   const d=b.p_dados;let keys;
   if(b.p_acao==='team_add'){for(const p of d.people)team.push({id:p.person_id,name:p.person_id,role:'Pedreiro',start:d.date});keys=d.people.map(p=>({kind:'primeline',person_id:p.person_id,work_id:d.work_id,date:d.date}));}
   if(b.p_acao==='team_remove'){for(const p of d.people)team.find(x=>x.id===p.person_id).end=d.date;keys=d.people.map(p=>({kind:'primeline',person_id:p.person_id,work_id:d.work_id,date:d.date}));}
   if(b.p_acao==='save'){facts[d.key.person_id]={intervals:d.intervals,state:'registered'};keys=[d.key];}
   if(b.p_acao==='external_register'){const p={id:d.request_id,name:d.name,role:d.role,date:d.date,sheet:{intervals:d.intervals,state:'registered'}};externals.push(p);keys=[{kind:'external',person_id:p.id,date:d.date,work_id:d.work_id}];}
   return Response.json({version:2,committed:true,request_id:d.request_id,changed_keys:keys});
  }
  throw Error('Endpoint inesperado '+name);
 };
 window.module=createAttendanceModule({root:document.querySelector('#root'),supabase:transport,isConfigured:true,toast:(m)=>messages.push(m),confirm:async()=>true,now:()=>new Date('2026-10-10T18:00:00Z')});await module.show();
});}
try{
 for(const width of [375,430,768,1440]){
  const page=await browser.newPage({viewport:{width,height:1000}});page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});await page.route('**/*',route=>new URL(route.request().url()).hostname==='127.0.0.1'?route.continue():new URL(route.request().url()).hostname==='fonts.googleapis.com'?route.fulfill({status:200,contentType:'text/css',body:'/* Font stylesheet stub: synthetic test has no external network. */'}):route.abort());await setup(page);
  assert.equal(await page.locator('.sheet-person').count(),1);assert.equal(await page.locator('[data-sheet-management]').textContent(),'');assert.ok(!(await page.locator('#root').textContent()).includes('Geração automática'));pass++;
  await page.locator('[data-sheet-date]').fill('2026-10-09');await page.waitForFunction(()=>calls.at(-1)?.b?.p_data==='2026-10-09');assert.equal(await page.locator('.sheet-person').count(),1);pass++;
  await page.locator('[data-sheet-edit=p]').click();await page.locator('[name=start0]').fill('08:00');await page.locator('[name=end0]').fill('12:00');await page.locator('[name=start1]').fill('13:00');await page.locator('[name=end1]').fill('16:00');assert.equal(await page.locator('[data-sheet-total]').textContent(),'TOTAL: 7h');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>facts.p);assert.match(await page.locator('.sheet-person').first().textContent(),/TOTAL: 7h/);pass++;
  await page.locator('[data-sheet-add]').click();await page.locator('[data-sheet-candidate]').first().waitFor();assert.equal(await page.locator('[data-sheet-candidate]').count(),2);assert.match(await page.locator('[data-sheet-detail]').textContent(),/DELEGAÇÃO POR CONFIGURAR/);assert.match(await page.locator('[data-sheet-detail]').textContent(),/ALGARVE/);await page.locator('[data-sheet-candidate=p2]').check();await page.locator('[data-sheet-candidate=p3]').check();await page.locator('[data-sheet-add-selected]').click();await page.waitForFunction(()=>team.length===3);assert.equal(await page.evaluate(()=>calls.filter(x=>x.b.p_acao==='team_add').length),2);pass++;
  for(const [name,intervals,total] of [['Externo 6h',[['10:00','16:00']],'6h'],['Externo 7h',[['08:00','12:00'],['13:00','16:00']],'7h']]){
   await page.locator('[data-sheet-add-external]').click();await page.evaluate(()=>{const p=document.querySelector('[name=provider_id]');p.add(new Option('Fornecedor sintético','provider'));});await page.locator('[name=provider_id]').selectOption('provider');
   // Provider authorization comes from the loaded context, exactly as production.
   await page.locator('[name=name]').fill(name);await page.locator('[name=role]').selectOption('servente');for(let i=0;i<intervals.length;i++){await page.locator('[name=start'+i+']').fill(intervals[i][0]);await page.locator('[name=end'+i+']').fill(intervals[i][1]);}
   assert.equal(await page.locator('[data-sheet-total]').textContent(),'TOTAL: '+total);await page.locator('[name=reason]').fill('Factos sintéticos');
   await page.locator('[data-sheet-external-form] button[type=submit]').click();await page.waitForFunction(n=>externals.some(p=>p.name===n),name);assert.ok((await page.locator('.sheet-person').allTextContents()).some(t=>t.includes(name)&&t.includes('TOTAL: '+total)));pass++;
  }
  assert.equal(await page.locator('[data-sheet-bulk=normal]').isDisabled(),true);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(shots,'folha-'+width+'.png')});pass++;
  await page.evaluate(async()=>{team=[];externals=[];await module.refresh();});assert.match(await page.locator('[data-sheet-summary]').textContent(),/SEM EQUIPA/);assert.ok(!(await page.locator('[data-sheet-summary]').textContent()).includes('DIA COMPLETO'));pass++;
  await page.evaluate(async()=>{
   document.querySelector('#root').innerHTML='';const {createActionPlanModule}=await import('/src/action-plan.js');window.taskReports=[];window.planningState='em_execucao';window.role='encarregado';window.planCalls=[];
   const rpc=async(url,options)=>{const b=options?JSON.parse(options.body):null;planCalls.push({url,b});
    if(url.startsWith('fases?'))return Response.json([{id:'phase',obra_id:'work'}]);
    if(url.startsWith('planeamento_itens?'))return Response.json([{id:'task',fase_id:'phase',codigo:'F01.1',descricao:'Trabalho sintético',estado:planningState,data_inicio_prevista:'2020-01-01',data_fim_prevista:'2020-01-02'}]);
    if(url.endsWith('fn_folha_gestao_contexto_v2'))return Response.json({version:2,tasks:[],task_reports:taskReports,overtime:[],history:[],permissions:{admin:false,he_review:false,task_report:role==='encarregado',task_review:role==='diretor_obra'}});
    if(url.endsWith('fn_folha_gestao_v2')){if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'report-preview'});taskReports=[{tarefa_id:'task',estado:'reported',reportado_por:'foreman',reportado_em:'2026-10-10T18:00:00Z'}];return Response.json({version:2,committed:true,request_id:b.p_dados.request_id,revision:1});}
    throw Error('Endpoint inesperado '+url);
   };
   window.messages=[];window.plan=createActionPlanModule({toast:(m,type)=>messages.push({m,type}),root:document.querySelector('#root'),supabase:rpc,isConfigured:true,getWorks:()=>[{id:'work',numero:120}],getRole:()=>role,confirm:async()=>true});await plan.show();
  });
  await page.locator('[data-action-report]').click();await page.waitForFunction(()=>document.querySelector('#root').textContent.includes('AGUARDA CONFIRMAÇÃO DO DIRETOR'));
  assert.equal(await page.evaluate(()=>planningState),'em_execucao');assert.equal(await page.evaluate(()=>messages.some(x=>x.type==='error')),false);assert.equal(await page.locator('[data-action-report]').count(),0);assert.equal(await page.evaluate(()=>planCalls.filter(x=>x.b?.p_confirmar).length),1);pass++;
  await page.evaluate(async()=>{role='diretor_obra';await plan.refresh();});assert.equal(await page.locator('[data-action-report]').count(),0);assert.match(await page.locator('#root').textContent(),/CONCLUSÃO REPORTADA/);pass++;
  await page.evaluate(source=>{
   const selectedVacationMonth='2026-10',vacationMonthBounds=()=>({start:'2026-10-01',end:'2026-10-31',days:31}),isVacation=x=>x.tipo==='ferias',compareVacationPeople=(a,b)=>a.nome.localeCompare(b.nome),activeHoliday=()=>null,personFunctionClass=()=>'',formatOptionalDate=x=>x;
   const safeText=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
   const renderer=eval('('+source+')');document.querySelector('#root').innerHTML=renderer([{id:'p',nome:'Pedreiro sintético'},{id:'d',nome:'Diretor sintético'},{id:'a',nome:'Administrativo sintético'}],[{colaborador_id:'d',data:'2026-10-12',tipo:'ferias'}]);
  },vacationRenderer);
  assert.equal(await page.locator('.vacation-map-row').count(),3);assert.match(await page.locator('#root').textContent(),/Diretor sintético/);assert.equal(await page.locator('form,input,select').count(),0);assert.equal(await page.locator('.vacation-map-row i.vacation').count(),1);pass++;
  await page.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({pass,fail:0,consoleErrors:errors.length,screenshots:shots,backend:'Mocks sintéticos; autorização e persistência verificadas na suite PostgreSQL.'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
