// Synthetic browser reads only; every request is intercepted locally.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const browser=await chromium.launch({channel:process.env.PLANNING_BROWSER || 'msedge',headless:true});
let passed=0;
try {
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(/^\/src\/[\w-]+\.js$/.test(u.pathname))return route.fulfill({contentType:'text/javascript',body:await readFile(new URL('..'+u.pathname,import.meta.url),'utf8')});
  if(u.pathname!=='/')return route.abort();
  return route.fulfill({contentType:'text/html',body:`<meta charset="utf-8"><select id="planning-work"></select><div id="planning-content"></div><script type="module">
   import {createPlanningModule,canReadPlanningCosts} from '/src/planning.js';
   window.role=new URL(location.href).searchParams.get('role')||'';window.calls=[];window.messages=[];
   const task={id:'task',fase_id:'phase',codigo:'F01.1',descricao:'Tarefa operacional sintética',responsavel:'Responsável sintético',peso_percentual:100,percentual_executado:25,data_inicio_prevista:'2026-10-01',data_fim_prevista:'2026-10-10',valor_orca_pl:987654.32,valor_estimado:987654.32,custo_estado:'adjudicado'};
   const api=async(path,options={})=>{calls.push({path,method:options.method||'GET'});
    if(path.startsWith('fases?'))return Response.json([{id:'phase',obra_id:'work',codigo:'F01',descricao:'Fase sintética',peso_percentual:100}]);
    if(path.startsWith('planeamento_itens?'))return Response.json([task]);
    if(path.startsWith('itens_orcamento?'))return Response.json([{id:'budget',fase_id:'phase',codigo:'ECONOMIC-SECRET'}]);
    if(path==='rpc/fn_resumo_custos_obra'){
     if(!canReadPlanningCosts(role))throw Error('Forbidden cost request must never happen');
     const status=Number(new URL(location.href).searchParams.get('error'));
     if(status)return Response.json({code:'42501'},{status});
     return Response.json({real:{total:12345.67},por_concluir:{pl:20},componentes:[{planeamento_item_id:'task',valor_real_pl:12345.67,estado_custo:'concluido'}]});
    }
    return Response.json([]);
   };
   window.module=createPlanningModule({supabase:api,isSupabaseConfigured:true,getWorks:()=>[{id:'work',numero:1,nome:'Obra sintética'}],getRole:()=>role,toast:m=>messages.push(m)});
   window.ready=module.refresh();
  </script>`});
 });
 const allowed=['gestao_plataforma','gerencia','administrativo','financeiro','diretor_obra','adjunto','preparador'];
 const denied=['encarregado','unknown',''];
 for(const [width,height] of [[1440,900],[820,1180],[390,844]]){
  await page.setViewportSize({width,height});
  for(const role of [...allowed,...denied]){
   await page.goto('http://localhost/?role='+role);await page.evaluate(()=>ready);
   assert.equal(await page.locator('[data-edit-item=task] [name=descricao]').inputValue(),'Tarefa operacional sintética');
   const evidence=await page.evaluate(()=>({calls,messages,html:document.querySelector('#planning-content').innerHTML}));
   const summary=evidence.calls.filter(x=>x.path==='rpc/fn_resumo_custos_obra');
   const budget=evidence.calls.filter(x=>x.path.startsWith('itens_orcamento?'));
   const itemRead=evidence.calls.find(x=>x.path.startsWith('planeamento_itens?')).path;
   if(allowed.includes(role)){
    assert.equal(summary.length,1);assert.equal(budget.length,1);
    assert.equal(await page.locator('[name=valor_orca_pl]').count(),1);
    assert.equal(await page.locator('.planning-cost-reference').count(),1);
    assert.match(evidence.html,/ECONOMIC-SECRET/);
   }else{
    assert.equal(summary.length,0);assert.equal(budget.length,0);
    assert.doesNotMatch(itemRead,/select=\*|valor_|custo_|item_orcamento_id|compromisso_/);
    assert.equal(await page.locator('[name=valor_orca_pl],[name=custo_estado],[name=item_orcamento_id],.planning-cost-reference,.planning-cost-summary').count(),0);
    assert.doesNotMatch(evidence.html,/987654|ECONOMIC-SECRET|CUSTOS INDISPONÍVEIS|VALOR ORÇA/);
   }
   assert.deepEqual(evidence.messages,[]);
   assert.equal(evidence.calls.filter(x=>['PATCH','DELETE','PUT'].includes(x.method)).length,0);
   passed++;console.log('PASS '+(role||'no-profile')+' '+width+'x'+height);
  }
 }
 // The same module must discard previous costs on a later restricted read.
 await page.goto('http://localhost/?role=gestao_plataforma');await page.evaluate(()=>ready);
 await page.evaluate(async()=>{role='encarregado';calls=[];await module.refresh();});
 assert.equal(await page.locator('.planning-cost-summary,[name=valor_orca_pl]').count(),0);
 assert.equal(await page.evaluate(()=>calls.some(x=>x.path==='rpc/fn_resumo_custos_obra'||x.path.startsWith('itens_orcamento?'))),false);
 passed++;console.log('PASS previous costs removed on restricted reload');
 for(const status of [403,500]){
  await page.goto('http://localhost/?role=diretor_obra&error='+status);await page.evaluate(()=>ready);
  assert.match(await page.evaluate(()=>messages.join(' ')),/Não foi possível carregar os custos/);
  assert.match(await page.locator('.planning-cost-reference').textContent(),/CUSTOS INDISPONÍVEIS/);
  passed++;console.log('PASS authorized '+status+' remains a visible error');
 }
 assert.deepEqual(errors,[]);console.log(passed+' PASS; 0 FAIL; clean console; synthetic data only.');
}finally{await browser.close();}
