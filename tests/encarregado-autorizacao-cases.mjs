import assert from 'node:assert/strict';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
export const internalWriters=['fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()'];
export async function authorizationCases({t,q,asRole,stage}) {
 const callAs=async(role,sql,params=[])=>{await q('BEGIN');try{await q('SET LOCAL ROLE '+role);return await q(sql,params);}finally{await q('ROLLBACK');}};
 if(stage==='before') {
  await q("INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo) VALUES($1,$1,$3,'encarregado',true),($2,$2,$3,'encarregado',false)",[id(19),id(20),id(1)]);
  await q("INSERT INTO previsao_financeira_mensal(id,obra_id,mes,tipo,fechado,saidas_previstas_sem_iva,saidas_previstas_com_iva) VALUES($1,$2,current_date,'previsao',false,10,10)",[id(700),id(200)]);
  // Month normalization is part of the actual function contract.
  await q("UPDATE previsao_financeira_mensal SET mes=date_trunc('month',current_date)");
  await q('INSERT INTO mapas_comparativos(id,obra_id,melhor_preco_comparativo) VALUES($1,$2,999)',[id(701),id(200)]);
  await q("UPDATE obras SET planeamento_baseline_congelado=false,data_inicio=current_date-60");
  await q("INSERT INTO fornecedores(id,empresa_id,nome,nif,condicoes) VALUES($1,$2,'Fornecedor sintético','SYNTHETIC','SECRET')",[id(500),id(1)]);
  await q("INSERT INTO faturas(id,obra_id,fornecedor_id,valor,numero_doc,estado_pagamento) VALUES($1,$2,$3,999,'SYNTHETIC','pendente')",[id(702),id(118),id(500)]);
  await q('INSERT INTO lancamentos_materiais(id,obra_id,valor_total) VALUES($1,$2,456)',[id(703),id(200)]);
  await q("INSERT INTO faturas_itens(id,fatura_id,designacao,valor_total) VALUES($1,$2,'SYNTHETIC',999)",[id(704),id(702)]);
  for(const work of [120,118,200]){
   await q('INSERT INTO contratos(id,obra_id,venda_contratual_inicial) VALUES(gen_random_uuid(),$1,12345)',[id(work)]);
   await q('INSERT INTO consultas_subempreitada(id,obra_id,custo_direto,preco_venda) VALUES(gen_random_uuid(),$1,123,456)',[id(work)]);
   await q("INSERT INTO documentos_obra(id,obra_id,tipo,nome_arquivo) VALUES(gen_random_uuid(),$1,'desenho','SYNTHETIC')",[id(work)]);
   await q("INSERT INTO rnc(id,obra_id,descricao) VALUES(gen_random_uuid(),$1,'SYNTHETIC')",[id(work)]);
  }
  await q("INSERT INTO documentos_obra(id,obra_id,tipo,nome_arquivo) VALUES(gen_random_uuid(),$1,'financeiro','PRIVATE_SYNTHETIC')",[id(120)]);
  await q("INSERT INTO documentos(id,empresa_id,entidade_tipo,entidade_id,tipo_documento) VALUES(gen_random_uuid(),$1,'colaborador',$2,'contrato')",[id(1),id(30)]);
  for(const recipient of [10,18])await q("INSERT INTO alertas(id,empresa_id,tipo,entidade_tipo,entidade_id,destinatario_utilizador_id,estado) VALUES(gen_random_uuid(),$1,'movimentacao_equipa','colaborador',$2,$3,'pendente')",[id(recipient===10?1:2),id(30),id(recipient)]);
  for(const person of [30,31,35])await q("INSERT INTO ausencias(id,colaborador_id,data,tipo,estado,comentario) VALUES(gen_random_uuid(),$1,current_date,'ferias','aprovada','PRIVATE_SYNTHETIC')",[id(person)]);
  await t.test('P0 real reproduzido: anon altera previsão financeira de outra empresa',async()=>{
   await q('BEGIN');try{await q('SET LOCAL ROLE anon');await q('SELECT fn_ajustar_saida_prevista_mensal($1,current_date,500)',[id(200)]);await q('RESET ROLE');assert.equal(Number((await q('SELECT saidas_previstas_sem_iva v FROM previsao_financeira_mensal WHERE id=$1',[id(700)])).rows[0].v),510);}finally{await q('ROLLBACK');}
  });
  await t.test('P0 real reproduzido: anon altera comparativo e congela obra alheia',async()=>{
   await q('BEGIN');try{await q('SET LOCAL ROLE anon');await q('SELECT fn_atualizar_melhor_preco_comparativo($1)',[id(701)]);await q('SELECT fn_congelar_planeamento_baseline($1)',[id(200)]);await q('RESET ROLE');assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(701)])).rows[0].v),0);assert.equal((await q('SELECT planeamento_baseline_congelado v FROM obras WHERE id=$1',[id(200)])).rows[0].v,true);}finally{await q('ROLLBACK');}
  });
  await t.test('P0 transitivo reproduzido: anon aciona congelamento global',async()=>{
   await q('BEGIN');try{await q('SET LOCAL ROLE anon');await q('SELECT fn_verificar_congelamentos_pendentes()');await q('RESET ROLE');assert.equal((await q('SELECT count(*)::int n FROM obras WHERE planeamento_baseline_congelado')).rows[0].n,4);}finally{await q('ROLLBACK');}
  });
  await t.test('P1: férias globais, fornecedores e pesquisa financeira com UUID conhecido',async()=>{
   assert.equal((await asRole(10,'SELECT * FROM ausencias')).rowCount,3);
   assert.equal((await asRole(10,'SELECT nif,condicoes FROM fornecedores')).rowCount,1);
   assert.equal((await asRole(10,'SELECT * FROM fn_verificar_fatura_semelhante($1,999,\'SYNTHETIC\',NULL)',[id(500)])).rowCount,1);
   assert.ok((await asRole(10,'SELECT * FROM quadro_pessoal_alocacao')).rowCount>1);
   assert.equal(Number((await asRole(10,'SELECT fn_custo_real_ligado($1) v',[id(200)])).rows[0].v),456);
  });
  await t.test('P1: RPC antiga aceita preview de pessoa noutra obra',async()=>{
   const r=(await asRole(10,"SELECT fn_quadro_operar('minha_obra',jsonb_build_object('colaborador_id',$1::uuid,'obra_id',$2::uuid,'data',current_date,'periodo','dia_inteiro'),false,NULL) v",[id(32),id(120)])).rows[0].v;
   assert.equal(r.estado,'PREVISUALIZACAO');assert.equal(r.obra_origem_id,id(122));assert.equal(r.obra_destino_id,id(120));
  });
  return;
 }
 await t.test('writers internos: anon/auth sem EXECUTE; owner e serviço preservados',async()=>{
  for(const signature of internalWriters) {
   const r=(await q("SELECT has_function_privilege('anon',$1,'EXECUTE') a,has_function_privilege('authenticated',$1,'EXECUTE') u,has_function_privilege('service_role',$1,'EXECUTE') s,has_function_privilege('postgres',$1,'EXECUTE') p",[signature])).rows[0];assert.deepEqual(r,{a:false,u:false,s:true,p:true});
  }
  await assert.rejects(()=>callAs('anon','SELECT fn_ajustar_saida_prevista_mensal($1,current_date,500)',[id(200)]),/permission denied/);
  for(const n of [10,11,12,13,14,15,16,18,19,20,21])await assert.rejects(()=>asRole(n,'SELECT fn_ajustar_saida_prevista_mensal($1,current_date,500)',[id(200)]),/permission denied/);
  await q('BEGIN');try{await q('SELECT fn_ajustar_saida_prevista_mensal($1,current_date,1)',[id(200)]);assert.equal(Number((await q('SELECT saidas_previstas_sem_iva v FROM previsao_financeira_mensal WHERE id=$1',[id(700)])).rows[0].v),11);}finally{await q('ROLLBACK');}
 });
 await t.test('Enc: alocações/férias/fornecedores/avaliações não têm bypass direto',async()=>{
  for(const table of ['quadro_pessoal_alocacao','ausencias','fornecedores','fornecedores_aliases','fornecedores_mesclagens','avaliacoes_subempreiteiro','faturas','faturas_itens','pagamentos_subempreitada','contratos'])assert.equal((await asRole(10,'SELECT * FROM '+table)).rowCount,0,table);
  assert.equal((await asRole(10,"UPDATE quadro_pessoal_alocacao SET periodo='tarde' WHERE id=$1 RETURNING id",[id(1030)])).rowCount,0);
  assert.equal((await asRole(10,'DELETE FROM quadro_pessoal_alocacao WHERE id=$1 RETURNING id',[id(1030)])).rowCount,0);
  await assert.rejects(()=>asRole(10,"INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,periodo,criado_por) VALUES(gen_random_uuid(),$1,$2,current_date,'dia_inteiro',$3)",[id(30),id(120),id(10)]),/row-level security/);
  await assert.rejects(()=>asRole(10,"SELECT fn_quadro_operar('minha_obra','{}',false,NULL)"),/USE_QUADRO_V1/);
 });
 await t.test('ausências: projeção mínima da equipa; outra empresa/sem responsabilidade/inativo',async()=>{
  const rows=(await asRole(10,'SELECT * FROM fn_ausencias_equipa_encarregado(current_date,current_date)')).rows;
  assert.equal(rows.length,1);assert.equal(rows[0].colaborador_id,id(30));assert.deepEqual(Object.keys(rows[0]),['id','colaborador_id','data','tipo','estado']);
  assert.equal((await asRole(18,'SELECT * FROM fn_ausencias_equipa_encarregado(current_date,current_date)')).rows[0].colaborador_id,id(35));
  for(const n of [19,20,21,999])await assert.rejects(()=>asRole(n,'SELECT * FROM fn_ausencias_equipa_encarregado(current_date,current_date)'),/PERMISSION_DENIED/);
 });
 await t.test('pesquisa faturas: Enc nega UUID conhecido; técnico só obra própria; RH conserva',async()=>{
  for(const n of [10,18,19,20,21,999])for(const extra of ['',',$2'])await assert.rejects(()=>asRole(n,'SELECT * FROM fn_verificar_fatura_semelhante($1,999,\'SYNTHETIC\',NULL'+extra+')',extra?[id(500),null]:[id(500)]),/PERMISSION_DENIED/);
  for(const n of [14,15,16])assert.equal((await asRole(n,'SELECT * FROM fn_verificar_fatura_semelhante($1,999,\'SYNTHETIC\',NULL)',[id(500)])).rowCount,0);
  for(const n of [11,12,13,17])assert.equal((await asRole(n,'SELECT * FROM fn_verificar_fatura_semelhante($1,999,\'SYNTHETIC\',NULL)',[id(500)])).rowCount,1);
 });
 await t.test('financeiro: custo agregado, views, pagamentos e alterações recusados com IDs conhecidos',async()=>{
  for(const n of [10,18,19,20,21,999])await assert.rejects(()=>asRole(n,'SELECT fn_custo_real_ligado($1)',[id(200)]),/PERMISSION_DENIED/);
  for(const sql of ["SELECT fn_marcar_fatura_paga($1,current_date)","SELECT fn_decidir_fatura($1,'aprovado','teste')","SELECT fn_avancar_estado_fluxo_fatura($1,'paga',current_date,'teste')"])await assert.rejects(()=>asRole(10,sql,[id(702)]),/reservad|permiss|acesso|autoriza|Só o Financeiro/i);
  assert.deepEqual((await asRole(10,'SELECT * FROM fn_listar_rastreio_faturas()')).rows,[]);
  await assert.rejects(()=>asRole(10,'SELECT fn_mapa_gestao_obras()'),/acesso/i);
  for(const view of ['vw_previsao_mensal','vw_tees_resumo'])await assert.rejects(()=>asRole(10,'SELECT * FROM '+view),/permission denied/);
 });
 await t.test('matriz: obras/documentos/RNC autorizados; RH/consultas económicas negados',async()=>{
  for(const n of [10,18]){
   const work=id(n===10?120:200);
   assert.deepEqual((await asRole(n,'SELECT id FROM obras')).rows.map(r=>r.id),[work]);
   for(const table of ['documentos_obra','rnc']){const rows=(await asRole(n,'SELECT * FROM '+table)).rows;assert.equal(rows.length,1);assert.equal(rows[0].obra_id,work);}
   for(const table of ['documentos','consultas_subempreitada','contratos','faturas_itens'])assert.equal((await asRole(n,'SELECT * FROM '+table)).rowCount,0,table);
   const alerts=(await asRole(n,'SELECT * FROM alertas')).rows;assert.equal(alerts.length,1);assert.equal(alerts[0].destinatario_utilizador_id,id(n));
  }
  for(const n of [19,20,21,999]){
   for(const table of ['obras','colaboradores','subempreitadas','ausencias','fornecedores','quadro_pessoal_alocacao'])assert.equal((await asRole(n,'SELECT * FROM '+table)).rowCount,0,'actor '+n+' '+table);
  }
 });
}
