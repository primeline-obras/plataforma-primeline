import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const styles = await readFile(new URL("../src/styles.css", import.meta.url), "utf8");

assert.match(app, /alteracoes_tee\?select=\*&obra_id=eq\./);
assert.match(app, /data-work-tab="tees"/);
assert.match(app, /function renderTeesTab\(work\)/);
assert.match(app, /data-new-tee/);
assert.match(app, /data-edit-tee/);
assert.match(app, /function openTeeDialog\(teeId = ""\)/);
assert.match(app, /name="numero"[\s\S]*name="revisao"[\s\S]*name="descricao"/);
assert.match(app, /name="valor"[\s\S]*name="preco_custo"/);
assert.match(app, /name="data_inicio_execucao"[\s\S]*name="data_fim_execucao"/);
assert.match(app, /ESTE TEE NÃO PERTENCE A UMA FASE ESPECÍFICA/);
assert.match(app, /String\(phase\.codigo \|\| ""\)\.toUpperCase\(\) === "F01"/);
assert.match(app, /method: teeId \? "PATCH" : "POST"/);
assert.match(app, /if \(hasFullAccess\(\)\)[\s\S]*estado_aprovacao_gerencia/);
assert.match(app, /Quando o TEE estiver aprovado pelo cliente[\s\S]*planeamento e a previsão financeira/);
assert.match(styles, /\.tees-workspace/);
assert.match(styles, /\.tee-card/);

console.log("Formulário de TEEs, regra F01 e edição protegida validados.");
