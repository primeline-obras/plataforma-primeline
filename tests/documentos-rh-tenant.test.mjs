import test from 'node:test';import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createRequire} from 'node:module';import {spawnSync} from 'node:child_process';import {createServer} from 'node:net';
const require=createRequire(import.meta.url),bin=process.env.QUADRO_PG_BIN,deps=process.env.QUADRO_TEST_DEPS;
const read=p=>readFile(new URL(p,import.meta.url),'utf8'),id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
function run(name,args){const r=spawnSync(join(bin,name+'.exe'),args,{encoding:'utf8',windowsHide:true,timeout:60000,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,r.stderr||name);}
test('RH documents: independent PostgreSQL RLS and main-compatible scripts',{skip:!bin||!deps,timeout:180000},async t=>{
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
 await t.test('postcheck rejects every policy/helper/ACL delta against the reviewed installation',async()=>{
  const post=await read('../supabase/documentos_rh_tenant_postcheck.sql');
  for(const mutation of [
   'ALTER POLICY rh_empresa_guard ON documentos USING(false)',
   'ALTER POLICY rh_empresa_guard ON documentos USING(true)',
   "ALTER POLICY rh_empresa_guard ON documentos USING(entidade_tipo IN('colaborador','viatura'))",
   'ALTER POLICY rh_empresa_guard ON documentos WITH CHECK(true)',
   'CREATE POLICY extra_permissive ON documentos FOR ALL TO authenticated USING(true) WITH CHECK(true)',
   'DROP POLICY rh_empresa_guard ON documentos; CREATE POLICY rh_empresa_guard ON ausencias_anexos AS RESTRICTIVE FOR ALL TO authenticated USING(false) WITH CHECK(false)',
   'ALTER FUNCTION primeline_documentos_rh_privado.empresa(uuid) SECURITY INVOKER',
   'GRANT EXECUTE ON FUNCTION primeline_documentos_rh_privado.empresa(uuid) TO anon',
   'ALTER TABLE documentos DISABLE ROW LEVEL SECURITY',
   "UPDATE storage.buckets SET public=true WHERE id='documentos'"
  ]) {
   await q('BEGIN');await q(mutation);
   await assert.rejects(q(post),/DOCUMENT_CATALOG_DRIFT/);await q('ROLLBACK');
   await q(post);
  }
 });
 await t.test('all eight preserved permissive metadata policies guarded, including pl_admin_total',async()=>{assert.equal((await q("SELECT count(*)::int n FROM pg_policies WHERE tablename='documentos'")).rows[0].n,9);for(const n of [10,13])assert.equal((await as(n,'SELECT * FROM documentos')).rowCount,3);assert.equal((await as(11,'SELECT * FROM documentos')).rowCount,2);assert.equal((await as(12,"SELECT * FROM documentos WHERE entidade_tipo IN('colaborador','viatura')")).rowCount,0);});
 for(const [tipo,n] of [['colaborador',20],['viatura',30]])await t.test(tipo+': A/B SELECT INSERT UPDATE DELETE and wrong entity/company refused',async()=>{
  assert.equal((await as(10,'SELECT * FROM documentos WHERE entidade_id=$1',[id(n+1)])).rowCount,0);
  await assert.rejects(as(10,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3)',[id(1),tipo,id(n+1)]),e=>e.code==='42501');
  await assert.rejects(as(10,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3)',[id(2),tipo,id(n)]),e=>e.code==='42501');
  await assert.rejects(as(10,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3)',[id(1),tipo,id(tipo==='viatura'?20:30)]),e=>e.code==='42501');
  assert.equal((await as(10,"UPDATE documentos SET nome_arquivo='forbidden' WHERE entidade_id=$1",[id(n+1)])).rowCount,0);assert.equal((await as(10,'DELETE FROM documentos WHERE entidade_id=$1',[id(n+1)])).rowCount,0);
  await assert.rejects(as(10,'UPDATE documentos SET entidade_id=$1 WHERE entidade_id=$2',[id(n+1),id(n)]),e=>e.code==='42501');
  const row=await as(10,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3) RETURNING id',[id(1),tipo,id(n)]);assert.equal((await as(10,"UPDATE documentos SET nome_arquivo='allowed' WHERE id=$1",[row.rows[0].id])).rowCount,1);assert.equal((await as(10,'DELETE FROM documentos WHERE id=$1',[row.rows[0].id])).rowCount,1);
 });
 for(const [tipo,n] of [['colaborador',20],['viatura',30]])await t.test('Storage '+tipo+': ownership, non-admin, invalid UUID, unsupported move/delete',async()=>{
  const own='rh/'+tipo+'/'+id(n)+'/synthetic.pdf',other='rh/'+tipo+'/'+id(n+1)+'/synthetic.pdf';assert.equal((await as(10,'SELECT * FROM storage.objects WHERE name=$1',[own])).rowCount,1);assert.equal((await as(10,'SELECT * FROM storage.objects WHERE name=$1',[other])).rowCount,0);assert.equal((await as(11,'SELECT * FROM storage.objects WHERE name=$1',[other])).rowCount,1);assert.equal((await as(12,'SELECT * FROM storage.objects WHERE name=$1',[own])).rowCount,0);
  await assert.rejects(as(10,"INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1)",[other+'-new']),e=>e.code==='42501');await assert.rejects(as(10,"INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1)",['rh/'+tipo+'/not-a-uuid/file']),e=>e.code==='42501');
  assert.equal((await as(10,'UPDATE storage.objects SET name=$1 WHERE name=$2',[other+'-moved',own])).rowCount,0);assert.equal((await as(10,'DELETE FROM storage.objects WHERE name=$1',[own])).rowCount,0);
  const added=await as(10,"INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1) RETURNING id",[own+'-new']);await q('DELETE FROM storage.objects WHERE id=$1',[added.rows[0].id]);
 });
 await t.test('alternate permissive Storage ALL cannot reopen cross-company read/move/delete',async()=>{await q('CREATE POLICY synthetic_admin_all ON storage.objects FOR ALL TO authenticated USING(fn_e_administrativo()) WITH CHECK(fn_e_administrativo())');try{
  const own='rh/colaborador/'+id(20)+'/synthetic.pdf',other='rh/colaborador/'+id(21)+'/synthetic.pdf';assert.equal((await as(13,'SELECT * FROM storage.objects WHERE name=$1',[other])).rowCount,0);await assert.rejects(as(13,'UPDATE storage.objects SET name=$1 WHERE name=$2',[other+'-moved',own]),e=>e.code==='42501');assert.equal((await as(13,'DELETE FROM storage.objects WHERE name=$1',[other])).rowCount,0);
  assert.equal((await as(13,'UPDATE storage.objects SET name=name WHERE name=$1',[own])).rowCount,1);
 }finally{await q('DROP POLICY synthetic_admin_all ON storage.objects');}});
 await t.test('absence attachments require company of source; work documents remain available',async()=>{assert.equal((await as(10,'SELECT * FROM ausencias_anexos')).rowCount,1);assert.equal((await as(11,'SELECT * FROM ausencias_anexos')).rowCount,1);await assert.rejects(as(10,"INSERT INTO ausencias_anexos(ausencia_id,arquivo_url) VALUES($1,'synthetic')",[id(61)]),e=>e.code==='42501');assert.equal((await as(12,"SELECT * FROM documentos WHERE entidade_tipo='auto_medicao'")).rowCount,1);assert.equal((await as(12,'SELECT * FROM storage.objects WHERE name=$1',[id(50)+'/work.pdf'])).rowCount,1);});
 await t.test('rollback restores compatibility without reopening tenant exposure or losing bytes',async()=>{await q(await read('../supabase/documentos_rh_tenant_rollback.sql'));const current=(await q("SELECT * FROM pg_policies WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects') ORDER BY schemaname,tablename,policyname")).rows;const old=(await q('SELECT * FROM primeline_documentos_rh_backup.policies ORDER BY schemaname,tablename,policyname')).rows;await q(await read('../supabase/documentos_rh_tenant_rollback_postcheck.sql'));assert.deepEqual(current.filter(p=>!p.policyname.startsWith('rh_')),old);assert.equal((await as(10,'SELECT * FROM ausencias_anexos')).rowCount,1);assert.equal((await q("SELECT to_regclass('folha_registos') r")).rows[0].r,null);});
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
