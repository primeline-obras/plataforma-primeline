// Offline selection persistence tests; no Supabase writes.
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
    if (/^\/src\/[\w-]+\.js$/.test(url.pathname)) return route.fulfill({ contentType: 'text/javascript', body: await readFile(new URL('..' + url.pathname, import.meta.url), 'utf8') });
    if (url.pathname !== '/') return route.abort();
    return route.fulfill({ contentType: 'text/html', body: `<select id="planning-work"></select><div id="planning-content"></div><script type="module">
      import { createPlanningModule } from '/src/planning.js';
      window.works=[{id:'w120',numero:120},{id:'w118',numero:118}]; window.calls=[];
      const api=async path=>{calls.push(path); return Response.json([])};
      window.planning=createPlanningModule({supabase:api,isSupabaseConfigured:true,getWorks:()=>works,toast:()=>{}});
      planning.show();
    </script>` });
  });
  const key = 'primeline_planning_work_id';
  const selected = async id => {
    await page.waitForFunction(id => document.querySelector('#planning-work')?.value === id && document.querySelector('#planning-content')?.textContent.includes('SEM FASES'), id);
    assert.equal(await page.evaluate(key => localStorage.getItem(key), key), id || null);
  };
  await page.goto('http://localhost/');
  await selected('w118');
  for (const id of ['w120', 'w118']) {
    await page.selectOption('#planning-work', id);
    await selected(id);
    await page.reload();
    await selected(id);
  }
  await page.evaluate(key => localStorage.setItem(key, 'invalid'), key);
  await page.reload();
  await selected('w118');
  await page.evaluate(() => planning.show({ workId: 'w120' }));
  await selected('w120');
  await page.evaluate(key => { localStorage.setItem(key, 'w118'); planning.show(); }, key);
  await selected('w120'); // Current in-memory selection has priority over storage.
  await page.evaluate(() => { works = works.filter(work => work.id !== 'w120'); planning.show({ workId: 'invalid' }); });
  await selected('w118');
  await page.evaluate(() => { works = []; planning.show(); });
  await selected('');
  assert.equal(await page.evaluate(() => calls.some(path => path.includes('eq.invalid'))), false);
  await page.addInitScript(() => {
    Storage.prototype.getItem = () => { throw new Error('Storage blocked'); };
    Storage.prototype.setItem = () => { throw new Error('Storage blocked'); };
    Storage.prototype.removeItem = () => { throw new Error('Storage blocked'); };
  });
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#planning-work')?.value === 'w118');
  assert.deepEqual(errors, []);
  console.log('PASS: refresh 120/118, invalid storage, explicit workId, current selection priority, removed works, empty list and blocked storage.');
} finally { await browser.close(); }
