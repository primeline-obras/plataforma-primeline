import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(new URL("../supabase/plano_acao_encarregado.sql", import.meta.url), "utf8");
const actionPlan = readFileSync(new URL("../src/action-plan.js", import.meta.url), "utf8");
const planning = readFileSync(new URL("../src/planning.js", import.meta.url), "utf8");
const access = readFileSync(new URL("../src/access-control.js", import.meta.url), "utf8");
const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
const styles = readFileSync(new URL("../src/styles.css", import.meta.url), "utf8");

test("encarregado atualiza tarefas apenas pela RPC restrita", () => {
  assert.match(migration, /security definer/i);
  assert.match(migration, /fn_e_encarregado_da_obra\(v_obra_id\)/i);
  assert.match(migration, /revoke all on function public\.fn_atualizar_tarefa_encarregado[\s\S]*from public, anon/i);
  assert.match(migration, /grant execute[\s\S]*to authenticated/i);
  assert.doesNotMatch(migration, /create policy[\s\S]*planeamento_itens[\s\S]*for update[\s\S]*encarregado/i);
});

test("RPC limita a alteração aos quatro campos aprovados", () => {
  const update = migration.match(/update public\.planeamento_itens[\s\S]*?returning \* into v_item;/i)?.[0] || "";
  assert.match(update, /estado\s*=/i);
  assert.match(update, /data_fim_real\s*=/i);
  assert.match(update, /impedido\s*=/i);
  assert.match(update, /observacao_impedimento\s*=/i);
  assert.doesNotMatch(update, /percentual_executado\s*=/i);
  assert.doesNotMatch(update, /data_inicio_prevista\s*=/i);
  assert.doesNotMatch(update, /data_fim_prevista\s*=/i);
});

test("impedimento exige observação e gera alerta urgente", () => {
  assert.match(migration, /planeamento_itens_impedimento_observacao_check/i);
  assert.match(migration, /trg_alertar_tarefa_impedida/i);
  assert.match(migration, /'tarefa_impedida'/i);
  assert.match(migration, /'URGENTE · Tarefa impedida'/i);
});

test("Plano de Ação oferece calendário, atrasadas, conclusão e impedimentos", () => {
  assert.match(access, /encarregado:[\s\S]*"action-plan"/i);
  assert.match(actionPlan, /action-calendar-grid/i);
  assert.match(actionPlan, /ATRASADAS/i);
  assert.match(actionPlan, /data-action-complete/i);
  assert.match(actionPlan, /data-action-block/i);
  assert.match(actionPlan, /rpc\/fn_atualizar_tarefa_encarregado/i);
  assert.match(planning, /planning-task-blocked/i);
});

test("encarregado vê as áreas autorizadas e a consulta de ausências", () => {
  const foremanAccess = access.match(/encarregado:\s*\{[\s\S]*?\n\s*\},/i)?.[0] || "";
  assert.match(foremanAccess, /views:\s*\["action-plan",\s*"planning",\s*"documents",\s*"rnc",\s*"rooms",\s*"team",\s*"workforce",\s*"settings"\]/i);
  assert.doesNotMatch(foremanAccess, /"overview"|"meeting"|"works"/i);
  assert.match(app, /function defaultViewForCurrentUser\(\)/i);
  assert.match(app, /permitted\.includes\("action-plan"\)/i);
});

test("prioridades e semana ficam lado a lado e o calendário usa descrição legível", () => {
  assert.match(actionPlan, /action-priority-grid[\s\S]*action-overdue[\s\S]*action-week/i);
  assert.match(actionPlan, /\$\{calendar\(\)\}/i);
  assert.match(actionPlan, /calendarTaskLabel\(item\)/i);
  assert.match(styles, /\.action-priority-grid\s*\{[^}]*grid-template-columns:\s*repeat\(2/i);
});
