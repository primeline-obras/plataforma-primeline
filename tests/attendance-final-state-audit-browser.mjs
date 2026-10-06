import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url));
const server=createServer(async(req,res)=>{
 try{
  if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta charset="utf-8"><div id="root"></div>');}
  const p=new URL(req.url,'http://local').pathname;if(!p.startsWith('/src/'))throw Error('denied');
  res.setHeader('Content-Type','text/javascript');res.end(await readFile(path.join(repo,p)));
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
 ['regularization persistent',{sheet:sheet('regularization')},'Regularização',1]
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
   await page.evaluate(async row=>{window.row=row;window.special=!!row.special_day;await module.show();},row);
   const text=await page.locator('.sheet-person').innerText(),summary=await page.locator('[data-sheet-summary]').innerText();
   const matches=text.includes(label)&&summary.includes(`${pending} pendentes`);
   if(matches)pass++;else mismatches.push({width,state,expected:label,expectedPending:pending,actual:text,summary});
  }
  assert.equal(await page.evaluate(()=>calls.some(n=>n.endsWith('fn_folha_operar_v2'))),false);await page.close();
 }
 assert.deepEqual(errors,[]);
 console.log(JSON.stringify({pass,fail:mismatches.length,pageErrors:0,mismatches,source:'SYNTHETIC ONLY; persistent-state evidence independently reproduced with PostgreSQL'}));
 if(mismatches.length)process.exitCode=1;
}finally{await browser.close();await new Promise(r=>server.close(r));}
