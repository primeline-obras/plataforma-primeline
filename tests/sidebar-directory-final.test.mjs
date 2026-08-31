import assert from "node:assert/strict";
import fs from "node:fs";

const identity = fs.readFileSync(new URL("../src/visual-identity-final.css", import.meta.url), "utf8");
const directory = fs.readFileSync(new URL("../src/subcontractors.js", import.meta.url), "utf8");
const grouping = fs.readFileSync(new URL("../src/supplier-directory-grouping.css", import.meta.url), "utf8");

assert.match(identity, /--accent:\s*#4A5568/i);
assert.match(identity, /--brand-amber:\s*#4A5568/i);
assert.match(identity, /\.sidebar nav button\s*\{[^}]*color:\s*#4A5568/i);
assert.doesNotMatch(identity, /#D9A441/i);

assert.match(directory, /function directoryGroups\(rows\)/);
assert.match(directory, /supplier-specialty-group/);
assert.match(directory, /\(right\.metrics\.rating \?\? -1\) - \(left\.metrics\.rating \?\? -1\)/);
assert.doesNotMatch(directory, /ADJUDICADO HISTÓRICO/);
assert.doesNotMatch(directory, /data-supplier-sort/);
assert.match(grouping, /supplier-specialty-group/);
assert.match(grouping, /grid-template-columns:\s*repeat\(3,1fr\)/);

console.log("Sidebar sem dourado e diretório agrupado por especialidade validados.");
