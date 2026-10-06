import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const sql=await read('supabase/folha_ponto_v2.sql'),aux=await read('supabase/folha_ponto_v2_gestao.sql');
const client=await read('src/attendance-client.js'),sheet=await read('src/attendance-sheet.js'),app=await read('src/app.js');
test('Folha usa somente RPCs controladas, sem fallback/DML; motivo obrigatório fora da janela ADM',()=>{
 assert.doesNotMatch(client+sheet,/fn_guardar_ponto_obra|fn_listar_ponto_obra|method:\s*['"](?:PATCH|DELETE)['"]/);
 assert.match(sheet,/MOTIVO DA CORREÇÃO \(OBRIGATÓRIO\)/);assert.match(sql,/CORRECTION_REASON_REQUIRED/);
 assert.match(sheet,/remove_from_day/);assert.match(sheet,/daySummary/);assert.match(sheet,/reason:.*\|\|null/);
 const vacation=app.slice(app.indexOf('async function saveVacationDays'),app.indexOf('async function loadTeamData'));
 assert.match(vacation,/vacation_replace/);assert.doesNotMatch(vacation,/method:\s*['"](?:POST|DELETE|PATCH)['"]|!isSupabaseConfigured\)\s*\{/);
});
test('origem v2 privada; preview não insere capacidade, operação/história apenas na confirmação',()=>{
 assert.match(sql,/p_origem='folha_v2' AND folha_privado.quadro_autorizado/);
 assert.doesNotMatch(sql,/quadro_permit|set_config\(/);
 assert.match(sql,/IF NOT p_confirmar THEN RETURN/);assert.match(sql,/INSERT INTO folha_privado.operacoes/);
 assert.match(sql,/PRIMARY KEY\(empresa_id,ator_id,request_id\)/);
 assert.match(sql,/UNIQUE\(folha_id,folha_revision\)/);
});
test('legado preservado, externos não entram em RH/financeiro; exportação salarial bloqueada',()=>{
 assert.doesNotMatch(sql+aux,/INSERT INTO public\.colaboradores|UPDATE public\.ponto_pessoal_obra|DELETE FROM public\.ponto_pessoal_obra|INSERT INTO public\.(faturas|pagamentos|custos)/);
 assert.match(sql,/LEGACY_CONFLICT/);assert.match(sql,/EXTERNAL_DAY_REQUIRED/);assert.match(sql,/OVERTIME_ORIGIN_CONFLICT/);
 assert.match(aux,/OFFICIAL_EXPORTER_REQUIRED/);assert.doesNotMatch(aux,/\b22\b|valor_hora/);
});
test('Fase B usa gate independente pós-hotfix e preserva policies existentes',async()=>{
 const pre=await read('supabase/quadro_fase_b_pos_hotfix_precheck.sql'),migration=await read('supabase/quadro_fase_b_pos_hotfix_migration.sql');
 assert.match(pre,/BEGIN READ ONLY/);assert.match(pre,/REAL CATALOG VALIDATION REQUIRED/);
 assert.match(pre,/actual IS DISTINCT FROM approved->'expected_catalog'/);assert.match(pre,/encarregado_sem_dml_direto/);
 assert.doesNotMatch(migration,/DROP POLICY|SET identidade_a|exigir_fase_a\(\)/);
 assert.match(migration,/REVOKE INSERT,UPDATE,DELETE/);assert.doesNotMatch(migration,/fn_guardar_ponto_obra/);
});
test('rollbacks explícitos, sem CASCADE e sem apagar evidência persistente',async()=>{
 for(const path of ['supabase/folha_ponto_v2_rollback.sql','supabase/folha_ponto_v2_gestao_rollback.sql','supabase/quadro_fase_b_pos_hotfix_rollback.sql']){
  const text=await read(path);assert.doesNotMatch(text,/\bCASCADE\b/i);
  if(path.includes('folha_ponto'))assert.match(text,/ROLLBACK_DATA_PRESENT/);
 }
});
