// Offline TEE import regression: real frontend, mocked workbook decoder and RPC.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || 'playwright');
const browser = await chromium.launch({ channel: process.env.PLANNING_BROWSER || 'msedge', headless: true });
const headers = ['Nº TEE*', 'Obra (nº)*', 'Fase (código)', 'Descrição', 'Especialidade', 'Valor (€)', 'Preço de Custo (€)', 'Dias de Prorrogação', 'Data de Envio', 'Data de Resposta', 'Estado Aprovação Cliente', 'Revisão', 'Data Início Execução', 'Data Fim Execução', 'Estado Operacional'];
const itemHeaders = ['Nº TEE*', 'Nº Artigo*', 'Descrição*', 'Unidade', 'Quantidade', 'Preço Unitário (€)', 'Valor Total (€)'];
const row = values => Array.from({ length: 15 }, (_, index) => values[index] ?? '');
const workbook = { Sheets: {
  'TEE_Cabeçalho': [headers,
    row({ 0: 'TEE 02', 1: 120, 3: 'Novo aprovado', 5: 100, 10: 'aprovado' }),
    row({ 0: ' tee   01 ', 1: 120, 7: 10, 11: 'R2' }),
    row({ 0: 'TEE 03', 1: 120 }),
    row({ 0: 'TEE 04', 1: 120, 3: 'Inválido', 10: 'rejeitado' }),
  ],
  'TEE_Itens': [itemHeaders, ['TEE 02', '1.1', 'Artigo', 'un', 2, 50, 100]],
} };
try {
  const page = await browser.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (/^\/src\/[\w-]+\.js$/.test(url.pathname)) {
      return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL('..' + url.pathname, import.meta.url), 'utf8') });
    }
    if (url.pathname !== '/') return route.abort();
    await route.fulfill({ contentType: 'text/html', body: `<meta charset="utf-8"><script type="module">
      import { createOperationalXlsxImport } from '/src/xlsx-operational-import.js';
      window.calls=[]; window.messages=[]; window.completed=0; window.mode='stale';
      window.XLSX={utils:{sheet_to_json:sheet=>sheet},read:buffer=>JSON.parse(new TextDecoder().decode(buffer))};
      window.context={work:{id:'w1',numero:120,data_fim_contratual_atual:'2026-12-31'},phases:[],
        tees:[
          {id:'t1',obra_id:'w1',numero:'TEE 01',descricao:'Anterior',estado_operacional:'em_elaboracao',estado_aprovacao_cliente:'pendente',data_envio:'2026-09-01'},
          {id:'t3',obra_id:'w1',numero:'TEE 03',descricao:'Sem alteração',estado_operacional:'aguarda_resposta',estado_aprovacao_cliente:'pendente'}
        ],onComplete:()=>{window.completed++;}};
      window.originalContext=JSON.stringify(context);
      window.importer=createOperationalXlsxImport({
        isConfigured:true,getProfile:()=>({}),toast:(message,type)=>messages.push({message,type}),
        supabase:async(path,options)=>{
          calls.push({path,method:options.method,body:JSON.parse(options.body)});
          if(mode==='stale')return Response.json({code:'STALE_REVISION',message:'Revisão desatualizada. Recarregue os TEEs.'},{status:409});
          if(mode==='invalid')return Response.json({version:1,committed:true,importadas:'2'});
          return Response.json({version:1,committed:true,importadas:2});
        }
      });
      importer.openTees(context);
    </script>` });
  });
  await page.goto('http://tee.test/');
  await page.locator('[data-xlsx-file]').setInputFiles({ name: 'revisoes.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: Buffer.from(JSON.stringify(workbook)) });
  await page.locator('[data-xlsx-confirm]').waitFor();
  const rows = page.locator('tbody tr');
  assert.equal(await rows.count(), 4);
  for (const [index, status] of ['NOVO', 'VAI ATUALIZAR', 'SEM ALTERAÇÃO', 'BLOQUEADO'].entries()) {
    assert.match(await rows.nth(index).innerText(), new RegExp(status));
    assert.equal(await rows.nth(index).locator('input').isChecked(), index < 2);
  }
  assert.equal(await rows.nth(3).locator('input').isDisabled(), true);
  assert.match(await rows.nth(0).innerText(), /execução por programar/);
  await page.locator('[data-xlsx-confirm]').click();
  await page.waitForFunction(() => messages.length > 0);
  assert.ok(await page.evaluate(() => messages.some(item => item.message.includes('Revisão desatualizada'))), JSON.stringify(await page.evaluate(() => ({messages, calls}))));
  assert.equal(await page.locator('.xlsx-import-overlay').isVisible(), true);
  assert.equal(await page.evaluate(() => completed), 0);
  assert.equal(await rows.nth(1).locator('input').isChecked(), true);
  const [call] = await page.evaluate(() => calls);
  assert.deepEqual(Object.keys(call.body).sort(), ['p_version', 'p_obra_id', 'p_linhas', 'p_nome_ficheiro'].sort());
  assert.equal(call.path, 'rpc/fn_importar_tees_revisoes');
  assert.equal(call.method, 'POST');
  assert.equal(call.body.p_version, 1);
  assert.equal(call.body.p_obra_id, 'w1');
  assert.equal(call.body.p_nome_ficheiro, 'revisoes.xlsx');
  assert.equal(call.body.p_linhas.length, 2);
  const [created, updated] = call.body.p_linhas;
  assert.equal(created.expected, null);
  assert.equal(created.id, undefined);
  assert.equal(created.fase_id, null);
  assert.equal(created.estado_operacional, 'aprovado');
  assert.equal(created.estado_aprovacao_cliente, 'aprovado');
  assert.equal(created.data_inicio_execucao, undefined);
  assert.deepEqual(created.itens, [{ linha: 2, numero_artigo: '1.1', descricao: 'Artigo', unidade: 'un', quantidade: 2, preco_unitario: 50, valor_total: 100 }]);
  assert.deepEqual(updated, { id: 't1', expected: await page.evaluate(() => context.tees[0]), revisao: 'R2', dias_prorrogacao: 10 });
  await page.evaluate(() => { window.mode = 'invalid'; });
  await page.locator('[data-xlsx-confirm]').click();
  await page.waitForFunction(() => messages.some(item => item.message.includes('não foi confirmada')));
  assert.equal(await page.evaluate(() => completed), 0);
  assert.equal(await page.locator('.xlsx-import-overlay').isVisible(), true);
  await page.evaluate(() => { window.mode = 'success'; });
  await page.locator('[data-xlsx-confirm]').click();
  await page.waitForFunction(() => completed === 1);
  assert.equal(await page.locator('.xlsx-import-overlay').isHidden(), true);
  assert.deepEqual(await page.evaluate(() => calls), [call, call, call]);
  assert.equal(await page.evaluate(() => JSON.stringify(context) === originalContext), true);
  assert.ok(await page.evaluate(() => messages.some(item => item.message.startsWith('2 linha(s) importada(s)'))));
  assert.deepEqual(errors, []);
  console.log('PASS: TEE preview, payload, new/revision/items, stale and invalid responses preserve preview, success closes and reloads; no other writes.');
} finally { await browser.close(); }
