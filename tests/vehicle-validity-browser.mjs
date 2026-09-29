// Offline browser integration: real fleet module and styles, no Supabase writes.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const index = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const styles = [...index.matchAll(/<link[^>]+rel="stylesheet"[^>]*>/g)].map(match => match[0]).join('');
const browser = await chromium.launch({ channel: process.env.PLANNING_BROWSER || 'msedge', headless: true });
try {
  const page = await browser.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (/^\/src\/[\w-]+\.(js|css)$/.test(url.pathname)) return route.fulfill({ contentType: url.pathname.endsWith('.js') ? 'text/javascript; charset=utf-8' : 'text/css; charset=utf-8', body: await readFile(new URL('..' + url.pathname, import.meta.url), 'utf8') });
    if (url.pathname !== '/') return route.abort();
    await route.fulfill({ contentType: 'text/html; charset=utf-8', body: `<meta name="viewport" content="width=device-width, initial-scale=1">${styles}<main id="fleet"></main><script type="module">
      import { createVehiclesModule } from '/src/vehicles.js';
      import { renewalExpiry } from '/src/vehicle-validity.js';
      window.calls=[]; window.messages=[]; window.mode='success'; window.historyFailure=false;
      window.current={id:'v1',marca_modelo:'Viatura de teste',matricula:'AA-00-AA',seguro_data:'2026-10-01',data_inspecao_proxima:'2026-11-01'};
      window.events=[{id:'initial-validity',viatura_id:'v1',tipo:'seguro',data:'2026-01-01',validade_operacao:'correcao_data',validade_anterior:null,validade_nova:'2026-10-01',validade_opcao:null,motivo:'Documento <confirmado>'},{id:'ordinary',viatura_id:'v1',tipo:'revisao',data:'2026-01-01',descricao:'Evento normal'}];
      const api=async(path,options={})=>{
        calls.push({path,method:options.method||'GET',body:options.body?JSON.parse(options.body):null});
        if(path==='rpc/fn_guardar_validade_viatura'){
          const p=JSON.parse(options.body);
          if(mode==='stale')return Response.json({code:'STALE_REVISION'},{status:409});
          if(mode==='forbidden')return Response.json({code:'42501'},{status:403});
          if(mode==='validation')return Response.json({code:'VALIDATION_FAILED'},{status:422});
          if(mode==='unconfirmed')return Response.json({version:1,committed:false});
          const column=p.p_tipo==='seguro'?'seguro_data':'data_inspecao_proxima';
          const expiry=p.p_operacao==='editar_data'?p.p_nova_data:renewalExpiry(p.p_data_base,p.p_validade_opcao,p.p_nova_data);
          const previous=current[column];
          current={...current,[column]:expiry};
          const event={id:'event-'+calls.length,viatura_id:'v1',tipo:p.p_tipo,data:p.p_data_base||'2026-09-29',descricao:'Validade atualizada',validade_operacao:p.p_operacao==='renovar'?'renovacao':'correcao_data',validade_anterior:previous,validade_nova:expiry,validade_base:p.p_data_base,validade_opcao:p.p_validade_opcao,motivo:p.p_motivo,registado_por:'admin',request_id:p.p_request_id};
          events.unshift(event);
          return Response.json({version:1,committed:true,idempotent:false,vehicle:current,validity:{},event,alert:{}});
        }
        if(path.startsWith('viaturas_eventos?')){
          if(options.method==='POST'){const event={id:'legacy',...JSON.parse(options.body)};events.unshift(event);return Response.json([event]);}
          if(historyFailure)return new Response('{}',{status:500});
          return Response.json(events);
        }
        if(path.startsWith('viaturas?')){
          if(options.method==='PATCH')current={...current,...JSON.parse(options.body)};
          return Response.json([current]);
        }
        return Response.json([]);
      };
      window.fleet=createVehiclesModule({root:document.querySelector('#fleet'),supabase:api,isConfigured:true,getCollaborators:()=>[],getSuppliers:()=>[],euro:new Intl.NumberFormat('pt-PT',{style:'currency',currency:'EUR'}),prettyDate:new Intl.DateTimeFormat('pt-PT'),toast:(message,type)=>messages.push({message,type})});
      fleet.show();
    </script>` });
  });
  await page.goto('http://localhost/');
  await page.locator('[data-fleet-validity]').first().waitFor();
  assert.equal(await page.locator('[data-fleet-validity]').count(), 4);
  const initial = page.locator('.fleet-timeline article').first();
  assert.match(await initial.innerText(), /Seguro · Correção de data/);
  assert.match(await initial.innerText(), /Validade: — → 01\/10\/2026/);
  assert.match(await initial.innerText(), /Motivo: Documento <confirmado>/);
  assert.equal(await initial.locator('confirmado').count(), 0, 'motivo é escapado');
  assert.doesNotMatch(await initial.innerText(), /Prazo:/);
  assert.equal(await initial.locator('button').count(), 0);
  const ordinaryBefore = await page.locator('.fleet-timeline article').filter({hasText:'Evento normal'}).innerHTML();
  const dialog = page.locator('.fleet-validity-dialog');
  const open = async (type, operation) => page.locator('[data-fleet-validity="'+type+'"][data-operation="'+operation+'"]').click();
  const submit = async () => dialog.locator('[type="submit"]').click();
  const rpcCalls = () => page.evaluate(() => calls.filter(call => call.path === 'rpc/fn_guardar_validade_viatura'));
  const close = () => dialog.locator('[data-validity-close]').last().click();
  for (const [option, expiry] of [['1_ano','2027-09-29'],['2_anos','2028-09-29'],['outra','2029-04-02']]) {
    const before = await page.evaluate(() => current.seguro_data);
    await open('seguro','renovar');
    await dialog.locator('[name="data_base"]').fill('2026-09-29');
    await dialog.locator('[name="validade_opcao"]').selectOption(option);
    if(option==='outra')await dialog.locator('[name="nova_data"]').fill(expiry);
    assert.equal(await dialog.locator('[data-validity-preview]').innerText(), expiry.split('-').reverse().join('/'));
    for(const width of [1366,390]){
      await page.setViewportSize({width,height:900});
      const rect=await dialog.boundingBox();
      assert.ok(rect.x>=0 && rect.x+rect.width<=width+1);
      assert.equal(await dialog.evaluate(node=>node.scrollWidth<=node.clientWidth+1),true);
    }
    await submit();
    await dialog.waitFor({state:'detached'});
    assert.equal(await page.locator('.fleet-deadline').first().locator('strong').first().innerText(),expiry.split('-').reverse().join('/'));
    const call=(await rpcCalls()).at(-1);
    assert.equal(call.body.p_data_atual_esperada,before);
    assert.equal(call.body.p_nova_data,option==='outra'?expiry:null);
    assert.equal(call.body.p_operacao,'renovar');
    assert.ok(call.body.p_request_id);
    const history = page.locator('.fleet-timeline article').first();
    assert.match(await history.innerText(), /Seguro · Renovação/);
    assert.ok((await history.innerText()).includes('Validade: '+before.split('-').reverse().join('/')+' → '+expiry.split('-').reverse().join('/')));
    assert.ok((await history.innerText()).includes('Prazo: '+({'1_ano':'1 ano','2_anos':'2 anos',outra:'Outra'})[option]));
    assert.doesNotMatch(await history.innerText(), /Motivo:/);
    assert.equal(await history.locator('button').count(), 0);

  }
  assert.equal(await page.locator('[data-fleet-edit-event]').count(),1);
  assert.equal(await page.locator('[data-fleet-delete-event]').count(),1);
  await open('inspecao','editar_data');
  await dialog.locator('[name="nova_data"]').fill('2027-05-12');
  await submit();
  assert.equal((await rpcCalls()).length,3,'motivo é obrigatório');
  await dialog.locator('[name="motivo"]').fill('Correção da data no documento');
  await submit();
  await dialog.waitFor({state:'detached'});
  const edited=(await rpcCalls()).at(-1).body;
  assert.equal(edited.p_operacao,'editar_data');
  assert.equal(edited.p_nova_data,'2027-05-12');
  assert.equal(edited.p_data_atual_esperada,'2026-11-01');
  assert.equal(edited.p_motivo,'Correção da data no documento');
  assert.equal(await page.locator('.fleet-deadline').nth(1).locator('strong').innerText(),'12/05/2027');
  const correction = page.locator('.fleet-timeline article').first();
  assert.match(await correction.innerText(), /Inspeção · Correção de data/);
  assert.match(await correction.innerText(), /Validade: 01\/11\/2026 → 12\/05\/2027/);
  assert.match(await correction.innerText(), /Motivo: Correção da data no documento/);
  assert.doesNotMatch(await correction.innerText(), /Prazo:/);
  assert.equal(await correction.locator('button').count(), 0);
  assert.equal(await page.locator('.fleet-timeline article').filter({hasText:'Evento normal'}).innerHTML(), ordinaryBefore);


  // Same dialog and content retain request ID across explicit retries.
  await open('seguro','editar_data');
  await dialog.locator('[name="nova_data"]').fill('2030-01-01');
  await dialog.locator('[name="motivo"]').fill('Correção');
  const cardBefore=await page.locator('.fleet-deadline').first().innerText();
  const historyBefore=await page.locator('.fleet-timeline').innerText();
  for(const [mode,text] of [['unconfirmed','não confirmou'],['stale','outro utilizador'],['forbidden','permissão'],['validation','inválidos']]){
    await page.evaluate(mode=>{window.mode=mode;},mode);
    await submit();
    await page.waitForFunction(text=>document.querySelector('.fleet-validity-dialog .form-error').textContent.includes(text),text);
    assert.equal(await page.locator('.fleet-deadline').first().innerText(),cardBefore);
    assert.equal(await page.locator('.fleet-timeline').innerText(),historyBefore);
    assert.equal(await dialog.locator('[name="nova_data"]').inputValue(),'2030-01-01');
  }
  const retries=(await rpcCalls()).slice(-4);
  assert.equal(new Set(retries.map(call=>call.body.p_request_id)).size,1);
  await close();
  // Success survives a failed history reload; never retries the write.
  await page.evaluate(()=>{window.mode='success';window.historyFailure=true;});
  await open('seguro','editar_data');
  await dialog.locator('[name="nova_data"]').fill('2030-02-03');
  await dialog.locator('[name="motivo"]').fill('Confirmado no documento');
  const count=(await rpcCalls()).length;
  await submit();
  await dialog.waitFor({state:'detached'});
  await page.waitForFunction(()=>messages.some(item=>item.message.includes('não foi possível atualizar o histórico')));
  assert.equal((await rpcCalls()).length,count+1);
  assert.equal(await page.locator('.fleet-deadline').first().locator('strong').innerText(),'03/02/2030');

  // Inspection's legacy form cannot write a due date, even with tampered controls.
  const legacy=page.locator('[data-fleet-event-form]');
  await page.locator('.fleet-form-card').first().locator('summary').click();
  await legacy.locator('[name="tipo"]').selectOption('inspecao');
  assert.equal(await legacy.locator('[name="atualizar_data"]').isDisabled(),true);
  const beforeLegacy=await page.evaluate(()=>calls.length);
  await legacy.evaluate(form=>{
    form.elements.atualizar_data.disabled=false;form.elements.atualizar_data.checked=true;
    form.elements.nova_data.disabled=false;form.elements.nova_data.value='2035-01-01';
    form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
  });
  assert.match(await legacy.locator('.form-error').innerText(),/card Seguro ou Inspeção/);
  assert.equal(await page.evaluate(()=>calls.length),beforeLegacy);
  // Revision retains the existing independent next-date behavior.
  await legacy.locator('[name="tipo"]').selectOption('revisao');
  await legacy.locator('[name="atualizar_data"]').check();
  await legacy.locator('[name="nova_data"]').fill('2027-02-03');
  await legacy.locator('[type="submit"]').click();
  await page.waitForFunction(()=>calls.some(call=>call.method==='PATCH'));
  const patch=await page.evaluate(()=>calls.find(call=>call.method==='PATCH'));
  assert.deepEqual(patch.body,{data_proxima_revisao:'2027-02-03'});
  assert.deepEqual(errors,[]);
  console.log('PASS: fleet validity modal, 1/2 years/custom, correction, errors, immediate cards, protected events, history failure, legacy inspection guard and responsive layout.');
} finally { await browser.close(); }
