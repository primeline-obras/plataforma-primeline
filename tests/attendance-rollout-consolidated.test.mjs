import {authorizationCases} from './encarregado-autorizacao-cases.mjs';
import {restCases} from './encarregado-autorizacao-rest.mjs';
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
test('consolidated rollout: reconstructed hotfix → documents → Folha; all drift gates',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client,types}=require(join(deps,'pg'));types.setTypeParser(1082,v=>v);
 const folder=await mkdtemp(join(tmpdir(),'primeline-escopo-')),data=join(folder,'data');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false,db;
 try{
  run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
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
 await t.test('final precheck returns ONE normal JSON result and recognises vulnerable known baseline',async()=>{
  const sql=await read('../supabase/pacote2_precheck_real_final_20261007.sql');
  assert.doesNotMatch(sql,/RAISE NOTICE|CREATE\s+(?:TABLE|FUNCTION|SCHEMA)|GRANT\s|REVOKE\s/i);
  const results=await q(sql);const rows=(Array.isArray(results)?results:[results]).flatMap(r=>r.rows||[]);
  assert.equal(rows.length,1);const v=rows[0].precheck_real_final;
  assert.equal(v.environment.read_only,'on');assert.equal(v.document_delete_rpc.state,'P1_KNOWN_BASELINE_READY_FOR_HOTFIX');
  assert.equal(v.verdict,'BLOCKED');assert.ok(v.blockers.length>0,'Synthetic reduced Storage/catalog must never be silently certified as real baseline');
  // Unit-check the decision engine with an explicitly SYNTHETIC expected catalog.
  // Production baseline/file is never changed and cannot be certified by this reduced fixture.
  const captured=await q(await read('../supabase/pacote2_validacao_real_final_readonly.sql'));
  const local=(Array.isArray(captured)?captured:[captured]).flatMap(r=>r.rows||[]).find(r=>r.readonly_catalog).readonly_catalog;
  for(const table of local.tables) table.indexes?.sort((a,b)=>Buffer.compare(Buffer.from(a.definition),Buffer.from(b.definition)));
  const localBaseline={functions:local.functions.map(({signature,owner,security_definer,config,acl,definition_sha256})=>({signature,owner,security_definer,config,acl,definition_sha256})),tables:local.tables};
  const literal=JSON.stringify(localBaseline).replaceAll("'","''");
  let synthetic=sql.replace(/WITH baseline AS \(SELECT '[\s\S]*?'::jsonb data\),/,()=> 'WITH baseline AS (SELECT '+"'"+literal+"'::jsonb data),");
  const localValues=local.counts.map(n=>"('"+n.relname+"',"+n.total+"::bigint)").join(',');
  synthetic=synthetic.replace(/expected_counts\(name,expected\) AS \(VALUES [\s\S]*?\),\r?\ncounts/,()=>"expected_counts(name,expected) AS (VALUES "+localValues+"),\ncounts");
  const readyRows=(await q(synthetic)).flatMap(r=>r.rows||[]);const ready=readyRows[0].precheck_real_final;
  assert.equal(ready.verdict,'READY_FOR_DOCUMENTAL_AND_V2_ROLLOUT',JSON.stringify(ready.blockers));
  assert.equal(ready.document_delete_rpc.state,'P1_KNOWN_BASELINE_READY_FOR_HOTFIX');
  await q('ALTER FUNCTION fn_apagar_documento_entidade(uuid) SECURITY INVOKER');
  try{const bad=(await q(synthetic)).flatMap(r=>r.rows||[])[0].precheck_real_final;assert.equal(bad.verdict,'BLOCKED');assert.equal(bad.document_delete_rpc.state,'DRIFT');}finally{await q('ALTER FUNCTION fn_apagar_documento_entidade(uuid) SECURITY DEFINER');}

 });
 for(const step of ['precheck','backup','','postcheck'])await q(await read('../supabase/documentos_rh_tenant'+(step?'_'+step:'')+'.sql'));
  await t.test('reviewed documentary delta composes exactly with existing hotfix',async()=>{await q(pre);});
  await t.test('unrelated table grant and incomplete documentary delta are rejected',async()=>{
   for(const sql of ['GRANT SELECT ON colaboradores TO anon','ALTER POLICY rh_empresa_guard ON documentos USING(false)','DROP POLICY rh_storage_empresa_guard ON storage.objects']) {
    await q('BEGIN');await q(sql);await assert.rejects(q(pre),/DRIFT/);await q('ROLLBACK');await q(pre);
   }
  });
  await t.test('single real-validation script is executable in a native read-only transaction',async()=>{await q(await read('../supabase/pacote2_validacao_real_final_readonly.sql'));});
  await q(await read('../supabase/folha_ponto_v2_backup.sql'));await q(await read('../supabase/folha_ponto_v2.sql'));await q(await read('../supabase/folha_ponto_v2_gestao.sql'));await q(await read('../supabase/folha_ponto_v2_postcheck.sql'));
  await t.test('Folha postcheck rejects a changed administrative helper, not just its name',async()=>{
   await q('BEGIN; ALTER FUNCTION folha_privado.adm_operacional() SECURITY INVOKER');
   await assert.rejects(q(await read('../supabase/folha_ponto_v2_postcheck.sql')),/FOLHA_FUNCTION_CATALOG_DRIFT/);await q('ROLLBACK');
   await q(await read('../supabase/folha_ponto_v2_postcheck.sql'));
   await q(await read('../supabase/pacote2_validacao_real_final_readonly.sql'));
  });
  await t.test('full empty installation and safe reverse sequence preserve the baseline',async()=>{
   await q(await read('../supabase/folha_ponto_v2_gestao_rollback.sql'));await q(await read('../supabase/folha_ponto_v2_rollback.sql'));
   await q(await read('../supabase/documentos_rh_tenant_postcheck.sql'));await q(await read('../supabase/documentos_rh_tenant_rollback.sql'));
   await q(await read('../supabase/documentos_rh_tenant_rollback_postcheck.sql'));
   await assert.rejects(q(scripts.postcheck),/POSTCHECK_CATALOG_DRIFT/);await q('ROLLBACK');
  });
 }finally{if(db)await db.end();if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
