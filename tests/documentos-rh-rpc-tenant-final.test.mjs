import test from 'node:test';import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createRequire} from 'node:module';import {spawnSync} from 'node:child_process';import {createServer} from 'node:net';
const require=createRequire(import.meta.url),bin=process.env.QUADRO_PG_BIN,deps=process.env.QUADRO_TEST_DEPS;
const read=p=>readFile(new URL(p,import.meta.url),'utf8'),id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
function run(name,args){const r=spawnSync(join(bin,name+'.exe'),args,{encoding:'utf8',windowsHide:true,timeout:60000,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,r.stderr||name);}
test('Final document RPC tenant and correlate regression',{skip:!bin||!deps,timeout:180000},async t=>{
 const folder=await mkdtemp(join(tmpdir(),'primeline-doc-tenant-')),data=join(folder,'data'),socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);let started=false;const clients=[];
 try{run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;const {Client}=require(join(deps,'pg'));async function connect(){const c=new Client({host:'127.0.0.1',port,user:'postgres',password:''});await c.connect();clients.push(c);return c;}
 const owner=await connect(),actor=await connect(),q=(s,p=[])=>owner.query(s,p);async function as(n,s,p=[]){await actor.query("SELECT set_config('test.actor',$1,false)",[id(n)]);await actor.query('SET ROLE authenticated');try{return await actor.query(s,p);}finally{await actor.query('RESET ROLE');}}
 await q(await read('./fixtures/documentos-rh-tenant-base.sql'));
 const snapshot=JSON.parse(await read('./fixtures/encarregado-catalogo-real-20261004.json'));for(const p of snapshot.catalog.tables.find(x=>x.name==='documentos').policies){const cmd={'*':'ALL',r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE'}[p.cmd];await q(`CREATE POLICY "${p.name}" ON documentos FOR ${cmd} TO authenticated${p.using?' USING('+p.using+')':''}${p.check?' WITH CHECK('+p.check+')':''}`);}
 for(const [n,c,role] of [[10,1,'administrativo'],[11,2,'administrativo'],[12,1,'encarregado'],[13,1,'gerencia']])await q('INSERT INTO utilizadores VALUES($1,$2,$3,true)',[id(n),id(c),role]);
 for(const [n,c] of [[20,1],[21,2]]){await q('INSERT INTO colaboradores VALUES($1,$2)',[id(n),id(c)]);await q('INSERT INTO viaturas VALUES($1,$2)',[id(n+10),id(c)]);await q('INSERT INTO obras VALUES($1,$2)',[id(n+30),id(c)]);await q('INSERT INTO ausencias VALUES($1,$2)',[id(n+40),id(n)]);await q("INSERT INTO ausencias_anexos VALUES($1,$2,'synthetic','synthetic')",[id(n+50),id(n+40)]);
 for(const tipo of ['colaborador','viatura']){const ent=tipo==='colaborador'?n:n+10;await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id,nome_arquivo) VALUES($1,$2,$3,'Synthetic')",[id(c),tipo,id(ent)]);await q("INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1)",['rh/'+tipo+'/'+id(ent)+'/synthetic.pdf']);}}
 await q('INSERT INTO autos_medicao VALUES($1,$2)',[id(80),id(50)]);await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,'auto_medicao',$2)",[id(1),id(80)]);await q("INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1)",[id(50)+'/work.pdf']);
 await q(await read('./fixtures/documentos-rh-correlatos-base.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-baseline.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-correlatos-baseline.sql'));
 await q(await read('../supabase/documentos_rh_tenant_precheck.sql'));await q(await read('../supabase/documentos_rh_tenant_backup.sql'));await q(await read('../supabase/documentos_rh_tenant.sql'));await q(await read('../supabase/documentos_rh_tenant_postcheck.sql'));

 await t.test('safe deletion: own tenant, cross tenant, inactive, forbidden role and audit',async()=>{
  await q('CREATE TABLE local_audit(id uuid,action text); CREATE FUNCTION local_doc_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.local_audit VALUES(OLD.id,TG_OP); RETURN OLD; END $$; CREATE TRIGGER audit AFTER DELETE ON documentos FOR EACH ROW EXECUTE FUNCTION local_doc_audit()');
  await q("INSERT INTO utilizadores VALUES($1,$2,'gestao_plataforma',true),($3,$2,'administrativo',false)",[id(14),id(1),id(15)]);
  for(const user of [10,13,14]){
   const row=(await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,'colaborador',$2) RETURNING id",[id(1),id(20)])).rows[0];
   await as(user,'SELECT fn_apagar_documento_entidade($1)',[row.id]);
   assert.equal((await q('SELECT count(*)::int n FROM local_audit WHERE id=$1',[row.id])).rows[0].n,1);
  }
  const foreign=(await q("SELECT id FROM documentos WHERE empresa_id=$1 LIMIT 1",[id(2)])).rows[0].id;
  for(const user of [10,13,14,15,12])await assert.rejects(as(user,'SELECT fn_apagar_documento_entidade($1)',[foreign]),e=>e.code==='42501');
  assert.equal((await q('SELECT count(*)::int n FROM documentos WHERE id=$1',[foreign])).rows[0].n,1);
  await assert.rejects(as(10,'SELECT fn_apagar_documento_entidade($1)',[id(999)]),e=>e.code==='P0002');
  const bad=(await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,'colaborador',$2) RETURNING id",[id(1),id(21)])).rows[0];
  await assert.rejects(as(10,'SELECT fn_apagar_documento_entidade($1)',[bad.id]),e=>e.code==='42501');
 });

 await t.test('work document/RNC RPCs retain legitimate work access and refuse another company',async()=>{
  await q('INSERT INTO rnc(id,obra_id) VALUES($1,$2),($3,$4)',[id(700),id(50),id(701),id(51)]);
  await q("INSERT INTO rnc_anexos(id,rnc_id,arquivo_url) VALUES($1,$2,'synthetic'),($3,$4,'synthetic')",[id(702),id(700),id(703),id(701)]);
  await q("INSERT INTO documentos_obra(id,obra_id) VALUES($1,$2),($3,$4)",[id(704),id(50),id(705),id(51)]);
  await assert.rejects(as(10,'SELECT fn_apagar_documento_obra($1)',[id(705)]),e=>e.code==='42501');
  await assert.rejects(as(10,'SELECT fn_apagar_anexo_rnc($1)',[id(703)]),e=>e.code==='42501');
  await assert.rejects(as(10,"SELECT fn_registar_documento_obra($1,'outro','synthetic',$2)",[id(51),id(51)+'/synthetic']),e=>e.code==='42501');
  await as(10,'SELECT fn_apagar_documento_obra($1)',[id(704)]);await as(10,'SELECT fn_apagar_anexo_rnc($1)',[id(702)]);
  await as(10,"SELECT fn_registar_documento_obra($1,'outro','synthetic',$2)",[id(50),id(50)+'/synthetic']);
 });
 await t.test('Storage namespaces: other companies cannot be reopened by a permissive ALL policy',async()=>{
  await q('INSERT INTO imoveis_empresa(id,empresa_id) VALUES($1,$2),($3,$4)',[id(800),id(1),id(801),id(2)]);
  await q('INSERT INTO pedidos_orcamento(id,empresa_id) VALUES($1,$2),($3,$4)',[id(802),id(1),id(803),id(2)]);
  await q('CREATE POLICY local_all ON storage.objects FOR ALL TO authenticated USING(true) WITH CHECK(true)');
  try{
   for(const [bucket,own,foreign] of [
    ['documentos','empresa/'+id(1)+'/synthetic','empresa/'+id(2)+'/synthetic'],
    ['documentos','entidades/imovel/'+id(800)+'/synthetic','entidades/imovel/'+id(801)+'/synthetic'],
    ['documentos','entidades/pedido_orcamento/'+id(802)+'/synthetic','entidades/pedido_orcamento/'+id(803)+'/synthetic'],
    ['documentos',id(50)+'/rnc/synthetic',id(51)+'/rnc/synthetic'],
    ['faturas',id(50)+'/faturas-anexos/synthetic',id(51)+'/faturas-anexos/synthetic']
   ]){
    await q('INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2)',[bucket,foreign]);
    await assert.rejects(as(10,'INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2)',[bucket,foreign+'-new']),e=>e.code==='42501');
    assert.equal((await as(10,'SELECT id FROM storage.objects WHERE bucket_id=$1 AND name=$2',[bucket,foreign])).rowCount,0);
    assert.equal((await as(10,'DELETE FROM storage.objects WHERE bucket_id=$1 AND name=$2',[bucket,foreign])).rowCount,0);
    await as(10,'INSERT INTO storage.objects(bucket_id,name) VALUES($1,$2)',[bucket,own]);
    await assert.rejects(as(10,'UPDATE storage.objects SET name=$1 WHERE name=$2',[foreign+'-moved',own]),e=>e.code==='42501');
    assert.equal((await as(10,'DELETE FROM storage.objects WHERE name=$1',[own])).rowCount,1);
   }
  }finally{await q('DROP POLICY local_all ON storage.objects');}
 });

 await t.test('all documentary correlates preserve legitimate action and refuse foreign targets',async()=>{
  for(const company of [1,2]){
   const n=company*100;
   await q('INSERT INTO imoveis_empresa(id,empresa_id) VALUES($1,$2)',[id(n),id(company)]);
   await q("INSERT INTO imoveis_anexos(id,imovel_id,arquivo_url) VALUES($1,$2,'synthetic')",[id(n+1),id(n)]);
   await q('INSERT INTO imoveis_reunioes_condominio(id,imovel_id) VALUES($1,$2)',[id(n+2),id(n)]);
   await q('INSERT INTO pedidos_orcamento(id,empresa_id) VALUES($1,$2)',[id(n+3),id(company)]);
   await q('INSERT INTO pedidos_orcamento_versoes(id,pedido_id) VALUES($1,$2)',[id(n+4),id(n+3)]);
   await q("INSERT INTO pedidos_orcamento_anexos(id,pedido_id,versao_id,arquivo_url) VALUES($1,$2,$3,'synthetic')",[id(n+5),id(n+3),id(n+4)]);
   await q('INSERT INTO viaturas_eventos(id,viatura_id) VALUES($1,$2)',[id(n+6),id(29+company)]);
  }
  for(const [fn,offset] of [['fn_apagar_anexo_imovel',1],['fn_apagar_reuniao_condominio',2],['fn_apagar_anexo_pedido_orcamento',5],['fn_apagar_versao_pedido_orcamento',4],['fn_cancelar_pedido_orcamento',3],['fn_apagar_imovel_empresa',0]]){
   await assert.rejects(as(10,'SELECT '+fn+'($1)',[id(200+offset)]),e=>e.code==='42501');
   await as(10,'SELECT '+fn+'($1)',[id(100+offset)]);
  }
  await assert.rejects(as(10,"SELECT fn_gerir_registo_frota('viaturas_eventos',$1,'apagar','{}')",[id(206)]),e=>e.code==='42501');
  await as(10,"SELECT fn_gerir_registo_frota('viaturas_eventos',$1,'editar','{\"descricao\":\"synthetic\"}')",[id(106)]);
  await as(10,"SELECT fn_gerir_registo_frota('viaturas_eventos',$1,'apagar','{}')",[id(106)]);
  await assert.rejects(as(10,"SELECT fn_guardar_validade_viatura(1,$1,'seguro','editar_data',NULL,'2027-01-01',NULL,NULL,'synthetic','request')",[id(31)]),e=>e.code==='42501');
  await assert.rejects(as(10,"SELECT fn_alterar_responsavel_viatura(1,$1,NULL,0,$2,NULL)",[id(31),id(501)]),e=>e.code==='42501');
  await q('UPDATE viaturas SET colaborador_atribuido_id=$1 WHERE id=$2',[id(20),id(30)]);
  await as(10,"SELECT fn_alterar_responsavel_viatura(1,$1,NULL,0,$2,NULL)",[id(30),id(502)]);
 });

 await t.test('concurrency: company change before delete is rechecked; delete locks target',async()=>{
  const monitor=await connect();
  const target=(await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,'colaborador',$2) RETURNING id",[id(1),id(20)])).rows[0].id;
  await q('BEGIN');await q('UPDATE documentos SET empresa_id=$1,entidade_id=$2 WHERE id=$3',[id(2),id(21),target]);
  const attempted=as(10,'SELECT fn_apagar_documento_entidade($1)',[target]).then(value=>({value}),error=>({error}));
  let blocked=false;for(let n=0;n<100;n++){blocked=(await monitor.query('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[actor.processID])).rows[0].blocked;if(blocked)break;await new Promise(r=>setTimeout(r,10));}
  assert.equal(blocked,true);await q('COMMIT');assert.equal((await attempted).error?.code,'42501');
  assert.equal((await q('SELECT empresa_id FROM documentos WHERE id=$1',[target])).rows[0].empresa_id,id(2));
  const second=(await q("INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,'colaborador',$2) RETURNING id",[id(1),id(20)])).rows[0].id;
  await actor.query('BEGIN');await as(10,'SELECT fn_apagar_documento_entidade($1)',[second]);
  const reassign=q('UPDATE documentos SET empresa_id=$1 WHERE id=$2',[id(2),second]);
  blocked=false;for(let n=0;n<100;n++){blocked=(await monitor.query('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[owner.processID])).rows[0].blocked;if(blocked)break;await new Promise(r=>setTimeout(r,10));}
  assert.equal(blocked,true);await actor.query('COMMIT');assert.equal((await reassign).rowCount,0);
 });

 await t.test('RPC, ACL and helper drift refused by postcheck; rollback retains guards',async()=>{
  for(const mutation of ['ALTER FUNCTION fn_apagar_documento_entidade(uuid) SECURITY INVOKER','GRANT EXECUTE ON FUNCTION fn_apagar_documento_entidade(uuid) TO anon','ALTER FUNCTION fn_gerir_registo_frota(text,uuid,text,jsonb) SET search_path=public']){
   await q('BEGIN');await q(mutation);await assert.rejects(q(await read('../supabase/documentos_rh_tenant_postcheck.sql')),/DOCUMENT_CATALOG_DRIFT/);await q('ROLLBACK');
  }
  await q(await read('../supabase/documentos_rh_tenant_rollback.sql'));
  const foreign=(await q('SELECT id FROM documentos WHERE empresa_id=$1 LIMIT 1',[id(2)])).rows[0].id;
  await assert.rejects(as(10,'SELECT fn_apagar_documento_entidade($1)',[foreign]),e=>e.code==='42501');
 });
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
