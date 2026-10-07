import test from 'node:test';import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {createRequire} from 'node:module';import {spawnSync} from 'node:child_process';import {createServer} from 'node:net';
const require=createRequire(import.meta.url),bin=process.env.QUADRO_PG_BIN,deps=process.env.QUADRO_TEST_DEPS;
const read=p=>readFile(new URL(p,import.meta.url),'utf8'),id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
function run(name,args){const r=spawnSync(join(bin,name+'.exe'),args,{encoding:'utf8',windowsHide:true,timeout:60000,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,r.stderr||name);}
test('AUDIT: bucket security metadata must be pinned',{skip:!bin||!deps,timeout:180000},async t=>{
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
 await q(await read('../supabase/documentos_rh_tenant_precheck.sql'));await q(await read('../supabase/documentos_rh_tenant_backup.sql'));await q(await read('../supabase/documentos_rh_tenant.sql'));await q(await read('../supabase/documentos_rh_tenant_postcheck.sql'));
 // Independent negative drift cases; candidate scripts stay unchanged.
 const post=await read('../supabase/documentos_rh_tenant_postcheck.sql');
 for(const [label,mutation] of [
  ['bucket table ACL','GRANT UPDATE ON storage.buckets TO authenticated'],
  ['bucket column ACL','GRANT UPDATE(public) ON storage.buckets TO authenticated'],
  ['bucket RLS','ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY'],
  ['bucket owner','ALTER TABLE storage.buckets OWNER TO service_role'],
  ['bucket policy','ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY; CREATE POLICY audit_bucket ON storage.buckets FOR UPDATE TO authenticated USING(true) WITH CHECK(true)']
 ]) await t.test(label+' drift must fail documentary postcheck',async()=>{
  await q('BEGIN');try {await q(mutation);await assert.rejects(q(post),/DOCUMENT_CATALOG_DRIFT/);}finally{await q('ROLLBACK');}
 });
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
