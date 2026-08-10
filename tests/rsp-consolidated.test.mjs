import assert from "node:assert/strict";
import fs from "node:fs";
import { accessFor } from "../src/access-control.js";

const dashboard = fs.readFileSync(new URL("../src/production-dashboard.js", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

for (const role of ["gerencia", "administrativo", "financeiro", "diretor_obra", "adjunto", "preparador"]) {
  assert.equal(accessFor({ role }).views.includes("rsp"), true, `${role} deve ver a RSP`);
}
assert.equal(accessFor({ role: "encarregado" }).views.includes("rsp"), false);

assert.match(app, /data-view="rsp"/);
assert.match(app, /id="rsp-view"/);
assert.match(app, /productionDashboard\.showRsp\(\)/);
assert.match(dashboard, /async function loadMeetingState\(work\)/);
assert.match(dashboard, /function meetingModel\(state\)/);
assert.match(dashboard, /async function showRsp\(\)/);
assert.match(dashboard, /states\.push\(await loadMeetingState\(works\[index\]\)\)/);
assert.match(dashboard, /states\.map\(renderRspWork\)/);
assert.match(dashboard, /meetingModel\(state\)/);
assert.match(dashboard, /REUNIÃO SEMANAL DE PRODUÇÃO/);
assert.match(dashboard, /OBRA EXECUTADA/);
assert.match(dashboard, /PRAZO CONSUMIDO/);
assert.match(dashboard, /CASH FLOW MENSAL/);
assert.match(dashboard, /PLANEAMENTO DE FASES/);

console.log("RSP consolidada reutiliza o carregador e os cálculos da reunião individual.");
