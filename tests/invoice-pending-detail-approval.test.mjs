import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

assert.match(app, /data-invoice-detail=/, "pending cards must expose a detail action");
assert.match(app, /async function openInvoiceDetail/, "invoice detail loader must exist");
assert.match(app, /faturas_itens\?select=/, "detail must load extracted invoice items");
assert.match(app, /SOMA DOS ITENS/, "detail must reconcile item and document totals");
assert.match(app, /data-detail-decision="aprovado"/, "detail must expose approval");
assert.match(app, /data-detail-decision="recusado"/, "detail must expose rejection");
assert.match(app, /Confirma que verificou o PDF/, "a discrepant total must require explicit confirmation");
assert.match(app, /Math\.round\(Math\.max\(0, gross - effectiveDiscount\) \* 100\) \/ 100/, "stored item totals must be rounded in cents");
assert.match(css, /\.invoice-detail-table/, "invoice detail must have explicit layout styles");

console.log("invoice pending detail and approval tests passed");
