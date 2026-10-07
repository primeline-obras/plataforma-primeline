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
test('AUDIT: rollback dependency continuity',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 async function as(c,user,sql,params=[]){await c.query("SELECT set_config('test.actor',$1,false)",[id(user)]);await c.query('SET ROLE authenticated');try{return (await c.query(sql,params)).rows[0]?.v;}catch(error){await c.query('ROLLBACK');throw error;}finally{await c.query('RESET ROLE');}}
 const call=(c,user,action,d,confirm=false,token=null)=>as(c,user,'SELECT fn_folha_operar_v2($1,$2,$3,$4) v',[action,action==='save'||action==='bulk'?{...d,reason:d.reason||'Correção sintética administrativa',...(d.items?{items:d.items.map(x=>({...x,reason:x.reason||'Correção sintética administrativa'}))}:{})}:d,confirm,token]);
 const perform=async(user,action,d)=>{const p=await call(a,user,action,d);assert.equal(p.committed,false);return call(a,user,action,d,true,p.versao);};
 const count=async(table)=>(await q(`SELECT count(*)::int n FROM ${table}`)).rows[0].n;
 await t.test('management rollback preserves standalone vacation revision and administrative replay evidence',async()=>{
  for(const [insert,check] of [
   ["INSERT INTO folha_ferias_revisoes VALUES('"+id(1)+"','"+id(30)+"',1)",'SELECT count(*)::int n FROM folha_ferias_revisoes'],
   ["INSERT INTO folha_privado.operacoes(empresa_id,ator_id,request_id,payload,token,resultado) VALUES('"+id(1)+"','"+id(10)+"','"+id(98999)+"','{\"contract\":\"gestao_v2\"}','synthetic','{}')","SELECT count(*)::int n FROM folha_privado.operacoes WHERE payload->>'contract'='gestao_v2'"]
  ]) {
   await q(insert);
   try {await assert.rejects(q(await read('../supabase/folha_ponto_v2_gestao_rollback.sql')),/ROLLBACK_DATA_PRESENT/);}
   finally {await q('ROLLBACK');}
   assert.equal((await q(check)).rows[0].n,1);
   await q('TRUNCATE folha_ferias_revisoes,folha_privado.operacoes');
  }
 });
 await q(await read('../supabase/folha_ponto_v2_gestao_rollback.sql'));
 await q('TRUNCATE folha_config_empresa,folha_horarios');
 await t.test('management rollback must leave the remaining core able to commit a legitimate sheet',async()=>{
  await a.query('BEGIN');
  const payload={version:2,request_id:id(98001),work_id:null,date:day,key:{person_id:id(30),work_id:null,date:day,kind:'primeline'},expected_revision:0,intervals:[{start:'09:00',end:'17:00'}],reason:'Synthetic concurrency audit'};
  const p=await as(a,10,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['save',payload]);
  const committed=await as(a,10,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['save',payload,p.versao]);assert.equal(committed.committed,true);
  await a.query('COMMIT');
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos')).rows[0].n,1);
 });
 await t.test('core rollback waits for legitimate writer then refuses committed facts',async()=>{
  await q('TRUNCATE folha_he,folha_historico,folha_registos,folha_privado.operacoes');
  await a.query('BEGIN');
  const payload={version:2,request_id:id(98002),work_id:null,date:day,key:{person_id:id(30),work_id:null,date:day,kind:'primeline'},expected_revision:0,intervals:[{start:'09:00',end:'17:00'}],reason:'Synthetic rollback concurrency'};
  const preview=await as(a,10,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['save',payload]);
  await as(a,10,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['save',payload,preview.versao]);
  const pending=result(b.query(await read('../supabase/folha_ponto_v2_rollback.sql')));
  let blocked=false;
  for(let n=0;n<100;n++){if((await q('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[b.processID])).rows[0].blocked){blocked=true;break;}await delay(25);}
  assert.equal(blocked,true);await a.query('COMMIT');
  const outcome=await pending;await b.query('ROLLBACK');
  assert.match(outcome.error?.message||'',/ROLLBACK_DATA_PRESENT|lock timeout/);
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos')).rows[0].n,1);
 });
 await t.test('writer entering after rollback locks cannot commit a fact that is dropped',async()=>{
  await q('TRUNCATE folha_he,folha_historico,folha_registos,folha_privado.operacoes');
  await b.query('BEGIN; LOCK TABLE quadro_pessoal_alocacao IN SHARE ROW EXCLUSIVE MODE; SELECT pg_advisory_xact_lock(61001,1)');
  const payload={version:2,request_id:id(98003),work_id:null,date:day,key:{person_id:id(30),work_id:null,date:day,kind:'primeline'},expected_revision:0,intervals:[{start:'09:00',end:'17:00'}],reason:'Synthetic late writer'};
  const writing=result((async()=>{const preview=await as(a,10,'SELECT fn_folha_operar_v2($1,$2,false,NULL) v',['save',payload]);return as(a,10,'SELECT fn_folha_operar_v2($1,$2,true,$3) v',['save',payload,preview.versao]);})());
  let blocked=false;
  for(let n=0;n<100;n++){if((await q('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[a.processID])).rows[0].blocked){blocked=true;break;}await delay(25);}
  assert.equal(blocked,true);
  const removed=await result(b.query(await read('../supabase/folha_ponto_v2_rollback.sql')));await b.query('ROLLBACK');
  const written=await writing;
  if(!removed.error){assert.ok(written.error);assert.equal((await q("SELECT to_regclass('public.folha_registos') IS NULL missing")).rows[0].missing,true);}
  else {assert.equal((await q('SELECT count(*)::int n FROM folha_registos')).rows[0].n,written.error?0:1);}
 });
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
