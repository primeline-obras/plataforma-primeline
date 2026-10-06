// Local frontend only, synthetic RPCs. External traffic is blocked.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const folder=path.join(tmpdir(),'primeline-adm-rules-browser');await mkdir(folder,{recursive:true});
const server=createServer(async(req,res)=>{try{const p=new URL(req.url,'http://local').pathname;
 if(p==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div>');}
 if(!p.startsWith('/src/'))throw Error('Forbidden');res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(process.cwd(),p)));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const url='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({channel:'msedge',headless:true});let groups=0;const errors=[];
try {for(const width of [1440,820,390])for(const role of ['administrativo','gestao_plataforma','encarregado']){
 const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());await page.goto(url);
 await page.evaluate(async role=>{
  const {createAttendanceManagementModule}=await import('/src/attendance-management.js');const admin=role!=='encarregado',adm=role==='administrativo';
  window.calls=[];window.toasts=[];window.events=[];window.vacations=[];window.vrevision=0;window.entitlements=[];window.payroll=[];
  window.config={revision:1,correction_days:1,office_expected_minutes:480,calendar_complete:true,calendar_validated_years:[2026],holiday_dates:['2026-10-12'],he_eligible_roles:['pedreiro','servente']};
  window.he={id:'he',obra_id:'own',folha_id:'sheet',folha_revision:1,revision:1,minutes:60,estado:'pending_validation',sheet:{date:'2026-09-08',intervals:[{start:'09:00',end:'18:00'}]}};
  window.absence={id:'absence',data:'2026-10-01',tipo:'baixa_doenca',estado:'ausente_pendente',document_pending:true};
  window.module=createAttendanceManagementModule({confirm:async()=>true,toast:m=>toasts.push(m),supabase:async(name,options)=>{
   const b=JSON.parse(options.body),d=b.p_dados;calls.push({name,b});
   if(name.endsWith('contexto_v2'))return Response.json({version:2,permissions:{admin,adm,he_review:false,task_report:!admin,task_review:false},tasks:[],task_reports:[],overtime:admin?[he]:[],history:events,people:admin?[{id:'p',name:'Pessoa sintética'}]:[],config,absences:adm?[absence]:[],vacations,vacation_revision:vrevision,entitlements,payroll,live_facts:{sheets:[{id:'sheet',date:'2026-10-05',state:'registered',minutes:480,special_day:false}],absences:[],pending_days:[],legacy_days:[]}});
   if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'synthetic-preview'});
   events.push({action:b.p_acao,at:'2026-10-06',ator_id:'synthetic',antes:null,depois:d});
   if(b.p_acao==='he_validate'){he.estado='validated_pending_rule';he.revision++;}
   if(b.p_acao==='he_process'){he.processado_em='2026-10-06';he.revision++;}
   if(b.p_acao==='configure_he_eligibility'){config.he_eligible_roles=d.roles;config.revision++;}
   if(b.p_acao==='vacation_set'){vacations=d.dates.map(data=>({data}));vrevision++;}
   if(b.p_acao==='vacation_entitlement')entitlements=[{ano:d.year,dias:d.days,saldo_transitado:d.carry,dias_adicionais:d.additional,validade_transitado:'2026-04-30',fonte:d.source,revision:1}];
   if(b.p_acao==='absence_confirm')absence.estado='confirmada';
   if(b.p_acao==='payroll_save')payroll=[{competencia:d.month,estado:'draft',manuais:d.manual,revision:1}];
   if(b.p_acao==='payroll_validate'){payroll[0].estado='validated';payroll[0].revision++;}
   if(b.p_acao==='payroll_close'){payroll[0].estado='closed';payroll[0].recibos_recebidos_em='2026-10-06';payroll[0].revision++;}
   if(b.p_acao==='payroll_reopen'){payroll[0].estado='draft';payroll[0].recibos_recebidos_em=null;payroll[0].revision++;}
   return Response.json({version:2,committed:true,request_id:d.request_id,revision:d.expected_revision+1});
  }});await module.show(document.querySelector('#root'),{workId:null,date:'2026-10-06'});
 },role);
 if(role==='encarregado'){
  assert.equal(await page.locator('[data-management-tab=vacations],[data-management-tab=payroll],[data-management-tab=absences]').count(),0);groups++;
 }else{
  assert.equal(await page.locator('[data-management-action=he_validate]').count(),role==='administrativo'?1:0);
  if(role==='administrativo'){
   await page.locator('[data-management-action=he_validate]').click();await page.waitForFunction(()=>he.estado==='validated_pending_rule');
   assert.match(await page.locator('[data-management-body]').textContent(),/Prazo dependente de calendário/);
   await page.locator('[data-management-action=he_process]').click();await page.waitForFunction(()=>he.processado_em);assert.match(await page.locator('[data-management-body]').textContent(),/Pago \/ processado/);groups++;
  }
  await page.locator('[data-management-tab=vacations]').click();await page.locator('[data-management-person]').selectOption('p');await page.waitForFunction(()=>document.querySelector('[data-management-vacations]'));
  await page.locator('[name=from]').fill('2026-10-09');await page.locator('[name=to]').fill('2026-10-12');await page.locator('[data-management-add-range]').click();
  assert.equal(await page.locator('[data-management-unselect]').count(),1);assert.match(await page.evaluate(()=>toasts.at(-1)),/3 dias excluídos/);
  await page.locator('[data-management-vacations] button[value=set]').click();await page.waitForFunction(()=>vrevision===1);assert.deepEqual(await page.evaluate(()=>calls.find(x=>x.b.p_acao==='vacation_set'&&x.b.p_confirmar).b.p_dados.dates),['2026-10-09']);groups++;
  await page.locator('[name=days]').fill('17');await page.locator('[name=source]').fill('Fonte sintética');await page.locator('[name=carry]').fill('3');await page.locator('[name=additional]').fill('2');await page.locator('[name=authorization]').fill('Autorização sintética');await page.locator('[data-management-entitlement] button').click();await page.waitForFunction(()=>entitlements.length===1);assert.match(await page.locator('[data-management-body]').textContent(),/transitado 3.*adicionais 2/);groups++;
  await page.locator('[data-management-tab=payroll]').click();assert.equal(await page.locator('[name=premium]').count(),0);assert.match(await page.locator('[data-management-body]').textContent(),/QUANTIDADE DE QUILÓMETROS/);assert.match(await page.locator('[data-management-body]').textContent(),/AJUDAS DE CUSTO NACIONAL \(€\)/);assert.equal(await page.locator('[name=note]').inputValue(),'');
  await page.locator('[name=km]').fill('12.5');await page.locator('[name=allowance]').fill('0');await page.locator('[name=note]').fill('Manual sintético');await page.locator('[data-management-payroll] button').click();await page.waitForFunction(()=>payroll.length===1);
  const manual=await page.evaluate(()=>payroll[0].manuais);assert.deepEqual(manual,{km:12.5,allowance:0,note:'Manual sintético'});assert.equal(await page.locator('button:has-text("EXPORTAR")').isDisabled(),true);groups++;
  if(role==='administrativo'){
   await page.locator('[data-management-payroll-action=payroll_validate]').click();await page.waitForFunction(()=>payroll[0].estado==='validated');await page.locator('[data-management-payroll-action=payroll_close]').click();await page.waitForFunction(()=>payroll[0].estado==='closed');assert.match(await page.locator('[data-management-body]').textContent(),/Recibos recebidos em/);
   await page.locator('[data-management-payroll-action=payroll_reopen]').click();await page.waitForFunction(()=>payroll[0].estado==='draft');groups++;
   await page.locator('[data-management-tab=absences]').click();assert.match(await page.locator('[data-management-body]').textContent(),/DOCUMENTO PENDENTE/);assert.equal(await page.locator('[data-management-absence]').isDisabled(),true);
   await page.evaluate(()=>{absence.document_pending=false;});await page.locator('[data-management-person]').selectOption('');await page.locator('[data-management-person]').selectOption('p');await page.waitForFunction(()=>document.querySelector('[data-management-absence]'));
   await page.locator('[data-absence-reason]').fill('Documentação conferida');await page.locator('[data-management-absence]').click();await page.waitForFunction(()=>absence.estado==='confirmada');groups++;
   await page.locator('[data-management-tab=schedule]').click();await page.locator('[name=roles]').fill('Pedreiro\nServente');await page.locator('[data-management-eligibility] button').click();await page.waitForFunction(()=>config.revision===2);groups++;
  }else{assert.equal(await page.locator('[data-management-payroll-action]').count(),0);groups++;}
 }
 if(role==='administrativo'){
  await page.evaluate(async()=>{
   module.reset();const fresh=document.createElement('div');fresh.id='root';document.querySelector('#root').replaceWith(fresh);
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');window.sheetCalls=[];window.actual={person_id:'p',name:'Sintético dia especial',role:'Pedreiro',can_write:true,revision:1,expected_minutes:480,special_day:true,special_review_pending:true,sheet:{state:'registered',intervals:[{start:'09:00',end:'17:00'}]}};
   const sheet=createAttendanceModule({root:fresh,isConfigured:true,now:()=>new Date('2026-10-06T19:00:00Z'),confirm:async()=>true,toast:()=>{},supabase:async(name,options)=>{
    const b=JSON.parse(options.body);sheetCalls.push({name,b});
    if(name.endsWith('fn_folha_contexto_v2'))return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Sintética'}],rows:b.p_obra_id?[actual]:[],external_rows:[],office_available:false,permissions:{write:true,allocation_write:true,external_write:false},admin:true,correction_days:1,special_day:true,schedule:{intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}]}});
    if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'synthetic'});
    actual.revision++;return Response.json({version:2,committed:true,request_id:b.p_dados.request_id,changed_keys:[b.p_dados.key]});
   }});await sheet.show();
  });
  await page.locator('[data-sheet-date]').fill('2026-10-03');await page.locator('[data-sheet-work]').selectOption('own');await page.waitForFunction(()=>document.querySelector('[data-sheet-edit]'));
  assert.match(await page.locator('[data-sheet-summary]').textContent(),/1 pendentes/);assert.doesNotMatch(await page.locator('[data-sheet-summary]').textContent(),/DIA COMPLETO/);assert.equal(await page.locator('[data-sheet-bulk=normal]').isDisabled(),true);
  await page.locator('[data-sheet-edit]').click();assert.equal(await page.locator('[name=reason]').getAttribute('required'),'');
  await page.locator('[data-sheet-form] button').click();assert.equal(await page.evaluate(()=>sheetCalls.filter(x=>x.b.p_acao==='save').length),0);
  await page.locator('[name=reason]').fill('Correção administrativa sintética');await page.locator('[data-sheet-form] button').click();await page.waitForFunction(()=>actual.revision===2);
  assert.equal(await page.evaluate(()=>sheetCalls.find(x=>x.b.p_acao==='save').b.p_dados.reason),'Correção administrativa sintética');groups++;
 }
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2));assert.ok(await page.evaluate(()=>calls.every(x=>x.name.startsWith('rpc/fn_folha_'))));
 await page.screenshot({path:path.join(folder,`${role}-${width}.png`),fullPage:true});await page.close();groups++;
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({groups,fail:0,pageErrors:errors.length,viewports:3,profiles:3,screenshots:folder}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
