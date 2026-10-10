// Bootstrap below is copied from the existing synthetic rollout fixture; no real data.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
const require=createRequire(import.meta.url),bin=process.env.QUADRO_PG_BIN,deps=process.env.QUADRO_TEST_DEPS;
const read=async p=>(await readFile(new URL(p,import.meta.url),'utf8')).replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
const meta=JSON.parse(await read('./fixtures/quadro-funcoes-instaladas.json'));
const migration=await read('../supabase/quadro_controlado_fase_a.sql'),postFinal=await read('../supabase/quadro_controlado_fase_b_postcheck.sql');
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
function run(name,args){const r=spawnSync(join(bin,name+(process.platform==='win32'?'.exe':'')),args,{encoding:'utf8',timeout:60000,windowsHide:true,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,name+': '+(r.error?.message||r.stderr));return r.stdout;}
const result=p=>p.then(value=>({value}),error=>({error}));
test('Focused gate and legacy cutover chain',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client,types}=require(join(deps,'pg'));types.setTypeParser(1082,value=>value);const folder=await mkdtemp(join(tmpdir(),'primeline-quadro-pg176-')),data=join(folder,'data');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false;const clients=[];
 async function connect(database='postgres'){const c=new Client({host:'127.0.0.1',port,user:'postgres',database,password:'',ssl:false});await c.connect();clients.push(c);return c;}
 try {
 run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
 const admin=await connect(),a=await connect(),b=await connect(),q=(s,p=[])=>admin.query(s,p);
 await q(await read('./fixtures/quadro-base.sql'));await q(JSON.parse(await read('./fixtures/quadro-alertas-indice-real.json')).index.definition);await q('GRANT SELECT ON alertas TO authenticated');
 // Funções realmente instaladas, sem dados reais. Helpers periféricos não exercitados são stubs explícitos na fixture.
 const all=[...meta.functions,...meta.rhFunctions];const unique=new Map(all.map(f=>[f.signature,f]));
 for(const f of unique.values()){await q(f.definition);if(f.acl){await q('REVOKE ALL ON FUNCTION '+f.signature+' FROM PUBLIC,anon,authenticated,service_role');for(const acl of f.acl){const grantee=acl.slice(0,acl.indexOf('='));if(acl.includes('=X/'))await q('GRANT EXECUTE ON FUNCTION '+f.signature+' TO '+(grantee||'PUBLIC'));}}}
 await q('INSERT INTO empresas VALUES($1),($2)',[id(1),id(2)]);
 for(const [n,role,company] of [[10,'administrativo',1],[11,'gerencia',1],[12,'gestao_plataforma',1],[13,'encarregado',1],[14,'diretor_obra',1],[15,'adjunto',1],[16,'preparador',1],[17,'administrativo',2],[18,'encarregado',1]])
  await q('INSERT INTO utilizadores(id,empresa_id,nome,email,funcao,ativo,auth_user_id) VALUES($1,$2,$3,$4,$5,true,$1)',[id(n),id(company),'Perfil sintético '+n,'user'+n+'@synthetic.test',role]);
 for(let n=20;n<=49;n++)await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,$3,'Pedreiro','2026-01-01')",[id(n),id(n===49?2:1),'Pessoa sintética '+n]);
 for(const [n,user] of [[60,14],[61,15],[62,16]])await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao,utilizador_id) VALUES($1,$2,$3,'Cargo formal distinto','2026-01-01',$4)",[id(n),id(1),'Próprio sintético '+n,id(user)]);
 for(const [n,company] of [[100,1],[101,1],[102,1],[103,2]])await q("INSERT INTO obras(id,empresa_id,numero,nome,tipo) VALUES($1,$2,$3,$4,'reabilitacao')",[id(n),id(company),n,'Destino sintético '+n]);
 for(const [user,role,work] of [[13,'encarregado',100],[13,'encarregado',101],[18,'encarregado',102],[14,'diretor_obra',100],[15,'adjunto',100],[16,'preparador',100]])await q('INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,$3)',[id(work),id(user),role]);
 for(let n=0;n<227;n++)await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,'2026-01-01','2026-01-01'::date+$4::integer,'dia_inteiro',$5)",[id(1000+n),id(20),id(100),n,id(10)]);
 // Conflitos legados deliberados; a migration não os corrige.
 await q("UPDATE quadro_pessoal_alocacao SET colaborador_id=$1,data='2026-09-29' WHERE id IN($2,$3)",[id(21),id(1000),id(1001)]);
 await q('UPDATE quadro_pessoal_alocacao SET obra_id=$1 WHERE id=$2',[id(101),id(1001)]);
 for(let n=0;n<98;n++)await q("INSERT INTO quadro_pessoal_movimentos(id,empresa_id,colaborador_id,data,acao) VALUES($1,$2,$3,'2026-09-01','adicionada')",[id(2000+n),id(1),id(20)]);
 await q("INSERT INTO ausencias(colaborador_id,data,tipo,estado) VALUES($1,'2026-09-29','ferias','confirmada'),($2,'2026-01-03','falta_injustificada','ausente_pendente')",[id(21),id(20)]);
 // Todos os seis triggers instalados, com auditoria e alertas sintéticos.
 const guards=meta.tables.find(x=>x.name==='quadro_pessoal_alocacao').triggers;
 for(const trigger of guards)await q(trigger.function);
 for(const trigger of guards)await q(trigger.definition);
 for(const table of meta.tables.filter(x=>['quadro_pessoal_alocacao','quadro_pessoal_movimentos'].includes(x.name))){
 await q('ALTER TABLE '+table.name+' ENABLE ROW LEVEL SECURITY');
 await q('GRANT SELECT,INSERT,UPDATE,DELETE ON '+table.name+' TO authenticated');
 for(const p of table.policies||[])await q(`CREATE POLICY "${p.policyname}" ON ${table.name} FOR ${p.cmd} TO authenticated${p.qual?' USING ('+p.qual+')':''}${p.with_check?' WITH CHECK ('+p.with_check+')':''}`);
 }
 await q(await read('../supabase/quadro_controlado_backup.sql')); await q(migration);
 await q(`CREATE TABLE fornecedores(id uuid PRIMARY KEY,empresa_id uuid,nome text);
 CREATE TABLE subempreitadas(id uuid PRIMARY KEY,obra_id uuid,fornecedor_id uuid);
 CREATE TABLE horas_extraordinarias(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),colaborador_id uuid,data date);
 INSERT INTO fornecedores VALUES('${id(300)}','${id(1)}','Fornecedor sintético'),('${id(301)}','${id(2)}','Outro tenant');
 INSERT INTO subempreitadas VALUES('${id(302)}','${id(100)}','${id(300)}');`);
 await q(`CREATE TABLE fases(id uuid PRIMARY KEY,obra_id uuid);
 CREATE TABLE planeamento_itens(id uuid PRIMARY KEY,fase_id uuid,estado text,arquivado_em timestamptz);
 INSERT INTO fases VALUES('${id(500)}','${id(100)}');
 INSERT INTO planeamento_itens VALUES('${id(501)}','${id(500)}','em_execucao',NULL);`);
 await q('CREATE TABLE ausencias_anexos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),ausencia_id uuid NOT NULL REFERENCES ausencias(id),arquivo_url text NOT NULL,nome_arquivo text NOT NULL,criado_em timestamptz NOT NULL DEFAULT now())');
 // Main-compatible documentary layer; synthetic private Storage catalog only.
 await q(`CREATE TABLE viaturas(id uuid PRIMARY KEY,empresa_id uuid);
 CREATE TABLE documentos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),empresa_id uuid,entidade_tipo text,entidade_id uuid,nome_arquivo text);
 CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean);INSERT INTO storage.buckets VALUES('documentos',false);
 CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text,name text);
 ALTER TABLE documentos ENABLE ROW LEVEL SECURITY;ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
 GRANT USAGE ON SCHEMA storage TO authenticated;GRANT SELECT,INSERT,UPDATE,DELETE ON documentos,storage.objects TO authenticated;
 CREATE POLICY pl_documentos_rh ON documentos FOR ALL TO authenticated USING(fn_e_administrativo()) WITH CHECK(fn_e_administrativo());
 CREATE POLICY storage_rh ON storage.objects FOR SELECT TO authenticated USING(bucket_id='documentos' AND fn_e_administrativo());`);
 await q(await read('./fixtures/documentos-rh-correlatos-base.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-baseline.sql'));
 await q(await read('./fixtures/documentos-rh-rpc-correlatos-baseline.sql'));
 await q(await read('./fixtures/documentos-rh-storage-hosted-owner.sql'));
 for(const step of ['precheck','backup','','intermediate_postcheck'])await q(await read('../supabase/documentos_rh_tenant'+(step?'_'+step:'')+'.sql'));
 await q(await read('./fixtures/documentos-rh-storage-dashboard-policy.sql'));await q(await read('../supabase/documentos_rh_tenant_postcheck.sql'));
 await q(`CREATE FUNCTION fn_encarregado_acesso_direto_bloqueado() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT EXISTS(SELECT 1 FROM utilizadores WHERE id=fn_utilizador_atual_id() AND funcao='encarregado') $$;
 CREATE POLICY encarregado_sem_dml_direto ON quadro_pessoal_alocacao AS RESTRICTIVE FOR ALL TO authenticated USING(NOT fn_encarregado_acesso_direto_bloqueado()) WITH CHECK(NOT fn_encarregado_acesso_direto_bloqueado());`);
 await q(await read('../supabase/folha_ponto_v2_backup.sql'));
 await q(await read('../supabase/folha_ponto_v2.sql'));
 await q(await read('../supabase/folha_ponto_v2_gestao.sql'));
 await q(await read('../supabase/folha_ponto_v2_postcheck.sql'));

 const gate=await read('../supabase/pacote2_gate_pre_cutover.sql');
 const pre=await read('../supabase/folha_v2_legacy_cutover_precheck.sql');
 const cut=await read('../supabase/folha_v2_legacy_cutover.sql');
 const post=await read('../supabase/folha_v2_legacy_cutover_postcheck.sql');
 const rollback=await read('../supabase/folha_v2_legacy_cutover_rollback.sql');
 const start=pre.lastIndexOf('actual:=(')+9;
 const catalogSql=pre.slice(start,pre.indexOf('\n IF actual IS DISTINCT',start)).replace(/\);\s*$/,'');
 const {createHash}=await import('node:crypto');
 const manifest=JSON.parse(await read('../docs/pacote-2-frontend-assets-20261007.json'));
 const hash=createHash('sha256').update(manifest.files.slice().sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0).map(f=>f.path+'\t'+f.sha256+'\n').join(''),'utf8').digest('hex');
 const status=r=>(Array.isArray(r)?r:[r]).flatMap(x=>x.rows||[]).map(x=>x.status);
 const refuses=async(sql,pattern)=>{try{await assert.rejects(q(sql),pattern);}finally{await q('ROLLBACK');}};

 await t.test('gate creation: exact catalog, real manifest fingerprint, single private row',async()=>{
  assert.ok(status(await q(gate)).includes('PACOTE2_GATE_PRE_CUTOVER_OK'));
  const rows=(await q('SELECT * FROM primeline_pacote2_gate.aprovacao')).rows;
  assert.equal(rows.length,1);assert.equal(rows[0].frontend_assets_sha256,hash);
  assert.deepEqual(rows[0].expected_catalog,(await q(catalogSql)).rows[0].jsonb_build_object);
  assert.equal((await q("SELECT relrowsecurity FROM pg_class WHERE oid='primeline_pacote2_gate.aprovacao'::regclass")).rows[0].relrowsecurity,true);
  for(const role of ['anon','authenticated','service_role'])assert.equal((await q("SELECT has_schema_privilege($1,'primeline_pacote2_gate','USAGE') OR has_table_privilege($1,'primeline_pacote2_gate.aprovacao','SELECT,INSERT,UPDATE,DELETE') AS exposed",[role])).rows[0].exposed,false);
 });
 const saved=(await q('SELECT * FROM primeline_pacote2_gate.aprovacao')).rows[0];
 await t.test('identical existing gate reused without any mutation',async()=>{await q(gate);assert.deepEqual((await q('SELECT * FROM primeline_pacote2_gate.aprovacao')).rows[0],saved);});
 if(!process.env.GATE_SMOKE_ONLY){
  for(const [name,change] of [
   ['stale catalog',"expected_catalog='{}'"],['wrong installation',"installation_id='wrong'"],
   ['frontend false','frontend_validated=false'],['backend false','backend_v2_validated=false'],
   ['invalid hash',"frontend_assets_sha256='invalid'"],['different valid hash',"frontend_assets_sha256=repeat('a',64)"],
   ['consumed gate','consumed_at=now()'],['future review',"reviewed_at=now()+interval '1 day'"]]){
   await t.test(name+' rejected by reusable gate and precheck',async()=>{
    await q('UPDATE primeline_pacote2_gate.aprovacao SET '+change);
    await refuses(gate,/GATE_APPROVAL_MISMATCH/);
    // The unchanged cutover precheck validates hash format. The dedicated gate
    // additionally binds it to the exact published manifest fingerprint.
    if(name==='different valid hash')assert.ok(status(await q(pre)).includes('LEGACY_CUTOVER_PRECHECK_OK'));
    else await refuses(pre,/POST_HOTFIX|INSTALLATION_MISMATCH/);
    await q('UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1,installation_id=$2,frontend_validated=true,backend_v2_validated=true,frontend_assets_sha256=$3,consumed_at=NULL,reviewed_at=$4',[saved.expected_catalog,saved.installation_id,hash,saved.reviewed_at]);
   });
  }
  await t.test('unexpected grant and missing RLS rejected',async()=>{
   await q('GRANT SELECT ON primeline_pacote2_gate.aprovacao TO authenticated');await refuses(gate,/GATE_NOT_PRIVATE/);await refuses(pre,/GATE_NOT_PRIVATE/);await q('REVOKE SELECT ON primeline_pacote2_gate.aprovacao FROM authenticated');
   await q('ALTER TABLE primeline_pacote2_gate.aprovacao DISABLE ROW LEVEL SECURITY');await refuses(gate,/GATE_NOT_PRIVATE/);await q('ALTER TABLE primeline_pacote2_gate.aprovacao ENABLE ROW LEVEL SECURITY');
  });
  await t.test('multiple gate rows rejected without overwrite',async()=>{
   await q('INSERT INTO primeline_pacote2_gate.aprovacao SELECT * FROM primeline_pacote2_gate.aprovacao');await refuses(gate,/GATE_APPROVAL_MISMATCH/);await refuses(pre,/POST_HOTFIX_VALIDATION_REQUIRED/);
   await q('DELETE FROM primeline_pacote2_gate.aprovacao WHERE ctid IN(SELECT ctid FROM primeline_pacote2_gate.aprovacao OFFSET 1)');
  });
  await t.test('legacy/V2 collision refused without creating cutover',async()=>{
   await q(`INSERT INTO ponto_pessoal_obra(empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES('${id(1)}','${id(100)}','${id(30)}','2026-09-25','presente','${id(10)}');
   INSERT INTO folha_registos(empresa_id,obra_id,data,colaborador_id,intervals,minutes,estado,special_day,revision,criado_por,atualizado_por,request_id) VALUES('${id(1)}','${id(100)}','2026-09-25','${id(30)}','[{"start":"09:00","end":"13:00"}]',240,'registered',false,1,'${id(10)}','${id(10)}','${id(9999)}');`);
   await refuses(pre,/LEGACY_V2_CONFLICT/);assert.equal((await q("SELECT to_regclass('folha_privado.legacy_cutover') IS NULL absent")).rows[0].absent,true);
   await q('DELETE FROM folha_registos;DELETE FROM folha_historico;DELETE FROM folha_gestao_historico;DELETE FROM ponto_pessoal_obra;');
  });
 }
 await t.test('exact precheck → cutover → postcheck',async()=>{
  assert.ok(status(await q(pre)).includes('LEGACY_CUTOVER_PRECHECK_OK'));await q(cut);
  assert.ok(status(await q(post)).includes('LEGACY_CUTOVER_POSTCHECK_OK'));
 });
 await t.test('four writes closed with 42501; SELECT and unconsumed gate preserved',async()=>{
  for(const sql of ['INSERT INTO ponto_pessoal_obra DEFAULT VALUES','UPDATE ponto_pessoal_obra SET horas=0','DELETE FROM ponto_pessoal_obra','TRUNCATE ponto_pessoal_obra']){
   await q('BEGIN');await refuses(sql,e=>e.code==='42501'&&e.message==='LEGACY_WRITER_CLOSED: use Folha de Ponto V2');
  }
  assert.equal((await q('SELECT count(*)::int n FROM ponto_pessoal_obra')).rows[0].n,0);
  assert.equal((await q('SELECT consumed_at FROM primeline_pacote2_gate.aprovacao')).rows[0].consumed_at,null);
 });
 if(!process.env.GATE_SMOKE_ONLY){
  await t.test('already cut over refused; altered snapshot/helper/trigger detected',async()=>{
   await refuses(pre,/POST_HOTFIX_CATALOG_DRIFT|CUTOVER_STATE_INVALID/);
   await refuses(cut,/POST_HOTFIX_CATALOG_DRIFT|CUTOVER_STATE_INVALID/);
   await q(`INSERT INTO folha_privado.legacy_cutover(empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES('${id(1)}','${id(100)}','${id(30)}','2026-09-25','presente','${id(10)}')`);await refuses(post,/LEGACY_DATA_CHANGED/);await q('DELETE FROM folha_privado.legacy_cutover');
   const helper=(await q("SELECT pg_get_functiondef('folha_privado.legacy_closed()'::regprocedure) def")).rows[0].def;
   await q("CREATE OR REPLACE FUNCTION folha_privado.legacy_closed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$ BEGIN RETURN NULL; END $$");await refuses(post,/CUTOVER_HELPER_BODY_DRIFT/);await q(helper);
   await q('ALTER TABLE ponto_pessoal_obra DISABLE TRIGGER trg_01_folha_legacy_closed');await refuses(post,/LEGACY_WRITER_NOT_CLOSED/);await q('ALTER TABLE ponto_pessoal_obra ENABLE TRIGGER trg_01_folha_legacy_closed');
  });
  await t.test('rollback rejects V2 facts; empty rollback preserves data and permits exact replay',async()=>{
   await q(`INSERT INTO folha_registos(empresa_id,obra_id,data,colaborador_id,intervals,minutes,estado,special_day,revision,criado_por,atualizado_por,request_id) VALUES('${id(1)}','${id(100)}','2026-09-25','${id(30)}','[{"start":"09:00","end":"13:00"}]',240,'registered',false,1,'${id(10)}','${id(10)}','${id(9998)}')`);
   await refuses(rollback,/ROLLBACK_V2_FACTS_PRESENT/);await q('DELETE FROM folha_registos;DELETE FROM folha_historico;DELETE FROM folha_gestao_historico;');
   await q(rollback);assert.equal((await q("SELECT to_regclass('folha_privado.legacy_cutover') IS NULL absent")).rows[0].absent,true);
   await q(gate);await q(pre);await q(cut);await q(post);
  });
 }
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
