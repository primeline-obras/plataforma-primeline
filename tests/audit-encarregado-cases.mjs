// Independent adversarial checks. FINDING means a reproduced defect, not acceptance.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHmac} from 'node:crypto';
import {createServer} from 'node:net';
import {writeFile} from 'node:fs/promises';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const inventories={};
export async function independentAudit({t,q,asRole,port,stage}) {
 const functions=(await q("SELECT p.oid::regprocedure::text signature,p.proname name,p.prosecdef security_definer,pg_get_userbyid(p.proowner) owner,p.proconfig search_path,p.proacl::text raw_acl,pg_get_function_result(p.oid) result,pg_get_functiondef(p.oid) definition,has_function_privilege('anon',p.oid,'EXECUTE') anon,has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated,has_function_privilege('service_role',p.oid,'EXECUTE') service_role FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' ORDER BY p.oid::regprocedure::text")).rows;
 for(const f of functions){const body=f.definition.slice(f.definition.indexOf('AS $')).replace(/--[^\n]*/g,'');f.calls=[...new Set(body.match(/fn_\w+(?=\s*\()/g)||[])];f.direct_writer=/\b(insert\s+into|update\s+[\w."%]+(?:\s+\w+)?\s+set|delete\s+from|truncate\s)/i.test(body);f.writer=f.direct_writer;f.guards=body.split('\n').map(x=>x.trim()).filter(x=>/fn_(e_|pode_|rh_empresa|medicina_guardar|quadro_pode)|empresa_id|ativo IS|ativo is|responsavel_id.*<>|criado_por.*<>/.test(x));}
 for(let i=0;i<functions.length;i++){let change=false;for(const f of functions)if(!f.writer&&f.calls.some(n=>functions.some(c=>c.name===n&&c.writer))){f.writer=true;change=true;}if(!change)break;}
 const exposed=new Set(['fn_ajustar_saida_prevista_mensal','fn_atualizar_melhor_preco_comparativo','fn_congelar_planeamento_baseline','fn_verificar_congelamentos_pendentes']);
 const financial=new Set(['fn_marcar_fatura_paga','fn_desmarcar_fatura_paga','fn_devolver_fatura_financeiro','fn_marcar_faturacao_auto_paga','fn_registar_recebimento_parcial','fn_avancar_estado_fluxo_fatura']);
 inventories[stage]=functions.map(({definition,...f})=>({...f,classification:financial.has(f.name)?'P0 cross-tenant reproduzido':exposed.has(f.name)?(stage==='before'?'P0 anon reproduzido':'OK bloqueio reproduzido'):f.result==='trigger'?'TRIGGER: autoridade do writer chamador':!f.anon&&!f.authenticated?'OK interno owner/serviço':f.writer&&f.security_definer?'REVISÃO ESTÁTICA: guardas e tenant indicados; sem prova exaustiva de todos os ramos':'LEITURA/INVOKER: matriz e RLS aplicáveis',tenant_explicit:/empresa_id/.test(definition)}));
 await writeFile(new URL('./audit-encarregado-inventario.json',import.meta.url),JSON.stringify(inventories,null,2)+'\n');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const hp=socket.address().port;await new Promise(r=>socket.close(r));
 const secret='independent-audit-synthetic-only-secret-20261004';
 const jwt=(n,role='authenticated')=>{const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');const data=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role,sub:id(n),exp:Math.floor(Date.now()/1000)+900});return data+'.'+createHmac('sha256',secret).update(data).digest('base64url');};
 const child=spawn(process.env.QUADRO_POSTGREST,[],{windowsHide:true,stdio:'ignore',env:{...process.env,PGRST_DB_URI:`postgresql://postgres@127.0.0.1:${port}/postgres`,PGRST_DB_SCHEMAS:'public',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:secret,PGRST_SERVER_HOST:'127.0.0.1',PGRST_SERVER_PORT:String(hp)}});
 const request=(path,body,n=null,role='authenticated')=>fetch('http://127.0.0.1:'+hp+'/'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(n===null?{}:{Authorization:'Bearer '+jwt(n,role)})},...(body?{body:JSON.stringify(body)}:{})});
 const today=(await q('SELECT current_date::text d')).rows[0].d;
 const targets=[['fn_ajustar_saida_prevista_mensal',{p_obra_id:id(200),p_mes:today,p_variacao:7}],['fn_atualizar_melhor_preco_comparativo',{p_mapa_id:id(701)}],['fn_congelar_planeamento_baseline',{p_obra_id:id(200)}],['fn_verificar_congelamentos_pendentes',{}]];
 try {
  let ready=false;for(let i=0;i<100;i++){try{if((await request('')).ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}assert.ok(ready,'local PostgREST readiness');
  if(stage==='before') {
   for(const [name,payload] of targets)await t.test('INDEPENDENT baseline HTTP anon P0: '+name,async()=>{
    const r=await request('rpc/'+name,payload);assert.ok(r.ok,name+': '+r.status+' '+await r.text());
    if(name.includes('ajustar'))assert.equal(Number((await q('SELECT saidas_previstas_sem_iva v FROM previsao_financeira_mensal WHERE id=$1',[id(700)])).rows[0].v),17);
    else if(name.includes('melhor'))assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(701)])).rows[0].v),0);
    else assert.equal((await q('SELECT count(*)::int n FROM obras WHERE planeamento_baseline_congelado')).rows[0].n,name.includes('pendentes')?4:1);
   });
   await q('UPDATE previsao_financeira_mensal SET saidas_previstas_sem_iva=10,saidas_previstas_com_iva=10; UPDATE mapas_comparativos SET melhor_preco_comparativo=999; UPDATE obras SET planeamento_baseline_congelado=false,planeamento_baseline_congelado_em=NULL');
   return;
  }
  for(const [name,payload] of targets)await t.test('INDEPENDENT candidate HTTP deny: '+name,async()=>{
   for(const n of [null,10,18,20,999]){const r=await request('rpc/'+name,payload,n);assert.ok([401,403,404].includes(r.status),name+' actor '+n+': '+r.status);}
  });
  await t.test('INDEPENDENT PUBLIC-only role cannot execute any of the four',async()=>{
   await q('BEGIN; CREATE ROLE audit_public_only; GRANT USAGE ON SCHEMA public TO audit_public_only');try{
    for(const sig of ['fn_ajustar_saida_prevista_mensal(uuid,date,numeric)','fn_atualizar_melhor_preco_comparativo(uuid)','fn_congelar_planeamento_baseline(uuid)','fn_verificar_congelamentos_pendentes()'])assert.equal((await q("SELECT has_function_privilege('audit_public_only',$1,'EXECUTE') v",[sig])).rows[0].v,false);
   }finally{await q('ROLLBACK');}
  });
  await t.test('INDEPENDENT legitimate trigger can call revoked monthly helper',async()=>{
   await q('BEGIN');try{
    await q('CREATE TRIGGER audit_monthly AFTER UPDATE ON subempreitadas FOR EACH ROW EXECUTE FUNCTION fn_sincronizar_subempreitada_previsao()');
    await q("UPDATE subempreitadas SET estado='adjudicado',data_inicio_prevista=current_date,data_fim_prevista=current_date+2 WHERE id=$1",[id(43)]);
    assert.equal(Number((await q('SELECT saidas_previstas_sem_iva v FROM previsao_financeira_mensal WHERE id=$1',[id(700)])).rows[0].v),1009);
   }finally{await q('ROLLBACK');}
  });
  await t.test('INDEPENDENT owner/job invokes all four helpers after revoke',async()=>{
   await q('BEGIN');try{await q('SELECT fn_ajustar_saida_prevista_mensal($1,current_date,7),fn_congelar_planeamento_baseline($1)',[id(200)]);await q('SELECT fn_atualizar_melhor_preco_comparativo($1)',[id(701)]);await q('SELECT fn_verificar_congelamentos_pendentes()');assert.equal((await q('SELECT count(*)::int n FROM obras WHERE planeamento_baseline_congelado')).rows[0].n,4);}finally{await q('ROLLBACK');}
  });
  await t.test('INDEPENDENT comparative trigger and authorised wrapper survive revoke',async()=>{
   await q('BEGIN');try{
    await q('CREATE TRIGGER audit_price AFTER INSERT OR UPDATE ON comparativo_itens_precos FOR EACH ROW EXECUTE FUNCTION fn_recalcular_mapa_apos_preco()');
    await q('INSERT INTO mapas_comparativos(id,obra_id) VALUES($1,$2)',[id(890),id(120)]);
    await q('INSERT INTO comparativo_itens(id,mapa_id) VALUES($1,$2)',[id(891),id(890)]);
    await q("INSERT INTO comparativo_itens_precos(id,item_id,preco_total,comparavel,estado_ambito) VALUES($1,$2,37,true,'incluido')",[id(892),id(891)]);
    assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(890)])).rows[0].v),37);
    await q('DELETE FROM comparativo_itens_precos WHERE id=$1',[id(892)]);
    await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(14)]);await q('SET LOCAL ROLE authenticated');await q('SELECT fn_eliminar_item_comparativo($1)',[id(891)]);await q('RESET ROLE');
    assert.equal(Number((await q('SELECT melhor_preco_comparativo v FROM mapas_comparativos WHERE id=$1',[id(890)])).rows[0].v),0);
   }finally{await q('ROLLBACK');}
  });
  await t.test('FINDING: Financeiro company 1 pays invoice company 2 by known UUID',async()=>{
   await q('BEGIN');try{
    await q("INSERT INTO faturas(id,obra_id,valor,estado_aprovacao,estado_pagamento) VALUES($1,$2,543,'aprovado','por_pagar')",[id(880),id(200)]);
    await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(17)]);await q('SET LOCAL ROLE authenticated');
    const r=(await q('SELECT (fn_marcar_fatura_paga($1,current_date)).estado_pagamento estado',[id(880)])).rows[0];assert.equal(r.estado,'pago');
    await q('RESET ROLE');assert.equal((await q('SELECT estado_pagamento v FROM faturas WHERE id=$1',[id(880)])).rows[0].v,'pago');
   }finally{await q('ROLLBACK');}
  });
  for(const [name,start,expected] of [['fn_desmarcar_fatura_paga','pago','por_pagar'],['fn_devolver_fatura_financeiro','por_pagar','pendente']])await t.test('FINDING: cross-company '+name,async()=>{
   await q('BEGIN');try{
    await q("INSERT INTO faturas(id,obra_id,valor,tipo_origem,estado_aprovacao,estado_pagamento) VALUES($1,$2,543,'material','aprovado',$3)",[id(880),id(200),start]);
    await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(17)]);await q('SET LOCAL ROLE authenticated');
    await q('SELECT '+name+'($1'+(name.includes('devolver')?",'AUDIT_SYNTHETIC'":'')+')',[id(880)]);await q('RESET ROLE');
    assert.equal((await q('SELECT '+(name.includes('devolver')?'estado_aprovacao':'estado_pagamento')+' v FROM faturas WHERE id=$1',[id(880)])).rows[0].v,expected);
   }finally{await q('ROLLBACK');}
  });
  await t.test('FINDING HTTP: Financeiro pays another tenant through workflow RPC',async()=>{
   await q("INSERT INTO faturas(id,obra_id,tipo_origem,valor,estado_aprovacao,estado_pagamento) VALUES($1,$2,'material',543,'aprovado','por_pagar')",[id(883),id(200)]);
   try{
    const r=await request('rpc/fn_avancar_estado_fluxo_fatura',{p_fatura_id:id(883),p_novo_estado:'paga',p_data_pagamento:today,p_observacao:null},17);
    assert.equal(r.status,200);const row=await r.json();assert.equal(row.obra_id,id(200));assert.equal(row.estado_pagamento,'pago');
    assert.equal((await q('SELECT estado_pagamento v FROM faturas WHERE id=$1',[id(883)])).rows[0].v,'pago');
   }finally{await q('DELETE FROM faturas WHERE id=$1;',[id(883)]);await q('DELETE FROM faturas_eventos WHERE fatura_id=$1',[id(883)]);await q('DELETE FROM log_auditoria WHERE registo_id=$1',[id(883)]);}
  });
  for(const partial of [false,true])await t.test('FINDING: cross-company '+(partial?'fn_registar_recebimento_parcial':'fn_marcar_faturacao_auto_paga'),async()=>{
   await q('BEGIN');try{
    await q("INSERT INTO faturacao(id,obra_id,valor,estado,estado_aprovacao,estado_pagamento,valor_recebido) VALUES($1,$2,543,'emitida','aprovado','por_pagar',0)",[id(880),id(200)]);
    await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(17)]);await q('SET LOCAL ROLE authenticated');
    await q(partial?"SELECT fn_registar_recebimento_parcial(1,$1,current_date,10,'AUDIT_REQUEST',0)":"SELECT fn_marcar_faturacao_auto_paga($1,current_date,543)",[id(880)]);await q('RESET ROLE');
    assert.equal(Number((await q('SELECT valor_recebido v FROM faturacao WHERE id=$1',[id(880)])).rows[0].v),partial?10:543);
   }finally{await q('ROLLBACK');}
  });
  await t.test('FINDING: inactive Encarregado retains targeted alerts',async()=>{
   await q("INSERT INTO alertas(id,tipo,destinatario_utilizador_id,descricao) VALUES($1,'movimentacao_equipa',$2,'AUDIT_SYNTHETIC')",[id(881),id(20)]);
   try{const r=await request('alertas?id=eq.'+id(881)+'&select=descricao',undefined,20);assert.equal(r.status,200);assert.equal((await r.json())[0].descricao,'AUDIT_SYNTHETIC');}finally{await q('DELETE FROM alertas WHERE id=$1',[id(881)]);}
  });
 }finally{child.kill();await new Promise(r=>{if(child.exitCode!==null)r();else child.once('exit',r);});}
}
