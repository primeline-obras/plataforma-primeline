import assert from "node:assert/strict";
import fs from "node:fs";

const read = path => fs.readFileSync(new URL(path, import.meta.url), "utf8");
const app = read("../src/app.js");
const css = read("../src/styles.css");
const sql = read("../supabase/faturas_apagar_administrativo.sql");

assert.match(app, /isAdministrative\(\) \? `<label><input type="radio"/);
assert.match(app, /APAGAR SELECIONADA/);
assert.match(app, /Tens a certeza que queres apagar esta fatura\?/);
assert.match(app, /ESTA AÇÃO NÃO PODE SER DESFEITA/);
assert.match(app, /rpc\/fn_apagar_fatura_administrativo/);
assert.match(css, /\.invoice-trace-delete/);

assert.match(sql, /array\['faturas_itens', 'faturas_anexos', 'faturas_guias'\]/);
assert.match(sql, /on delete cascade not valid/i);
assert.match(sql, /if public\.fn_e_admin\(\)/);
assert.match(sql, /u\.funcao = 'administrativo'/);
assert.match(sql, /Só o papel Administrativo pode apagar faturas/);
assert.match(sql, /trg_auditoria_faturas/);
assert.match(sql, /'numero_doc', v_fatura\.numero_doc/);
assert.match(sql, /delete from public\.faturas/);
assert.match(sql, /revoke delete on table public\.faturas from authenticated/);

console.log("Eliminação administrativa de faturas, cascata e auditoria validadas.");
