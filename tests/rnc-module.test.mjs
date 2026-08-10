import assert from "node:assert/strict";
import fs from "node:fs";
import { rncCode } from "../src/rnc.js";

const read = path => fs.readFileSync(new URL(path, import.meta.url), "utf8");
const moduleSource = read("../src/rnc.js");
const pdfSource = read("../src/rnc-pdf.js");
const migration = read("../supabase/rnc_workflow.sql");
const app = read("../src/app.js");
const styles = read("../src/styles.css");

assert.match(moduleSource, /fn_criar_rnc/);
assert.match(moduleSource, /fn_definir_acao_rnc/);
assert.match(moduleSource, /fn_verificar_rnc/);
assert.match(moduleSource, /observação de verificação ou anexe uma prova/i);
assert.match(moduleSource, /fn_fechar_rnc/);
assert.match(moduleSource, /avaliacoes_subempreiteiro_anexos/);
assert.match(pdfSource, /RNC_\$\{work\.numero\}_\$\{String\(rnc\.numero\)\.padStart\(3, "0"\)\}\.pdf/);

assert.match(migration, /pg_advisory_xact_lock/);
assert.match(migration, /fn_e_encarregado_da_obra/);
assert.match(migration, /observacao_verificacao/);
assert.match(migration, /faturas_anexos_insert/);
assert.match(migration, /avaliacoes_subempreiteiro_anexos_insert/);

assert.match(app, /ANEXOS ADICIONAIS/);
assert.match(app, /não substituem a guia de remessa/);
assert.match(app, /uploadInvoiceAttachment/);
assert.match(styles, /\.rnc-column > header h2 \{ color:#fff;/);
assert.equal(rncCode({ numero: 120 }, 1), "RNC-120-001");
assert.match(moduleSource, /CÓDIGO DA RNC/);
assert.match(pdfSource, /pdf\.text\(rncCode\(work, rnc\.numero\)/);

console.log("Módulo RNC, prova de verificação, PDF e anexos opcionais validados.");
