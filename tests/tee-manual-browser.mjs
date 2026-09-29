// Runs the actual manual TEE functions with an isolated DOM and mocked persistence.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const app = await readFile(new URL('../src/app.js', import.meta.url), 'utf8');
const index = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const stylesheets = [...index.matchAll(/<link[^>]+rel="stylesheet"[^>]*>/g)].map(match => match[0]).join('');
const manual = app.slice(app.indexOf('function teeApprovalLabel('), app.indexOf('function phasePlanningRecord('));
const browser = await chromium.launch({ channel: process.env.PLANNING_BROWSER || 'msedge', headless: true });
try {
  const page = await browser.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (/^\/src\/[\w-]+\.js$/.test(url.pathname)) return route.fulfill({ contentType: 'text/javascript; charset=utf-8', body: await readFile(new URL('..' + url.pathname, import.meta.url), 'utf8') });
    if (/^\/src\/[\w-]+\.css$/.test(url.pathname)) return route.fulfill({ contentType: 'text/css; charset=utf-8', body: await readFile(new URL('..' + url.pathname, import.meta.url), 'utf8') });
    if (url.pathname !== '/') return route.abort();
    await route.fulfill({ contentType: 'text/html; charset=utf-8', body: `
      <meta name="viewport" content="width=device-width, initial-scale=1">
      ${stylesheets}
      <div class="dialog-backdrop" id="workflow-dialog" hidden><section class="work-dialog-card workflow-dialog-card" role="dialog" aria-modal="true"><div class="panel-title"><span id="workflow-dialog-title"></span><button type="button">×</button></div><div id="workflow-dialog-content"></div></section></div>
      <script type="module">
        import { teeState } from '/src/tee-index.js';
        const $ = selector => document.querySelector(selector);
        const safeText = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
        const canEditWork = () => true;
        const selectedWorkId = 'work', works = [{id:'work',data_fim_contratual_atual:'2026-12-31'}], isSupabaseConfigured = true;
        window.calls=[]; window.messages=[]; window.mode='success';
        const toast = message => messages.push(message);
        const renderWorkDetail = () => {};
        const closeWorkflowDialog = () => { $('#workflow-dialog').hidden = true; };
        const workDetails = {phases:[{id:'phase',codigo:'F01',descricao:'Estaleiro'}],rfis:[],tees:[]};
        const supabase = async (path,options) => {
          const body=JSON.parse(options.body); calls.push({path,method:options.method,body});
          if(mode==='error')return Response.json({message:'Gravação recusada.'},{status:403});
          if(mode==='empty')return Response.json([]);
          return Response.json([{...workDetails.tees[0],...body,id:workDetails.tees[0]?.id || 'new-tee'}]);
        };
        ${manual}
        window.open = value => { workDetails.tees = value ? [structuredClone(value)] : []; openTeeDialog(value?.id || ''); };
        window.getTee = () => workDetails.tees[0];
        window.getWork = () => works[0];
      </script>` });
  });
  await page.goto('http://localhost/');
  const prior = { id: 'tee', obra_id: 'work', numero: 'TEE 01', descricao: 'Anterior', fase_id: 'phase', rfi_id: 'unloaded-rfi', revisao: null, valor: 100, preco_custo: 70, dias_prorrogacao: 3, data_inicio_execucao: '2026-10-01', data_fim_execucao: '2026-10-31', data_aprovacao_cliente: '2026-09-01', estado_operacional: null };
  const open = value => page.evaluate(value => window.open(value), value);
  const submit = () => page.locator('#tee-form button[type="submit"]').click();
  const operational = page.locator('[name="estado_operacional"]');
  const client = page.locator('[name="estado_aprovacao_cliente"]');
  for (const [clientState, sent, expected] of [
    ['aprovado', null, 'aprovado'], ['recusado', null, 'rejeitado'],
    ['pendente', '2026-09-01', 'aguarda_resposta'], ['pendente', null, 'em_elaboracao'],
  ]) {
    const tee = { ...prior, estado_aprovacao_cliente: clientState, data_envio: sent };
    await open(tee);
    assert.equal(await operational.inputValue(), expected);
    assert.equal(await client.inputValue(), clientState);
    assert.deepEqual(await page.evaluate(() => getTee()), tee);
    assert.equal(await page.evaluate(() => calls.length), 0);
  }
  assert.deepEqual(await operational.locator('option').allTextContents(), ['Em elaboração', 'Aguarda resposta', 'Aprovado', 'Rejeitado']);
  assert.deepEqual(await client.locator('option').allTextContents(), ['Pendente', 'Aprovado', 'Recusado']);
  for (const [op, customer] of [['em_elaboracao','pendente'],['aguarda_resposta','pendente'],['aprovado','aprovado'],['rejeitado','recusado']]) {
    await operational.selectOption(op);
    assert.equal(await client.inputValue(), customer);
  }
  await client.selectOption('aprovado');
  assert.equal(await operational.inputValue(), 'aprovado');
  await client.selectOption('recusado');
  assert.equal(await operational.inputValue(), 'rejeitado');
  await client.selectOption('pendente');
  assert.equal(await operational.inputValue(), 'em_elaboracao');
  await page.evaluate(() => { document.querySelector('[name="estado_operacional"]').value = 'aprovado'; });
  await submit();
  assert.match(await page.locator('.form-error').innerText(), /incompatíveis/);
  assert.equal(await page.evaluate(() => calls.length), 0);

  // A legacy NULL is saved only on explicit submission; unchanged values are omitted.
  const pending = { ...prior, estado_aprovacao_cliente: 'pendente', data_envio: '2026-09-01' };
  // Actual modal styles: full-width multiline description, aligned and contained.
  for (const width of [1440, 1366, 1024, 768, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    await open(pending);
    await page.locator('[name="descricao"]').fill('Descrição multilinha do TEE.\nSegunda linha para verificar a altura e o alinhamento.\n' + 'Texto longo '.repeat(30));
    await page.locator('.workflow-dialog-card').evaluate(card => { card.scrollTop = 0; });
    const geometry = await page.locator('[name="descricao"]').evaluate(field => {
      const rect = element => { const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height, right: r.right, bottom: r.bottom }; };
      const label = field.closest('label'), form = field.form;
      return { field: rect(field), label: rect(label), first: rect(form.elements.numero), next: rect(label.nextElementSibling), style: { resize: getComputedStyle(field).resize, display: getComputedStyle(field).display }, viewport: innerWidth };
    });
    assert.ok(Math.abs(geometry.field.width - geometry.label.width) < 1, JSON.stringify(geometry));
    assert.ok(Math.abs(geometry.field.x - geometry.first.x) < 1);
    assert.ok(geometry.field.height >= 104);
    assert.ok(geometry.field.y > geometry.label.y);
    assert.ok(geometry.field.bottom <= geometry.next.y);
    assert.ok(geometry.field.x >= 0 && geometry.field.right <= geometry.viewport);
    assert.deepEqual(geometry.style, { resize: 'vertical', display: 'block' });
    if (process.env.TEE_SCREENSHOT_DIR && [1366, 390].includes(width)) {
      await page.screenshot({ path: process.env.TEE_SCREENSHOT_DIR + '/tee-description-' + width + '.png' });
    }
  }
  await page.setViewportSize({ width: 1366, height: 900 });

  await open(pending);
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(await page.evaluate(() => calls[0]), { path: 'alteracoes_tee?id=eq.tee&select=*', method: 'PATCH', body: { estado_operacional: 'aguarda_resposta' } });
  assert.deepEqual(await page.evaluate(() => getTee()), { ...pending, estado_operacional: 'aguarda_resposta' });
  assert.equal(await page.locator('#workflow-dialog').isHidden(), true);

  await open({ ...pending, estado_operacional: 'aguarda_resposta' });
  await operational.selectOption('aprovado');
  await page.locator('[name="dias_prorrogacao"]').fill('15');
  await page.locator('[name="descricao"]').fill('Revisto');
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(await page.evaluate(() => calls[1].body), { descricao: 'Revisto', dias_prorrogacao: 15, estado_operacional: 'aprovado', estado_aprovacao_cliente: 'aprovado' });
  assert.equal(await page.evaluate(() => getTee().data_aprovacao_cliente), prior.data_aprovacao_cliente);
  assert.equal(await page.evaluate(() => getWork().data_fim_contratual_atual), '2026-12-31');

  await open({ ...pending, estado_operacional: 'aguarda_resposta' });
  await page.locator('[name="descricao"]').fill('Falha preserva edição');
  await page.evaluate(() => { window.mode = 'error'; });
  await submit();
  await page.waitForFunction(() => document.querySelector('.form-error').textContent.includes('Gravação recusada'));
  assert.equal(await page.locator('#workflow-dialog').isVisible(), true);
  assert.equal(await page.locator('[name="descricao"]').inputValue(), 'Falha preserva edição');
  assert.equal(await page.evaluate(() => getTee().descricao), pending.descricao);
  await page.evaluate(() => { window.mode = 'empty'; });
  await submit();
  await page.waitForFunction(() => document.querySelector('.form-error').textContent.includes('não confirmou'));
  assert.equal(await page.locator('#workflow-dialog').isVisible(), true);

  await open(null);
  await page.evaluate(() => { window.mode = 'success'; });
  await page.locator('[name="descricao"]').fill('Novo');
  await page.locator('[name="fase_id"]').selectOption('phase');
  await operational.selectOption('rejeitado');
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  const created = await page.evaluate(() => calls.at(-1));
  assert.equal(created.method, 'POST');
  assert.equal(created.body.estado_operacional, 'rejeitado');
  assert.equal(created.body.estado_aprovacao_cliente, 'recusado');
  assert.equal(created.body.obra_id, 'work');

  // Existing NULL phase is displayed without any write or automatic association.
  const phaseSelect = page.locator('[name="fase_id"]');
  const noPhase = page.locator('[name="sem_fase_especifica"]');
  const unassigned = { ...pending, fase_id: null, estado_operacional: 'aguarda_resposta' };
  const beforeOpen = await page.evaluate(() => calls.length);
  await open(unassigned);
  assert.equal(await noPhase.isChecked(), true);
  assert.equal(await phaseSelect.inputValue(), '');
  assert.deepEqual(await page.evaluate(() => getTee()), unassigned);
  assert.equal(await page.evaluate(() => calls.length), beforeOpen);
  await page.locator('[name="descricao"]').fill('Editado sem fase');
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => getTee().fase_id), null);
  assert.equal(await page.evaluate(() => Object.hasOwn(calls.at(-1).body, 'fase_id')), false);

  // Explicitly removing an existing phase sends NULL, never F01.
  await open({ ...pending, estado_operacional: 'aguarda_resposta' });
  assert.equal(await noPhase.isChecked(), false);
  await noPhase.check();
  assert.equal(await phaseSelect.inputValue(), '');
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.deepEqual(await page.evaluate(() => calls.at(-1).body), { fase_id: null, estado_operacional: 'aguarda_resposta' });
  assert.equal(await page.evaluate(() => getTee().fase_id), null);

  // A new TEE can be created without a phase even when F01 exists.
  await open(null);
  await page.locator('[name="descricao"]').fill('Novo sem fase');
  await phaseSelect.selectOption('phase');
  assert.equal(await noPhase.isChecked(), false);
  await noPhase.check();
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => calls.at(-1).method), 'POST');
  assert.equal(await page.evaluate(() => calls.at(-1).body.fase_id), null);

  // Choosing a phase later is explicit, and clearing the selector is also NULL.
  await open(unassigned);
  await phaseSelect.selectOption('phase');
  assert.equal(await noPhase.isChecked(), false);
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => calls.at(-1).body.fase_id), 'phase');
  await open({ ...unassigned, fase_id: 'phase' });
  await phaseSelect.selectOption('');
  assert.equal(await noPhase.isChecked(), true);
  await submit();
  await page.locator('#workflow-dialog').waitFor({ state: 'hidden' });
  assert.equal(await page.evaluate(() => calls.at(-1).body.fase_id), null);
  assert.ok(await page.evaluate(() => calls.every(call => call.path.startsWith('alteracoes_tee?'))));
  assert.deepEqual(errors, []);
  console.log('PASS: NULL phase creation/editing without F01 fallback; description layout at 320–1440px; manual TEE states, NULL UI defaults, compatible selections, sparse PATCH, preserved fields, errors, POST and no contractual-date writes.');
} finally { await browser.close(); }
