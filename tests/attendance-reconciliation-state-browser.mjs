import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {tmpdir} from 'node:os';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url));
const screenshots=path.join(tmpdir(),'primeline-folha-reconciliation');await mkdir(screenshots,{recursive:true});
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<html data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div></html>');}
  const p=new URL(req.url,'http://local').pathname;if(!p.startsWith('/src/'))throw Error('denied');
  res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(repo,p)));
 }catch{res.writeHead(404);res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:true});let pass=0;const errors=[],mismatches=[];
const full=[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}];
const sheet=(state,intervals=full)=>({state,intervals});
const cases=[
 ['none',{},'Não registado',1],
 ['open',{sheet:sheet('open',[{start:'09:00',end:null}])},'Em aberto',1],
 ['registered',{sheet:sheet('registered')},'Registado',0],
 ['missing',{sheet:sheet('missing',[full[0]])},'Horas em falta',1],
 ['vacation',{absence:{tipo:'ferias',estado:'confirmada'}},'Férias',0],
 ['absence',{absence:{tipo:'falta_justificada_sem_remuneracao',estado:'justificada'}},'Ausência',0],
 ['pending justification',{absence:{tipo:'falta_injustificada',estado:'ausente_pendente'}},'JUSTIFICAÇÃO PENDENTE',1],
 ['regularization derived',{sheet:sheet('regularization'),absence:{tipo:'ferias',estado:'confirmada'}},'Regularização',1],
 ['legacy',{legacy:true,can_write:false,can_remove:false},'REGISTO LEGADO',0],
 ['legacy conflict',{legacy:true,conflict:'LEGACY_CONFLICT',sheet:sheet('regularization')},'Regularização',1],
 ['potential HE',{sheet:sheet('registered',[{start:'09:00',end:'18:00'}]),overtime:{estado:'potential'}},'Potencial HE',0],
 ['pending_rule',{sheet:sheet('registered'),special_day:true},'Dia especial · regra pendente',0],
 ['pending_validation',{sheet:sheet('registered'),overtime:{estado:'pending_validation'}},'validação administrativa pendente',0],
 ['rejected',{sheet:sheet('registered'),overtime:{estado:'rejected'}},'HE rejeitada',0],
 ['validated_pending_rule',{sheet:sheet('registered'),overtime:{estado:'validated_pending_rule'}},'regra financeira pendente',0],
 ['regularization persistent',{sheet:sheet('regularization')},'Regularização',1],
 ['vacation added',{sheet:sheet('regularization'),absence:{tipo:'ferias',estado:'confirmada'}},'Regularização',1],
 ['vacation removed full',{sheet:sheet('registered')},'Registado',0],
 ['vacation removed short',{sheet:sheet('missing',[{start:'09:00',end:'16:00'}])},'Horas em falta',1],
 ['vacation removed open',{sheet:sheet('open',[{start:'09:00',end:null}])},'Em aberto',1],
 ['backend missing authoritative',{sheet:sheet('missing')},'Horas em falta',1],
 ['backend open authoritative',{sheet:sheet('open')},'Em aberto',1],
 ['HE generation blocked',{sheet:sheet('registered',[{start:'09:00',end:'18:00'}]),overtime:{estado:'none'}},'Registado',0],
 ['historical calendar snapshot',{sheet:sheet('registered'),special_day:false,calendar_special_day:true,overtime:{estado:'none'}},'Registado',0]
];
try{
 for(const width of [1440,820,390]){
  const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',r=>new URL(r.request().url()).hostname==='127.0.0.1'?r.continue():r.abort());
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.evaluate(async()=>{
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');window.row={};window.special=false;window.calls=[];
   window.module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,now:()=>new Date('2026-09-25T18:00:00Z'),toast:()=>{},supabase:async(name,options)=>{
    calls.push(name);if(!name.endsWith('fn_folha_contexto_v2'))throw Error('Unexpected RPC');const b=JSON.parse(options.body);
    return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Synthetic'}],rows:[{person_id:'p',name:'Synthetic',role:'Synthetic',sheet:null,expected_minutes:480,revision:0,...row}],external_rows:[],special_day:special,permissions:{write:false,allocation_write:false,external_write:false}});
   }});
  });
  for(const [state,row,label,pending] of cases){
   await page.evaluate(async row=>{window.row=row;window.special=row.calendar_special_day??!!row.special_day;await module.show();},row);
   const text=await page.locator('.sheet-person').innerText(),summary=await page.locator('[data-sheet-summary]').innerText();
   const matches=text.includes(label)&&summary.includes(`${pending} pendentes`);
   if(row.overtime?.estado==='none')assert.doesNotMatch(text,/Potencial HE|Dia especial/);
   if(matches)pass++;else mismatches.push({width,state,expected:label,expectedPending:pending,actual:text,summary});
  }
  assert.equal(await page.evaluate(()=>calls.some(n=>n.endsWith('fn_folha_operar_v2'))),false);
  // Exercise the actual vacation form and the parent Folha refresh, with RPC mocks only.
  await page.evaluate(async()=>{
   const {createAttendanceModule}=await import('/src/attendance-sheet.js');window.transitionCalls=[];window.vacationActive=false;window.vacationRevision=0;
   window.transitionModule=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,now:()=>new Date('2026-09-25T18:00:00Z'),toast:()=>{},confirm:async()=>true,supabase:async(name,options)=>{
    const b=JSON.parse(options.body);transitionCalls.push({name,b});
    if(name.endsWith('fn_folha_contexto_v2'))return Response.json({version:2,date:b.p_data,work_id:b.p_obra_id,works:[{id:'own',number:1,name:'Synthetic'}],management:true,admin:true,tipo_local:'obra',rows:[{person_id:'p',name:'Synthetic',role:'Synthetic',sheet:{state:vacationActive?'regularization':'registered',intervals:[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}]},absence:vacationActive?{tipo:'ferias',estado:'confirmada'}:null,expected_minutes:480,revision:vacationRevision+1,can_write:true}],external_rows:[],special_day:false,permissions:{write:true,allocation_write:true,external_write:false}});
    if(name.endsWith('fn_folha_gestao_contexto_v2'))return Response.json({version:2,permissions:{admin:true,he_review:false,task_report:false,task_review:false},task_reports:[],people:[{id:'p',name:'Synthetic'}],tasks:[],overtime:[],vacations:vacationActive?[{data:'2026-09-25',estado:'confirmada'}]:[],vacation_revision:vacationRevision,entitlements:[],payroll:[],history:[],config:{calendar_complete:true},live_facts:{sheets:[],absences:[],pending_days:[],legacy_days:[]}});
    if(name.endsWith('fn_folha_gestao_v2')){
     if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'synthetic-preview'});
     vacationActive=b.p_acao==='vacation_set';vacationRevision++;
     return Response.json({version:2,committed:true,request_id:b.p_dados.request_id,revision:b.p_dados.expected_revision+1});
    }
    throw Error('Unexpected RPC '+name);
   }});await transitionModule.show();
  });
  await page.locator('[data-management-tab="vacations"]').click();await page.locator('[data-management-person]').selectOption('p');
  assert.match(await page.locator('.sheet-person b').innerText(),/Registado/);pass++;
  await page.locator('[data-management-vacations] input[name="single"]').fill('2026-09-25');await page.locator('[data-management-add-date]').click();
  await page.locator('[data-management-vacations] button[value="set"]').click();
  await page.waitForFunction(()=>document.querySelector('.sheet-person b')?.textContent==='Regularização');
  assert.match(await page.locator('[data-sheet-summary]').innerText(),/1 pendentes/);pass++;
  await page.screenshot({path:path.join(screenshots,`regularization-${width}.png`),fullPage:true});
  await page.locator('[data-management-select-date]').click();await page.locator('[data-management-vacations] button[value="remove"]').click();
  await page.waitForFunction(()=>document.querySelector('.sheet-person b')?.textContent==='Registado');
  assert.match(await page.locator('[data-sheet-summary]').innerText(),/DIA COMPLETO/);pass++;
  await page.screenshot({path:path.join(screenshots,`registered-${width}.png`),fullPage:true});
  const ops=await page.evaluate(()=>transitionCalls.filter(x=>x.name.endsWith('fn_folha_gestao_v2')));
  assert.equal(ops.length,4);assert.equal(ops[0].b.p_dados.request_id,ops[1].b.p_dados.request_id);assert.equal(ops[2].b.p_dados.request_id,ops[3].b.p_dados.request_id);assert.notEqual(ops[0].b.p_dados.request_id,ops[2].b.p_dados.request_id);
  await page.close();
 }
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({pass,fail:mismatches.length,pageErrors:0,mismatches,screenshots,source:'SYNTHETIC ONLY; persistent-state evidence independently reproduced with PostgreSQL'}));
 if(mismatches.length)process.exitCode=1;
}finally{await browser.close();await new Promise(r=>server.close(r));}
