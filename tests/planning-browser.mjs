// Offline browser regression. All requests are fulfilled locally; no Supabase connection.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const browser = await chromium.launch({ channel: process.env.PLANNING_BROWSER || 'msedge', headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith('/src/') && /^\/src\/[\w-]+\.js$/.test(url.pathname)) {
      return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL(`..${url.pathname}`, import.meta.url), 'utf8') });
    }
    if (url.pathname !== '/') return route.abort();
    await route.fulfill({ contentType: 'text/html', body: `<select id="planning-work"></select><div id="planning-content"></div>
      <script type="module">
        import { createPlanningModule } from '/src/planning.js';
        window.calls=[]; window.messages=[];
        const tasks=['a','b'].map(id=>({id,fase_id:'phase',codigo:id,descricao:id,peso_percentual:50,percentual_executado:0,data_inicio_prevista:'2026-10-01',data_fim_prevista:'2026-10-10'}));
        const api=async(path, options)=>{
          calls.push({path,options});
          if(path.startsWith('fases?'))return Response.json([{id:'phase',obra_id:'work',codigo:'F01',descricao:'Fase',peso_percentual:100}]);
          if(path.startsWith('planeamento_itens?'))return Response.json(tasks);
          if(path==='rpc/fn_resumo_custos_obra')return Response.json({real:{},por_concluir:{},componentes:[]});
          if(path==='rpc/fn_guardar_planeamento_lote')return new Response('{"code":"PGRST202"}',{status:404});
          return Response.json([]);
        };
        window.module=createPlanningModule({supabase:api,isSupabaseConfigured:true,getWorks:()=>[{id:'work',numero:1,nome:'Teste'}],getRole:()=> 'diretor_obra',toast:m=>messages.push(m)});
        module.show();
      </script>` });
  });
  await page.goto('http://planning.test/');
  const description = page.locator('[data-edit-item="a"] [name="descricao"]');
  await description.fill('Alteração local');
  await page.locator('[data-toggle-editor-phase]').click();
  await page.locator('[data-toggle-editor-phase]').click();
  assert.equal(await description.inputValue(), 'Alteração local');
  assert.match(await page.locator('[data-save-batch]').innerText(), /1/);
  await page.locator('[data-remove-task="a"]').click();
  assert.match(await page.locator('.planning-weights').innerText(), /FALTA DISTRIBUIR 50.00%/);
  await page.locator('[data-save-batch]').click();
  assert.equal(await page.locator('[data-confirm-batch]').isDisabled(), true);
  await page.locator('[data-redistribute]').click();
  assert.equal(await page.locator('[data-edit-item="b"] [name="peso_percentual"]').inputValue(), '100');
  await page.locator('[data-save-batch]').click();
  await page.locator('[data-archive-reason]').fill('Teste de retirada');
  await page.locator('[data-confirm-batch]').click();
  await page.waitForFunction(() => messages.some(message => message.includes('suporte transacional')));
  assert.equal(await page.evaluate(() => module.hasUnsavedChanges()), true);
  assert.equal(await page.evaluate(() => calls.filter(call => call.options && call.path !== 'rpc/fn_resumo_custos_obra').length), 1);
  await page.evaluate(() => module.show());
  assert.equal(await description.inputValue(), 'Alteração local');
  assert.deepEqual(errors, []);
  console.log('PASS: edições locais, fases recolhidas, arquivo, pesos, preview e falha RPC preservam o lote.');
} finally { await browser.close(); }
