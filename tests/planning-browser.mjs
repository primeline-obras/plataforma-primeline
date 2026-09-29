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
        window.calls=[]; window.messages=[]; window.dependencyFailure=new URL(location.href).searchParams.get('failure');
        const tasks=['a','b'].map(id=>({id,fase_id:'phase',codigo:id,descricao:id,peso_percentual:50,percentual_executado:0,data_inicio_prevista:'2026-10-01',data_fim_prevista:'2026-10-10'}));
        tasks.push({...tasks[0],id:'archived',codigo:'ARQ',descricao:'Arquivada',arquivado_em:'2026-09-28'});
        const api=async(path, options)=>{
          calls.push({path,options});
          if(path.startsWith('fases?'))return Response.json([{id:'phase',obra_id:'work',codigo:'F01',descricao:'Fase',peso_percentual:100}]);
          if(path.startsWith('planeamento_itens?'))return Response.json(tasks);
          if(path.startsWith('planeamento_itens_dependencias?')) {
            if(dependencyFailure==='http')return new Response('{}',{status:500});
            if(dependencyFailure==='network')throw new Error('Offline');
            if(dependencyFailure==='invalid')return Response.json({});
            return Response.json([]);
          }
          if(path==='rpc/fn_resumo_custos_obra')return Response.json({real:{},por_concluir:{},componentes:[]});
          if(path==='rpc/fn_guardar_planeamento_lote')return new Response('{"code":"PGRST202"}',{status:404});
          return Response.json([]);
        };
        window.module=createPlanningModule({supabase:api,isSupabaseConfigured:true,getWorks:()=>[{id:'work',numero:1,nome:'Teste'}],getRole:()=> 'diretor_obra',toast:m=>messages.push(m)});
        module.show();
      </script>` });
  });
  await page.goto('http://planning.test/');
  await page.locator('.planning-work-data summary').click();
  assert.match(await page.locator('.planning-work-data').innerText(), /Prazo contratual não configurado/);
  assert.match(await page.locator('.planning-work-data').innerText(), /Fim operacional previsto/);
  assert.equal(await page.locator('.planning-unified-detail > header > span').innerText(), '2 TAREFAS');
  assert.equal(await page.locator('[data-dependency-choice] option[value="archived"]').count(), 0);
  assert.equal(await page.locator('[data-edit-item="a"] [data-dependency-choice] option[value="b"]').count(), 1);
  const description = page.locator('[data-edit-item="a"] [name="descricao"]');
  await description.fill('Alteração local');
  await page.locator('[data-toggle-editor-phase]').click();
  await page.locator('[data-toggle-editor-phase]').click();
  assert.equal(await description.inputValue(), 'Alteração local');
  assert.match(await page.locator('[data-save-batch]').innerText(), /1/);
  await page.locator('[data-remove-task="a"]').click();
  assert.match(await page.locator('.planning-weights').innerText(), /FALTA DISTRIBUIR 50.00%/);
  assert.equal(await page.locator('.planning-unified-detail > header > span').innerText(), '1 TAREFAS');
  assert.equal(await page.locator('[data-edit-item="b"] [data-dependency-choice] option[value="a"]').count(), 0);
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

  for (const failure of ['http', 'network', 'invalid']) {
    await page.goto('http://planning.test/?failure=' + failure);
    await page.waitForFunction(() => messages.some(message => message.includes('dependências não foram carregadas')));
    assert.equal(await page.locator('[data-edit-item]').count(), 2);
    assert.match(await page.locator('[role="alert"]').innerText(), /preview e a gravação estão bloqueados/);
    await description.fill('Edição durante falha');
    assert.equal(await page.locator('[data-save-batch]').isDisabled(), true);
    await page.locator('[data-toggle-editor-phase]').click();
    await page.locator('[data-toggle-editor-phase]').click();
    assert.equal(await description.inputValue(), 'Edição durante falha');
    assert.equal(await page.locator('[data-save-batch]').isDisabled(), true);
    // Exercise the handler guards even if a click bypasses the disabled button.
    await page.evaluate(() => {
      document.querySelector('[data-save-batch]').dispatchEvent(new MouseEvent('click', { bubbles: true }));
      const button = document.createElement('button');
      button.dataset.confirmBatch = '';
      document.querySelector('#planning-content').append(button);
      button.click();
      button.remove();
    });
    assert.equal(await page.locator('.planning-batch-preview').count(), 0);
    assert.equal(await page.evaluate(() => calls.filter(call => call.path === 'rpc/fn_guardar_planeamento_lote').length), 0);
    assert.equal(await page.evaluate(() => module.hasUnsavedChanges()), true);
    await page.evaluate(() => { window.dependencyFailure = null; window.reloadPromise = module.refresh(); });
    await page.locator('.platform-decision-dialog button[type="submit"]').click();
    await page.evaluate(() => window.reloadPromise);
    assert.equal(await page.locator('[role="alert"]').count(), 0);
    await description.fill('Edição após recuperação');
    assert.equal(await page.locator('[data-save-batch]').isEnabled(), true);
    await page.locator('[data-save-batch]').click();
    assert.equal(await page.locator('[data-confirm-batch]').isEnabled(), true);
    await page.locator('[data-confirm-batch]').click();
    await page.waitForFunction(() => calls.some(call => call.path === 'rpc/fn_guardar_planeamento_lote'));
  }
  assert.deepEqual(errors, []);
  console.log('PASS: falhas de dependências e recuperação, exclusão de arquivo, edições locais, fases recolhidas, arquivo, pesos, preview e falha RPC preservam o lote.');
} finally { await browser.close(); }
