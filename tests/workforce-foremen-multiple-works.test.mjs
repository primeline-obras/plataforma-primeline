import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const app = await readFile(new URL("../src/app.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../supabase/quadro_pessoal_encarregados_multiplas_obras.sql", import.meta.url), "utf8");

assert.match(app, /role\.includes\("encarregado"\)/, "O frontend deve reconhecer encarregados pela função.");
assert.match(app, /const allowsMultipleWorks = isWorkforceForeman\(person\)/, "A gravação deve permitir várias obras aos encarregados.");
assert.match(app, /if \(!allowsMultipleWorks && conflicting\.length\)/, "A substituição automática deve ficar limitada aos restantes colaboradores.");
assert.match(app, /data-source-ids=/, "Cada íman persistido deve guardar os ids das suas próprias alocações.");
assert.match(app, /quadro_pessoal_alocacao\?id=in\.\(/, "A remoção deve atingir apenas a colocação selecionada.");

assert.match(migration, /drop index if exists public\.quadro_pessoal_alocacao_colaborador_data_periodo_key/i);
assert.match(migration, /v_funcao like '%encarregado%'/i, "O trigger deve abrir a exceção apenas para encarregados.");
assert.match(migration, /O colaborador já está colocado nessa linha, data e período/i, "O trigger deve bloquear duplicados exatos.");
assert.match(migration, /O colaborador já tem uma alocação incompatível/i, "O trigger deve manter o conflito para os restantes papéis.");

console.log("workforce foremen multiple works tests passed");
