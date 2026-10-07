import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
const require=createRequire(import.meta.url);
const bin=process.env.QUADRO_PG_BIN, deps=process.env.QUADRO_TEST_DEPS;
const read=async p=>(await readFile(new URL(p,import.meta.url),'utf8')).replace(/^\uFEFF/,'');
const fixture=JSON.parse(await read('./fixtures/encarregado-catalogo-real-20261004.json'));
const integrity=JSON.parse(await read('./fixtures/encarregado-autorizacao-integridade-20261004.json'));
const snapshotQuery=await read('./fixtures/encarregado-catalogo-snapshot-query.sql');
const scripts=Object.fromEntries(await Promise.all(['precheck','backup','migration','postcheck','rollback'].map(async k=>[k,await read('../supabase/encarregado_escopo_'+k+'.sql')])));
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const qi=s=>'"'+s.replaceAll('"','""')+'"';
function run(name,args){const r=spawnSync(join(bin,name+(process.platform==='win32'?'.exe':'')),args,{encoding:'utf8',timeout:60000,windowsHide:true,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,name+': '+(r.error?.message||r.stderr));return r.stdout;}
test('hosted ownership: non-superuser, failed old migration, preserved backup, resume and complete Folha rollout',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client,types}=require(join(deps,'pg'));types.setTypeParser(1082,v=>v);
 const folder=await mkdtemp(join(tmpdir(),'primeline-escopo-')),data=join(folder,'data');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','local_bootstrap','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false,db,bootstrap;
 try{
  run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
  bootstrap=new Client({host:'127.0.0.1',port,user:'local_bootstrap',database:'postgres',ssl:false});await bootstrap.connect();
  await bootstrap.query('CREATE ROLE postgres LOGIN SUPERUSER;ALTER DATABASE postgres OWNER TO postgres');
  db=new Client({host:'127.0.0.1',port,user:'postgres',database:'postgres',password:'',ssl:false});await db.connect();const q=(s,p=[])=>db.query(s,p);
  await q(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
   CREATE SCHEMA auth; GRANT USAGE ON SCHEMA auth,public TO anon,authenticated,service_role;
   CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
   SET check_function_bodies=off;`);
  // Reproduz TODOS os tipos, policies, grants, views e funções do catálogo real.
  // Sem linhas reais, defaults/triggers/FKs operacionais não são disparados nesta fixture.
  for(const table of fixture.catalog.tables.filter(x=>x.kind==='r'))
   await q('CREATE TABLE public.'+qi(table.name)+'('+table.columns.map(c=>qi(c.name)+' '+c.type).join(',')+')');
  for(const def of Object.values(fixture.details.definitions))await q(def);
  for(const table of fixture.catalog.tables.filter(x=>x.kind==='v'))await q('CREATE VIEW public.'+qi(table.name)+(table.options?' WITH ('+table.options.join(',')+')':'')+' AS '+table.view_definition);
  const perms={r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE',D:'TRUNCATE',x:'REFERENCES',t:'TRIGGER',m:'MAINTAIN',X:'EXECUTE'};
  async function acl(kind,name,value,column){
   if(value===null)return;
   const targets=kind==='FUNCTION' && value.startsWith('{=X/')?'anon,authenticated,service_role':'PUBLIC,anon,authenticated,service_role';
   await q('REVOKE ALL'+(column?' ('+qi(column)+')':'')+' ON '+kind+' '+name+' FROM '+targets);
   for(const item of value.slice(1,-1).split(',')){
    const [role,rest]=item.split('='),priv=rest.split('/')[0];
    if(!priv)continue;
    await q('GRANT '+[...priv].map(p=>perms[p]+(column?' ('+qi(column)+')':'')).join(',')+' ON '+kind+' '+name+' TO '+(role?qi(role):'PUBLIC'));
   }
  }
  for(const f of fixture.catalog.functions)await acl('FUNCTION','public.'+f.signature,f.acl);
  for(const table of fixture.catalog.tables){
   const name='public.'+qi(table.name);await acl('TABLE',name,table.acl);
   for(const col of table.columns)if(col.acl)await acl('TABLE',name,col.acl,col.name);
   if(table.rls)await q('ALTER TABLE '+name+' ENABLE ROW LEVEL SECURITY');
   if(table.force_rls)await q('ALTER TABLE '+name+' FORCE ROW LEVEL SECURITY');
   for(const p of table.policies||[])await q('CREATE POLICY '+qi(p.name)+' ON '+name+' AS '+(p.permissive?'PERMISSIVE':'RESTRICTIVE')+' FOR '+({r:'SELECT',a:'INSERT',w:'UPDATE',d:'DELETE','*':'ALL'}[p.cmd])+' TO '+p.roles.map(r=>r==='PUBLIC'?'PUBLIC':qi(r)).join(',')+(p.using?' USING ('+p.using+')':'')+(p.check?' WITH CHECK ('+p.check+')':''));
  }
  await q('SET check_function_bodies=on');
  // Install the real triggers reached by the P0 UPDATE reproductions. No production rows.
  for(const trigger of integrity.triggers.filter(x=>['obras','mapas_comparativos','planeamento_itens','previsao_financeira_mensal'].includes(x.table)))await q(trigger.definition);
  const rebuilt=(await q(snapshotQuery)).rows[0].jsonb_build_object;
  for(const a of rebuilt.tables){
   const original=fixture.catalog.tables.find(t=>t.name===a.name);
   const expected={...original,columns:original.columns.map(({name,type,acl})=>({name,type,acl}))};
   assert.deepEqual(a,expected,'catálogo da tabela '+a.name);
  }
  for(const a of rebuilt.functions){const f=fixture.catalog.functions.find(f=>f.signature===a.signature);assert.deepEqual(a,{signature:f.signature,owner:f.owner,acl:'{'+(f.acl||'{=X/postgres,postgres=X/postgres}').slice(1,-1).split(',').sort().join(',')+'}',definition:fixture.details.definitions[f.signature].replaceAll('\r','')},a.signature);}
  // Fixture omitted constraints; restore synthetic unique IDs required by new FKs.
  for(const table of fixture.catalog.tables.filter(x=>x.kind==='r'&&x.columns.some(c=>c.name==='id'))) await q('ALTER TABLE public.'+qi(table.name)+' ADD UNIQUE(id)');
  await q(scripts.precheck);await q(scripts.backup);await q(scripts.migration);await q(scripts.postcheck);
  await q(`CREATE SCHEMA primeline_quadro_rollout;
   CREATE TABLE primeline_quadro_rollout.controlo(singleton boolean,estado text,instalacao_id uuid);
   INSERT INTO primeline_quadro_rollout.controlo VALUES(true,'a',gen_random_uuid());
   CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean);INSERT INTO storage.buckets VALUES('documentos',false);
   CREATE TABLE storage.objects(id uuid PRIMARY KEY,bucket_id text,name text);ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
   GRANT USAGE ON SCHEMA storage TO authenticated;GRANT SELECT,INSERT ON storage.objects TO authenticated;
   CREATE POLICY documents_read ON storage.objects FOR SELECT TO authenticated USING(bucket_id='documentos');
   CREATE POLICY documents_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='documentos');`);
  const pre=await read('../supabase/folha_ponto_v2_precheck.sql');
  await t.test('missing documentary delta is rejected',async()=>{await assert.rejects(q(pre),/does not exist/);await q('ROLLBACK');});
  await q(await read('./fixtures/documentos-rh-correlatos-base.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-baseline.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-correlatos-baseline.sql'));
 await q(await read('./fixtures/documentos-rh-storage-hosted-owner.sql'));

  await q("INSERT INTO storage.objects(id,bucket_id,name) VALUES('00000000-0000-4000-8000-000000000001','documentos','synthetic-only.pdf')");
  const b=(s,p=[])=>bootstrap.query(s,p);
  // Reproduce all 18 frozen real policy definitions, with synthetic rows only.
  const realPolicies=JSON.parse(await read('./fixtures/pacote2-real-baseline-20261007.json')).tables.find(t=>t.schema==='storage'&&t.name==='objects').policies;
  await b("DROP POLICY documents_read ON storage.objects;DROP POLICY documents_insert ON storage.objects;CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $body$ SELECT (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1] $body$;GRANT USAGE ON SCHEMA storage TO anon,authenticated");
  for(const p of realPolicies)await b('CREATE POLICY '+qi(p.policyname)+' ON storage.objects AS '+p.permissive+' FOR '+p.cmd+' TO authenticated'+(p.qual?' USING('+p.qual+')':'')+(p.with_check?' WITH CHECK('+p.with_check+')':''));
  await b('INSERT INTO empresas(id) VALUES($1),($2)',[id(9101),id(9102)]);
  await b("INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo) VALUES($1,$2,$3,'administrativo',true)",[id(9103),id(9104),id(9101)]);
  await b("INSERT INTO storage.objects(id,bucket_id,name) VALUES($1,'documentos',$2),($3,'documentos',$4)",[id(9105),'empresa/'+id(9101)+'/synthetic.pdf',id(9106),'empresa/'+id(9102)+'/synthetic.pdf']);
  // Existing client-role capability required by Folha precheck, never Storage-owner membership.
  await b('GRANT authenticated TO postgres;ALTER ROLE postgres NOSUPERUSER BYPASSRLS');
  const normal=(await q("SELECT current_user,session_user,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) superuser")).rows[0];
  assert.deepEqual(normal,{current_user:'postgres',session_user:'postgres',superuser:false});
  const resume=await read('../supabase/documentos_rh_tenant_resume_precheck_20261007.sql');
  assert.match(resume,/BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY/);
  assert.doesNotMatch(resume,/RAISE NOTICE|CREATE\s+(?:TABLE|FUNCTION|SCHEMA)|GRANT\s|REVOKE\s/i);
  const rows=r=>(Array.isArray(r)?r:[r]).flatMap(x=>x.rows||[]);
  const gate=async sql=>{const r=rows(await q(sql));assert.equal(r.length,1);return r[0].resume_precheck;};
  // Explicit synthetic substitution only: the committed production baseline remains unchanged.
  const captured=rows(await q(await read('../supabase/pacote2_validacao_real_final_readonly.sql'))).find(r=>r.readonly_catalog).readonly_catalog;
  for(const table of captured.tables)table.indexes?.sort((a,b)=>Buffer.compare(Buffer.from(a.definition),Buffer.from(b.definition)));
  const syntheticCatalog={functions:captured.functions.map(({signature,owner,security_definer,config,acl,definition_sha256})=>({signature,owner,security_definer,config,acl,definition_sha256})),tables:captured.tables};
  let synthetic=resume.replace(/WITH baseline AS \(SELECT '[\s\S]*?'::jsonb data\),/,()=>"WITH baseline AS (SELECT '"+JSON.stringify(syntheticCatalog).replaceAll("'","''")+"'::jsonb data),");
  synthetic=synthetic.replace(/expected_counts\(name,expected\) AS \(VALUES [\s\S]*?\),\r?\ncounts/,()=>"expected_counts(name,expected) AS (VALUES "+captured.counts.map(n=>"('"+n.relname+"',"+n.total+"::bigint)").join(',')+"),\ncounts");
  await t.test('native owner DDL refused; Dashboard requirement replaces SET membership gate',async()=>{
   for(const sql of ['ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY','CREATE POLICY forbidden ON storage.objects USING(true)'])await assert.rejects(q(sql),e=>e.code==='42501');
   await q(await read('../supabase/documentos_rh_tenant_precheck.sql'));
   const v=await gate(synthetic);assert.equal(v.resume_state,'CLEAN_START');assert.equal(v.verdict,'BLOCKED');assert.equal(v.set_role_required,false);assert.equal(v.storage_policy_ddl,'STORAGE_DASHBOARD_POLICY_REQUIRED');
   assert.ok(!v.blockers.some(x=>x.reason==='STORAGE_OWNER_CAPABILITY_BLOCKED'));
   assert.equal((await q("SELECT pg_has_role('postgres','supabase_storage_admin','SET') v")).rows[0].v,false);
  });
  const docPre=await read('../supabase/documentos_rh_tenant_precheck.sql'),docBackup=await read('../supabase/documentos_rh_tenant_backup.sql'),docMigration=await read('../supabase/documentos_rh_tenant.sql');
  await q(docPre);await q(docBackup);
  const backupDigest=async()=>{
   const r={};for(const name of ['documentos','anexos','objects','policies','tables','rpc'])r[name]=(await q("SELECT count(*)::int count,md5(coalesce(string_agg(to_jsonb(t)::text,chr(10) ORDER BY to_jsonb(t)::text),'')) hash FROM primeline_documentos_rh_backup."+name+' t')).rows[0];return r;
  };
  const before=await backupDigest();
  await t.test('exact old Git migration fails 42501 and rolls back, retaining the existing backup',async()=>{
   const old=spawnSync('git',['show','cf0957447f171cfa274444d5437cbf587f0076ca:supabase/documentos_rh_tenant.sql'],{encoding:'utf8',windowsHide:true});assert.equal(old.status,0);
   await assert.rejects(q(old.stdout),e=>e.code==='42501'&&/must be owner of table objects/.test(e.message));await q('ROLLBACK');
   assert.equal((await q("SELECT to_regnamespace('primeline_documentos_rh_privado') private")).rows[0].private,null);
   assert.deepEqual(await backupDigest(),before);
  });
  await t.test('existing-backup resume yields exactly one READY JSON and all baseline hashes',async()=>{
   const actual=await gate(resume);assert.equal(actual.verdict,'BLOCKED','Reduced synthetic catalog cannot certify the frozen real catalog');
   const v=await gate(synthetic);assert.equal(v.verdict,'READY_TO_RESUME_DOCUMENTAL_MIGRATION',JSON.stringify(v.blockers));
   assert.equal(v.resume_state,'VALID_EXISTING_BACKUP_RESUME');assert.equal(v.backup_private,true);assert.equal(v.backup_matches_live,true);assert.equal(v.migration_partial,false);assert.equal(Object.keys(v.baseline_rpc_hashes).length,13);
  });
  await t.test('backup, owner, RLS, metadata and partial-state drift block without replacing evidence',async()=>{
   const variants=[
    ["UPDATE primeline_documentos_rh_backup.objects SET name='changed' WHERE id='00000000-0000-4000-8000-000000000001'",'PARTIAL_OR_UNKNOWN_STATE'],
    ["UPDATE storage.objects SET name='live-changed' WHERE id='00000000-0000-4000-8000-000000000001'",'PARTIAL_OR_UNKNOWN_STATE'],
    ['GRANT USAGE ON SCHEMA primeline_documentos_rh_backup TO authenticated','PARTIAL_OR_UNKNOWN_STATE'],
    ['ALTER TABLE primeline_documentos_rh_backup.objects ADD COLUMN accidental text','PARTIAL_OR_UNKNOWN_STATE'],
    ['CREATE SCHEMA primeline_documentos_rh_privado','PARTIAL_OR_UNKNOWN_STATE'],
    ['CREATE TABLE primeline_documentos_rh_backup.unexpected(id int)','PARTIAL_OR_UNKNOWN_STATE'],
    ['ALTER TABLE storage.objects OWNER TO postgres','PARTIAL_OR_UNKNOWN_STATE'],
    ['ALTER TABLE storage.buckets DISABLE ROW LEVEL SECURITY','VALID_EXISTING_BACKUP_RESUME'],
    ['ALTER FUNCTION fn_apagar_documento_entidade(uuid) SECURITY INVOKER','PARTIAL_OR_UNKNOWN_STATE']
   ];
   for(const [change,state] of variants){await b('BEGIN');await b(change);await b('COMMIT');
    // Restore with exact inverse after the read-only check; fixture changes only.
    try{const v=await gate(synthetic);assert.equal(v.verdict,'BLOCKED',change);assert.equal(v.resume_state,state,change);}finally{
    if(change.includes("backup.objects SET"))await b("UPDATE primeline_documentos_rh_backup.objects SET name='synthetic-only.pdf' WHERE id='00000000-0000-4000-8000-000000000001'");
    else if(change.includes("UPDATE storage.objects"))await b("UPDATE storage.objects SET name='synthetic-only.pdf' WHERE id='00000000-0000-4000-8000-000000000001'");
    else if(change.startsWith('GRANT'))await b('REVOKE USAGE ON SCHEMA primeline_documentos_rh_backup FROM authenticated');
    else if(change.includes('ADD COLUMN'))await b('DROP TABLE primeline_documentos_rh_backup.objects;CREATE TABLE primeline_documentos_rh_backup.objects AS TABLE storage.objects;ALTER TABLE primeline_documentos_rh_backup.objects OWNER TO postgres;REVOKE ALL ON primeline_documentos_rh_backup.objects FROM PUBLIC,anon,authenticated,service_role');
    else if(change.startsWith('CREATE SCHEMA'))await b('DROP SCHEMA primeline_documentos_rh_privado');
    else if(change.startsWith('CREATE TABLE'))await b('DROP TABLE primeline_documentos_rh_backup.unexpected');
    else if(change.includes('OWNER TO'))await b('ALTER TABLE storage.objects OWNER TO supabase_storage_admin;GRANT SELECT ON storage.objects TO postgres');
    else if(change.includes('DISABLE'))await b('ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY');
    else await b('ALTER FUNCTION fn_apagar_documento_entidade(uuid) SECURITY DEFINER');}
   }
   // A dropped column leaves a physical attisdropped slot: replace only this synthetic test table.
   await b('DROP TABLE primeline_documentos_rh_backup.objects;CREATE TABLE primeline_documentos_rh_backup.objects AS TABLE storage.objects;ALTER TABLE primeline_documentos_rh_backup.objects OWNER TO postgres;REVOKE ALL ON primeline_documentos_rh_backup.objects FROM PUBLIC,anon,authenticated,service_role');
   assert.deepEqual(await backupDigest(),before);
  });
  await t.test('RLS-filtered visibility cannot be certified as a complete backup comparison',async()=>{
   await b('ALTER ROLE postgres NOBYPASSRLS');
   try{const v=await gate(synthetic);assert.equal(v.verdict,'BLOCKED');assert.equal(v.backup_full_visibility,false);assert.equal(v.backup_matches_live,false);}
   finally{await b('ALTER ROLE postgres BYPASSRLS');}
  });
  await t.test('corrected documentary migration/postcheck preserve managed owners, RLS, data and ACL',async()=>{
   assert.equal((await gate(synthetic)).verdict,'READY_TO_RESUME_DOCUMENTAL_MIGRATION');
   const initial=(await q("SELECT c.relname,c.relowner,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN('storage.objects'::regclass,'storage.buckets'::regclass) ORDER BY c.relname")).rows;
   await q(docMigration);await q(await read('../supabase/documentos_rh_tenant_intermediate_postcheck.sql'));
   const post=await read('../supabase/documentos_rh_tenant_postcheck.sql');
   await assert.rejects(q(post),/DOCUMENT_CATALOG_DRIFT/);await q('ROLLBACK');
   // Separate external owner connection is local simulation only, not a claimed hosted capability.
   await b(await read('./fixtures/documentos-rh-storage-dashboard-policy.sql'));
   await q(post);
   for(const mutation of ["ALTER POLICY documentos_empresa_storage_select ON storage.objects USING(bucket_id='documentos')", "ALTER POLICY documentos_empresa_storage_select ON storage.objects USING(primeline_documentos_rh_privado.objeto(name))", "CREATE POLICY unintended_or ON storage.objects FOR SELECT TO authenticated USING(true)","UPDATE storage.buckets SET public=true WHERE id='documentos'",'ALTER TABLE storage.objects OWNER TO postgres']){
    await b(mutation);await assert.rejects(q(post),/DOCUMENT_CATALOG_DRIFT|STORAGE_OWNER_OR_RLS_DRIFT/);await q('ROLLBACK');
    if(mutation.includes('unintended_or'))await b('DROP POLICY unintended_or ON storage.objects');
    if(mutation.includes('public=true'))await b("UPDATE storage.buckets SET public=false WHERE id='documentos'");
    if(mutation.includes('OWNER TO'))await b('ALTER TABLE storage.objects OWNER TO supabase_storage_admin;GRANT SELECT ON storage.objects TO postgres');
    await b(await read('./fixtures/documentos-rh-storage-dashboard-policy.sql'));
   }
   await q(post);
   assert.equal((await q("SELECT pg_has_role('postgres','supabase_storage_admin','SET') v")).rows[0].v,false);
   await q("SELECT set_config('request.jwt.claim.sub',$1,false)",[id(9104)]);await q('SET ROLE authenticated');
   try{assert.equal((await q("SELECT * FROM storage.objects WHERE name=$1",['empresa/'+id(9101)+'/synthetic.pdf'])).rowCount,1);assert.equal((await q("SELECT * FROM storage.objects WHERE name=$1",['empresa/'+id(9102)+'/synthetic.pdf'])).rowCount,0);await assert.rejects(q("INSERT INTO storage.objects(id,bucket_id,name) VALUES($1,'documentos',$2)",[id(9107),'empresa/'+id(9102)+'/new.pdf']),e=>e.code==='42501');}
   finally{await q('RESET ROLE');}
   assert.deepEqual((await q("SELECT c.relname,c.relowner,c.relrowsecurity,c.relacl FROM pg_class c WHERE c.oid IN('storage.objects'::regclass,'storage.buckets'::regclass) ORDER BY c.relname")).rows,initial);
   assert.equal((await q('SELECT current_user')).rows[0].current_user,'postgres');
   assert.equal((await q("SELECT has_schema_privilege('supabase_storage_admin','primeline_documentos_rh_privado','USAGE') v")).rows[0].v,false);
   assert.equal((await q("SELECT count(*)::int n FROM pg_policies WHERE schemaname='storage' AND coalesce(qual,with_check) LIKE '%objeto_empresa%'")).rows[0].n,18);
   assert.deepEqual(await backupDigest(),before);
  });
  await t.test('final gate rejects original-backup metadata drift without accepting new evidence',async()=>{
   await q('CREATE INDEX local_backup_drift ON primeline_documentos_rh_backup.objects(id)');
   await assert.rejects(q(await read('../supabase/documentos_rh_tenant_postcheck.sql')),/DOCUMENT_ORIGINAL_BACKUP_CHANGED/);await q('ROLLBACK');
   await q('DROP INDEX primeline_documentos_rh_backup.local_backup_drift');await q(await read('../supabase/documentos_rh_tenant_postcheck.sql'));assert.deepEqual(await backupDigest(),before);
  });
  await t.test('normal non-superuser executes full Folha sequence and safe reverse sequence',async()=>{
   for(const name of ['folha_ponto_v2_precheck','folha_ponto_v2_backup','folha_ponto_v2','folha_ponto_v2_gestao','folha_ponto_v2_postcheck'])await q(await read('../supabase/'+name+'.sql'));
   for(const name of ['folha_ponto_v2_gestao_rollback','folha_ponto_v2_rollback','documentos_rh_tenant_postcheck','documentos_rh_tenant_rollback','documentos_rh_tenant_rollback_postcheck'])await q(await read('../supabase/'+name+'.sql'));
   assert.deepEqual(await backupDigest(),before);assert.equal((await q('SELECT current_user')).rows[0].current_user,'postgres');
  });
 }finally{if(bootstrap)await bootstrap.end();if(db)await db.end();if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
