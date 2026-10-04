import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHmac} from 'node:crypto';
import {createServer} from 'node:net';
import {createRequire} from 'node:module';
import {join} from 'node:path';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
export async function financialCases({t,q,port,stage}) {
 const today=(await q('SELECT current_date::text d')).rows[0].d;
 const cases=[
  {name:'fn_marcar_fatura_paga',sig:'uuid,date',args:{p_fatura_id:id(880),p_data_pagamento:today},sql:'SELECT fn_marcar_fatura_paga($1,current_date)'},
  {name:'fn_desmarcar_fatura_paga',sig:'uuid',args:{p_fatura_id:id(880)},sql:'SELECT fn_desmarcar_fatura_paga($1)',paid:true},
  {name:'fn_devolver_fatura_financeiro',sig:'uuid,text',args:{p_fatura_id:id(880),p_observacao:'SYNTHETIC'},sql:"SELECT fn_devolver_fatura_financeiro($1,'SYNTHETIC')"},
  {name:'fn_avancar_estado_fluxo_fatura',sig:'uuid,text,date,text',args:{p_fatura_id:id(880),p_novo_estado:'paga',p_data_pagamento:today,p_observacao:null},sql:"SELECT fn_avancar_estado_fluxo_fatura($1,'paga',current_date,NULL)"},
  {name:'fn_marcar_faturacao_auto_paga',sig:'uuid,date,numeric',billing:true,args:{p_faturacao_id:id(880),p_data_pagamento:today,p_valor_pago:543},sql:'SELECT fn_marcar_faturacao_auto_paga($1,current_date,543)'},
  {name:'fn_registar_recebimento_parcial',sig:'integer,uuid,date,numeric,text,numeric',billing:true,partial:true,args:{p_version:1,p_faturacao_id:id(880),p_data:today,p_valor:10,p_request_id:'SYNTHETIC_FINANCIAL',p_valor_recebido_esperado:0},sql:"SELECT fn_registar_recebimento_parcial(1,$1,current_date,10,'SYNTHETIC_FINANCIAL',0)"}
 ];
 if(stage==='before') {
  await q("INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo) VALUES($1,$1,$2,'financeiro',true),($3,$3,$4,'financeiro',false)",[id(22),id(2),id(23),id(1)]);
  // Receipts use the captured unique request contract and UUID generation.
  await q('ALTER TABLE faturacao_recebimentos ALTER COLUMN id SET DEFAULT gen_random_uuid(); CREATE UNIQUE INDEX synthetic_receipt_request ON faturacao_recebimentos(request_id)');
  await q("INSERT INTO fornecedores(id,empresa_id,nome) VALUES($1,$2,'SYNTHETIC_OTHER_COMPANY')",[id(890),id(2)]);
 }
 const clean=async()=>{
  await q('DELETE FROM faturacao_recebimentos WHERE faturacao_id=$1',[id(880)]);
  await q('DELETE FROM faturas WHERE id=$1',[id(880)]);
  await q('DELETE FROM faturacao WHERE id=$1',[id(880)]);
  await q('DELETE FROM faturas_eventos WHERE fatura_id=$1',[id(880)]);
  await q('DELETE FROM alertas WHERE entidade_id=$1',[id(880)]);
  await q('DELETE FROM log_auditoria WHERE registo_id=$1',[id(880)]);
 };
 const prepare=async(c,work)=>{
  await clean();
  if(c.billing)await q("INSERT INTO faturacao(id,obra_id,valor,estado,estado_aprovacao,estado_pagamento,valor_recebido) VALUES($1,$2,543,'emitida','aprovado','por_pagar',0)",[id(880),id(work)]);
  else await q("INSERT INTO faturas(id,obra_id,valor,tipo_origem,estado_aprovacao,estado_pagamento,estado_fluxo) VALUES($1,$2,543,'material','aprovado',$3,$4)",[id(880),id(work),c.paid?'pago':'por_pagar',c.paid?'paga':'enviada_financeiro']);
 };
 const state=async()=> (await q("SELECT jsonb_build_object('faturas',(SELECT jsonb_agg(to_jsonb(x)) FROM faturas x),'faturacao',(SELECT jsonb_agg(to_jsonb(x)) FROM faturacao x),'receipts',(SELECT jsonb_agg(to_jsonb(x)) FROM faturacao_recebimentos x),'events',(SELECT jsonb_agg(to_jsonb(x)) FROM faturas_eventos x),'alerts',(SELECT jsonb_agg(to_jsonb(x)) FROM alertas x),'audit',(SELECT jsonb_agg(to_jsonb(x)) FROM log_auditoria x)) s")).rows[0].s;
 const effect=async c=>{
  const r=(await q('SELECT * FROM '+(c.billing?'faturacao':'faturas')+' WHERE id=$1',[id(880)])).rows[0];
  if(c.billing)assert.equal(Number(r.valor_recebido),c.partial?10:543);
  else if(c.name.includes('desmarcar'))assert.equal(r.estado_pagamento,'por_pagar');
  else if(c.name.includes('devolver'))assert.equal(r.estado_aprovacao,'pendente');
  else assert.equal(r.estado_pagamento,'pago');
 };
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const hp=socket.address().port;await new Promise(r=>socket.close(r));
 const secret='synthetic-only-financial-authorization-20261004';
 const jwt=n=>{const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const data=enc({alg:'HS256',typ:'JWT'})+'.'+enc({role:'authenticated',sub:id(n),exp:Math.floor(Date.now()/1000)+900});return data+'.'+createHmac('sha256',secret).update(data).digest('base64url');};
 const child=spawn(process.env.QUADRO_POSTGREST,[],{windowsHide:true,stdio:'ignore',env:{...process.env,PGRST_DB_URI:`postgresql://postgres@127.0.0.1:${port}/postgres`,PGRST_DB_SCHEMAS:'public',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:secret,PGRST_SERVER_HOST:'127.0.0.1',PGRST_SERVER_PORT:String(hp)}});
 const request=(path,body,n)=>fetch('http://127.0.0.1:'+hp+'/'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(n==null?{}:{Authorization:'Bearer '+jwt(n)})},...(body?{body:JSON.stringify(body)}:{})});
 try {
  let ready=false;for(let i=0;i<100;i++){try{if((await request('')).ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}assert.ok(ready,'PostgREST local');
  for(const c of cases) {
   if(stage==='before')await t.test('BASELINE cross-company HTTP: '+c.name,async()=>{await prepare(c,200);const r=await request('rpc/'+c.name,c.args,17);assert.equal(r.status,200,await r.text());await effect(c);await clean();});
   else {
    await t.test('CANDIDATE HTTP own-company + denial + atomicity: '+c.name,async()=>{
     for(const actor of [17,12,13]){await prepare(c,120);const r=await request('rpc/'+c.name,c.args,actor);assert.equal(r.status,200,await r.text());await effect(c);}
     for(const [actor,work,target] of [[17,200,880],[22,120,880],[23,120,880],[20,120,880],[10,120,880],[11,120,880],[999,120,880],[null,120,880],[17,120,9999]]){
      await prepare(c,work);const before=await state();const args={...c.args,...(c.billing?{p_faturacao_id:id(target)}:{p_fatura_id:id(target)})};
      const r=await request('rpc/'+c.name,args,actor);assert.ok([401,403,404].includes(r.status),c.name+' actor '+actor+': '+r.status+' '+await r.text());assert.deepEqual(await state(),before,'no partial writes');
     }
     // SQL has exactly the same resource authorization.
     await prepare(c,200);await q('BEGIN');try{await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(17)]);await q('SET LOCAL ROLE authenticated');await assert.rejects(()=>q(c.sql,[id(880)]),/FORBIDDEN/);}finally{await q('ROLLBACK');}
     const privileges=(await q("SELECT has_function_privilege('anon',$1,'EXECUTE') a,has_function_privilege('authenticated',$1,'EXECUTE') u,has_function_privilege('service_role',$1,'EXECUTE') s",[c.name+'('+c.sig+')'])).rows[0];assert.deepEqual(privileges,{a:false,u:true,s:false});
     await clean();
    });
   }
  }
  await t.test(stage+' alerts: recipient, role and residual responsibility',async()=>{
   await q("INSERT INTO obra_responsaveis(id,obra_id,utilizador_id,papel) VALUES($1,$2,$3,'encarregado')",[id(889),id(120),id(20)]);
   for(const [n,type,entity,work,role] of [[884,'movimentacao_equipa','quadro',null,null],[885,'seguro_viatura','viaturas',null,null],[886,'compromisso_agenda','agenda',null,null],[887,'teste','obra',120,'encarregado']])await q("INSERT INTO alertas(id,empresa_id,tipo,entidade_tipo,obra_id,destinatario_utilizador_id,destinatario_role,expira_em,estado) VALUES($1,$2,$3,$4,$5,$6,$7,now()+interval '1 day','pendente')",[id(n),id(1),type,entity,work?id(work):null,id(20),role]);
   try {
    const r=await request('alertas?select=id&or=(id.eq.'+id(884)+',id.eq.'+id(885)+',id.eq.'+id(886)+',id.eq.'+id(887)+')',null,20);assert.equal(r.status,200);const rows=await r.json();assert.equal(rows.length,stage==='before'?3:0);
    const active=await request('alertas?select=id',null,10);assert.equal(active.status,200);assert.ok((await active.json()).length>0);
   } finally {await q('DELETE FROM obra_responsaveis WHERE id=$1',[id(889)]);await q('DELETE FROM alertas WHERE id=ANY($1::uuid[])',[[884,885,886,887].map(id)]);}
  });
  if(stage==='after') {
   await t.test('partial receipt replay is authorized before returning billing',async()=>{
    const c=cases[5];await prepare(c,120);assert.equal((await request('rpc/'+c.name,c.args,17)).status,200);assert.equal((await request('rpc/'+c.name,c.args,17)).status,200);assert.equal((await q('SELECT count(*)::int n FROM faturacao_recebimentos WHERE faturacao_id=$1',[id(880)])).rows[0].n,1);
    assert.equal((await request('rpc/'+c.name,c.args,22)).status,403);await clean();
   });
   await t.test('PUBLIC does not execute financial RPCs; private helper is owner-only',async()=>{
    await q('BEGIN; CREATE ROLE financial_public_only');try{for(const c of cases)assert.equal((await q("SELECT has_function_privilege('financial_public_only',$1,'EXECUTE') v",[c.name+'('+c.sig+')'])).rows[0].v,false);for(const role of ['anon','authenticated','service_role'])assert.equal((await q('SELECT has_function_privilege($1,$2,\'EXECUTE\') v',[role,'fn_financeiro_autorizar_obra(uuid,boolean)'])).rows[0].v,false);}finally{await q('ROLLBACK');}
   });
   await t.test('partial receipt concurrency and simultaneous replay',async()=>{
    const c=cases[5];await prepare(c,120);
    const results=await Promise.all(['RACE_A','RACE_B'].map(p_request_id=>request('rpc/'+c.name,{...c.args,p_request_id},17)));
    assert.deepEqual(results.map(r=>r.status).sort(),[200,400]);assert.equal(Number((await q('SELECT valor_recebido v FROM faturacao WHERE id=$1',[id(880)])).rows[0].v),10);
    await prepare(c,120);const replay=await Promise.all([request('rpc/'+c.name,c.args,17),request('rpc/'+c.name,c.args,17)]);assert.ok(replay.every(r=>r.status===200));assert.equal((await q('SELECT count(*)::int n FROM faturacao_recebimentos WHERE faturacao_id=$1',[id(880)])).rows[0].n,1);await clean();
   });
   await t.test('authorization holds actor and work locks until transaction ends',async()=>{
    const require=createRequire(import.meta.url);const {Client}=require(join(process.env.QUADRO_TEST_DEPS,'pg'));const other=new Client({host:'127.0.0.1',port,user:'postgres',database:'postgres',password:'',ssl:false});await other.connect();
    await prepare(cases[0],120);await q('BEGIN');try{
     await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(17)]);await q('SET LOCAL ROLE authenticated');await q(cases[0].sql,[id(880)]);await q('RESET ROLE');
     await other.query("SET lock_timeout='150ms'");
     for(const sql of ["UPDATE utilizadores SET ativo=false WHERE id=$1","UPDATE utilizadores SET empresa_id='00000000-0000-4000-8000-000000000002' WHERE id=$1"]){await assert.rejects(()=>other.query(sql,[id(17)]),e=>e.code==='55P03');}
     await assert.rejects(()=>other.query('UPDATE obras SET empresa_id=$2 WHERE id=$1',[id(120),id(2)]),e=>e.code==='55P03');
    }finally{await q('ROLLBACK');await other.end();await clean();}
   });
  }
  await t.test(stage+' alternate REST financial writer: cross-company DELETE',async()=>{
   const c=cases[0];await prepare(c,200);const before=await state();
   const response=await fetch('http://127.0.0.1:'+hp+'/faturas?id=eq.'+id(880),{method:'DELETE',headers:{'Content-Type':'application/json',Authorization:'Bearer '+jwt(13),Prefer:'return=representation'}});
   assert.equal(response.status,200);const rows=await response.json();
   if(stage==='before'){assert.equal(rows.length,1);assert.equal(rows[0].id,id(880));}else{assert.equal(rows.length,0);assert.deepEqual(await state(),before);}
   await clean();
  });
  const wrappers=[
   {name:'fn_decidir_fatura',args:{p_fatura_id:id(880),p_decisao:'aprovado',p_observacao:null},setup:"UPDATE faturas SET estado_aprovacao='pendente',estado_fluxo='em_validacao' WHERE id=$1"},
   {name:'fn_decidir_faturacao_auto',args:{p_faturacao_id:id(880),p_decisao:'aprovado'},billing:true,setup:"UPDATE faturacao SET estado_aprovacao='pendente' WHERE id=$1"},
   {name:'fn_devolver_fatura_administrativo',args:{p_fatura_id:id(880),p_observacao:'SYNTHETIC'},setup:"UPDATE faturas SET estado_aprovacao='pendente',estado_fluxo='em_validacao' WHERE id=$1"},
   {name:'fn_vincular_fatura_subempreitada',args:{p_fatura_id:id(880),p_subempreitada_id:null},setup:"UPDATE faturas SET tipo_origem='subempreitada',estado_aprovacao='pendente',estado_fluxo='em_validacao' WHERE id=$1"}
  ];
  for(const w of wrappers)await t.test(stage+' alternate wrapper: '+w.name,async()=>{
   await prepare(w,200);await q(w.setup,[id(880)]);const before=await state();const r=await request('rpc/'+w.name,w.args,13);
   assert.equal(r.status,stage==='before'?200:403,await r.text());if(stage==='after')assert.deepEqual(await state(),before);
   if(stage==='after'){await prepare(w,120);await q(w.setup,[id(880)]);const positive=await request('rpc/'+w.name,w.args,14);assert.equal(positive.status,200,await positive.text());}
   await clean();
  });
  for(const withObservation of [false,true])await t.test(stage+' pending invoice overload '+withObservation,async()=>{
   const c=cases[0];await prepare(c,200);await q("UPDATE faturas SET estado_aprovacao='pendente',estado_fluxo='recebida',criado_por=$2 WHERE id=$1",[id(880),id(13)]);
   const payload={p_fatura_id:id(880),p_obra_id:id(200),p_tipo_origem:'estaleiro',p_fornecedor_id:id(890),p_subempreitada_id:null,p_numero_doc:'SYNTHETIC',p_data_fatura:today,p_valor:543,p_condicao_pagamento:'imediato',p_data_vencimento:null,p_itens:[],...(withObservation?{p_observacao:'SYNTHETIC'}:{})};
   const before=await state();const negative=await request('rpc/fn_editar_fatura_pendente',payload,13);assert.equal(negative.status,stage==='before'?200:403,await negative.text());if(stage==='after')assert.deepEqual(await state(),before);
   if(stage==='after'){
    await prepare(c,120);await q("UPDATE faturas SET estado_aprovacao='pendente',estado_fluxo='recebida',criado_por=$2 WHERE id=$1",[id(880),id(11)]);
    const own={...payload,p_obra_id:id(120),p_fornecedor_id:id(500)};const positive=await request('rpc/fn_editar_fatura_pendente',own,11);assert.equal(positive.status,200,await positive.text());
    const move=await request('rpc/fn_editar_fatura_pendente',payload,11);assert.equal(move.status,403);const badSupplier=await request('rpc/fn_editar_fatura_pendente',{...own,p_fornecedor_id:id(890)},11);assert.equal(badSupplier.status,403);
   }
   await clean();
  });
  for(const kind of ['guia','anexo'])await t.test(stage+' attachment deletion: '+kind,async()=>{
   const table=kind==='guia'?'faturas_guias':'faturas_anexos';const c=cases[0];await prepare(c,200);await q('INSERT INTO '+table+'(id,fatura_id,arquivo_url) VALUES($1,$2,\'SYNTHETIC\')',[id(891),id(880)]);
   try{const negative=await request('rpc/fn_apagar_'+kind+'_fatura',{['p_'+kind+'_id']:id(891)},17);assert.equal(negative.status,stage==='before'?200:403,await negative.text());if(stage==='after'){assert.equal((await q('SELECT count(*)::int n FROM '+table+' WHERE id=$1',[id(891)])).rows[0].n,1);await q('UPDATE faturas SET obra_id=$2 WHERE id=$1',[id(880),id(120)]);const positive=await request('rpc/fn_apagar_'+kind+'_fatura',{['p_'+kind+'_id']:id(891)},17);assert.equal(positive.status,200,await positive.text());}}finally{await q('DELETE FROM '+table+' WHERE id=$1',[id(891)]);await clean();}
  });
  for(const item of [false,true])await t.test(stage+' comparative deletion '+item,async()=>{
   await q('INSERT INTO mapas_comparativos(id,obra_id) VALUES($1,$2)',[id(892),id(200)]);if(item)await q('INSERT INTO comparativo_itens(id,mapa_id) VALUES($1,$2)',[id(893),id(892)]);
   try{const path='rpc/'+(item?'fn_eliminar_item_comparativo':'fn_eliminar_mapa_comparativo');const payload=item?{p_item_id:id(893)}:{p_mapa_id:id(892)};const negative=await request(path,payload,13);assert.equal(negative.status,stage==='before'?200:403,await negative.text());if(stage==='after'){await q('UPDATE mapas_comparativos SET obra_id=$2 WHERE id=$1',[id(892),id(120)]);const positive=await request(path,payload,14);assert.equal(positive.status,200,await positive.text());}}finally{await q('DELETE FROM comparativo_itens WHERE id=$1',[id(893)]);await q('DELETE FROM mapas_comparativos WHERE id=$1',[id(892)]);await q('DELETE FROM log_auditoria WHERE registo_id=ANY($1::uuid[])',[[id(892),id(893)]]);}
  });
  if(stage==='after')await t.test('all 24 restrictive financial policies: own/foreign expressions',async()=>{
   const policies=(await q("SELECT c.relname tab,p.polcmd cmd,pg_get_expr(p.polqual,p.polrelid) qual,pg_get_expr(p.polwithcheck,p.polrelid) chk FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid WHERE p.polname LIKE 'financeiro_empresa_%' ORDER BY c.relname,p.polname")).rows;assert.equal(policies.length,24);
   await prepare(cases[0],120);
   await q('BEGIN');try{
    await q('INSERT INTO mapas_comparativos(id,obra_id) VALUES($1,$2)',[id(895),id(120)]);await q('INSERT INTO comparativo_itens(id,mapa_id) VALUES($1,$2)',[id(896),id(895)]);
    await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(13)]);
    for(const p of policies){
     const row=p.tab==='faturas'||p.tab==='faturacao'?{obra_id:id(120)}:p.tab.startsWith('faturas_')?{fatura_id:id(880)}:p.tab==='mapas_comparativos'?{obra_id:id(120)}:p.tab==='comparativo_itens_precos'?{item_id:id(896)}:{mapa_id:id(895)};
     for(const expression of [p.qual,p.chk].filter(Boolean)){
      const sql='SELECT '+expression+' ok FROM jsonb_populate_record(NULL::public.'+p.tab+',$1::jsonb) AS '+p.tab;
      assert.equal((await q(sql,[JSON.stringify(row)])).rows[0].ok,true,p.tab+' own');
      await q('UPDATE obras SET empresa_id=$2 WHERE id=$1',[id(120),id(2)]);
      assert.equal((await q(sql,[JSON.stringify(row)])).rows[0].ok,false,p.tab+' foreign');
      await q('UPDATE obras SET empresa_id=$2 WHERE id=$1',[id(120),id(1)]);
     }
    }
   }finally{await q('ROLLBACK');await clean();}
  });
  if(stage==='after')await t.test('technical forecasting trigger, comparative wrapper and freeze job preserved',async()=>{
   await q('BEGIN');try{
    await q('CREATE TRIGGER synthetic_monthly AFTER UPDATE ON subempreitadas FOR EACH ROW EXECUTE FUNCTION fn_sincronizar_subempreitada_previsao()');
    await q("UPDATE subempreitadas SET estado='adjudicado',data_inicio_prevista=current_date,data_fim_prevista=current_date+2 WHERE id=$1",[id(43)]);
    assert.equal(Number((await q('SELECT saidas_previstas_sem_iva v FROM previsao_financeira_mensal WHERE id=$1',[id(700)])).rows[0].v),1009);
    await q('CREATE TRIGGER synthetic_comparative AFTER INSERT ON comparativo_itens_precos FOR EACH ROW EXECUTE FUNCTION fn_recalcular_mapa_apos_preco()');
    await q('INSERT INTO mapas_comparativos(id,obra_id) VALUES($1,$2)',[id(897),id(120)]);await q('INSERT INTO comparativo_itens(id,mapa_id) VALUES($1,$2)',[id(898),id(897)]);await q("INSERT INTO comparativo_itens_precos(id,item_id,preco_total,comparavel,estado_ambito) VALUES($1,$2,37,true,'incluido')",[id(899),id(898)]);
    assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(897)])).rows[0].v),37);
    await q('DELETE FROM comparativo_itens_precos WHERE id=$1',[id(899)]);await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(14)]);await q('SET LOCAL ROLE authenticated');await q('SELECT fn_eliminar_item_comparativo($1)',[id(898)]);await q('RESET ROLE');
    assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(897)])).rows[0].v),0);
    await q('SELECT fn_verificar_congelamentos_pendentes()');assert.equal((await q('SELECT count(*)::int n FROM obras WHERE planeamento_baseline_congelado')).rows[0].n,4);
   }finally{await q('ROLLBACK');}
  });
 } finally {await clean();child.kill();await new Promise(r=>setTimeout(r,150));}
}
