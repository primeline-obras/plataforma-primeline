import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const css = readFileSync(new URL("../src/visual-phase2.css", import.meta.url), "utf8");

assert.match(html, /visual-phase2\.css\?v=1/);
assert.match(css, /table thead th[\s\S]*?color:\s*var\(--text-secondary\)/);
assert.match(css, /table tbody td,[\s\S]*?border-bottom:\s*\.5px solid/);
assert.match(css, /table tbody tr:nth-child\(odd\)[\s\S]*?background:\s*var\(--card\)/);
assert.match(css, /table tbody a[\s\S]*?color:\s*var\(--text-primary\)/);
assert.match(css, /border-radius:\s*999px\s*!important/);
assert.match(css, /\.work-status\.adjudicado[\s\S]*?background:\s*var\(--pos-bg\)/);
assert.match(css, /\.work-status\.em_curso[\s\S]*?background:\s*var\(--warn-bg\)/);
assert.match(css, /\.work-status\.aguarda_resposta[\s\S]*?background:\s*var\(--state-neutral-bg\)/);
assert.match(css, /\.work-status\.recusado[\s\S]*?background:\s*var\(--neg-bg\)/);

console.log("Tabelas e badges semânticos da fase 2 validados.");
