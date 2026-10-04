import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const inventory=JSON.parse(await readFile(new URL('./fixtures/writers-economicos-inventario-20261004.json',import.meta.url),'utf8'));

// Functional defensive tests only: synthetic local resources, each scenario rolled back.
export async function economicWriterCases({t,q,connect}) {
 const cases=[
  ['fn_concluir_custo_pl','SELECT fn_concluir_custo_pl($1,77)',9014,'planeamento_custos_componentes','valor_real_pl',77],
  ['fn_concluir_custo_pl_fase','SELECT fn_concluir_custo_pl_fase($1,77)',9013,'orcamento_fases','valor_real_pl',77],
  ['fn_concluir_custos_pl_tarefa','SELECT * FROM fn_concluir_custos_pl_tarefa($1)',9011,'planeamento_custos_componentes','estado_custo','concluido'],
  ['fn_confirmar_custo_real_pl','SELECT fn_confirmar_custo_real_pl($1,77)',9011,'planeamento_itens','valor_real_pl',77],
  ['fn_confirmar_remocao_custo_estimado_subempreitada','SELECT fn_confirmar_remocao_custo_estimado_subempreitada($1)',9020,'planeamento_custos_componentes','estado_custo','adjudicado'],
  ['fn_guardar_componente_custo',"SELECT fn_guardar_componente_custo($1,'PL',77,'concluido',66,$2)",9011,'planeamento_custos_componentes','valor_orcamentado',77],
  ['fn_eliminar_proposta_comparativo','SELECT fn_eliminar_proposta_comparativo($1)',9031,'comparativo_propostas',null,null],
  ['fn_criar_fornecedor_comparativo',"SELECT fn_criar_fornecedor_comparativo($1,'Fornecedor novo sintético')",9030,'fornecedores','nome','Fornecedor novo sintético'],
  ['fn_importar_proposta_comparativo',"SELECT fn_importar_proposta_comparativo($1,$2,'{}',$3)",9030,'comparativo_itens_precos','preco_unitario',77],
  ['fn_criar_subempreitada_do_comparativo',"SELECT fn_criar_subempreitada_do_comparativo($1,$2,$3,current_date,current_date,'30_dias')",9030,'subempreitadas','mapa_comparativo_id',id(9030)],
  ['fn_guardar_lancamento_gestao_obras',"SELECT fn_guardar_lancamento_gestao_obras($1,$2,'materiais',current_date,'Sintético','Teste',NULL,'un',1,77,NULL,77)",9040,'gestao_obras_lancamentos','valor',77],
  ['fn_apagar_lancamento_gestao_obras','SELECT fn_apagar_lancamento_gestao_obras($1)',9040,'gestao_obras_lancamentos',null,null]
 ];
 const tables=['planeamento_custos_componentes','planeamento_itens','orcamento_fases','fornecedores','comparativo_propostas','comparativo_itens','comparativo_itens_precos','comparativo_ajustes','mapas_comparativos','subempreitadas','gestao_obras_lancamentos','previsao_financeira_mensal','alertas','log_auditoria'];
 const state=async()=>{const result={};for(const name of tables)result[name]=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) s FROM public.'+name+' x')).rows[0].s;return result;};
 async function prepare(work,name) {
  for(const table of ['planeamento_custos_componentes','fornecedores','comparativo_propostas','comparativo_itens','comparativo_itens_precos','subempreitadas','gestao_obras_lancamentos'])
   await q('ALTER TABLE public.'+table+' ALTER COLUMN id SET DEFAULT gen_random_uuid()');
  await q('CREATE UNIQUE INDEX economic_component_no_item ON planeamento_custos_componentes(planeamento_item_id,tipo) WHERE item_orcamento_id IS NULL; CREATE UNIQUE INDEX economic_component_item ON planeamento_custos_componentes(planeamento_item_id,tipo,item_orcamento_id) WHERE item_orcamento_id IS NOT NULL');
  await q("INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo) VALUES($1,$1,$2,'gestao_plataforma',false),($3,$3,NULL,'gestao_plataforma',true)",[id(9003),id(1),id(9004)]);
  await q('INSERT INTO fases(id,obra_id) VALUES($1,$2)',[id(9010),id(work)]);
  await q("INSERT INTO planeamento_itens(id,fase_id,descricao,estado,executado_por,valor_orca_pl,valor_estimado) VALUES($1,$2,'Sintético','concluido','PL',88,88)",[id(9011),id(9010)]);
  await q('INSERT INTO itens_orcamento(id,fase_id,numero_artigo,descricao,quantidade) VALUES($1,$2,\'SYNTHETIC\',\'Sintético\',1)',[id(9012),id(9010)]);
  await q('INSERT INTO orcamento_fases(id,obra_id,fase_id,custo_total_estimado) VALUES($1,$2,$3,88)',[id(9013),id(work),id(9010)]);
  await q("INSERT INTO planeamento_custos_componentes(id,planeamento_item_id,tipo,valor_orcamentado,estado_custo) VALUES($1,$2,'PL',88,'orcamentado_nao_comprometido')",[id(9014),id(9011)]);
  await q("INSERT INTO fornecedores(id,empresa_id,nome) VALUES($1,$2,'Fornecedor sintético A'),($3,$4,'Fornecedor sintético B')",[id(9021),id(work===200?2:1),id(9022),id(work===200?1:2)]);
  await q("INSERT INTO subempreitadas(id,obra_id,fornecedor_id,estado,valor_adjudicado) VALUES($1,$2,$3,'em_execucao',88)",[id(9020),id(work),id(9021)]);
  await q("INSERT INTO planeamento_custos_componentes(id,planeamento_item_id,tipo,subempreitada_id,estado_custo) VALUES($1,$2,'subempreitada',$3,'orcamentado_nao_comprometido')",[id(9015),id(9011),id(9020)]);
  await q('INSERT INTO mapas_comparativos(id,obra_id,valor_adjudicado_real,especialidade) VALUES($1,$2,88,\'Sintético\')',[id(9030),id(work)]);
  if(name!=='fn_importar_proposta_comparativo')await q('INSERT INTO comparativo_propostas(id,mapa_id,fornecedor_id) VALUES($1,$2,$3)',[id(9031),id(9030),id(9021)]);
  await q('INSERT INTO comparativo_itens(id,mapa_id,numero,designacao,quantidade) VALUES($1,$2,\'SYNTHETIC\',\'Sintético\',1)',[id(9032),id(9030)]);
  await q('INSERT INTO gestao_obras_lancamentos(id,obra_id,categoria,valor) VALUES($1,$2,\'materiais\',88)',[id(9040),id(work)]);
 }
 const args=(c,target=c[2])=>{
  if(c[0]==='fn_guardar_componente_custo')return [id(target),null];
  if(c[0]==='fn_importar_proposta_comparativo')return [id(target),id(9021),JSON.stringify([{itemId:id(9032),normalizedQuantity:1,unitPrice:77}])];
  if(c[0]==='fn_criar_subempreitada_do_comparativo')return [id(target),id(9031),id(9010)];
  if(c[0]==='fn_guardar_lancamento_gestao_obras')return [id(target),id(120)];
  return [id(target)];
 };
 async function scenario(c,{work=120,actor=12,target=c[2],change,params,code,positive=false}={}) {
  await q('BEGIN');
  try {
   await prepare(work,c[0]);if(change)await change();
   const before=await state();
   await q('SAVEPOINT operation');await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(actor)]);await q('SET LOCAL ROLE authenticated');
   if(positive){
    await q(c[1],params??args(c,target));await q('RESET ROLE');
    const after=await state();assert.notDeepEqual(after,before,'legitimate operation has its expected effect');
    if(c[4]===null)assert.equal((await q('SELECT count(*)::int n FROM '+c[3]+' WHERE id=$1',[id(c[2])])).rows[0].n,0);
    else assert.ok((after[c[3]]||[]).some(row=>typeof c[5]==='number'?Number(row[c[4]])===c[5]:row[c[4]]===c[5]),c[0]+' expected final value');
   }else {
    await assert.rejects(()=>q(c[1],params??args(c,target)),e=>code?e.code===code:['P0001','P0002','42501'].includes(e.code));
    await q('ROLLBACK TO SAVEPOINT operation');assert.deepEqual(await state(),before,'no partial writes after refusal');
   }
  }finally{await q('ROLLBACK');}
 }
 for(const c of cases) {
  await t.test('tenant writer '+c[0]+': legitimate role, foreign company, inactive, missing and atomicity',async()=>{
   await scenario(c,{positive:true});
   if(!c[0].includes('lancamento_gestao_obras'))await scenario(c,{actor:13,positive:true});
   if(!c[0].includes('lancamento_gestao_obras'))await scenario(c,{actor:14,positive:true});
   else await scenario(c,{actor:11,positive:true});
   await scenario(c,{work:200,code:'42501'});
   await scenario(c,{actor:9003,code:'42501'});
   await scenario(c,{actor:9004,code:'42501'});
   await scenario(c,{actor:999,code:'42501'});
   await scenario(c,{actor:10,code:'42501'});
   await scenario(c,{target:99999});
  });
 }
 const byName=n=>cases.find(c=>c[0]===n);
 await t.test('launch INSERT/UPDATE: validate original and replacement company',async()=>{
  const c=byName('fn_guardar_lancamento_gestao_obras');
  await scenario(c,{params:[null,id(120)],positive:true});
  await scenario(c,{params:[null,id(200)],code:'42501'});
  await scenario(c,{work:200,params:[id(9040),id(120)],code:'42501'});
  await scenario(c,{params:[id(9040),id(200)],code:'42501'});
 });
 await t.test('component: budget item and subcontract must match real task work',async()=>{
  const c=byName('fn_guardar_componente_custo');
  await scenario(c,{params:[id(9011),id(9012)],positive:true});
  await scenario(c,{params:[id(9011),id(9012)],change:()=>q('UPDATE fases SET obra_id=$1 WHERE id=$2',[id(200),id(9010)]),code:'42501'});
  await scenario(c,{params:[id(9011),id(9012)],change:()=>q('UPDATE itens_orcamento SET fase_id=$1 WHERE id=$2',[id(9050),id(9012)]),code:'42501'});
  await scenario({...c,1:c[1].replace("'PL'","'subempreitada'")},{change:async()=>{await q('UPDATE planeamento_itens SET subempreitada_id=$1 WHERE id=$2',[id(9020),id(9011)]);await q('UPDATE subempreitadas SET obra_id=$1 WHERE id=$2',[id(200),id(9020)]);},code:'42501'});
  await scenario(byName('fn_confirmar_remocao_custo_estimado_subempreitada'),{change:()=>q('UPDATE fases SET obra_id=$1 WHERE id=$2',[id(200),id(9010)]),code:'42501'});
 });
 await t.test('comparative: foreign supplier, item, proposal and phase rejected atomically',async()=>{
  const imp=byName('fn_importar_proposta_comparativo'),sub=byName('fn_criar_subempreitada_do_comparativo');
  await scenario(imp,{params:[id(9030),id(9022),JSON.stringify([{itemId:id(9032),unitPrice:77}])],code:'42501'});
  await scenario(imp,{change:()=>q('UPDATE comparativo_itens SET mapa_id=$1 WHERE id=$2',[id(99999),id(9032)]),code:'42501'});
  await scenario(sub,{change:()=>q('UPDATE comparativo_propostas SET mapa_id=$1 WHERE id=$2',[id(99999),id(9031)]),code:'23514'});
  await scenario(sub,{change:()=>q('UPDATE fases SET obra_id=$1 WHERE id=$2',[id(200),id(9010)]),code:'23514'});
  await scenario(sub,{change:()=>q('UPDATE comparativo_propostas SET fornecedor_id=$1 WHERE id=$2',[id(9022),id(9031)]),code:'42501'});
 });
 await t.test('12 definitions match approved bodies, safe config and previous contracts/ACL',async()=>{
  for(const f of inventory.functions){
   const row=(await q("SELECT md5(replace(prosrc,chr(13),'')) hash,prosecdef,pg_get_userbyid(proowner) owner,proconfig,proacl::text acl FROM pg_proc WHERE oid=$1::regprocedure",[f.signature])).rows[0];
   assert.equal(row.hash,f.expected_body_md5);assert.equal(row.prosecdef,true);assert.equal(row.owner,'postgres');assert.deepEqual(row.proconfig,['search_path=pg_catalog, public, pg_temp']);
   assert.deepEqual(row.acl.slice(1,-1).split(',').sort(),['authenticated=X/postgres','postgres=X/postgres']);
   const definition=(await q('SELECT pg_get_functiondef($1::regprocedure) d',[f.signature])).rows[0].d;
   assert.equal(definition.split(' LANGUAGE ')[0],f.original_definition.split(' LANGUAGE ')[0],'arguments, defaults and return contract preserved');
  }
 });
 await t.test('actor and real work stay locked during a legitimate cost operation',async()=>{
  const other=await connect();
  await q('BEGIN');
  try {
   await prepare(120,'fn_concluir_custo_pl');
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);await q('SET LOCAL ROLE authenticated');
   await q('SELECT fn_concluir_custo_pl($1,77)',[id(9014)]);await q('RESET ROLE');
   for(const [sql,params] of [
    ['UPDATE obras SET empresa_id=$1 WHERE id=$2',[id(2),id(120)]],
    ['UPDATE utilizadores SET ativo=false WHERE id=$1',[id(12)]]
   ]){
    await other.query('BEGIN; SET LOCAL lock_timeout=\'150ms\'');
    await assert.rejects(()=>other.query(sql,params),e=>e.code==='55P03');
    await other.query('ROLLBACK');
   }
  }finally{
   await q('ROLLBACK');await other.query('ROLLBACK');await other.end();
  }
 });
}
