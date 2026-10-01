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
const screenshots = process.env.RH_SCREENSHOTS || path.join(os.tmpdir(), "primeline-rh-frontend");
await mkdir(screenshots, { recursive: true });
// Test-only access to the real module's consumers. Never written to app.js.
const hooks = `
window.rhTest = {
  authorize(role, workId, type) {
    accessContext = {role, isAdmin: role === 'gestao_plataforma', profile: {ativo:true}};
    teamData.quadroReady = true;
    const global = ['administrativo','gerencia','gestao_plataforma'].includes(role);
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
    window.allocations = [];
    window.people = [
      { id: "p1", nome: "Ana Ativa", funcao: "Administrativa", data_saida: null },
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
      if (resource === "rpc/fn_quadro_contexto") return Response.json({ version:1, allocations, revisions:[], can_manage_global:true, read_work_ids:['w1'], edit_work_ids:['w1'], people, works:[{id:'w1',numero:'120',nome:'Obra sintética',situacao:'em_curso'}] });
      if (resource === "rpc/fn_quadro_operar") {
        if (!body.p_confirmar) return Response.json({version:1,committed:false,versao:'test-preview'});
        allocations = [{id:'a-test',...body.p_dados}]; allocationRevision++;
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
  await page.goto(`${origin}/?view=team`);
  await page.waitForFunction(() => document.querySelector('#toggle-inactive-collaborators')?.textContent.includes('(1)'));
  await page.locator("#team-directory").getByText("Ana Ativa", { exact: true }).waitFor();
  await page.locator("#toggle-inactive-collaborators").click();
  await page.locator("#inactive-collaborators").getByText("Inês Inativa", { exact: true }).waitFor();
  assert.equal(await page.locator("#team-directory").getByText("Inês Inativa", { exact: true }).count(), 0);
  assert.equal(await page.locator("#inactive-collaborators").getByText("Ana Ativa", { exact: true }).count(), 0);
  const collaboratorCalls = await page.evaluate(() => calls.filter(call => call.resource === "colaboradores"));
  assert.ok(collaboratorCalls.some(call => new URLSearchParams(call.query).get("data_saida") === "not.is.null"));
  assert.ok(collaboratorCalls.some(call => new URLSearchParams(call.query).get("data_saida") === "is.null"));
  for (const [label, width, height] of [["desktop", 1440, 1000], ["tablet", 820, 1180], ["mobile", 390, 844]]) {
    await page.setViewportSize({ width, height });
    await page.locator("#inactive-collaborators").scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(screenshots, `inativos-${label}.png`), fullPage: true, animations: "disabled" });
    assert.equal(await page.locator("#inactive-collaborators").isVisible(), true);
  }
  console.log("PASS RH-01: real consumer + wrapper, active/inactive separated, three viewports");

  for (const role of ["administrativo", "gerencia", "gestao_plataforma", "diretor_obra", "encarregado", "preparador", "financeiro"]) {
    const admin = ["administrativo", "gerencia", "gestao_plataforma"].includes(role);
    const operational = role === "encarregado";
    for (const [workId, type, expected] of [[null, "escritorio", admin], ["w1", "obra", admin || operational], ["other", "obra", false], [null, "obra", false], [null, "invalid", false], ["w1", "escritorio", false], [null, "garantia", admin]]) {
      assert.equal(await page.evaluate(args => rhTest.authorize(...args), [role, workId, type]), expected, `${role}/${workId}/${type}`);
    }
  }
  await page.evaluate(() => rhTest.authorize("administrativo", null, "escritorio"));
  await page.evaluate(() => rhTest.save("p1", "2026-10-05", { type: "escritorio" }));
  const allocation = await page.evaluate(() => calls.find(call => call.resource === "rpc/fn_quadro_operar" && call.body.p_confirmar));
  assert.equal(allocation.body.p_dados.obra_id, null);
  assert.equal(allocation.body.p_dados.tipo_alocacao, "escritorio");
  const writes = await page.evaluate(() => calls.filter(call => call.resource === "rpc/fn_quadro_operar" && call.body.p_confirmar).length);
  await page.evaluate(async () => {
    await rhTest.save("p1", "2026-10-06", { type: "obra" });
    rhTest.authorize("encarregado", null, "escritorio");
    await rhTest.save("p1", "2026-10-06", { type: "escritorio" });
    rhTest.authorize("administrativo", null, "escritorio");
  });
  assert.equal(await page.evaluate(() => calls.filter(call => call.resource === "rpc/fn_quadro_operar" && call.body.p_confirmar).length), writes);
  console.log("PASS RH-02: 49 permission combinations + real save consumer, invalid destinations issue no write");

  const hostile = '<img src=x onerror="window.rhInjected=true"><b data-hostile>Nome & texto</b>';
  await page.evaluate(value => rhTest.hostile(value), hostile);
  const overtime = page.locator("#team-overtime .overtime-row");
  assert.equal(await overtime.locator("img,b,[data-hostile]").count(), 0);
  assert.equal(await overtime.locator("strong").first().textContent(), hostile);
  assert.ok((await overtime.locator("span").first().textContent()).includes(`Obra ${hostile} · ${hostile}`));
  assert.equal(await page.evaluate(() => window.rhInjected), undefined);
  assert.equal(await page.evaluate(() => {
    const container = document.createElement('div');
    container.innerHTML = rhTest.magnet({id:'hostile',nome:'Ana" onmouseover="alert(1)'});
    return container.querySelector('button').hasAttribute('onmouseover');
  }), false, 'nearby RH magnet title cannot create event attributes');
  console.log("PASS RH-08: hostile and inert markup remain literal text in all three fields");
  await page.evaluate(() => rhTest.hostile("Texto seguro"));

  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.evaluate(() => rhTest.legacyForm());
  const legacy = page.locator("[data-vehicle-edit-form]");
  assert.equal(await legacy.locator('[name="colaborador_atribuido_id"]').count(), 0);
  // Even an injected obsolete form field cannot re-enable the old payload.
  await legacy.evaluate(form => {
    const input = document.createElement("input"); input.name = "colaborador_atribuido_id"; input.value = "p2"; form.append(input); form.requestSubmit();
  });
  await page.waitForFunction(() => calls.some(call => call.resource === "viaturas" && call.method === "PATCH"));
  await page.waitForFunction(() => !document.querySelector('[data-vehicle-edit-form]'));
  const patches = await page.evaluate(() => calls.filter(call => call.resource === "viaturas" && call.method === "PATCH"));
  assert.ok(patches.every(call => !Object.hasOwn(call.body, "colaborador_atribuido_id")));
  await page.evaluate(() => rhTest.legacyForm());
  await page.locator("[data-vehicle-edit-form]").scrollIntoViewIfNeeded();
  await page.screenshot({ path: path.join(screenshots, "viatura-formulario-antigo.png"), fullPage: true, animations: "disabled" });
  await page.locator("[data-manage-vehicle-assignment]").click();
  await page.locator("[data-fleet-assignment]").waitFor();
  assert.equal(await page.locator("#vehicles-view").isVisible(), true);
  await page.screenshot({ path: path.join(screenshots, "viaturas-controladas.png"), fullPage: true, animations: "disabled" });
  console.log("PASS RH-15: no responsible select/PATCH; real click opens controlled Vehicles module");
  assert.deepEqual(errors, [], "browser console/page errors");
  console.log(`PASS clean console; local server ${origin}; screenshots ${screenshots}`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
