import assert from 'node:assert/strict';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');

// Independent functional confirmation of the existing preview/token contract.
// Synthetic rows only; the complete scenario is rolled back.
export async function finalAuditCases({t,q}) {
 await t.test('audit: budget phase importer refuses an existing target belonging to another company',async()=>{
  await q('BEGIN');
  try {
   await q('CREATE UNIQUE INDEX audit_budget_phase ON orcamento_fases(fase_id)');
   await q('INSERT INTO fases(id,obra_id,codigo,descricao) VALUES($1,$2,\'SYN-AUDIT-RELATION\',\'Fase sintética\')',[id(91001),id(120)]);
   // Same related-resource coherence scenario as the existing tenant suites.
   await q('INSERT INTO orcamento_fases(id,obra_id,fase_id,custo_total_estimado) VALUES($1,$2,$3,10)',[id(91002),id(200),id(91001)]);
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);
   await q('SET LOCAL ROLE authenticated');
   let error;
   try {await q("SELECT fn_importar_orcamento_fases($1,$2,'Sintético')",[id(120),JSON.stringify([{fase_id:id(91001),custo_total_estimado:77}])]);}catch(e){error=e;}
   if(error){assert.equal(error.code,'42501');}
   else {
    await q('RESET ROLE');
    const row=(await q('SELECT obra_id,custo_total_estimado FROM orcamento_fases WHERE id=$1',[id(91002)])).rows[0];
    assert.fail('Expected tenant refusal; existing budget target remains in company B and its cost changed from 10 to '+row.custo_total_estimado+' (foreign work retained: '+(row.obra_id===id(200))+')');
   }
  } finally {await q('ROLLBACK');}
 });
 await t.test('audit: legitimate planning cost confirmation and replay preserve the functional contract',async()=>{
  await q('BEGIN');
  try {
   await q('ALTER TABLE planeamento_lote_tokens ALTER COLUMN token SET DEFAULT gen_random_uuid(); ALTER TABLE planeamento_lote_tokens ALTER COLUMN expira_em SET DEFAULT now()+interval \'15 minutes\'');
   await q('ALTER TABLE planeamento_custos_componentes ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX audit_component_no_item ON planeamento_custos_componentes(planeamento_item_id,tipo) WHERE item_orcamento_id IS NULL; CREATE UNIQUE INDEX audit_component_item ON planeamento_custos_componentes(planeamento_item_id,tipo,item_orcamento_id) WHERE item_orcamento_id IS NOT NULL');
   await q('ALTER TABLE planeamento_fases_resumo ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX audit_phase_summary ON planeamento_fases_resumo(fase_id)');
   await q('INSERT INTO fases(id,obra_id,codigo,descricao) VALUES($1,$2,\'SYN-AUDIT\',\'Fase sintética\')',[id(90001),id(120)]);
   await q("INSERT INTO planeamento_itens(id,fase_id,codigo,descricao,peso_percentual,percentual_executado,estado,custo_estado,executado_por,valor_estimado,data_inicio_prevista,data_fim_prevista) VALUES($1,$2,'SYN-AUDIT','Tarefa sintética',100,0,'por_iniciar','orcamentado','PL',10,'2030-01-01','2030-01-02')",[id(90002),id(90001)]);
   const items=(await q('SELECT to_jsonb(pi) v FROM planeamento_itens pi JOIN fases f ON f.id=pi.fase_id WHERE f.obra_id=$1 ORDER BY pi.id',[id(120)])).rows.map(r=>r.v);
   const lote={version:1,obra_id:id(120),expected_items:items,expected_dependencies:[],changes:[{id:id(90002),valor_estimado:77}],dependencies:[],approved_cascade:[]};
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);
   await q('SET LOCAL ROLE authenticated');
   const preview=(await q('SELECT fn_guardar_planeamento_lote($1,NULL) v',[JSON.stringify(lote)])).rows[0].v;
   assert.deepEqual(preview.conflicts,[]);
   assert.ok(preview.confirmation_token);
   const confirmed=(await q('SELECT fn_guardar_planeamento_lote($1,$2) v',[JSON.stringify(lote),preview.confirmation_token])).rows[0].v;
   assert.equal(confirmed.committed,true);
   const replay=(await q('SELECT fn_guardar_planeamento_lote($1,$2) v',[JSON.stringify(lote),preview.confirmation_token])).rows[0].v;
   assert.deepEqual(replay,confirmed);
   await q('RESET ROLE');
   assert.equal(Number((await q('SELECT valor_estimado FROM planeamento_itens WHERE id=$1',[id(90002)])).rows[0].valor_estimado),77);
   assert.equal((await q('SELECT count(*)::int n FROM planeamento_lote_tokens WHERE token=$1 AND consumido_em IS NOT NULL',[preview.confirmation_token])).rows[0].n,1);
  } finally {await q('ROLLBACK');}
 });
}
