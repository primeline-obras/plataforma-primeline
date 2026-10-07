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
test('AUDIT: rollout prerequisites and read-only collector',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 for(const step of ['precheck','backup','','postcheck'])await q(await read('../supabase/documentos_rh_tenant'+(step?'_'+step:'')+'.sql'));
 await q(await read('../supabase/folha_ponto_v2_backup.sql'));
 await q(await read('../supabase/folha_ponto_v2.sql'));
 await q(await read('../supabase/folha_ponto_v2_gestao.sql'));
 await q(await read('../supabase/folha_ponto_v2_postcheck.sql'));
 await admin.query("SELECT set_config('test.actor',$1,false)",[id(10)]);
 const today=(await q("SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date::text d")).rows[0].d;
 const day='2026-09-25';
 await q(`INSERT INTO folha_horarios VALUES('${id(100)}','${id(1)}','[{"period":"manha","start":"09:00","end":"13:00"},{"period":"tarde","start":"14:00","end":"18:00"}]',480,1);
 INSERT INTO folha_config_empresa(empresa_id,correction_days) VALUES('${id(1)}',1);`);
 let seq=9000;
 const key=(person=30,date=day,kind='primeline',work=100)=>({person_id:id(person),work_id:id(work),date,kind});
 const sheet=(person=30,date=day)=>({version:2,request_id:id(seq++),work_id:id(100),date,key:key(person,date),expected_revision:0,intervals:[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}],reason:null});
 const alloc=(person=30,date=day)=>({version:2,request_id:id(seq++),work_id:id(100),date,person_id:id(person),period:'dia_inteiro',expected_allocation_revision:0});
 async function as(c,user,sql,params=[]){await c.query("SELECT set_config('test.actor',$1,false)",[id(user)]);await c.query('SET ROLE authenticated');try{return (await c.query(sql,params)).rows[0]?.v;}finally{await c.query('RESET ROLE');}}
 const call=(c,user,action,d,confirm=false,token=null)=>as(c,user,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',[action,action==='save'||action==='bulk'?{...d,reason:d.reason||'Correção sintética administrativa',...(d.items?{items:d.items.map(x=>({...x,reason:x.reason||'Correção sintética administrativa'}))}:{})}:d,confirm,token]);
 const perform=async(user,action,d)=>{const p=await call(a,user,action,d);assert.equal(p.committed,false);return call(a,user,action,d,true,p.versao);};
 const count=async(table)=>(await q(`SELECT count(*)::int n FROM ${table}`)).rows[0].n;
 const pre=await read('../supabase/quadro_fase_b_pos_hotfix_precheck.sql');
 await q(`CREATE FUNCTION fn_encarregado_acesso_direto_bloqueado() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT EXISTS(SELECT 1 FROM utilizadores WHERE id=fn_utilizador_atual_id() AND funcao='encarregado') $$;
 CREATE POLICY encarregado_sem_dml_direto ON quadro_pessoal_alocacao AS RESTRICTIVE FOR ALL TO authenticated USING(NOT fn_encarregado_acesso_direto_bloqueado()) WITH CHECK(NOT fn_encarregado_acesso_direto_bloqueado());
 CREATE SCHEMA primeline_pacote2_gate;REVOKE ALL ON SCHEMA primeline_pacote2_gate FROM PUBLIC,anon,authenticated,service_role;
 CREATE TABLE primeline_pacote2_gate.aprovacao(release_id text,reviewed_by text,reviewed_at timestamptz,consumed_at timestamptz,frontend_assets_sha256 text,frontend_validated boolean,backend_v2_validated boolean,installation_id text,expected_catalog jsonb);
 ALTER TABLE primeline_pacote2_gate.aprovacao ENABLE ROW LEVEL SECURITY;
 REVOKE ALL ON primeline_pacote2_gate.aprovacao FROM PUBLIC,anon,authenticated,service_role;`);
 const catalogSql=pre.slice(pre.lastIndexOf('actual:=(')+9,pre.lastIndexOf('\n IF actual IS DISTINCT')).replace(/\);\s*$/,'');
 const catalog=(await q(catalogSql)).rows[0].jsonb_build_object;
 await q("INSERT INTO primeline_pacote2_gate.aprovacao VALUES('pacote2_folha_v2_20261005','postgres',now(),NULL,$1,true,true,(SELECT instalacao_id::text FROM primeline_quadro_rollout.controlo WHERE singleton),$2)",['0'.repeat(64),catalog]);
 await t.test('B must refuse while legacy writer remains open',async()=>{
  assert.equal((await q("SELECT to_regprocedure('folha_privado.legacy_closed()') IS NULL missing")).rows[0].missing,true);
  try{await assert.rejects(q(pre),/CUTOVER|LEGACY/);}finally{await q('ROLLBACK');}
 });
 const collector=await read('../supabase/pacote2_validacao_real_final_readonly.sql');
 async function collect(){const notices=[];const listener=n=>notices.push(n.message);admin.on('notice',listener);try{const result=await q(collector);const rows=(Array.isArray(result)?result:[result]).flatMap(r=>r.rows||[]);const catalog=rows.find(r=>r.readonly_catalog)?.readonly_catalog;delete catalog.environment.at;return {catalog,notices};}finally{admin.off('notice',listener);}}
 await t.test('collector must distinguish approved catalog from stale approval',async()=>{
  const before=await collect();await q("UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog='{}'");
  try{const after=await collect();assert.notDeepEqual(after,before,'Stale gate fingerprint is invisible in collector output');}finally{await q('UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1',[catalog]);}
 });
 await t.test('B rejects stale signature and unapproved table grant',async()=>{
  await q("UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog='{}'");try{await assert.rejects(q(pre),/POST_HOTFIX_CATALOG_DRIFT|CUTOVER_REQUIRED/);}finally{await q('ROLLBACK');await q('UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1',[catalog]);}
  await q('GRANT UPDATE ON folha_registos TO authenticated');try{await assert.rejects(q(pre),/POST_HOTFIX_CATALOG_DRIFT|CUTOVER_REQUIRED/);}finally{await q('ROLLBACK');await q('REVOKE UPDATE ON folha_registos FROM authenticated');}
 });
 await t.test('collector distinguishes old policy, incomplete calendar, writer and catalog drift',async()=>{
  const before=await collect();
  const installed=(await q("SELECT qual FROM pg_policies WHERE policyname='pl_documentos_rh' AND schemaname='public' AND tablename='documentos'")).rows[0].qual;
  const original=(await q("SELECT qual FROM primeline_documentos_rh_backup.policies WHERE policyname='pl_documentos_rh' AND tablename='documentos'")).rows[0].qual;
  for(const [change,undo] of [
   ['ALTER POLICY pl_documentos_rh ON documentos USING('+original+')','ALTER POLICY pl_documentos_rh ON documentos USING('+installed+')'],
   ["UPDATE folha_config_empresa SET calendar_complete=true,calendar_validated_years=ARRAY[2026]","UPDATE folha_config_empresa SET calendar_complete=false,calendar_validated_years=ARRAY[]::integer[]"],
   ["CREATE FUNCTION folha_privado.legacy_closed() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'AUDIT_ONLY'; END $$",'DROP FUNCTION folha_privado.legacy_closed()'],
   ['GRANT UPDATE ON folha_registos TO authenticated','REVOKE UPDATE ON folha_registos FROM authenticated']
  ]) {await q(change);try{assert.notDeepEqual(await collect(),before);}finally{await q(undo);}assert.deepEqual(await collect(),before);}
 }); await t.test('cutover → refreshed approval → B → rollback preserves closed writer',async()=>{
  // Restore exact documentary expression after the collector mutation.
  const doc=(await q('SELECT catalogo FROM primeline_documentos_rh_backup.instalacao')).rows[0].catalogo;
  const policy=doc.policies.find(p=>p.policyname==='rh_empresa_guard');await q('ALTER POLICY rh_empresa_guard ON documentos USING('+policy.qual+')');
  await q('UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1',[(await q(catalogSql)).rows[0].jsonb_build_object]);
  await q(await read('../supabase/folha_v2_legacy_cutover_precheck.sql'));
  await q(await read('../supabase/folha_v2_legacy_cutover.sql'));await q(await read('../supabase/folha_v2_legacy_cutover_postcheck.sql'));
  try{await assert.rejects(q(pre),/POST_HOTFIX_CATALOG_DRIFT|CUTOVER_REQUIRED/);}finally{await q('ROLLBACK');}
  await q('UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1',[(await q(catalogSql)).rows[0].jsonb_build_object]);
  const readiness=async()=>JSON.parse((await collect()).notices.find(n=>n.startsWith('READINESS_AGGREGATE: ')).slice('READINESS_AGGREGATE: '.length)).phase_b_approval;
  assert.equal((await readiness()).state,'MATCH');
  const savedApproval=(await q('SELECT to_jsonb(x) value FROM primeline_pacote2_gate.aprovacao x')).rows[0].value;
  for(const [mutation,expectedState,undo,params=[]] of [
   ["UPDATE primeline_pacote2_gate.aprovacao SET installation_id='wrong-installation'",'INCOMPATIBLE','UPDATE primeline_pacote2_gate.aprovacao SET installation_id=$1',[savedApproval.installation_id]],
   ['GRANT SELECT ON primeline_pacote2_gate.aprovacao TO authenticated','INCOMPATIBLE','REVOKE SELECT ON primeline_pacote2_gate.aprovacao FROM authenticated'],
   ['UPDATE primeline_pacote2_gate.aprovacao SET consumed_at=now()','INCOMPATIBLE','UPDATE primeline_pacote2_gate.aprovacao SET consumed_at=NULL'],
   ["UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog='{}'",'STALE','UPDATE primeline_pacote2_gate.aprovacao SET expected_catalog=$1',[savedApproval.expected_catalog]],
   ['DELETE FROM primeline_pacote2_gate.aprovacao','ABSENT','INSERT INTO primeline_pacote2_gate.aprovacao SELECT * FROM jsonb_populate_record(NULL::primeline_pacote2_gate.aprovacao,$1)',[savedApproval]],
   ['ALTER TABLE primeline_pacote2_gate.aprovacao RENAME TO audit_saved_approval','ABSENT','ALTER TABLE primeline_pacote2_gate.audit_saved_approval RENAME TO aprovacao'],
   ['GRANT UPDATE ON folha_registos TO authenticated','STALE','REVOKE UPDATE ON folha_registos FROM authenticated'],
   ['ALTER TABLE ponto_pessoal_obra DISABLE TRIGGER trg_01_folha_legacy_closed','STALE','ALTER TABLE ponto_pessoal_obra ENABLE TRIGGER trg_01_folha_legacy_closed']
  ]) {
   await q(mutation);try {assert.equal((await readiness()).state,expectedState);}finally{await q('ROLLBACK');await q(undo,params);}
  }
  for(const mutation of [
   'DROP TRIGGER trg_01_folha_legacy_closed ON ponto_pessoal_obra',
   'ALTER TABLE ponto_pessoal_obra DISABLE TRIGGER trg_01_folha_legacy_closed',
   "ALTER FUNCTION folha_privado.legacy_closed() SECURITY INVOKER",
   'GRANT SELECT ON folha_privado.legacy_cutover TO authenticated'
  ]) {
   await q('BEGIN');try {await q(mutation);await assert.rejects(q(pre),/LEGACY|CUTOVER/);}finally{await q('ROLLBACK');}
  }
  await q(pre);await q(await read('../supabase/quadro_fase_b_pos_hotfix_backup.sql'));await q(await read('../supabase/quadro_fase_b_pos_hotfix_migration.sql'));await q(await read('../supabase/quadro_fase_b_pos_hotfix_postcheck.sql'));
  await q(await read('../supabase/quadro_fase_b_pos_hotfix_rollback.sql'));await q(await read('../supabase/folha_v2_legacy_cutover_postcheck.sql'));
  await q(await read('../supabase/folha_v2_legacy_cutover_rollback.sql'));
 });
 await t.test('management rollback must refuse an in-flight legitimate payroll commit',async()=>{
  await a.query('BEGIN');
  const data={version:2,request_id:id(97001),expected_revision:0,person_id:id(30),month:'2026-09-01',manual:{km:0,allowance:0,note:'Synthetic audit'}};
  const p=await as(a,10,'SELECT fn_folha_gestao_v2($1,$2,false,NULL) v',['payroll_save',data]);
  const committed=await as(a,10,'SELECT fn_folha_gestao_v2($1,$2,true,$3) v',['payroll_save',data,p.versao]);assert.equal(committed.committed,true);
  const rollbackSql=await read('../supabase/folha_ponto_v2_gestao_rollback.sql');
  await b.query("SET statement_timeout='10s'");
  const pending=result(b.query(rollbackSql));
  let blocked=false;
  for(let n=0;n<100;n++){const r=await q('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[b.processID]);if(r.rows[0].blocked){blocked=true;break;}await delay(25);}
  assert.equal(blocked,true,'Rollback must reach an observable lock wait');
  await a.query('COMMIT');const outcome=await pending;await b.query('ROLLBACK');
  const retained=(await q("SELECT to_regclass('public.folha_vencimentos') IS NOT NULL retained" )).rows[0].retained;
  console.log('AUDIT_ROLLBACK_PAYROLL_TABLE_RETAINED='+retained);
  assert.ok(outcome.error,'Rollback completed after the checked tables gained committed payroll facts; payroll table retained='+retained);
  assert.match(outcome.error.message,/ROLLBACK_DATA_PRESENT|lock timeout|statement timeout/);
  assert.equal((await q('SELECT count(*)::int n FROM folha_vencimentos')).rows[0].n,1);
 }); }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
