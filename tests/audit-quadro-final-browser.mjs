// Independent local audit. FINDING assertions intentionally reproduce defects; a passing runner is not product acceptance.
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
let assetMode='candidate';
const {execFileSync}=await import('node:child_process');
const baseApp=execFileSync('git',['show','9e0e6c40b439160201289823db8cfee0b9adad02:src/app.js'],{encoding:'utf8',windowsHide:true});
const hooks = `
window.quadroTest = {
  state: () => ({ allocations: teamData.allocations, revisions: teamData.quadroContext?.revisions, ready:teamData.quadroReady }),
  period: value => { selectedWorkforcePeriod=value; },
  remove: async () => { selectedWorkforcePersonId='p1';selectedWorkforceSourceDate='2026-10-05';selectedWorkforceSourcePeriod='dia_inteiro';selectedWorkforceSourceIds=teamData.allocations.filter(row=>row.colaborador_id==='p1'&&row.data==='2026-10-05').map(row=>row.id);await removeWorkforceAllocation(); },
  role: value => {accessContext={role:value,isAdmin:false,profile:{ativo:true}};renderTeam();},
  save: saveWorkforceAllocation,
};
window.rhTest = {
  authorize(role, workId, type) {
    accessContext = {role, isAdmin: role === 'gestao_plataforma', profile: {ativo:true}};
    teamData.quadroReady = true;
    const global = ['administrativo','gestao_plataforma'].includes(role);
    teamData.quadroContext = { can_manage_global:global, edit_work_ids:global || role === 'encarregado' ? ['w1'] : [], revisions:[] };
    return canManageWorkforceWork(workId, type);
  },
  save: saveWorkforceAllocation,
  magnet: renderWorkforceMagnet,
  hostile(value) {
    collaborators[0].nome = value;
    works[0].numero = value; works[0].nome = value;
    renderTeam();
  },
  legacyForm() {
    document.querySelector('[data-team-panel="vehicles"]').hidden = false;
    selectedVehicleEditId = teamData.vehicles[0].id;
    document.querySelector('#team-vehicles').innerHTML = renderVehicleEditForm(teamData.vehicles[0]);
  }
};`;
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
    res.end(name === "src/app.js" ? (assetMode==='old'?baseApp:data.toString()) + hooks : data);
  } catch { res.statusCode = 404; res.end(); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ channel: "msedge", headless: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
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
    window.quadroFailure = null; window.auditMode=null; window.auditDelay=0;
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
      if (resource === "rpc/fn_e_admin") return Response.json(false);
      if (resource === "rpc/fn_listar_rastreio_faturas") return Response.json([]);
      if (resource === 'rpc/fn_quadro_contexto_v1' && auditMode==='missingBackend') return Response.json({message:'PGRST202: missing RPC'},{status:404});
      if (resource === 'quadro_pessoal_alocacao') { if(method!=='GET')return Response.json({message:'permission denied'},{status:403}); return Response.json(allocations); }
      if (resource === 'rpc/fn_quadro_operar')return Response.json({message:'CLIENT_UPGRADE_REQUIRED'},{status:403});
      if (resource === "rpc/fn_quadro_contexto_v1") return Response.json({ version:1, allocations, revisions:[{colaborador_id:'p1',data:'2026-10-05',revisao:allocationRevision}], can_manage_global:false, read_work_ids:['w1','w2'], edit_work_ids:['w1','w2'], people:people.filter(p=>!p.data_saida), works:[{id:'w1',numero:'120',nome:'Obra sintética',situacao:'em_curso'},{id:'w2',numero:'118',nome:'Outra obra sintética',situacao:'em_curso'}] });
      if (resource === "rpc/fn_quadro_operar_v1") {
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
  for(const [name,width,height] of [['desktop',1440,1000],['tablet',820,1180],['mobile',390,844]]){
    errors.length=0;await page.setViewportSize({width,height});await page.goto(origin+'/?view=workforce');await page.waitForFunction(()=>quadroTest?.state().ready);await page.locator('#edit-workforce').click();

    await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await page.locator('[data-workforce-period]').selectOption('manha');
    const attemptedTarget=cell('w2','2026-10-05');await attemptedTarget.scrollIntoViewIfNeeded();const touch=await attemptedTarget.boundingBox();const hit=await page.evaluate(r=>{const el=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('[data-workforce-cell]');return {date:el?.dataset.date,work:el?.dataset.workId};},touch);
    if(hit.date!=='2026-10-05'||hit.work!=='w2'){
      await page.mouse.click(touch.x+touch.width/2,touch.y+touch.height/2);await page.waitForTimeout(200);const sent=await confirms();assert.ok(sent.length);assert.notEqual(sent[0].body.p_dados.data,'2026-10-05');evidence.push({name,width,target:touch,hit,sentDate:sent[0].body.p_dados.data});console.log('FINDING P1 UX: '+name+' — centro de 05/10 atinge '+hit.date+'; gravação simulada enviou '+sent[0].body.p_dados.data+'; largura '+touch.width.toFixed(1)+'px');await page.screenshot({path:path.join(screenshots,'audit-final-'+name+'.png'),fullPage:true,animations:'disabled'});continue;
    }
    await attemptedTarget.click();await page.waitForFunction(()=>allocationRevision===1);assert.equal((await confirms()).length,1);assert.equal((await confirms())[0].body.p_dados.periodo,'manha');
    await page.evaluate(()=>{auditDelay=120;});await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await cell('w1','2026-10-06').dblclick();await page.waitForFunction(()=>allocationRevision===2);assert.equal((await confirms()).length,2);await page.evaluate(()=>{auditDelay=0;});
    await cell('w1','2026-10-06').locator('[data-workforce-person="p1"]').click();await cell('w2','2026-10-06').click();await page.waitForFunction(()=>allocationRevision===3);assert.equal((await confirms()).length,3);
    await cell('w2','2026-10-06').locator('[data-workforce-person="p1"]').click();await page.locator('#remove-workforce-allocation').click();await page.waitForFunction(()=>allocationRevision===4);assert.equal((await confirms()).at(-1).body.p_acao,'remover');assert.equal(await cell('w2','2026-10-06').locator('[data-workforce-person]').count(),0);
    await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await page.evaluate(()=>{quadroFailure={stage:'preview',code:'OVERLAP_CONFLICT'};});const conflictCount=(await confirms()).length;await cell('w2','2026-10-09').click();await page.waitForTimeout(100);assert.equal((await confirms()).length,conflictCount);await page.evaluate(()=>{quadroFailure=null;});await page.locator('#finish-workforce-edit').click();await page.locator('#edit-workforce').click();await page.locator('#workforce-roster [data-workforce-person="p1"]').click();
    await page.evaluate(()=>{quadroFailure={stage:'confirm',code:'STALE_REVISION'};});const staleCount=(await confirms()).length;const contexts=await page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_contexto_v1').length);await cell('w2','2026-10-10').click();await page.waitForFunction(()=>document.querySelector('#workforce-edit-message').textContent.includes('alterada por outro utilizador'));assert.equal((await confirms()).length,staleCount+1);assert.equal(await page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_contexto_v1').length),contexts+1);await page.evaluate(()=>{quadroFailure=null;});await page.locator('#finish-workforce-edit').click();await page.locator('#edit-workforce').click();await page.locator('#workforce-roster [data-workforce-person="p1"]').click();
    const before=(await confirms()).length;await page.locator('#finish-workforce-edit').click();await cell('w2','2026-10-07').click();assert.equal((await confirms()).length,before);await page.locator('#edit-workforce').click();await page.locator('#workforce-roster [data-workforce-person="p1"]').click();
    await page.evaluate(()=>{quadroFailure={stage:'preview',code:'ABSENCE_CONFLICT'};});const target=cell('w2','2026-10-07');await target.click();await page.waitForFunction(()=>document.querySelector('#workforce-edit-message').textContent.includes('ausência'));assert.equal((await confirms()).length,before);
    const disabled=await target.evaluate(el=>({saving:el.classList.contains('saving'),pointer:getComputedStyle(el).pointerEvents}));assert.equal(disabled.saving,true);assert.equal(disabled.pointer,'none');await page.evaluate(()=>{quadroFailure=null;});const retry=await target.click({timeout:600}).then(()=>false,()=>true);assert.equal(retry,true);console.log('FINDING P1: '+name+' — célula fica saving/pointer-events:none após erro; retry real bloqueado');
    await page.locator('#finish-workforce-edit').click();await page.locator('#edit-workforce').click();await page.locator('#workforce-roster [data-workforce-person="p1"]').click();await page.evaluate(()=>{auditMode='lost';});const prior=await page.evaluate(()=>quadroTest.state().allocations);const count=(await confirms()).length;await cell('w2','2026-10-08').click();await page.waitForFunction(()=>document.querySelector('#workforce-edit-message').textContent.includes('Failed to fetch'));assert.equal((await confirms()).length,count+1);assert.deepEqual(await page.evaluate(()=>quadroTest.state().allocations),prior);await page.evaluate(()=>{auditMode=null;});
    await page.reload();await page.waitForFunction(()=>quadroTest?.state().ready);await page.locator('#edit-workforce').click();await page.locator('#workforce-roster [data-workforce-person="p1"]').click();const targetSize=await cell('w2','2026-10-05').boundingBox();const board=await page.locator('#team-board').evaluate(el=>({width:el.clientWidth,scroll:el.scrollWidth,overflow:getComputedStyle(el).overflowX}));evidence.push({name,width,target:targetSize,board});
    await page.screenshot({path:path.join(screenshots,'audit-final-'+name+'.png'),fullPage:true,animations:'disabled'});assert.deepEqual(errors,[]);
    console.log('PASS '+name+': Encarregado, select período, mover, duplo clique, terminar, ausência, perda resposta sem retry, reload; célula '+targetSize.width.toFixed(1)+'px');
  }
  await page.addInitScript(()=>{window.auditMode='missingBackend';});await page.goto(origin+'/?view=workforce');await page.waitForFunction(()=>window.quadroTest);assert.equal(await page.locator('#edit-workforce').isVisible(),false);assert.equal((await confirms()).length,0);console.log('PASS novo frontend / backend RPC ausente: edição fechada');
  await page.setViewportSize({width:1440,height:1000});assetMode='old';await page.addInitScript(()=>{window.auditMode=null;});await page.goto(origin+'/?view=workforce');await page.waitForFunction(()=>window.quadroTest);await page.evaluate(()=>quadroTest.role('administrativo'));await page.locator('#edit-workforce').click();await page.locator('[data-workforce-person="p1"]').first().click();await cell('w1','2026-10-06').click();await page.waitForTimeout(300);const oldCalls=await page.evaluate(()=>calls.filter(c=>(c.resource==='quadro_pessoal_alocacao'||c.resource==='rpc/fn_quadro_operar')&&c.method!=='GET'));assert.ok(oldCalls.length>0);assert.equal(await page.evaluate(()=>allocations[0].obra_id),'w1');console.log('PASS aba/cache antigo / backend B: tentativa antiga recusada, mock persistido intacto');
  console.log('METRICS '+JSON.stringify(evidence));
} finally {
  await browser.close();await new Promise(resolve=>server.close(resolve));
}