import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/tees_previsao_encarregados.sql", import.meta.url), "utf8");

assert.match(migration, /add column if not exists data_inicio_execucao date/i);
assert.match(migration, /add column if not exists data_fim_execucao date/i);
assert.match(migration, /add column if not exists tee_id uuid/i);
assert.match(migration, /create trigger trg_sincronizar_tee_planeamento/i);
assert.match(migration, /create trigger trg_sincronizar_subempreitada_previsao/i);
assert.match(migration, /create trigger trg_sincronizar_tee_previsao/i);
assert.match(migration, /coalesce\(p\.fechado, false\)/i, "A automação deve respeitar meses fechados.");
assert.match(migration, /coalesce\(old\.preco_custo, 0\)/i, "TEEs devem alimentar saídas pelo preço de custo.");
assert.match(migration, /fn_e_encarregado_da_obra/i);
assert.match(migration, /tipo in \('desenho', 'desenhos_preparacao', 'plantas_projeto'\)/i);
const foremanPolicies = [...migration.matchAll(/create policy[\s\S]*?;/gi)]
  .map(match => match[0])
  .filter(policy => policy.includes("fn_e_encarregado_da_obra"));
assert(foremanPolicies.length >= 7, "Devem existir políticas de leitura para todos os módulos pedidos.");
foremanPolicies.forEach(policy => assert.match(policy, /for select/i, "Encarregados só podem surgir em políticas SELECT."));

console.log("TEEs, previsão mensal e leitura dos encarregados validados.");
