import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import path from 'node:path';
export async function auditAttendanceCases(t,{q,a,as,aux,auxDo,id,connect}) {
 let seq=960000;const data=x=>({version:2,request_id:id(seq++),expected_revision:0,...x});
 const raw=(actor,action,d,confirm=false,token=null)=>as(a,actor,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',[action,d,confirm,token]);
 async function save(d){const p=await raw(10,'save',d);return raw(10,'save',d,true,p.versao);}
 async function seed(person,work,date,hours=9){await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Audit synthetic','Pedreiro','2020-01-01')",[id(person),id(1)]);
  await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,date_trunc('week',$4::date)::date,$4,'dia_inteiro',$5)",[id(seq++),id(person),id(work),date,id(10)]);
  await save(data({work_id:id(work),date,key:{kind:'primeline',person_id:id(person),work_id:id(work),date},intervals:[{start:'08:00',end:hours===9?'17:00':'16:00'}],reason:'Synthetic audited hours'}));
 }
 const hs=[];for(let person=24001;person<=24004;person++){await seed(person,100,'2026-09-18');hs.push((await q('SELECT h.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(person)])).rows[0]);}
 await t.test('independent audit HE: Diretor and Adjunto each approve/reject; raw operational projection exact',async()=>{
  for(const [i,actor,action] of [[0,14,'he_approve'],[1,14,'he_reject'],[2,15,'he_approve'],[3,15,'he_reject']]){
   assert.ok(hs[i]);const r=await auxDo(actor,action,data({id:hs[i].id,expected_revision:1}));assert.equal(r.result.estado,action==='he_approve'?'pending_validation':'rejected');assert.doesNotMatch(JSON.stringify(r),/processado|prazo_processamento|payment|payroll/);
  }
  for(const actor of [14,15]){const c=await as(a,actor,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);assert.ok(c.overtime.length);assert.doesNotMatch(JSON.stringify(c),/processado_em|processado_por|prazo_processamento|he_validate|he_process|configure_he_eligibility/);for(const h of c.overtime)assert.deepEqual(Object.keys(h).sort(),['id','obra_id','folha_id','folha_revision','minutes','estado','revision','sheet','person_name'].sort());}
 });
 await t.test('independent audit HE: preview → role reduction → commit/replay denied for validate/process, then legitimate replay preserved',async()=>{
  for(const action of ['he_validate','he_process']){
   const h=(await q('SELECT * FROM folha_he WHERE id=$1',[hs[0].id])).rows[0],d=data({id:h.id,expected_revision:h.revision}),p=await aux(10,action,d);
   assert.equal(p.committed,false);await q("UPDATE utilizadores SET funcao='adjunto' WHERE id=$1",[id(10)]);
   try{await assert.rejects(aux(10,action,d,true,p.versao),e=>e.code==='42501');}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
   const r=await aux(10,action,d,true,p.versao);assert.equal(r.committed,true);
   await q("UPDATE utilizadores SET funcao='diretor_obra' WHERE id=$1",[id(10)]);try{await assert.rejects(aux(10,action,d,true,p.versao),e=>e.code==='42501');}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
   assert.deepEqual(await aux(10,action,d,true,p.versao),r);
  }
  const c=await as(a,10,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);assert.ok(c.overtime.find(h=>h.id===hs[0].id).processado_em);assert.ok(c.history.some(h=>h.entidade_id===hs[0].id&&h.action==='he_process'&&h.dominio==='administrativo'));
  const enc=await as(a,13,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);assert.deepEqual(enc.overtime,[]);assert.ok(enc.history.every(h=>h.dominio==='tarefas'));
 });
 const work=id(24050),person=id(24010),date='2026-09-12';await q("INSERT INTO obras(id,empresa_id,numero,nome,tipo) VALUES($1,$2,24050,'Audit special work','reabilitacao')",[work,id(1)]);
 for(const [actor,role] of [[13,'encarregado'],[14,'diretor_obra'],[15,'adjunto']])await q('INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,$3)',[work,id(actor),role]);
 await q("INSERT INTO folha_horarios VALUES($1,$2,'[{\"period\":\"manha\",\"start\":\"09:00\",\"end\":\"13:00\"},{\"period\":\"tarde\",\"start\":\"14:00\",\"end\":\"18:00\"}]',480,1)",[work,id(1)]);
 await seed(24010,24050,date,8);await auxDo(10,'payroll_save',data({person_id:person,month:'2026-09-01',manual:{km:0,allowance:0,note:'Synthetic audit only'}}));
 const current=async()=>(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[person,date])).rows[0];
 const daily=()=>as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[date,work]);
 const payroll=()=>as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,$2) v',[person,'2026-09-01']);
 const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT);let queue=Promise.resolve();const requests=[],browserDb=await connect();
 const server=createServer((req,res)=>{if(req.method==='POST'){
  queue=queue.then(async()=>{try{let body='';for await(const c of req)body+=c;const d=JSON.parse(body),actor=Number(req.headers['x-test-actor']);assert.ok([10,13,14,15].includes(actor));let sql,params;
   switch(req.url){case '/rpc/fn_folha_contexto_v2':sql='SELECT fn_folha_contexto_v2($1,$2) v';params=[d.p_data,d.p_obra_id];break;
    case '/rpc/fn_folha_gestao_contexto_v2':sql='SELECT fn_folha_gestao_contexto_v2($1,$2,$3) v';params=[d.p_obra_id,d.p_colaborador_id,d.p_competencia];break;
    case '/rpc/fn_folha_operar_v2':assert.equal(d.p_acao,'save');sql='SELECT fn_folha_operar_v2($1,$2,$3,$4) v';params=[d.p_acao,d.p_dados,d.p_confirmar,d.p_versao];break;
    case '/rpc/fn_folha_gestao_v2':assert.equal(d.p_acao,'special_review');sql='SELECT fn_folha_gestao_v2($1,$2,$3,$4) v';params=[d.p_acao,d.p_dados,d.p_confirmar,d.p_versao];break;
    default:throw Error('RPC outside audit scope');}
   const result=await as(browserDb,actor,sql,params);requests.push({rpc:req.url,actor,action:d.p_acao,confirmed:d.p_confirmar});res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
  }catch(e){res.writeHead(e.code==='42501'?403:e.code==='40001'?409:500,{'Content-Type':'application/json'});res.end(JSON.stringify({message:e.message,code:e.code}));}});return;
 }
 (async()=>{try{const p=new URL(req.url,'http://local').pathname;if(p==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="daily"></div><div id="management"></div>');}
  assert.ok(p.startsWith('/src/'));res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(process.cwd(),p)));}catch{res.writeHead(404);res.end();}})();
 });await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port,browser=await chromium.launch({channel:'msedge',headless:true}),errors=[],screenshots=path.join(tmpdir(),'primeline-audit-security-live-pg');await mkdir(screenshots,{recursive:true});let checks=0;
 try{for(const width of [1440,820,390]){
  await t.test('independent browser + PostgreSQL: '+width+' HE profiles and review → factual edit → payroll parity',async()=>{
   const page=await browser.newPage({viewport:{width,height:1000}});page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});await page.route('**/*',r=>new URL(r.request().url()).origin===origin?r.continue():r.fulfill({status:200,body:'',contentType:'text/css'}));await page.goto(origin);
   for(const actor of [14,15,10,13]){
    await page.evaluate(async({actor,work})=>{{const fresh=document.createElement('div');fresh.id='management';document.querySelector('#management').replaceWith(fresh);}const {createAttendanceManagementModule}=await import('/src/attendance-management.js');const module=createAttendanceManagementModule({toast:()=>{},confirm:async()=>true,supabase:(name,o)=>fetch('/'+name,{...o,headers:{'Content-Type':'application/json','x-test-actor':String(actor)}})});await module.show(document.querySelector('#management'),{workId:work,date:'2026-09-18'});},{actor,work:id(100)});
    const text=await page.locator('#management').textContent();if(actor===10)assert.match(text,/Pago \/ processado/);else assert.doesNotMatch(text,/Pago \/ processado|Prazo:|Processamento pendente/);if(actor===13)assert.equal(await page.locator('#management [data-management-tab=he]').count(),0);checks++;
   }
   await page.evaluate(async({date,person})=>{{const fresh=document.createElement('div');fresh.id='management';document.querySelector('#management').replaceWith(fresh);}const supabase=(name,o)=>fetch('/'+name,{...o,headers:{'Content-Type':'application/json','x-test-actor':'10'}});const {createAttendanceModule}=await import('/src/attendance-sheet.js'),{createAttendanceManagementModule}=await import('/src/attendance-management.js');window.auditDaily=createAttendanceModule({root:document.querySelector('#daily'),isConfigured:true,toast:()=>{},confirm:async()=>true,now:()=>new Date('2026-10-06T19:00:00Z'),supabase});await auditDaily.show();window.auditManagement=createAttendanceManagementModule({toast:()=>{},confirm:async()=>true,supabase});await auditManagement.show(document.querySelector('#management'),{workId:null,date});}, {date,person});
   await page.locator('#daily [data-sheet-date]').fill(date);await page.locator('#daily [data-sheet-work]').selectOption(work);await page.waitForSelector('#daily .sheet-person');await page.locator('#management [data-management-tab=payroll]').click();await page.locator('#management [data-management-person]').selectOption(person);await page.waitForSelector('#management [data-management-special]');
   assert.match(await page.locator('#daily [data-sheet-summary]').textContent(),/1 pendentes/);assert.doesNotMatch(await page.locator('#daily [data-sheet-summary]').textContent(),/DIA COMPLETO/);assert.match(await page.locator('#daily .sheet-person').textContent(),/REQUER REVISÃO/);assert.match(await page.locator('#management').textContent(),/1 factos pendentes/);checks++;
   await page.locator('#management [data-management-special]').click();await page.waitForFunction(()=>document.querySelector('#management').textContent.includes('DIA ESPECIAL · REVISTO'));await page.locator('#daily [data-sheet-refresh]').click();await page.waitForFunction(()=>document.querySelector('#daily [data-sheet-summary]')?.textContent.includes('DIA COMPLETO'));
   assert.match(await page.locator('#daily .sheet-person').textContent(),/DIA ESPECIAL · REVISTO/);assert.doesNotMatch(await page.locator('#daily').textContent(),/REQUER REVISÃO/);assert.match(await page.locator('#management').textContent(),/0 factos pendentes/);const db=await current(),ctx=await daily(),facts=await payroll();assert.ok(db.special_reviewed_at);assert.equal(ctx.rows[0].special_reviewed,true);assert.equal(ctx.summary.pending,0);assert.equal(ctx.summary.complete,true);assert.equal(facts.live_facts.sheets[0].special_reviewed,true);checks++;
   await page.screenshot({path:path.join(screenshots,`reviewed-${width}.png`),fullPage:true});await page.locator('#daily [data-sheet-edit]').first().click();const hour=width===1440?'07':width===820?'06':'05';await page.locator('#daily [name=start0]').fill(hour+':00');await page.locator('#daily [name=end0]').fill(String(Number(hour)+8).padStart(2,'0')+':00');await page.locator('#daily [name=reason]').fill('Independent synthetic audit factual correction');await page.locator('#daily [data-sheet-form] button').click();await page.waitForFunction(()=>document.querySelector('#daily .sheet-person')?.textContent.includes('REQUER REVISÃO'));
   assert.equal((await current()).special_reviewed_at,null);assert.equal((await daily()).summary.complete,false);assert.equal((await payroll()).live_facts.sheets[0].special_reviewed,false);await page.locator('#management [data-management-person]').selectOption('');await page.locator('#management [data-management-person]').selectOption(person);await page.waitForSelector('#management [data-management-special]');assert.match(await page.locator('#management').textContent(),/1 factos pendentes/);checks++;
   await page.screenshot({path:path.join(screenshots,`invalidated-${width}.png`),fullPage:true});await page.close();await queue;
  });
 }
 assert.deepEqual(errors,[]);console.log('AUDIT_ATTENDANCE_BROWSER '+JSON.stringify({checks,viewports:3,errors,screenshots,source:'unchanged frontend calling real RPCs on local PostgreSQL fixture',writes:requests.filter(r=>r.confirmed).length}));
 }finally{await queue;await browser.close();await new Promise(r=>server.close(r));}
}
