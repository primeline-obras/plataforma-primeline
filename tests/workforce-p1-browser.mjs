// Offline acceptance for P1: physical mouse/tap through the real handler, no force-click.
import assert from "node:assert/strict";
import { readFile, mkdir } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";
import os from "node:os";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLANNING_PLAYWRIGHT || "playwright");
const root = fileURLToPath(new URL("../", import.meta.url));
const screenshots = process.env.RH_SCREENSHOTS || path.join(os.tmpdir(), "primeline-quadro-offline");
await mkdir(screenshots, { recursive: true });
// Test-only access to the real module's consumers. Never written to app.js.
const hooks = `window.quadroTest={state:()=>({allocations:teamData.allocations,ready:teamData.quadroReady})};`;
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/config.js") {
      res.setHeader("Content-Type", "text/javascript");
      return res.end('window.PRIMELINE_CONFIG={supabaseUrl:"https://synthetic.test",supabaseAnonKey:"synthetic"};');
    }
    const name = url.pathname === "/" ? "index.html" : url.pathname.slice(1);
    if (!(name === "index.html" || name.startsWith("src/") || name.startsWith("assets/")) || name.includes("..")) {
      res.statusCode = 404; return res.end();
    }
    const data = await readFile(path.join(root, name));
    const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2" };
    res.setHeader("Content-Type", mime[path.extname(name)] || "application/octet-stream");
    res.end(name === "src/app.js" ? data.toString() + hooks : data);
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ channel: "msedge", headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, hasTouch: true });
  const errors = [];
  page.on("pageerror", error => { errors.push(error.message); console.error(error.message); });
  page.on("console", message => { if (message.type() === "error") { errors.push(message.text()); console.error(message.text()); } });
  // All non-local network is intercepted, including CDN scripts. No production session.
  await page.route("**/*", route => route.request().url().startsWith(origin)
    ? route.continue() : route.fulfill({ contentType: "text/javascript", body: "" }));
  await page.addInitScript(() => {
    sessionStorage.setItem("primeline_supabase_session", JSON.stringify({ access_token: "synthetic", user: { id: "auth-test" } }));
    window.calls = [];
    window.allocationRevision = 0;
    window.allocations = [{id:'seed-allocation',colaborador_id:'p1',data:'2026-10-05',periodo:'dia_inteiro',obra_id:'w1',tipo_alocacao:'obra',descricao_livre:null}];
    window.testFault=null;window.quadroFailure = null; window.auditMode=null; window.auditDelay=0;
    window.people = [
      { id: "p1", nome: "Ana Ativa", funcao: "Pedreiro", data_saida: null },
      { id: "p2", nome: "Inês Inativa", funcao: "Técnica", data_saida: "2026-09-01" },
    ];
    window.fetch = async (address, options = {}) => {
      const url = new URL(address, location.href);
      if (url.hostname !== "synthetic.test") throw Error(`Unexpected fetch: ${url}`);
      const resource = url.pathname.replace("/rest/v1/", "");
      const method = options.method || "GET";
      const body = options.body ? JSON.parse(options.body) : null;
      calls.push({ resource, query: url.search, method, body });
      if(resource==='rpc/fn_listar_ponto_obra') return Response.json({obras:[{id:'w1'},{id:'w2'}],linhas:people.filter(p=>!p.data_saida).map(p=>({colaborador_id:p.id,nome:p.nome,funcao:p.funcao}))});
      if(resource==='rpc/fn_colaborador_na_obra_atual_encarregado') return Response.json(true);
      if(resource==='rpc/fn_ausencias_equipa_encarregado') return Response.json([]);
      if (resource === "rpc/fn_e_admin") return Response.json(false);
      if (resource === "rpc/fn_listar_rastreio_faturas") return Response.json([]);
      if (resource === 'rpc/fn_quadro_contexto_v1' && auditMode==='missingBackend') return Response.json({message:'PGRST202: missing RPC'},{status:404});
      if (resource === 'quadro_pessoal_alocacao') { if(method!=='GET')return Response.json({message:'permission denied'},{status:403}); return Response.json(allocations); }
      if (resource === 'rpc/fn_quadro_operar')return Response.json({message:'CLIENT_UPGRADE_REQUIRED'},{status:403});
      if (resource === "rpc/fn_quadro_contexto_v1") return Response.json({ version:1, allocations, revisions:[{colaborador_id:'p1',data:'2026-10-05',revisao:allocationRevision}], can_manage_global:false, read_work_ids:['w1','w2'], edit_work_ids:['w1','w2'], people:people.filter(p=>!p.data_saida), works:[{id:'w1',numero:'120',nome:'Obra sintética',situacao:'em_curso'},{id:'w2',numero:'118',nome:'Outra obra sintética',situacao:'em_curso'}] });
      if (resource === "rpc/fn_quadro_operar_v1") {
        if(testFault?.stage===(body.p_confirmar?'confirm':'preview')) {
          if(testFault.kind==='network')throw new TypeError('Synthetic network failure');
          if(testFault.kind==='unexpected')throw new Error('Synthetic unexpected error');
          if(testFault.kind==='invalid')return Response.json({version:1,committed:body.p_confirmar?false:true});
        }

        if (quadroFailure?.stage === (body.p_confirmar ? 'confirm' : 'preview')) {
          if (quadroFailure.uncommitted) return Response.json({version:1,committed:false});
          return Response.json({message:quadroFailure.code},{status:400});
        }
        if (auditDelay)await new Promise(r=>setTimeout(r,auditDelay));
        if (!body.p_confirmar) return Response.json({version:1,committed:false,versao:'test-preview'});
        if (body.p_acao === 'remover') allocations=allocations.filter(row=>!body.p_dados.ids.includes(row.id));
        else allocations=[{id:'saved-allocation',...body.p_dados}];
        allocationRevision++;
        if(auditMode==='lost')throw new TypeError('Failed to fetch after synthetic commit');
        return Response.json({version:1,committed:true,revision:allocationRevision,allocations});
      }
      if (method !== "GET") {
        if (resource === "quadro_pessoal_alocacao" && method === "POST") return Response.json([{ id: "a-test", ...body }]);
        if (resource === "viaturas" && method === "PATCH") return Response.json([{ id: "v1", ...body }]);
        throw Error(`Unexpected synthetic write: ${method} ${resource}`);
      }
      if (resource === "utilizadores") return Response.json([{ id: "u1", auth_user_id: "auth-test", funcao: "encarregado", ativo: true, nome: "Encarregado Teste" }]);
      if (resource === "colaboradores") return Response.json(people.filter(person => url.searchParams.get("data_saida") === "not.is.null" ? person.data_saida !== null : person.data_saida === null));
      if (resource === "obras") return Response.json([{ id: "w1", numero: "120", nome: "Obra sintética", situacao: "em_execucao" }]);
      if (resource === "horas_extraordinarias") return Response.json([{ id: "he1", colaborador_id: "p1", obra_id: "w1", data: "2026-09-30", horas: 2, estado_pagamento: "por_pagar" }]);
      if (resource === "viaturas") return Response.json([{ id: "v1", marca_modelo: "Viatura de teste", matricula: "AA-00-AA", colaborador_atribuido_id: "p1", atribuicao_revisao: 1 }]);
      return Response.json([]);
    };
  });


  const evidence=[];
  const cell=(work,date)=>page.locator('[data-workforce-cell][data-work-id="'+work+'"][data-date="'+date+'"]');
  const confirms=()=>page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_operar_v1'&&c.body.p_confirmar));
  const settled=async()=>{await page.waitForFunction(()=>!document.querySelector('#team-board .saving'));await page.waitForTimeout(30);};
  async function physical(work,date,tap=false){
    const target=cell(work,date);await target.scrollIntoViewIfNeeded();const r=await target.boundingBox();assert.ok(r.width>=44,JSON.stringify(r));
    const hit=await page.evaluate(r=>{const el=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('[data-workforce-cell]');return {date:el?.dataset.date,work:el?.dataset.workId};},r);
    assert.deepEqual(hit,{date,work});
    const visual=await target.evaluate(el=>{const week=el.parentElement;const weeks=[...week.parentElement.querySelectorAll('.workforce-week-cell')];const i=weeks.indexOf(week),day=[...week.children].indexOf(el);const header=document.querySelector('.workforce-grid-head').children[i+1];return {day:header.querySelectorAll('.workforce-day-labels b small')[day].textContent,columns:getComputedStyle(week).gridTemplateColumns.split(' ').length,scroll:document.querySelector('#team-board').scrollLeft};});
    assert.equal(visual.day,date.slice(8));assert.equal(visual.columns,7);
    if(tap)await page.touchscreen.tap(r.x+r.width/2,r.y+r.height/2);else await page.mouse.click(r.x+r.width/2,r.y+r.height/2);
    return {...r,hit,visual};
  }
  for(const [name,width,height] of [['desktop',1440,1000],['tablet',820,1180],['mobile',390,844]]){
    errors.length=0;await page.setViewportSize({width,height});await page.goto(origin+'/?view=workforce');await page.waitForFunction(()=>quadroTest?.state().ready);await page.locator('#team-week').fill('2026-09-28');await page.locator('#team-week').dispatchEvent('change');await page.locator('#edit-workforce').click();
    const dates=['2026-09-21','2026-09-24','2026-09-27','2026-10-05','2026-10-08','2026-10-11','2026-10-12','2026-10-15','2026-10-18'];
    const boxes=[];
    for(const [i,date] of dates.entries()){
      await page.locator('#workforce-roster [data-workforce-person="p1"]').click();const before=(await confirms()).length;
      boxes.push(await physical('w2',date,i%2===1));await settled();assert.equal((await confirms()).length,before+1);assert.equal((await confirms()).at(-1).body.p_dados.data,date);
    }
    const scroll=await page.locator('#team-board').evaluate(el=>({left:el.scrollLeft,width:el.clientWidth,scrollWidth:el.scrollWidth,overflow:getComputedStyle(el).overflowX}));assert.ok(scroll.scrollWidth>scroll.width);assert.ok(scroll.left>0);assert.equal(scroll.overflow,'auto');const boardBox=await page.locator('#team-board').boundingBox();await page.mouse.move(boardBox.x+boardBox.width/2,Math.min(boardBox.y+40,height-40));await page.mouse.wheel(-400,0);await page.waitForTimeout(120);assert.ok(await page.locator('#team-board').evaluate(el=>el.scrollLeft)<scroll.left);
    await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await page.locator('[data-workforce-period]').selectOption('manha');await physical('w1','2026-10-05',true);await settled();assert.equal((await confirms()).at(-1).body.p_dados.periodo,'manha');
    await cell('w1','2026-10-05').locator('[data-workforce-person="p1"]').click();await physical('w2','2026-10-05',true);await settled();assert.equal((await confirms()).at(-1).body.p_dados.obra_id,'w2');
    await cell('w2','2026-10-05').locator('[data-workforce-person="p1"]').click();await page.locator('#remove-workforce-allocation').click();await settled();assert.equal((await confirms()).at(-1).body.p_acao,'remover');assert.equal(await cell('w2','2026-10-05').locator('[data-workforce-person]').count(),0);
    const cases=[
      {stage:'preview',code:'ABSENCE_CONFLICT'}, {stage:'preview',code:'LEGACY_CONFLICT'},
      {stage:'preview',code:'PERMISSION_DENIED'}, {stage:'confirm',code:'ABSENCE_CONFLICT'},
      {stage:'confirm',code:'LEGACY_CONFLICT'}, {stage:'confirm',code:'STALE_REVISION'},
      {stage:'preview',kind:'network'}, {stage:'confirm',kind:'network'},
      {stage:'preview',kind:'invalid'}, {stage:'confirm',kind:'invalid'}, {stage:'confirm',kind:'unexpected'}
    ];
    for(const fault of cases){
      await page.locator('#workforce-roster [data-workforce-person="p1"]').click();const before=await page.evaluate(()=>quadroTest.state().allocations),n=(await confirms()).length;
      await page.evaluate(f=>{quadroFailure=f.code?f:null;testFault=f.kind?f:null;},fault);await physical('w2','2026-10-06',name!=='desktop');await settled();
      assert.deepEqual(await page.evaluate(()=>quadroTest.state().allocations),before);assert.equal((await confirms()).length,n+(fault.stage==='confirm'?1:0));
      assert.equal(await cell('w2','2026-10-06').evaluate(el=>({saving:el.classList.contains('saving'),pointer:getComputedStyle(el).pointerEvents})).then(x=>x.saving||x.pointer==='none'),false);
      assert.ok((await page.locator('#workforce-edit-message').textContent()).length);await page.waitForTimeout(80);assert.equal((await confirms()).length,n+(fault.stage==='confirm'?1:0));
      await page.evaluate(()=>{quadroFailure=null;testFault=null;});
      await physical('w2','2026-10-06',name!=='desktop');await settled();assert.equal((await confirms()).length,n+(fault.stage==='confirm'?2:1));
      await cell('w2','2026-10-06').locator('[data-workforce-person="p1"]').click();await page.locator('#remove-workforce-allocation').click();await settled();
    }
    await page.locator('#workforce-roster [data-workforce-person="p1"]').click();const lostBefore=await page.evaluate(()=>quadroTest.state().allocations),lostN=(await confirms()).length;await page.evaluate(()=>{auditMode='lost';});await physical('w2','2026-10-10');await settled();assert.deepEqual(await page.evaluate(()=>quadroTest.state().allocations),lostBefore);assert.equal((await confirms()).length,lostN+1);await page.waitForTimeout(100);assert.equal((await confirms()).length,lostN+1);await page.evaluate(()=>{auditMode=null;});
    // A second target clicked while the first request is active must not be visually stuck either.
    await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await page.evaluate(()=>{auditDelay=250;});const n=(await confirms()).length;
    const r=await physical('w2','2026-10-07');await page.mouse.click(r.x+r.width/2,r.y+r.height/2);await physical('w2','2026-10-08');await settled();assert.equal((await confirms()).length,n+1);assert.equal(await page.locator('#team-board .saving').count(),0);await page.evaluate(()=>{auditDelay=0;});
    await page.locator('#finish-workforce-edit').click();const cancelled=(await confirms()).length;await physical('w2','2026-10-09');assert.equal((await confirms()).length,cancelled);await page.locator('#edit-workforce').click();
    await page.screenshot({path:path.join(screenshots,'quadro-p1-'+name+'.png'),fullPage:true,animations:'disabled'});await page.reload();await page.waitForFunction(()=>quadroTest?.state().ready);assert.deepEqual(errors,[]);
    evidence.push({name,width,height,days:dates,minimumWidth:Math.min(...boxes.map(b=>b.width)),scroll,mouseAndTap:true,failureCases:cases.length});
    console.log('PASS '+name+': 9 datas em 3 semanas, mouse/tap/labels/hit-test/scroll, mover/retirar/manhã, 11 falhas+retry físico, duplo clique/cancelar/reload');
  }
  console.log('UX_EVIDENCE '+JSON.stringify(evidence));
} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
