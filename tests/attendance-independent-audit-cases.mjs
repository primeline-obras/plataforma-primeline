import assert from 'node:assert/strict';

// Read-only analysis and synthetic local fixtures. This module never connects to production.
export async function independentAuditCases(t,{q,a,b,as,call,aux,auxDo,id,today}) {
 const own=id(100),foreign=id(103),person=id(80),date='2026-09-18';let seq=700000;
 const data=extra=>({version:2,request_id:id(seq++),work_id:own,date,expected_revision:0,...extra});
 await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Pessoa de auditoria','Cargo formal','2026-01-01')",[person,id(1)]);
 await t.test('auditoria: ACL de todas as tabelas/RPCs/helpers e owner/search_path',async()=>{
  const tables=(await q("SELECT n.nspname,c.relname,c.relrowsecurity,c.relowner='postgres'::regrole owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND (n.nspname='folha_privado' OR n.nspname='public' AND c.relname LIKE 'folha_%')")).rows;
  assert.equal(tables.length,13);assert.ok(tables.every(x=>x.relrowsecurity&&x.owner));
  const privileges=(await q("SELECT count(*)::int n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl WHERE c.relkind='r' AND (n.nspname='folha_privado' OR n.nspname='public' AND c.relname LIKE 'folha_%') AND acl.grantee<>'postgres'::regrole")).rows[0].n;assert.equal(privileges,0);
  const funcs=(await q("SELECT n.nspname,p.proname,p.proowner='postgres'::regrole owner,p.proconfig,has_function_privilege('authenticated',p.oid,'EXECUTE') auth,has_function_privilege('anon',p.oid,'EXECUTE') anon,has_function_privilege('service_role',p.oid,'EXECUTE') service FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='folha_privado' OR n.nspname='public' AND p.proname LIKE 'fn_folha_%'")).rows;
  assert.equal(funcs.filter(x=>x.nspname==='public').length,6);assert.ok(funcs.every(x=>x.owner&&x.proconfig?.includes('search_path=pg_catalog')&&!x.anon&&!x.service));assert.ok(funcs.every(x=>x.auth===(x.nspname==='public')));
 });
 await t.test('auditoria: vínculo ambíguo Escritório recusa Diretor, Adjunto e Preparador',async()=>{
  for(const user of [14,15,16]){await q('UPDATE colaboradores SET utilizador_id=$1 WHERE id=$2',[id(user),person]);try{const ctx=await as(a,user,'SELECT fn_folha_contexto_v2($1,NULL) v',[today]);assert.equal(ctx.office_available,false);await assert.rejects(call(a,user,'save',data({work_id:null,date:today,key:{kind:'primeline',person_id:person,work_id:null,date:today}})),e=>e.code==='42501');}finally{await q('UPDATE colaboradores SET utilizador_id=NULL WHERE id=$1',[person]);}}
 });
 await t.test('auditoria: Financeiro, sem perfil e inativo não obtêm escrita operacional',async()=>{
  for(const [n,role,active] of [[81,'financeiro',true],[83,'encarregado',false]]){await q('INSERT INTO utilizadores(id,empresa_id,nome,email,funcao,ativo,auth_user_id) VALUES($1,$2,$3,$4,$5,$6,$1)',[id(n),id(1),'Ator sintético',n+'@synthetic.test',role,active]);await assert.rejects(call(a,n,'allocate',data({person_id:person,period:'dia_inteiro',expected_allocation_revision:0})),e=>e.code==='42501');}
  await assert.rejects(call(a,82,'allocate',data({person_id:person,period:'dia_inteiro',expected_allocation_revision:0})),e=>e.code==='42501');
  for(const user of [14,15,16])await assert.rejects(call(a,user,'save',data({key:{kind:'primeline',person_id:person,work_id:own,date},funcao:'administrativo',empresa_id:id(2)})),e=>e.code==='42501');
 });
 await t.test('auditoria: oito operações recusadas fora do âmbito do Encarregado',async()=>{
  for(const action of ['save','bulk','allocate','transfer','remove_from_day','external_register'])await assert.rejects(call(a,13,action,data({work_id:foreign,person_id:person})),e=>e.code==='42501');
  for(const operation of ['start','finish','normal'])await assert.rejects(call(a,13,'bulk',data({work_id:foreign,operation,items:[]})),e=>e.code==='42501');
 });
 await t.test('auditoria: UUIDs/source falsos e stale preview não escrevem',async()=>{
  const d=data({person_id:person,period:'dia_inteiro',expected_allocation_revision:0});const preview=await call(a,13,'allocate',d);await assert.rejects(call(a,13,'allocate',d,true,'wrong'),/STALE_PREVIEW/);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[person])).rows[0].n,0);
  await call(a,13,'allocate',d,true,preview.versao);
  await assert.rejects(call(a,13,'remove_from_day',data({person_id:person,ids:[id(123)],expected_allocation_revision:1})),/STALE_ALLOCATION/);
  await assert.rejects(call(a,13,'transfer',data({person_id:person,source_work_id:foreign,period:'dia_inteiro',expected_allocation_revision:1})),/SOURCE_CONFLICT/);
 });
 await t.test('auditoria: original de request/payload é imutável e preview não aumenta histórico',async()=>{
  const request=(await q("SELECT payload,token FROM folha_privado.operacoes WHERE ator_id=$1 AND payload->>'action'='allocate' AND payload->'data'->>'person_id'=$2",[id(13),person])).rows[0];const d=request.payload.data;
  const before=(await q('SELECT count(*)::int n FROM folha_historico')).rows[0].n;await call(a,13,'allocate',d);assert.equal((await q('SELECT count(*)::int n FROM folha_historico')).rows[0].n,before);
  await assert.rejects(call(a,13,'allocate',{...d,period:'manha'}),/IDEMPOTENCY_CONFLICT/);
 });
 await t.test('auditoria: transferência concorrente tem só um commit',async()=>{
  const d1=data({person_id:person,work_id:id(101),source_work_id:own,period:'dia_inteiro',expected_allocation_revision:1});
  const d2={...d1,request_id:id(seq++),work_id:id(102)};
  const p1=await call(a,10,'transfer',d1),p2=await call(b,10,'transfer',d2);
  const result=await Promise.allSettled([call(a,10,'transfer',d1,true,p1.versao),call(b,10,'transfer',d2,true,p2.versao)]);
  assert.equal(result.filter(x=>x.status==='fulfilled').length,1);assert.match(result.find(x=>x.status==='rejected').reason.message,/STALE_REVISION/);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[person])).rows[0].n,1);
 });
 await t.test('auditoria: dois bulk normal concorrentes não persistem parcialmente',async()=>{
  const bulkDate='2026-09-17',items=[];
  for(const n of [84,85]){await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Equipa sintética','Cargo formal','2026-01-01')",[id(n),id(1)]);const d=data({date:bulkDate,person_id:id(n),period:'dia_inteiro',expected_allocation_revision:0});const p=await call(a,10,'allocate',d);await call(a,10,'allocate',d,true,p.versao);items.push({key:{kind:'primeline',person_id:id(n),work_id:own,date:bulkDate},expected_revision:0,intervals:[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}]});}
  const d1=data({date:bulkDate,operation:'normal',items}),d2={...d1,request_id:id(seq++)};const p1=await call(a,10,'bulk',d1),p2=await call(b,10,'bulk',d2);
  const result=await Promise.allSettled([call(a,10,'bulk',d1,true,p1.versao),call(b,10,'bulk',d2,true,p2.versao)]);assert.equal(result.filter(x=>x.status==='fulfilled').length,1);
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=ANY($1::uuid[])',[items.map(x=>x.key.person_id)])).rows[0].n,2);
 });
 await t.test('auditoria: reconciliação preserva alertas resolvidos e de outras origens',async()=>{
  const task=id(502);await q("INSERT INTO planeamento_itens(id,fase_id,estado) VALUES($1,$2,'em_execucao')",[task,id(500)]);
  await auxDo(13,'task_report',data({task_id:task}));
  await q("UPDATE alertas SET estado='resolvido' WHERE entidade_id=$1 AND destinatario_utilizador_id=$2",[task,id(15)]);
  await q("INSERT INTO alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,data_gatilho,destinatario_utilizador_id,enviar_email,ocorrencia_chave) VALUES($1,$2,'other_origin','planeamento_item',$3,'Alerta sintético',$4,$5,false,$6)",[id(1),own,task,date,id(14),id(seq++)]);
  const before=(await q("SELECT to_jsonb(x) value FROM alertas x WHERE entidade_id=$1 AND (tipo='other_origin' OR estado='resolvido') ORDER BY id",[task])).rows;
  await q("SELECT set_config('test.actor',$1,false)",[id(14)]);await q("UPDATE planeamento_itens SET estado='concluido' WHERE id=$1",[task]);
  const after=(await q("SELECT to_jsonb(x) value FROM alertas x WHERE entidade_id=$1 AND (tipo='other_origin' OR destinatario_utilizador_id=$2) ORDER BY id",[task,id(15)])).rows;
  assert.deepEqual(after,before);
 });
 await t.test('auditoria: histórico salarial não deve ser exposto ao Encarregado',async()=>{
  // Valid administrative RPC payload with explicit work scope. No direct economic table write.
  await auxDo(10,'payroll_save',data({person_id:person,month:'2026-09-01',manual:{premium:4321,note:'PRIVATE_SYNTHETIC_PAYROLL'}}));
  const ctx=await as(a,13,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[own]);
  assert.equal(ctx.history.some(x=>x.action==='payroll_save'),false,'P1: operational context returns administrative payroll history');
 });
 await t.test('auditoria: legado deve chegar ao consumidor do histórico',async()=>{
  const {createSheetClient}=await import('../src/attendance-client.js');const client=createSheetClient({supabase:async()=>Response.json({version:2,events:[],legacy:[{id:'legacy-only',estado:'presente'}],legacy_interpretation:'original'})});
  const history=await client.history({person_id:person,work_id:own,date,kind:'primeline'});
  assert.ok(history.some(x=>x.id==='legacy-only'||x.legacy?.length),'P2: client silently discards the returned legacy evidence');
 });
}
