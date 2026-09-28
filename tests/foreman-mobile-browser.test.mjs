import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';

// Integração exclusivamente local: APIs simuladas, sem Supabase ou SQL.
test('Chromium: equipa e ponto sem overflow em mobile/tablet; preview antes de confirmar', {skip:!process.env.QUADRO_PLAYWRIGHT}, async()=>{
 const {chromium}=await import(pathToFileURL(process.env.QUADRO_PLAYWRIGHT).href);
 const server=createServer(async(req,res)=>{
  try {
   const path=new URL(req.url,'http://localhost').pathname;
   if(path==='/') {res.setHeader('content-type','text/html');res.end('<html><head><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/foreman-attendance.css"></head><body><div id="team" style="padding:12px"></div><div id="attendance" hidden></div></body></html>');return;}
   if(!/^\/src\/[a-z0-9-]+\.(js|css)$/.test(path)) {res.writeHead(404);res.end();return;}
   res.setHeader('content-type',path.endsWith('.js')?'text/javascript':'text/css');res.end(await readFile(new URL(`..${path}`,import.meta.url)));
  } catch {res.writeHead(404);res.end();}
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
 try {
  browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  const page=await browser.newPage(),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>route.request().url().startsWith(`http://127.0.0.1:${server.address().port}/`)?route.continue():route.abort());
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.evaluate(async()=>{
   const {createForemanTeam}=await import('/src/foreman-team.js');const {createAttendanceModule}=await import('/src/attendance.js');
   const works=[{id:'120',numero:'120',nome:'Quinta da Marinha - Casa R'}];
   const p={colaborador_id:'p',nome:'João Afonso',funcao:'Pedreiro',periodo:'dia_inteiro',periodos:['dia_inteiro'],alocacoes:[],ausente:false};
   window.calls=[];
   const api=async(path,options)=>{const body=JSON.parse(options.body);window.calls.push({path,body});return new Response(JSON.stringify(path.endsWith('fn_equipa_obra_encarregado')?{obra_id:'120',obras:works,equipa:[p],candidatos:[p]}:path.endsWith('fn_quadro_operar')?{versao:'v1',acao:'adicionar'}:{obras:works,linhas:[p],pode_validar:false}));};
   window.team=createForemanTeam({root:document.querySelector('#team'),supabase:api,getRole:()=> 'encarregado',toast:()=>{},onAttendance:()=>{},onHistory:()=>{}});
   window.attendance=createAttendanceModule({root:document.querySelector('#attendance'),supabase:api,isConfigured:true,getRole:()=> 'encarregado',toast:()=>{}});
   await window.team.show();await window.attendance.show();
  });
  for(const width of [360,390,768,1280]) {
   await page.setViewportSize({width,height:900});
   for(const panel of ['team','attendance']) {
    await page.evaluate(panel=>{document.querySelector('#team').hidden=panel!=='team';document.querySelector('#attendance').hidden=panel!=='attendance';},panel);
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${panel} excede ${width}px`);
   }
  }
  await page.evaluate(()=>{document.querySelector('#team').hidden=false;document.querySelector('#attendance').hidden=true;});
  await page.setViewportSize({width:390,height:844});
  await page.locator('[data-team-add]').click();await page.locator('[data-candidate="p"]').click();await page.locator('[data-team-preview-button]').click();
  await page.waitForFunction(()=>document.querySelector('[data-team-preview-button]').textContent==='CONFIRMAR MOVIMENTAÇÃO');
  assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.body.p_confirmar).length),0);
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.locator('[data-team-preview-button]').click();await page.waitForFunction(()=>!document.querySelector('[data-team-cancel]'));
  assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.body.p_confirmar).length),1);assert.deepEqual(errors,[]);
 } finally {await browser?.close();await new Promise(r=>server.close(r));}
});
