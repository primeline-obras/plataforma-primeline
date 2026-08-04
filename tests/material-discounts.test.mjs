import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const [migration, app, comparison, readme] = await Promise.all([
  readFile(new URL("../supabase/faturas_materiais_descontos.sql", import.meta.url), "utf8"),
  readFile(new URL("../src/app.js", import.meta.url), "utf8"),
  readFile(new URL("../src/subcontractors.js", import.meta.url), "utf8"),
  readFile(new URL("../README.md", import.meta.url), "utf8"),
]);

assert.match(migration, /add column if not exists desconto_percentual numeric/i);
assert.match(migration, /add column if not exists valor_desconto numeric/i);
assert.match(app, /data-item-field="desconto_percentual"/i);
assert.match(app, /data-item-field="valor_desconto"/i);
assert.match(app, /discountX:\s*pdfHeaderColumn/i);
assert.match(app, /desconto_percentual:\s*item\.desconto_percentual/i);
assert.match(app, /valor_desconto:\s*item\.valor_desconto/i);
assert.match(comparison, /PREÇO BRUTO\/UN\./i);
assert.match(comparison, /PREÇO LÍQUIDO\/UN\./i);
assert.match(readme, /TEE transversal[\s\S]*Estaleiro \(`F01`\)/i);

console.log("Descontos de materiais e regra F01 para TEEs transversais validados.");
