import assert from "node:assert/strict";
import fs from "node:fs";

const app = fs.readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = fs.readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

assert.match(app, /planeamento_fases_resumo\?select=\*/);
assert.match(app, /function renderPhasesTab\(work\)/);
assert.match(app, /data-open-phase-planning/);
assert.match(app, /if \(selectedWorkTab === "phases"\) return renderPhasesTab\(work\)/);
assert.doesNotMatch(app, /<strong>FASES<\/strong><span>Este separador será desenvolvido/);
assert.match(styles, /\.work-phase-card/);
assert.match(styles, /\.work-phase-progress/);

console.log("work phases tab tests passed");
