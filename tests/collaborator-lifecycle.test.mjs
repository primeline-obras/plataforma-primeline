import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const sql = readFileSync(new URL("../supabase/colaboradores_crud_alocacao_inicial.sql", import.meta.url), "utf8");

assert.match(app, /id="new-collaborator"/);
assert.match(app, /fn_criar_colaborador_com_alocacao/);
assert.match(app, /fn_atualizar_colaborador_ciclo_vida/);
assert.match(app, /data_saida/);
assert.match(app, /data_nascimento/);
assert.match(app, /option value="escritorio">Escritório/);
assert.match(app, /inactiveCollaborators/);

assert.match(sql, /tipo_alocacao in \('obra', 'escritorio', 'garantia', 'pontual'\)/i);
assert.match(sql, /insert into public\.colaboradores/i);
assert.match(sql, /insert into public\.quadro_pessoal_alocacao/i);
assert.match(sql, /p_data_admissao/i);
assert.match(sql, /delete from public\.alertas/i);
assert.match(sql, /fn_verificar_alertas_vencimento/i);
assert.doesNotMatch(sql, /delete from public\.(ausencias|horas_extraordinarias|medicina_trabalho|epis|quadro_pessoal_alocacao)/i);

console.log("collaborator lifecycle checks passed");
