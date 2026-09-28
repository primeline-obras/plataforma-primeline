import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const moduleSource = await readFile(new URL("../src/monthly-map.js", import.meta.url), "utf8");
const apiSource = await readFile(new URL("../src/monthly-api.js", import.meta.url), "utf8");
assert.match(app, /data-finance-tab="financial-map"/);
assert.match(app, /data-finance-panel="financial-map"/);
assert.match(app, /function canViewFinancialMap\(\)[\s\S]*?hasFullAccess\(\) \|\| isFinancial\(\)/);
assert.match(app, /financialMapTab\.hidden = !canViewFinancialMap\(\)/);
assert.match(app, /from "\.\/monthly-map\.js/);
assert.doesNotMatch(app, /from "\.\/financial-map\.js/);
assert.doesNotMatch(moduleSource + apiSource, /select=\*|mapa_financeiro_ajustes|method: ['"](?:PATCH|DELETE)['"]/);
assert.match(moduleSource, /readMonthlySummary/);
assert.match(moduleSource, /readMonthlyOrigins/);
assert.match(moduleSource, /changeMonthlyState/);
assert.match(moduleSource, /recalculateMonthly/);
assert.match(app, /onCommitted: event => financialMapModule.invalidate\(event\)/);
console.log("Mapa mensal usa apenas RPCs rastreáveis e mantém permissões de acesso.");
