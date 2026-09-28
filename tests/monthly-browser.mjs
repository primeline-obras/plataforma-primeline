// Entirely offline: no Supabase, SQL, or external network request.
import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const browser = await chromium.launch({ channel: 'msedge', headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1400, height: 1000 } });
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (/^\/(src\/[\w-]+\.(js|css)|tests\/monthly-fixture.mjs)$/.test(url.pathname)) return route.fulfill({ contentType: url.pathname.endsWith('.css') ? 'text/css' : 'text/javascript', body: await readFile(new URL(`..${url.pathname}`, import.meta.url), 'utf8') });
    if (url.pathname !== '/') return route.abort();
    return route.fulfill({ contentType: 'text/html', body: `<link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><main style="padding:24px"><div id="root"></div></main><script type="module">
      import { createFinancialMapModule } from '/src/monthly-map.js';
      import { summaryFixture, preservedFixture } from '/tests/monthly-fixture.mjs';
      window.calls=[]; window.messages=[]; window.mode='missing';
      const api=async(path,options)=>{
        const body=JSON.parse(options.body); calls.push({path,body});
        if(mode==='missing')return Response.json({code:'PGRST202'},{status:404});
        if(path==='rpc/fn_resumo_financeiro_mensal_v1')return Response.json(summaryFixture());
        if(path==='rpc/fn_origens_financeiras_mensais_v1')return Response.json({version:1,work_id:'work',snapshot_id:mode==='stale'?'old':'snap1',month:body.p_mes,stage:body.p_estagio,total_amount:100,next_cursor:null,rows:[{allocation_id:'alloc1',origin_id:'invoice1',origin_type:'faturacao',document_id:'invoice1',movement_id:'receipt1',label:'FT 001',amount:100,date:'2026-09-20',competence_month:'2026-08'}]});
        if(path==='rpc/fn_definir_estado_mensal_v1')return Response.json({code:'STALE_REVISION',message:'Estado alterado por outro utilizador',conflicts:[{month:body.p_mes}]},{status:409});
        if(path==='rpc/fn_recalcular_previsao_mensal_v1')return Response.json({version:1,committed:true,preserved:preservedFixture,summary:summaryFixture()});
        throw new Error('Pedido não permitido: '+path);
      };
      window.module=createFinancialMapModule({root:document.querySelector('#root'),supabase:api,isConfigured:true,getWorks:()=>[{id:'work',numero:1,nome:'Obra de teste offline'}],euro:new Intl.NumberFormat('pt-PT',{style:'currency',currency:'EUR'}),toast:m=>messages.push(m),canManage:()=>true});
      await module.show();
    </script>` });
  });
  await page.goto('https://monthly.test/');
  await page.getByRole('alert').filter({ hasText: 'ainda não está disponível' }).waitFor();
  assert.equal(await page.locator('[data-monthly-cell]').count(), 0);
  assert.equal(await page.evaluate(() => calls.length), 1);
  await page.evaluate(() => { mode = 'success'; });
  await page.locator('[data-monthly-refresh]').click();
  await page.locator('[data-monthly-cell="2026-09:received"]').waitFor();
  assert.equal(await page.locator('[data-monthly-cell]').count(), 72);
  assert.equal(await page.locator('[data-monthly-state="2026-01"]').count(), 0);
  assert.equal(await page.evaluate(() => calls.filter(call => call.path.includes('origens')).length), 0);
  await page.locator('[data-monthly-cell="2026-09:received"]').click();
  await page.getByText('FT 001 ·', { exact: false }).waitFor();
  assert.match(await page.locator('.monthly-detail').innerText(), /competência 2026-08/);
  await page.locator('[data-monthly-state="2026-02"]').selectOption('em_fecho');
  await page.locator('[data-monthly-save-state="2026-02"]').click();
  await page.getByRole('alert').filter({ hasText: 'Estado alterado' }).waitFor({ timeout: 5000 }).catch(async error => { console.log(await page.evaluate(() => ({ calls, messages, alerts: [...document.querySelectorAll('[role="alert"]')].map(node => node.textContent) }))); throw error; });
  assert.equal(await page.locator('[data-monthly-state="2026-02"]').inputValue(), 'aberto');
  assert.equal(await page.evaluate(() => messages.length), 0);
  await page.locator('[data-monthly-recalculate]').click();
  await page.waitForFunction(() => messages.includes('Previsão recalculada; histórico preservado.'));
  assert.ok(await page.evaluate(() => calls.find(call => call.path.includes('recalcular')).body.p_meses.every(month => month !== '2026-01')));
  await page.evaluate(() => { mode = 'stale'; });
  await page.locator('[data-monthly-cell="2026-09:received"]').click();
  await page.getByRole('alert').filter({ hasText: 'não corresponde' }).waitFor();
  assert.equal(await page.locator('.monthly-detail li').count(), 0);
  await page.locator('[data-monthly-close-detail]').click();
  await mkdir(new URL('../outputs/', import.meta.url), { recursive: true });
  await page.screenshot({ path: new URL('../outputs/monthly-map-offline.png', import.meta.url).pathname.replace(/^\/([A-Z]:)/i, '$1'), fullPage: true });
  await page.evaluate(() => module.invalidate({ workId: 'work' }));
  assert.equal(await page.locator('[data-monthly-cell]').count(), 0);
  assert.ok(await page.evaluate(() => calls.every(call => call.path.startsWith('rpc/'))));
  assert.deepEqual(errors, []);
  console.log('PASS: indisponibilidade, seis estágios, detalhe lazy, conflitos, recálculo e invalidação após planeamento.');
} finally { await browser.close(); }

