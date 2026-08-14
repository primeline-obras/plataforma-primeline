import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");

const expected = new Map([
  ["overview", "layout-dashboard"],
  ["rsp", "users-round"],
  ["projects", "layout-kanban"],
  ["works", "building"],
  ["invoices", "receipt"],
  ["subcontractors", "hardhat"],
  ["planning", "gantt"],
  ["documents", "file-text"],
  ["rnc", "alert-triangle"],
  ["rooms", "presentation"],
  ["team", "users"],
]);

for (const [view, iconName] of expected) {
  assert.match(
    app,
    new RegExp(`data-view="${view}"[^>]*>\\$\\{icon\\("${iconName}"\\)\\}`),
    `${view} deve usar o ícone ${iconName}`,
  );
}

assert.equal(new Set(expected.values()).size, expected.size, "cada módulo deve ter uma silhueta única");
console.log("Ícones únicos da sidebar validados.");
