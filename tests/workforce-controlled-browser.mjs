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
    res.end(name === "src/app.js" ? data.toString() + hooks : data);
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
    window.quadroFailure = null;
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
      if (resource === "rpc/fn_quadro_contexto_v1") return Response.json({ version:1, allocations, revisions:[{colaborador_id:'p1',data:'2026-10-05',revisao:allocationRevision}], can_manage_global:true, read_work_ids:['w1','w2'], edit_work_ids:['w1','w2'], people:people.filter(p=>!p.data_saida), works:[{id:'w1',numero:'120',nome:'Obra sintética',situacao:'em_curso'},{id:'w2',numero:'118',nome:'Outra obra sintética',situacao:'em_curso'}] });
      if (resource === "rpc/fn_quadro_operar_v1") {
        if (quadroFailure?.stage === (body.p_confirmar ? 'confirm' : 'preview')) {
          if (quadroFailure.uncommitted) return Response.json({version:1,committed:false});
          return Response.json({message:quadroFailure.code},{status:400});
        }
        if (!body.p_confirmar) return Response.json({version:1,committed:false,versao:'test-preview'});
        if (body.p_acao === 'remover') allocations=allocations.filter(row=>!body.p_dados.ids.includes(row.id));
        else allocations=[{id:'saved-allocation',...body.p_dados}];
        allocationRevision++;
        return Response.json({version:1,committed:true,revision:allocationRevision,allocations});
      }
      if (method !== "GET") {
        if (resource === "quadro_pessoal_alocacao" && method === "POST") return Response.json([{ id: "a-test", ...body }]);
        if (resource === "viaturas" && method === "PATCH") return Response.json([{ id: "v1", ...body }]);
        throw Error(`Unexpected synthetic write: ${method} ${resource}`);
      }
      if (resource === "utilizadores") return Response.json([{ id: "u1", auth_user_id: "auth-test", funcao: "administrativo", ativo: true, nome: "Administrativo Teste" }]);
      if (resource === "colaboradores") return Response.json(people.filter(person => url.searchParams.get("data_saida") === "not.is.null" ? person.data_saida !== null : person.data_saida === null));
      if (resource === "obras") return Response.json([{ id: "w1", numero: "120", nome: "Obra sintética", situacao: "em_execucao" }]);
      if (resource === "horas_extraordinarias") return Response.json([{ id: "he1", colaborador_id: "p1", obra_id: "w1", data: "2026-09-30", horas: 2, estado_pagamento: "por_pagar" }]);
      if (resource === "viaturas") return Response.json([{ id: "v1", marca_modelo: "Viatura de teste", matricula: "AA-00-AA", colaborador_atribuido_id: "p1", atribuicao_revisao: 1 }]);
      return Response.json([]);
    };
  });

  await page.goto(origin+'/?view=workforce');
  await page.waitForFunction(()=>window.quadroTest?.state().ready);
  const cell=(work,date)=>page.locator('[data-workforce-cell][data-work-id="'+work+'"][data-date="'+date+'"]');
  assert.equal(await cell('w1','2026-10-05').locator('[data-workforce-person="p1"]').count(),1);
  assert.equal(await cell('w1','2026-10-06').locator('[data-workforce-person]').count(),0);
  assert.equal(await cell('w1','2026-10-06').locator('.workforce-arrow').count(),0);
  console.log('PASS explicit day: no magnet/arrow inherited into tomorrow');
  await page.locator('#edit-workforce').click();
  await page.locator('[data-workforce-person="p1"]').first().click();
  await cell('w2','2026-10-05').click();
  await page.waitForFunction(()=>quadroTest.state().allocations.some(row=>row.obra_id==='w2'));
  assert.equal(await cell('w2','2026-10-05').locator('[data-workforce-person="p1"]').count(),1);
  assert.equal(await cell('w1','2026-10-05').locator('[data-workforce-person="p1"]').count(),0);
  const confirmations=()=>page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_operar_v1'&&c.body.p_confirmar));
  assert.equal((await confirmations())[0].body.p_dados.expected_revision,0);
  assert.equal((await confirmations())[0].body.p_dados.periodo,'dia_inteiro');
  for(const [code,pattern] of [['ABSENCE_CONFLICT',/ausência/],['LEGACY_CONFLICT',/sobrepostas/],['PERMISSION_DENIED',/permissão/]]) {
    const snapshot=await page.evaluate(()=>quadroTest.state().allocations);
    await page.evaluate(value=>{quadroFailure={stage:'preview',code:value};},code);
    await page.evaluate(()=>quadroTest.save('p1','2026-10-05',{type:'obra',workId:'w1'}));
    assert.deepEqual(await page.evaluate(()=>quadroTest.state().allocations),snapshot);
    assert.match(await page.locator('#workforce-edit-message').textContent(),pattern);
  }
  await page.evaluate(()=>{quadroFailure={stage:'confirm',uncommitted:true};});
  const snapshot=await page.evaluate(()=>quadroTest.state().allocations);
  await page.evaluate(()=>quadroTest.save('p1','2026-10-05',{type:'obra',workId:'w1'}));
  assert.deepEqual(await page.evaluate(()=>quadroTest.state().allocations),snapshot);
  console.log('PASS failure/uncommitted: existing UI allocation preserved');
  await page.evaluate(()=>{quadroFailure={stage:'confirm',code:'STALE_REVISION'};});
  const beforeReload=await page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_contexto_v1').length);
  const beforeConfirm=(await confirmations()).length;
  await page.evaluate(()=>quadroTest.save('p1','2026-10-05',{type:'obra',workId:'w1'}));
  assert.equal((await confirmations()).length,beforeConfirm+1);
  assert.equal(await page.evaluate(()=>calls.filter(c=>c.resource==='rpc/fn_quadro_contexto_v1').length),beforeReload+1);
  assert.match(await page.locator('#workforce-edit-message').textContent(),/alterada por outro utilizador/);
  await page.evaluate(()=>{quadroFailure=null;});
  for(const role of ['gerencia','diretor_obra','adjunto','preparador']) {
    await page.evaluate(value=>quadroTest.role(value),role);
    assert.equal(await page.locator('#edit-workforce').isVisible(),false);
  }
  await page.evaluate(()=>quadroTest.role('administrativo'));
  assert.equal(await page.locator('#edit-workforce').isVisible(),true);
  await page.evaluate(()=>quadroTest.remove());
  assert.equal(await cell('w2','2026-10-05').locator('[data-workforce-person]').count(),0);
  assert.equal(await page.evaluate(()=>calls.some(c=>c.resource==='quadro_pessoal_alocacao'&&c.method!=='GET')),false);
  for(const [name,width,height] of [['desktop',1440,1000],['tablet',820,1180],['mobile',390,844]]) {
    await page.setViewportSize({width,height});await page.screenshot({path:path.join(screenshots,'quadro-'+name+'.png'),fullPage:true,animations:'disabled'});
  }
  assert.deepEqual(errors,[]);
  console.log('PASS scoped buttons, remove, no direct DML, three viewports and clean console');
} finally {
  await browser.close();await new Promise(resolve=>server.close(resolve));
}
