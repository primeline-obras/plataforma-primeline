import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const fixture=JSON.parse(await readFile(new URL('./fixtures/encarregado-catalogo-real-20261004.json',import.meta.url),'utf8'));
const integrity=JSON.parse(await readFile(new URL('./fixtures/encarregado-autorizacao-integridade-20261004.json',import.meta.url),'utf8'));
const scripts=Object.fromEntries(await Promise.all(['precheck','backup','migration','postcheck'].map(async k=>[k,await readFile(new URL('../supabase/encarregado_escopo_'+k+'.sql',import.meta.url),'utf8')])));
const gate=scripts.precheck.match(/DO \$budget_phase_coherence\$[\s\S]*?END \$budget_phase_coherence\$;/)[0];
const line=phase=>({fase_id:id(phase),descricao:'Importação sintética',venda_prevista:88,custo_total_estimado:77,margem_prevista:11,materiais:22});

export async function budgetTargetCases({t,q,connect}) {
 const state=async()=>{const data={};for(const table of fixture.catalog.tables.filter(t=>t.kind==='r'))data[table.name]=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) v FROM public."'+table.name+'" x')).rows[0].v;return data;};
 async function scenario({targetWork=120,existing=true,mixed=false,positive=false}) {
  await q('BEGIN');
  try {
   await q('ALTER TABLE orcamento_fases ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX target_budget_unique ON orcamento_fases(fase_id)');
   await q('INSERT INTO fases(id,obra_id) VALUES($1,$2),($3,$2)',[id(92001),id(120),id(92002)]);
   if(existing)await q("INSERT INTO orcamento_fases(id,obra_id,fase_id,descricao,custo_total_estimado,venda_prevista,margem_prevista,materiais) VALUES($1,$2,$3,'Original sintético',10,20,10,3)",[id(92003),id(targetWork),id(92002)]);
   const before=await state();
   await q(integrity.triggers.find(t=>t.table==='orcamento_fases').definition);
   await q('SAVEPOINT call');
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);await q('SET LOCAL ROLE authenticated');
   const lines=mixed?[line(92001),line(92002)]:[line(92002)];
   if(positive){
    const r=(await q("SELECT fn_importar_orcamento_fases($1,$2,'Sintético') v",[id(120),JSON.stringify(lines)])).rows[0].v;
    assert.equal(r.importadas,1);await q('RESET ROLE');
    const rows=(await q('SELECT * FROM orcamento_fases WHERE fase_id=$1',[id(92002)])).rows;
    assert.equal(rows.length,1);assert.equal(rows[0].obra_id,id(120));
    assert.equal(Number(rows[0].custo_total_estimado),77);assert.equal(Number(rows[0].venda_prevista),88);
    assert.equal(Number(rows[0].margem_prevista),11);assert.equal(Number(rows[0].materiais),22);
    if(existing)assert.equal(rows[0].id,id(92003));
    assert.ok((await q("SELECT count(*)::int n FROM log_auditoria WHERE tabela_afetada='public.orcamento_fases'")).rows[0].n>0);
   }else{
    await assert.rejects(()=>q("SELECT fn_importar_orcamento_fases($1,$2,'Sintético')",[id(120),JSON.stringify(lines)]),e=>e.code==='42501' && e.message==='FORBIDDEN: recurso relacionado indisponível.');
    await q('ROLLBACK TO SAVEPOINT call');assert.deepEqual(await state(),before,'all rows, economic fields and audit/import logs remain unchanged');
   }
  } finally {await q('ROLLBACK');}
 }
 await t.test('budget target A: same phase, another work in same company is refused',()=>scenario({targetWork:118}));
 await t.test('budget target B: legitimate existing target updates without replacing its ID',()=>scenario({positive:true}));
 await t.test('budget target C: legitimate absent target inserts normally',()=>scenario({existing:false,positive:true}));
 await t.test('budget target D: valid first phase and inconsistent second target roll back all rows/logs',()=>scenario({targetWork:200,mixed:true}));
 await t.test('budget target E: another company target is refused without economic changes',()=>scenario({targetWork:200}));
 await t.test('budget coherence gate is read-only, reports only IDs and rejects mismatches/missing phases',async()=>{
  for(const k of ['backup','migration','postcheck'])assert.ok(scripts[k].includes(gate),k+' uses the same gate');
  await q('BEGIN');
  try {
   await q('INSERT INTO fases(id,obra_id) VALUES($1,$2)',[id(92001),id(120)]);
   await q('INSERT INTO orcamento_fases(id,obra_id,fase_id) VALUES($1,$2,$3)',[id(92003),id(200),id(92001)]);
   for(const missing of [false,true]){
    if(missing)await q('UPDATE orcamento_fases SET fase_id=$1 WHERE id=$2',[id(99999),id(92003)]);
    const before=await state();await q('SAVEPOINT gate');
    await assert.rejects(()=>q(gate),e=>e.code==='23514' && e.message.startsWith('ORCAMENTO_FASES_OBRA_DIVERGENTE') && JSON.parse(e.detail)[0].orcamento_fase_id===id(92003));
    await q('ROLLBACK TO SAVEPOINT gate');assert.deepEqual(await state(),before);
   }
  } finally {await q('ROLLBACK');}
 });
 await t.test('budget target absent at prevalidation: concurrent foreign insertion is refused explicitly',async()=>{
  const other=await connect();let pending;
  try {
   await q('CREATE UNIQUE INDEX target_budget_race ON orcamento_fases(fase_id)');
   await q('INSERT INTO fases(id,obra_id) VALUES($1,$2)',[id(93001),id(120)]);
   await other.query('BEGIN');
   await other.query('INSERT INTO orcamento_fases(id,obra_id,fase_id,custo_total_estimado) VALUES($1,$2,$3,10)',[id(93002),id(200),id(93001)]);
   const pid=(await q('SELECT pg_backend_pid() pid')).rows[0].pid;
   await q('BEGIN');await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);await q('SET LOCAL ROLE authenticated');
   pending=q("SELECT fn_importar_orcamento_fases($1,$2,'Sintético')",[id(120),JSON.stringify([line(93001)])]).then(()=>({error:null}),error=>({error}));
   let waiting=false;
   for(let i=0;i<100;i++){
    const s=(await other.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid])).rows[0];
    if(s?.wait_event_type==='Lock'){waiting=true;break;}
    await new Promise(resolve=>setTimeout(resolve,20));
   }
   assert.equal(waiting,true,'import reaches the concurrent unique target');
   await other.query('COMMIT');const result=await pending;
   assert.equal(result.error?.code,'42501','no silently ignored upsert or foreign update');
   await q('ROLLBACK');
   const row=(await q('SELECT obra_id,custo_total_estimado FROM orcamento_fases WHERE id=$1',[id(93002)])).rows[0];
   assert.equal(row.obra_id,id(200));assert.equal(Number(row.custo_total_estimado),10);
  }finally{
   await other.query('ROLLBACK');if(pending)await pending;
   await q('ROLLBACK');await other.end();
   await q('DELETE FROM orcamento_fases WHERE id=$1',[id(93002)]);await q('DELETE FROM fases WHERE id=$1',[id(93001)]);
   await q('DROP INDEX IF EXISTS target_budget_race');
  }
 });
}
