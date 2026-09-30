import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const index=await readFile(new URL('../index.html',import.meta.url),'utf8');
const styles=[...index.matchAll(/<link[^>]+rel="stylesheet"[^>]*>/g)].map(m=>m[0]).join('');
const browser=await chromium.launch({channel:'msedge',headless:true});
try {
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(u.pathname.startsWith('/src/'))return route.fulfill({body:await readFile(new URL('..'+u.pathname,import.meta.url),'utf8'),contentType:u.pathname.endsWith('.css')?'text/css':'text/javascript'});
  if(u.pathname!=='/')return route.abort();
  await route.fulfill({contentType:'text/html',body:`<meta name="viewport" content="width=device-width">${styles}<main id="fleet"></main><script type="module">
   import {createVehiclesModule} from '/src/vehicles.js';
   window.calls=[];window.mode='ok';window.allowed=true;window.failCandidates=false;window.delaySave=false;window.failHistory=false;
   window.car={id:'v1',empresa_id:'e1',marca_modelo:'FIAT FIORINO',matricula:'79-VO-20',colaborador_atribuido_id:'a',atribuicao_revisao:7};
   window.people=[{id:'a',nome:'Vitor Lopes',empresa_id:'e1',data_saida:null},{id:'b',nome:'Ativo sem login',empresa_id:'e1',data_saida:null},{id:'i',nome:'Antigo',empresa_id:'e1',data_saida:'2026-01-01'},{id:'x',nome:'Outra empresa',empresa_id:'e2',data_saida:null}];
   window.historyRows=[];window.messages=[];
   const api=async(path,options={})=>{
    calls.push({path,body:options.body?JSON.parse(options.body):null});
    if(path.startsWith('rpc/')){
     if(delaySave)await new Promise(r=>setTimeout(r,100));
     if(mode==='network')throw Error('offline');
     if(mode==='stale'){car={...car,colaborador_atribuido_id:'b',atribuicao_revisao:8};return Response.json({code:'40001',message:'STALE_REVISION: changed'},{status:400});}
     if(mode==='permission')return Response.json({code:'42501'},{status:403});
     if(mode==='validation')return Response.json({code:'22023'},{status:400});
     const p=JSON.parse(options.body);
     if(mode==='unconfirmed')return Response.json({version:1,committed:false,viatura_id:'v1'});
     car={...car,colaborador_atribuido_id:p.p_novo_colaborador_id,atribuicao_revisao:car.atribuicao_revisao+1};
     historyRows=[{id:'h1',colaborador_anterior_id:'i',colaborador_novo_id:p.p_novo_colaborador_id,alterado_em:'2026-09-30T10:30:00Z',autor:{nome:'Administrativo'},motivo:p.p_motivo}];
     return Response.json({version:1,committed:true,viatura_id:'v1'});
    }
    if(path.startsWith('viaturas?'))return Response.json([car]);
    if(path.startsWith('viaturas_atribuicoes_historico?'))return failHistory?Response.json({message:'failed'},{status:500}):Response.json(historyRows);
    if(path.startsWith('colaboradores?')){
     if(path.includes('data_saida=is.null')){if(failCandidates)return Response.json({message:'failed'},{status:500});return Response.json(people.filter(c=>c.data_saida===null&&c.empresa_id==='e1'));}
     return Response.json(people.filter(c=>!path.includes('data_saida=is.null')||c.data_saida===null));
    }
    return Response.json([]);
   };
   window.PRIMELINE_CONFIG={supabaseUrl:'https://offline.test',supabaseAnonKey:'offline'};
   window.fetch=async(url,options)=>{const u=new URL(url);return api(u.pathname.slice('/rest/v1/'.length)+decodeURIComponent(u.search),options);};
   const {supabase}=await import('/src/supabase-browser.js');
   window.mod=createVehiclesModule({root:document.querySelector('#fleet'),supabase,isConfigured:true,getCollaborators:()=>[],getSuppliers:()=>[],canManageAssignment:()=>allowed,euro:new Intl.NumberFormat('pt-PT',{style:'currency',currency:'EUR'}),prettyDate:new Intl.DateTimeFormat('pt-PT'),toast:(...v)=>messages.push(v)});
   await mod.show();window.ready=true;
  </script>`});
 });
 await page.goto('http://localhost:4179');await page.waitForFunction(()=>window.ready);
 const button=page.locator('[data-fleet-assignment]');const dialog=page.locator('.fleet-assignment-dialog');
 const open=async()=>{await button.click();await page.waitForFunction(()=>!document.querySelector('.fleet-assignment-dialog select').disabled);};
 const close=async()=>{await dialog.locator('[data-close]').first().click();};
 const rpc=()=>page.evaluate(()=>calls.filter(c=>c.path.startsWith('rpc/')));
 assert.match(await page.locator('.fleet-detail-head').innerText(),/Vitor Lopes/);
 assert.match(await page.locator('.fleet-assignment-history').innerText(),/Sem alterações/);
 for(const [id,text] of [[null,'Sem atribuição'],['i','Antigo · INATIVO'],['unknown','Responsável indisponível'],['a','Vitor Lopes']]){
  await page.evaluate(async id=>{car.colaborador_atribuido_id=id;await mod.refresh();},id);
  assert.match(await page.locator('.fleet-detail-head').innerText(),new RegExp(text));
 }
 await open();const noChange=(await rpc()).length;await dialog.locator('[type=submit]').click();await dialog.locator('.form-error').filter({hasText:'diferente'}).waitFor();assert.equal((await rpc()).length,noChange);assert.deepEqual(await dialog.locator('option').evaluateAll(o=>o.map(x=>x.value)),['','a','b']);
 await dialog.locator('select').selectOption('b');await dialog.locator('textarea').fill('Teste');
 await page.evaluate(()=>mode='network');await dialog.locator('[type=submit]').click();await dialog.locator('.form-error').filter({hasText:'confirmar'}).waitFor();
 const first=(await rpc()).at(-1).body;assert.equal(first.p_revisao_esperada,7);assert.equal(first.p_novo_colaborador_id,'b');assert.equal(first.p_motivo,'Teste');assert.match(first.p_request_id,/^[0-9a-f-]{36}$/);
 await dialog.locator('[type=submit]').click();await page.waitForFunction(()=>!document.querySelector('.fleet-assignment-dialog [type=submit]').disabled);assert.deepEqual((await rpc()).at(-1).body,first);
 await dialog.locator('textarea').fill('Outro motivo');await dialog.locator('[type=submit]').click();await page.waitForFunction(()=>!document.querySelector('.fleet-assignment-dialog [type=submit]').disabled);assert.notEqual((await rpc()).at(-1).body.p_request_id,first.p_request_id);
 for(const [mode,text] of [['unconfirmed','não confirmou'],['permission','permissão'],['validation','validar']]){
  await page.evaluate(m=>window.mode=m,mode);await dialog.locator('[type=submit]').click();await page.waitForFunction(t=>document.querySelector('.fleet-assignment-dialog .form-error').textContent.includes(t),text);assert.match(await dialog.locator('.form-error').innerText(),new RegExp(text));
 }
 const before=(await rpc()).length;await page.evaluate(()=>mode='stale');await dialog.locator('[type=submit]').click();await page.waitForFunction(()=>document.querySelector('[data-current]').textContent.includes('Ativo sem login'));
 assert.equal((await rpc()).length,before+1);assert.match(await dialog.locator('.form-error').innerText(),/outro utilizador/);
 await dialog.locator('select').selectOption('');await page.evaluate(()=>{mode='ok';delaySave=true;});
 await dialog.locator('form').evaluate(f=>{f.requestSubmit();f.requestSubmit();});await page.waitForFunction(()=>!document.querySelector('.fleet-assignment-dialog'));
 assert.equal((await rpc()).length,before+2);const last=(await rpc()).at(-1).body;assert.equal(last.p_novo_colaborador_id,null);assert.equal(last.p_revisao_esperada,8);
 assert.match(await page.locator('.fleet-detail-head').innerText(),/Sem atribuição/);
 const hist=page.locator('.fleet-assignment-history');assert.match(await hist.innerText(),/Antigo → Sem atribuição/);assert.match(await hist.innerText(),/Administrativo/);assert.match(await hist.innerText(),/Outro motivo/);assert.match(await hist.innerText(),/30\/09\/2026/);assert.equal(await hist.locator('button').count(),0);
 await page.evaluate(async()=>{historyRows[0].colaborador_anterior_id='unknown';await mod.refresh();});assert.match(await hist.innerText(),/Colaborador indisponível/);
 for(const width of [1280,375]){
  await page.setViewportSize({width,height:800});await open();assert.equal(await dialog.evaluate(d=>d.getBoundingClientRect().width<=innerWidth),true);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:(process.env.TEMP||'/tmp')+'/vehicle-assignment-'+width+'.png',fullPage:true});await close();
 }
 await open();await dialog.locator('select').selectOption('b');await page.evaluate(()=>failHistory=true);await dialog.locator('[type=submit]').click();await dialog.locator('[type=submit]').filter({hasText:'RECARREGAR FICHA'}).waitFor();const confirmedCount=(await rpc()).length;await page.evaluate(()=>failHistory=false);await dialog.locator('[type=submit]').click();await page.waitForFunction(()=>!document.querySelector('.fleet-assignment-dialog'));assert.equal((await rpc()).length,confirmedCount);assert.match(await page.locator('.fleet-detail-head').innerText(),/Ativo sem login/);
 await page.evaluate(()=>failCandidates=true);await button.click();await dialog.locator('.form-error').filter({hasText:'carregar'}).waitFor();assert.equal(await dialog.locator('[type=submit]').isDisabled(),true);await close();
 await page.evaluate(async()=>{allowed=false;await mod.refresh();});assert.equal(await button.count(),0);
 assert.deepEqual(errors,[]);console.log('PASS: assignment offline — names, eligibility, payload, idempotency, errors, stale, double submit, history, permissions, desktop/mobile');
}finally{await browser.close();}
