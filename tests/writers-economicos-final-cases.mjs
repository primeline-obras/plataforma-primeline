import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const snapshot=JSON.parse(await readFile(new URL('./fixtures/encarregado-catalogo-real-20261004.json',import.meta.url),'utf8'));
const inventory=JSON.parse(await readFile(new URL('./fixtures/writers-economicos-final-inventario-20261004.json',import.meta.url),'utf8'));

export async function finalEconomicCases({t,q}) {
 const state=async()=>{const result={};for(const table of snapshot.catalog.tables.filter(t=>t.kind==='r'))result[table.name]=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) s FROM public."'+table.name+'" x')).rows[0].s;return result;};
 const tee=work=>({obra_id:id(work),fase_id:id(work===200?70072:70071),numero:'SYN-NEW',descricao:'TEE sintético',valor:10,preco_custo:5,itens:[{numero_artigo:'SYN-1',descricao:'Artigo sintético',quantidade:1,preco_unitario:10}]});
 const sub=work=>({obra_id:id(work),fase_id:id(work===200?70072:70071),fornecedor_id:id(work===200?70076:70075),trabalho:'Sintético',estado:'adjudicado',valor_adjudicado:44});
 const json=x=>JSON.stringify(x);
 const cases=[
  {name:'fn_confirmar_compromisso_subempreitada',sql:'SELECT * FROM fn_confirmar_compromisso_subempreitada($1)',args:()=>[id(70073)],missing:()=>[id(99999)],effect:r=>assert.equal(r.rows[0].compromisso_confirmado,true)},
  {name:'fn_importar_orcamento_fases',sql:'SELECT fn_importar_orcamento_fases($1,$2,\'Sintético\') v',args:work=>[id(work),json([{fase_id:id(work===200?70072:70071),descricao:'Sintético',custo_total_estimado:77}])],missing:()=>[id(99999),'[]'],effect:r=>assert.equal(r.rows[0].v.importadas,1)},
  {name:'fn_guardar_precos_candidato_subempreitada',sql:'SELECT fn_guardar_precos_candidato_subempreitada($1,$2) v',args:()=>[id(70079),json([{item_orcamento_id:id(70077),preco_unitario:77}])],missing:()=>[id(99999),'[]'],effect:r=>assert.equal(Number(r.rows[0].v),154)},
  {name:'fn_criar_consulta_subempreitada',sql:'SELECT * FROM fn_criar_consulta_subempreitada($1,$2,\'Sintético\',$3)',args:work=>[id(work),id(work===200?70072:70071),[id(70077)]],missing:()=>[id(99999),id(70071),[id(70077)]],effect:r=>assert.equal(r.rows[0].trabalho,'Sintético')},
  {name:'fn_adjudicar_candidato_subempreitada',sql:'SELECT * FROM fn_adjudicar_candidato_subempreitada($1,current_date,current_date,\'30_dias\')',args:()=>[id(70079)],missing:()=>[id(99999)],effect:r=>assert.equal(Number(r.rows[0].valor_adjudicado),55)},
  {name:'fn_registar_aditamento_subempreitada',sql:'SELECT * FROM fn_registar_aditamento_subempreitada($1,\'Sintético\',77,$2)',args:()=>[id(70074),id(70083)],missing:()=>[id(99999),null],effect:r=>assert.equal(Number(r.rows[0].valor),77)},
  {name:'fn_decidir_aditamento_subempreitada',sql:'SELECT * FROM fn_decidir_aditamento_subempreitada($1,\'aprovado\',\'Sintético\')',args:()=>[id(70082)],missing:()=>[id(99999)],effect:r=>assert.equal(r.rows[0].estado,'aprovado')},
  {name:'fn_concluir_subempreitada_com_avaliacao',sql:'SELECT * FROM fn_concluir_subempreitada_com_avaliacao($1,4,4,4,4,\'Sintético\')',args:()=>[id(70074)],missing:()=>[id(99999)],effect:r=>assert.equal(r.rows[0].estado,'concluido')},
  {name:'fn_importar_tees_xlsx',sql:'SELECT fn_importar_tees_xlsx($1,\'Sintético\') v',args:work=>[json([tee(work)])],missing:()=>[json([tee(99999)])],effect:r=>assert.equal(r.rows[0].v.importadas,1)},
  {name:'fn_importar_tees_revisoes',sql:'SELECT fn_importar_tees_revisoes(1,$1,$2,\'Sintético\') v',args:work=>[id(work),json([{...tee(work),estado_aprovacao_cliente:'pendente',estado_operacional:'nao_iniciado',revisao:'REV00'}])],missing:()=>[id(99999),'[]'],effect:r=>assert.equal(r.rows[0].v.committed,true)},
  {name:'fn_importar_subempreitadas_xlsx',sql:'SELECT fn_importar_subempreitadas_xlsx($1,\'Sintético\') v',args:work=>[json([sub(work)])],missing:()=>[json([sub(99999)])],effect:r=>assert.equal(r.rows[0].v.importadas,1)},
  {name:'fn_atualizar_venda_contrato_via_tee',internal:true,sql:'SELECT * FROM fn_atualizar_venda_contrato_via_tee($1)',args:()=>[id(70083)],missing:()=>[id(99999)],effect:r=>assert.ok(Number(r.rows[0].venda_contratual_efetiva)>0)},
  {name:'fn_definir_estado_mensal_v1',sql:'SELECT fn_definir_estado_mensal_v1($1,\'2030-01\',\'aberto\',NULL,\'SYNTHETIC-MONTH\') v',args:work=>[id(work)],missing:()=>[id(99999)],effect:r=>assert.equal(r.rows[0].v.state,'aberto')},
  {name:'fn_importar_mapa_financeiro_xlsx',sql:'SELECT fn_importar_mapa_financeiro_xlsx(2030,$1,\'Sintético\') v',args:work=>[json([{tipo:'obra',obra_id:id(work),meses:[77,88]}])],missing:()=>[json([{tipo:'obra',obra_id:id(99999),meses:[77]}])],effect:r=>assert.equal(r.rows[0].v.importadas,1)},
  {name:'fn_guardar_planeamento_lote',sql:'SELECT fn_guardar_planeamento_lote($1,NULL) v',args:work=>[json({version:1,obra_id:id(work),changes:[],expected_items:[],expected_dependencies:[],dependencies:[],approved_cascade:[]})],missing:()=>[json({version:1,obra_id:id(99999)})],effect:r=>assert.ok(r.rows[0].v.confirmation_token)},
  {name:'fn_criar_obra_de_modelo',sql:"SELECT fn_criar_obra_de_modelo($1,'70099','Modelo sintético',NULL,NULL,NULL,NULL,$2,'planeamento',NULL,NULL,true) v",args:work=>[id(work),null],missing:()=>[id(99999),null],effect:r=>assert.equal(r.rows[0].v.obra.empresa_id,id(1))}
 ];
 async function prepare(work) {
  const company=work===200?2:1;
  for(const table of ['planeamento_custos_componentes','orcamento_fases','consultas_subempreitada','consultas_subempreitada_candidatos','consultas_subempreitada_itens','consultas_subempreitada_candidatos_itens','subempreitadas','subempreitada_aditamentos','avaliacoes_subempreiteiro','alteracoes_tee','alteracoes_tee_itens','alteracoes_tee_revisoes','tee_importacoes_revisoes','financeiro_estados_mensais','financeiro_estados_mensais_historico'])await q('ALTER TABLE public.'+table+' ALTER COLUMN id SET DEFAULT gen_random_uuid()');
  await q('CREATE UNIQUE INDEX final_component_no_item ON planeamento_custos_componentes(planeamento_item_id,tipo) WHERE item_orcamento_id IS NULL; CREATE UNIQUE INDEX final_component_item ON planeamento_custos_componentes(planeamento_item_id,tipo,item_orcamento_id) WHERE item_orcamento_id IS NOT NULL');
  await q('ALTER TABLE planeamento_lote_tokens ALTER COLUMN token SET DEFAULT gen_random_uuid(); ALTER TABLE planeamento_lote_tokens ALTER COLUMN expira_em SET DEFAULT now()+interval \'15 minutes\'');
  await q('ALTER TABLE obras ALTER COLUMN id SET DEFAULT gen_random_uuid()');
  await q('ALTER TABLE mapa_financeiro_ajustes ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX final_mapa_ajuste ON mapa_financeiro_ajustes(obra_id,ano,mes)');
  await q('CREATE UNIQUE INDEX final_orcamento_fase ON orcamento_fases(fase_id); CREATE UNIQUE INDEX final_tee_importacao ON tee_importacoes_revisoes(obra_id,payload_hash); CREATE UNIQUE INDEX final_month ON financeiro_estados_mensais(obra_id,mes); CREATE UNIQUE INDEX final_month_request ON financeiro_estados_mensais_historico(request_id)');
  await q("INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo) VALUES($1,$1,$2,'gestao_plataforma',false),($3,$3,NULL,'gestao_plataforma',true)",[id(70003),id(1),id(70004)]);
  await q('INSERT INTO fases(id,obra_id) VALUES($1,$2),($3,$4)',[id(70071),id(work),id(70072),id(work===200?120:200)]);
  await q('INSERT INTO fornecedores(id,empresa_id,nome) VALUES($1,$2,\'Fornecedor sintético A\'),($3,$4,\'Fornecedor sintético B\')',[id(70075),id(company),id(70076),id(company===1?2:1)]);
  await q("INSERT INTO subempreitadas(id,obra_id,fase_id,fornecedor_id,estado,valor_adjudicado) VALUES($1,$2,$3,$4,'em_execucao',55)",[id(70074),id(work),id(70071),id(70075)]);
  await q("INSERT INTO planeamento_itens(id,fase_id,descricao,estado,executado_por,subempreitada_id) VALUES($1,$2,'Sintético','em_execucao','subempreitada',$3)",[id(70073),id(70071),id(70074)]);
  await q('INSERT INTO itens_orcamento(id,fase_id,quantidade,descricao) VALUES($1,$2,2,\'Sintético\')',[id(70077),id(70071)]);
  await q("INSERT INTO consultas_subempreitada(id,obra_id,fase_id,trabalho,estado) VALUES($1,$2,$3,'Sintético','em_consulta')",[id(70078),id(work),id(70071)]);
  await q('INSERT INTO consultas_subempreitada_candidatos(id,consulta_subempreitada_id,fornecedor_id,valor_total) VALUES($1,$2,$3,55)',[id(70079),id(70078),id(70075)]);
  await q('INSERT INTO consultas_subempreitada_itens(id,consulta_subempreitada_id,item_orcamento_id) VALUES($1,$2,$3)',[id(70080),id(70078),id(70077)]);
  await q("INSERT INTO subempreitada_aditamentos(id,subempreitada_id,obra_id,valor,estado) VALUES($1,$2,$3,55,'pendente')",[id(70082),id(70074),id(work)]);
  await q("INSERT INTO alteracoes_tee(id,obra_id,fase_id,numero,descricao,valor,estado_aprovacao_cliente) VALUES($1,$2,$3,'SYN-OLD','Sintético',100,'aprovado'),($4,$5,$6,'SYN-OTHER','Sintético',100,'aprovado')",[id(70083),id(work),id(70071),id(70084),id(work===200?120:200),id(70072)]);
 }
 async function scenario(c,{work=120,actor=12,params,change,positive=false,code,internal=c.internal}={}) {
  await q('BEGIN');
  try {
   await prepare(work);if(change)await change();const before=await state();await q('SAVEPOINT operation');
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(actor)]);if(!internal)await q('SET LOCAL ROLE authenticated');
   if(positive){const result=await q(c.sql,params??c.args(work));await q('RESET ROLE');c.effect(result);assert.notDeepEqual(await state(),before,'expected legitimate write');}
   else {await assert.rejects(()=>q(c.sql,params??c.args(work)),e=>code?e.code===code:['42501','P0001','P0002','23514'].includes(e.code));await q('ROLLBACK TO SAVEPOINT operation');assert.deepEqual(await state(),before,'no partial effect');}
  }finally{await q('ROLLBACK');}
 }
 for(const c of cases)await t.test('final economic '+c.name+': legitimate, other tenant, inactive, wrong role, missing and atomicity',async()=>{
  await scenario(c,{positive:true});await scenario(c,{work:200,code:'42501'});await scenario(c,{actor:70003,code:'42501'});
  await scenario(c,{actor:70004,code:'42501'});await scenario(c,{actor:10,code:'42501'});await scenario(c,{params:c.missing()});
  if(c.internal)await scenario(c,{internal:false,code:'42501'});
 });
 const get=n=>cases.find(c=>c.name===n);
 await t.test('all importer mixed payloads refuse/rollback the complete call',async()=>{
  await scenario(get('fn_importar_orcamento_fases'),{params:[id(120),json([{fase_id:id(70071),custo_total_estimado:1},{fase_id:id(70072),custo_total_estimado:2}])]});
  await scenario(get('fn_importar_tees_xlsx'),{params:[json([tee(120),{...tee(200),numero:'SYN-FOREIGN'}])],code:'42501'});
  await scenario(get('fn_importar_tees_revisoes'),{params:[id(120),json([tee(120),tee(200)])],code:'42501'});
  await scenario(get('fn_importar_subempreitadas_xlsx'),{params:[json([sub(120),sub(200)])],code:'42501'});
  await scenario(get('fn_importar_mapa_financeiro_xlsx'),{params:[json([{tipo:'obra',obra_id:id(120),meses:[77]},{tipo:'obra',obra_id:id(200),meses:[88]}])],code:'42501'});
 });
 await t.test('general expenses are explicitly closed before any write, in either payload order',async()=>{
  const c=get('fn_importar_mapa_financeiro_xlsx');
  const work={tipo:'obra',obra_id:id(120),meses:[77]};
  for(const categoria of ['remuneracoes_sede','despesas_sede','despesas_armazem']){
   const expense={tipo:'despesa_fixa',categoria,meses:[88]};
   for(const lines of [[expense],[work,expense],[expense,work]])
    await scenario(c,{params:[json(lines)],code:'0A000'});
  }
  await q('BEGIN');
  try {
   await prepare(120);
   await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(12)]);
   await q('SET LOCAL ROLE authenticated');
   await assert.rejects(()=>q(c.sql,[json([{tipo:'despesa_fixa',categoria:'despesas_sede',meses:[88]}])]),e=>e.code==='0A000' && e.message.includes('DESPESAS_GERAIS_BLOQUEADAS'));
  } finally {await q('ROLLBACK');}
 });
 await t.test('related entities cannot cross the tenant or real work',async()=>{
  await scenario(get('fn_confirmar_compromisso_subempreitada'),{change:()=>q('UPDATE subempreitadas SET obra_id=$1 WHERE id=$2',[id(200),id(70074)]),code:'42501'});
  await scenario(get('fn_guardar_precos_candidato_subempreitada'),{change:()=>q('UPDATE consultas_subempreitada_candidatos SET fornecedor_id=$1 WHERE id=$2',[id(70076),id(70079)]),code:'42501'});
  await scenario(get('fn_guardar_precos_candidato_subempreitada'),{change:()=>q('UPDATE itens_orcamento SET fase_id=$1 WHERE id=$2',[id(70072),id(70077)]),code:'42501'});
  await scenario(get('fn_criar_consulta_subempreitada'),{params:[id(120),id(70072),[id(70077)]]});
  await scenario(get('fn_adjudicar_candidato_subempreitada'),{change:()=>q('UPDATE consultas_subempreitada SET fase_id=$1 WHERE id=$2',[id(70072),id(70078)]),code:'42501'});
  await scenario(get('fn_adjudicar_candidato_subempreitada'),{change:()=>q('UPDATE consultas_subempreitada_candidatos SET fornecedor_id=$1 WHERE id=$2',[id(70076),id(70079)]),code:'42501'});
  await scenario(get('fn_registar_aditamento_subempreitada'),{params:[id(70074),id(70084)],code:'42501'});
  await scenario(get('fn_decidir_aditamento_subempreitada'),{change:()=>q('UPDATE subempreitada_aditamentos SET subempreitada_id=$1 WHERE id=$2',[id(99999),id(70082)]),code:'42501'});
  await scenario(get('fn_importar_subempreitadas_xlsx'),{params:[json([{...sub(120),fornecedor_id:id(70076)}])],code:'42501'});
  await scenario(get('fn_criar_obra_de_modelo'),{params:[id(120),id(35)],code:'42501'});
 });
 await t.test('monthly replay validates the real historic resource before returning',async()=>{
  const c=get('fn_definir_estado_mensal_v1');
  await scenario(c,{change:()=>q("INSERT INTO financeiro_estados_mensais_historico(id,obra_id,mes,estado_novo,revisao_nova,request_id) VALUES(gen_random_uuid(),$1,'2030-01-01','aberto',gen_random_uuid(),'SYNTHETIC-MONTH')",[id(200)]),code:'42501'});
 });
 await t.test('all new bodies/config/ACL/contracts match the approved inventory',async()=>{
  for(const f of inventory.functions){
   const row=(await q("SELECT md5(replace(prosrc,chr(13),'')) hash,prosecdef,pg_get_userbyid(proowner) owner,proconfig,proacl::text acl,pg_get_functiondef(oid) definition FROM pg_proc WHERE oid=$1::regprocedure",[f.signature])).rows[0];
   assert.equal(row.hash,f.expected_body_md5);assert.equal(row.prosecdef,true);assert.equal(row.owner,'postgres');assert.deepEqual(row.proconfig,['search_path=pg_catalog, public, pg_temp']);
   assert.equal(row.definition.split(' LANGUAGE ')[0],f.original_definition.split(' LANGUAGE ')[0]);
   assert.deepEqual(row.acl.slice(1,-1).split(',').sort(),f.external?['authenticated=X/postgres','postgres=X/postgres']:['postgres=X/postgres']);
  }
  for(const name of ['fn_economico_ator_atual()','fn_atualizar_venda_contrato_via_tee(uuid)'])for(const role of ['anon','authenticated','service_role'])assert.equal((await q('SELECT has_function_privilege($1,$2,\'EXECUTE\') p',[role,name])).rows[0].p,false);
 });
}
