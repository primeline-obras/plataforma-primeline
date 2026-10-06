import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {tmpdir} from 'node:os';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url));
const screenshots=path.join(tmpdir(),'primeline-p2-visible-synthetic');await mkdir(screenshots,{recursive:true});
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<html data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div></html>');}
  const p=new URL(req.url,'http://local').pathname;if(!p.startsWith('/src/')){res.writeHead(404);return res.end();}
  res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(repo,p)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:true});let pass=0;const errors=[];
try{
 for(const role of ['encarregado','diretor_obra','adjunto','administrativo'])for(const width of [1440,820,390]){
  const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.evaluate(async role=>{
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');
   window.calls=[];window.messages=[];window.scene='legacy';
   const writer=['encarregado','administrativo'].includes(role);
   window.module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:m=>messages.push(m),now:()=>new Date('2026-09-24T18:00:00Z'),supabase:async(name,options)=>{
    const b=JSON.parse(options.body);calls.push({name,b});
    if(name.endsWith('fn_folha_historico_v2'))return Response.json({version:2,events:[],legacy:[{id:'old',data:'2026-09-24',obra_id:'own',estado:'presente',horas:8}],legacy_interpretation:'original'});
    if(!name.endsWith('fn_folha_contexto_v2'))throw Error('Unexpected write RPC');
    const r={person_id:'p',name:'Synthetic',role:'Pedreiro',can_write:writer,can_remove:writer,expected_minutes:480,revision:0,sheet:null};
    if(scene==='legacy')Object.assign(r,{legacy:true,can_write:false,can_remove:false});
    if(scene==='pending')Object.assign(r,{absence:{tipo:'falta_injustificada',estado:'ausente_pendente'},can_remove:false});
    if(scene==='resolved')Object.assign(r,{absence:{tipo:'falta_justificada_sem_remuneracao',estado:'justificada'},can_remove:false});
    if(scene==='vacation')Object.assign(r,{absence:{tipo:'ferias',estado:'confirmada'},can_remove:false});
    if(scene==='both')Object.assign(r,{legacy:true,conflict:'LEGACY_CONFLICT',sheet:{intervals:[{start:'09:00',end:'13:00'}]},can_write:false,can_remove:false});
    if(scene==='work_absence')Object.assign(r,{absence:{tipo:'falta_injustificada',estado:'ausente_pendente'},sheet:{intervals:[{start:'09:00',end:'13:00'}]},can_remove:false});
    if(scene==='missing')r.sheet={intervals:[{start:'09:00',end:'13:00'}]};
    if(scene==='overtime')Object.assign(r,{sheet:{intervals:[{start:'09:00',end:'18:00'}]},overtime:{estado:'validated_pending_rule'}});
    return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Synthetic'}],rows:[r],external_rows:[],permissions:{write:writer,allocation_write:writer,external_write:false},schedule:{intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}]},special_day:scene==='special',admin:role==='administrativo',correction_days:7});
   }});await module.show();
  },role);
  let text=await page.locator('#root').innerText();assert.match(text,/REGISTO LEGADO/);assert.match(text,/0 pendentes.*DIA COMPLETO/);
  assert.equal(await page.locator('[data-sheet-edit]').count(),0);assert.equal(await page.locator('[data-sheet-remove]').count(),0);
  await page.locator('[data-sheet-history]').click();await page.waitForFunction(()=>document.querySelector('[data-sheet-legacy]'));
  text=await page.locator('[data-sheet-detail]').innerText();assert.match(text,/HISTÓRICO FOLHA V2\s+Sem alterações registadas/);assert.match(text,/REGISTO LEGADO/);
  assert.equal(await page.locator('[data-sheet-legacy] button').count(),0);pass++;
  await page.screenshot({path:path.join(screenshots,role+'-'+width+'-legacy.png'),fullPage:true});
  if(['encarregado','administrativo'].includes(role)){
   for(const operation of ['start','finish','normal'])await page.locator(`[data-sheet-bulk="${operation}"]`).evaluate(e=>{e.disabled=false;e.click();});
   assert.equal(await page.evaluate(()=>calls.some(c=>c.name.endsWith('fn_folha_operar_v2'))),false);pass++;
  }
  for(const scene of ['pending','resolved','vacation','both','work_absence','missing','overtime','special']){
   await page.evaluate(async scene=>{window.scene=scene;await module.refresh();},scene);text=await page.locator('#root').innerText();
   if(scene==='pending'||scene==='work_absence'){assert.match(text,/JUSTIFICAÇÃO PENDENTE/);assert.match(text,/1 pendentes/);assert.doesNotMatch(text,/DIA COMPLETO/);assert.equal(await page.locator('[data-sheet-remove]').count(),0);}
   if(scene==='pending'){
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2));
    await page.screenshot({path:path.join(screenshots,role+'-'+width+'-pending.png'),fullPage:true});
   }
   if(scene==='resolved'){assert.match(text,/Falta justificada sem remuneração · Justificada/);assert.match(text,/DIA COMPLETO/);}
   if(scene==='vacation'){assert.match(text,/Férias/);assert.match(text,/DIA COMPLETO/);}
   if(scene==='both'){assert.match(text,/Legado e Folha V2 coexistem/);assert.match(text,/Regularização/);assert.doesNotMatch(text,/DIA COMPLETO/);}
   if(scene==='work_absence')assert.match(text,/Regularização/);
   if(scene==='missing')assert.match(text,/HORAS EM FALTA — REQUER REGULARIZAÇÃO/);
   if(scene==='overtime')assert.match(text,/HE validada · regra financeira pendente/);
   if(scene==='special')assert.match(text,/DIA ESPECIAL — REQUER REVISÃO/);
   if(scene==='pending'&&['encarregado','administrativo'].includes(role)){
    for(const operation of ['start','finish','normal'])await page.locator(`[data-sheet-bulk="${operation}"]`).evaluate(e=>{e.disabled=false;e.click();});
    assert.equal(await page.evaluate(()=>calls.some(c=>c.name.endsWith('fn_folha_operar_v2'))),false);
   }
   pass++;
  }
  assert.ok(await page.locator('[data-sheet-history]').isVisible());
  if(role==='administrativo'){
   await page.evaluate(async()=>{
    const {createAttendanceManagementModule}=await import('/src/attendance-management.js');
    window.pendingAbsence=true;
    window.management=createAttendanceManagementModule({toast:()=>{},supabase:async()=>Response.json({version:2,permissions:{admin:true,he_review:false,task_report:false,task_review:false},people:[{id:'p',name:'Synthetic'}],tasks:[],task_reports:[],overtime:[],history:[],vacations:[{data:'2026-09-24',estado:pendingAbsence?'ausente_pendente':'confirmada'}],vacation_revision:0,entitlements:[],payroll:[{competencia:"2026-09-01",estado:"draft",revision:1,manuais:{km:0,allowance:0}}],config:{calendar_complete:true,calendar_validated_years:[2026]},live_facts:{sheets:[],pending_days:[],legacy_days:[],absences:[{date:'2026-09-24',type:'falta_injustificada',state:pendingAbsence?'ausente_pendente':'justificada'}]}})});
    await management.show(document.querySelector('#root'),{date:'2026-09-24',workId:null});
   });
   await page.locator('[data-management-tab=vacations]').click();await page.locator('[data-management-person]').selectOption('p');
   await page.waitForFunction(()=>document.querySelector('[data-management-body]')?.textContent.includes('Justificação pendente'));
   assert.match(await page.locator('[data-management-body]').innerText(),/2026-09-24 · Justificação pendente/);pass++;
   await page.locator('[data-management-tab=payroll]').click();
   await page.waitForFunction(()=>document.querySelector('[data-management-body]')?.textContent.includes('Justificação pendente'));
   assert.match(await page.locator('[data-management-body]').innerText(),/1 factos pendentes/);pass++;
   await page.evaluate(()=>pendingAbsence=false);await page.locator('[data-management-person]').selectOption('');await page.locator('[data-management-person]').selectOption('p');
   await page.waitForFunction(()=>document.querySelector('[data-management-body]')?.textContent.includes('Justificada'));
   assert.match(await page.locator('[data-management-body]').innerText(),/0 factos pendentes/);pass++;
   await page.locator('[data-management-tab=vacations]').click();
   assert.match(await page.locator('[data-management-body]').innerText(),/2026-09-24 · Confirmada/);pass++;
  }
  await page.close();
 }
 assert.deepEqual(errors,[]);console.log(JSON.stringify({pass,fail:0,roles:4,viewports:3,pageErrors:0,screenshots,source:'MOCK ONLY; PostgreSQL evidence in attendance-visible-state-cases.mjs'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
