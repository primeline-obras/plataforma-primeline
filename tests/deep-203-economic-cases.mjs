import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const snapshot=JSON.parse(await readFile(new URL('./fixtures/encarregado-catalogo-real-20261004.json',import.meta.url),'utf8'));
const inventory=JSON.parse(await readFile(new URL('./fixtures/writers-economicos-final-inventario-20261004.json',import.meta.url),'utf8'));

export async function deepEconomicPairs({t,q}) {
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

 const fs=await import('node:fs'),proofs=[];
 const roles=[[12,'gestao_plataforma'],[13,'gerencia'],[11,'administrativo'],[17,'financeiro'],[14,'diretor_obra'],[15,'adjunto'],[16,'preparador'],[10,'encarregado']];
 const map=[['BUDGET_IMPORT','fn_importar_orcamento_fases',[12,13,14]],['PRICE_SAVE','fn_guardar_precos_candidato_subempreitada',[12,13,14,15,16]],['AWARD','fn_adjudicar_candidato_subempreitada',[12,13,14,15,16]],['PLAN_BATCH','fn_guardar_planeamento_lote',[12,13,14,15,16]]];
 try{for(const [action,name,allowed]of map)for(const[actor,profile]of roles)await t.test('203 '+action+' / '+profile,async()=>{
  await q('BEGIN');try{await prepare(120);const c=cases.find(x=>x.name===name);let args=c.args(120);
   if(action==='PLAN_BATCH'){await q('ALTER TABLE planeamento_fases_resumo ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX deep_phase_summary ON planeamento_fases_resumo(fase_id)');await q("UPDATE planeamento_itens SET estado='por_iniciar',custo_estado='orcamentado',peso_percentual=100,percentual_executado=0,codigo='DEEP-PLAN',executado_por='PL',subempreitada_id=NULL,valor_estimado=10,data_inicio_prevista='2030-01-01',data_fim_prevista='2030-01-02' WHERE id=$1",[id(70073)]);const items=(await q('SELECT to_jsonb(pi) v FROM planeamento_itens pi JOIN fases f ON f.id=pi.fase_id WHERE f.obra_id=$1 ORDER BY pi.id',[id(120)])).rows.map(x=>x.v);args=[json({version:1,obra_id:id(120),expected_items:items,expected_dependencies:[],changes:[{id:id(70073),valor_estimado:77}],dependencies:[],approved_cascade:[]})]}
   const before=await state();await q('SAVEPOINT operation');await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(actor)]);await q('SET LOCAL ROLE authenticated');let r,error;
   try{r=await q(c.sql,args);if(action==='PLAN_BATCH'){const preview=r.rows[0].v;if(preview.conflicts?.length)throw Object.assign(new Error(JSON.stringify(preview.conflicts)),{code:'FIXTURE_CONFLICT'});r=await q('SELECT fn_guardar_planeamento_lote($1,$2) v',[args[0],preview.confirmation_token]);assert.equal(r.rows[0].v.committed,true)}else c.effect(r);await q('RESET ROLE')}catch(e){error={code:e.code||'ASSERT',message:e.message};await q('ROLLBACK TO SAVEPOINT operation')}
   const after=await state(),unchanged=JSON.stringify(before)===JSON.stringify(after),expectedAllowed=allowed.includes(actor);const result=error&&!['42501'].includes(error.code)?'BLOQUEADO':expectedAllowed?(!error&&!unchanged?'PASS':'FAIL'):(!!error&&unchanged?'PASS':'FAIL');
   proofs.push({action,profile,expected:expectedAllowed?'PERMITIR':'RECUSAR',observed:error||r.rows[0],result,no_write_on_denial:expectedAllowed?null:unchanged,environment:'Catálogo capturado com funções e ACL reais; seed sintético e migration consolidada',limit:'DML da fixture não reconstrói todas as constraints; persistência verificada dentro da transação revertida'});assert.notEqual(result,'FAIL',JSON.stringify(proofs.at(-1)));
  }finally{await q('ROLLBACK')}
 })}finally{fs.writeFileSync('docs/auditorias/validacao-profunda-20261014/EVIDENCIAS-ECONOMICOS-PERFIS.json',JSON.stringify({synthetic_only:true,production_access:false,proofs},null,2)+'\n')}
}
