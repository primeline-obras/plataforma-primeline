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
test('Folha v2: PostgreSQL 17.6 local, contratos e isolamento',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 await t.test('tabelas vazias, RLS e sem DML direto',async()=>{
  assert.equal(await count('folha_registos'),0);
  const rows=(await q("SELECT relname,relrowsecurity FROM pg_class WHERE relname IN('folha_registos','folha_historico','folha_externos','folha_he')")).rows;
  assert.equal(rows.length,4);assert.ok(rows.every(x=>x.relrowsecurity));
  await assert.rejects(as(a,10,'INSERT INTO folha_registos DEFAULT VALUES'),/permission denied/);
  await assert.rejects(as(a,10,"SELECT folha_privado.ator() v"),/permission denied/);
 });
 await t.test('Escritório: Diretor/Adjunto/Preparador próprios, identidade ligada e cargo formal preservado',async()=>{
  for(const [user,person] of [[14,60],[15,61],[16,62]]){
   const c=await as(a,user,'SELECT fn_folha_contexto_v2($1,NULL) v',[today]);assert.equal(c.rows.length,1);assert.equal(c.rows[0].person_id,id(person));assert.equal(c.rows[0].expected_minutes,480);
   const d={...sheet(person,today),work_id:null,key:{...key(person,today),work_id:null},intervals:[{start:'00:00',end:null}]};
   await perform(user,'save',d);const h=await as(a,user,'SELECT fn_folha_historico_v2($1) v',[d.key]);assert.equal(h.events.length,1);
   await assert.rejects(call(a,user,'save',{...d,request_id:id(seq++),key:{...d.key,person_id:id(30)}}),e=>e.code==='42501');
   await assert.rejects(call(a,user,'save',{...d,request_id:id(seq++),key:{...d.key,person_id:id(49)}}),e=>e.code==='42501');
  }
  await assert.rejects(call(a,13,'save',{...sheet(60,today),work_id:null,key:{...key(60,today),work_id:null}}),e=>e.code==='42501');
  await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(14)]);
  await assert.rejects(call(a,14,'save',{...sheet(60,today),work_id:null,key:{...key(60,today),work_id:null}}),e=>e.code==='42501');await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(14)]);
  await q('UPDATE colaboradores SET data_saida=$2 WHERE id=$1',[id(60),today]);await assert.rejects(call(a,14,'save',{...sheet(60,today),work_id:null,key:{...key(60,today),work_id:null},expected_revision:1}),e=>e.code==='42501');await q('UPDATE colaboradores SET data_saida=NULL WHERE id=$1',[id(60)]);
  await q('UPDATE colaboradores SET utilizador_id=NULL WHERE id=$1',[id(62)]);await assert.rejects(call(a,16,'save',{...sheet(62,today),work_id:null,key:{...key(62,today),work_id:null},expected_revision:1}),e=>e.code==='42501');await q('UPDATE colaboradores SET utilizador_id=$2 WHERE id=$1',[id(62),id(16)]);
 });
 await t.test('Escritório flexível: 8h deslocadas, acima sem HE, abaixo missing, unicidade NULL',async()=>{
  const d={...sheet(60),work_id:null,key:{...key(60),work_id:null},intervals:[{start:'09:15',end:'13:00'},{start:'14:00',end:'18:15'}]};
  await perform(10,'save',d);assert.equal((await q('SELECT minutes,estado FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(60),day])).rows[0].minutes,480);
  await q('UPDATE folha_config_empresa SET overtime_enabled=true,calendar_complete=true');
  await perform(10,'save',{...d,request_id:id(seq++),expected_revision:1,intervals:[{start:'09:00',end:'18:00'}]});assert.equal((await q('SELECT count(*)::int n FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(60)])).rows[0].n,0);
  await q('UPDATE folha_config_empresa SET overtime_enabled=false,calendar_complete=false');
  await perform(10,'save',{...d,request_id:id(seq++),expected_revision:2,intervals:[{start:'09:00',end:'12:00'}]});assert.equal((await q('SELECT estado FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(60),day])).rows[0].estado,'missing');
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(60),day])).rows[0].n,1);
  await assert.rejects(call(a,14,'save',{...d,request_id:id(seq++),expected_revision:3}),/CORRECTION_WINDOW_EXCEEDED/);
 });
 await t.test('contexto sem alocação anterior herdada; âmbito Encarregado',async()=>{
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[day,id(100)]);assert.equal(c.rows.length,0);assert.equal(c.works.length,2);assert.equal(c.schedule.expected_minutes,480);
  await assert.rejects(as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[day,id(103)]),/PERMISSION_DENIED/);
 });
 await t.test('contexto funciona em transação estritamente READ ONLY',async()=>{
  await a.query('BEGIN READ ONLY');
  try {const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',[day,id(100)]);assert.equal(c.work_id,id(100));}
  finally {await a.query('ROLLBACK');}
 });
 await t.test('alocar via núcleo v1; preview sem escrita, movimento e revisão',async()=>{
  const d=alloc();const n=await count('quadro_pessoal_alocacao');const p=await call(a,13,'allocate',d);assert.equal(await count('quadro_pessoal_alocacao'),n);
  const r=await call(a,13,'allocate',d,true,p.versao);assert.equal(r.committed,true);assert.equal(await count('quadro_pessoal_alocacao'),n+1);
  assert.equal((await q('SELECT revisao FROM quadro_dias_revisoes WHERE colaborador_id=$1 AND data=$2',[id(30),day])).rows[0].revisao,1);
 });
 await t.test('janela de um dia recusa retroativo do Encarregado',async()=>{await assert.rejects(call(a,13,'save',sheet()),/CORRECTION_WINDOW_EXCEEDED/);});
 await t.test('admin grava factos fechados com motivo; replay sem história duplicada',async()=>{
  const d=sheet();const r=await perform(10,'save',d);assert.equal(r.committed,true);
  const n=await count('folha_historico');const replay=await perform(10,'save',d);assert.deepEqual(replay,r);assert.equal(await count('folha_historico'),n);
  await assert.rejects(call(a,10,'save',{...d,note:'diferente'}),/IDEMPOTENCY_CONFLICT/);
  const row=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(30),day])).rows[0];assert.equal(row.minutes,480);assert.equal(row.estado,'registered');assert.equal(await count('folha_he'),0);
 });
 await t.test('correção preserva UUID, autoria, antes/depois e aumenta revisão',async()=>{
  const old=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(30),day])).rows[0];const d={...sheet(),expected_revision:1,intervals:[{start:'09:00',end:'18:00'}]};await perform(10,'save',d);
  const row=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(30),day])).rows[0];assert.equal(row.id,old.id);assert.equal(row.revision,2);assert.equal(row.criado_por,old.criado_por);
  const h=await as(a,13,'SELECT fn_folha_historico_v2($1) v',[key()]);assert.equal(h.events.length,3);assert.equal(h.events.at(-1).reason,'Correção sintética administrativa');assert.ok(h.events.at(-1).antes);
  await assert.rejects(q('DELETE FROM folha_historico'),/HISTORY_IMMUTABLE/);
 });
 await t.test('retirada com Folha existente recusa sem apagar',async()=>{const d={...alloc(),expected_allocation_revision:1,ids:(await q('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(30),day])).rows.map(x=>x.id)};await assert.rejects(call(a,13,'remove_from_day',d),/REGULARIZATION_REQUIRED/);});
 await t.test('retirada sem folha mantém histórico/movimento, replay e volta a zero',async()=>{
  await perform(13,'allocate',alloc(31));const ids=(await q('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(31),day])).rows.map(x=>x.id);
  await perform(13,'remove_from_day',{...alloc(31),expected_allocation_revision:1,ids});assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(31),day])).rows[0].n,0);
 });
 await t.test('transferência para obra própria a partir de outra obra mesma empresa',async()=>{
  await perform(10,'allocate',{...alloc(32),work_id:id(102)});
  await perform(13,'transfer',{...alloc(32),expected_allocation_revision:1,source_work_id:id(102)});
  assert.equal((await q('SELECT obra_id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(32),day])).rows[0].obra_id,id(100));
 });
 await t.test('dia normal: horário real, janela, sem futuro/sobrescrita e tudo atómico',async()=>{
  for(const n of [63,64,65])await q("INSERT INTO colaboradores(id,empresa_id,nome,data_admissao) VALUES($1,$2,'Normal sintético','2026-01-01')",[id(n),id(1)]);
  for(const n of [63,64])await perform(13,'allocate',alloc(n));
  const d={...alloc(63),operation:'normal',items:[{...sheet(63),intervals:[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}]},{...sheet(64),expected_revision:99}]};
  await assert.rejects(call(a,13,'bulk',d),/CORRECTION_WINDOW_EXCEEDED/);
  await assert.rejects(call(a,10,'bulk',d),/STALE_REVISION/);assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id IN($1,$2)',[id(63),id(64)])).rows[0].n,0);
  d.items[1].expected_revision=0;const p=await call(a,10,'bulk',d);assert.match(p.summary,/2 pessoas/);await call(a,10,'bulk',d,true,p.versao);
  await assert.rejects(call(a,10,'bulk',{...d,request_id:id(seq++)}),/NORMAL_DAY_CONFLICT/);
  await perform(13,'allocate',alloc(65,today));const future={...alloc(65,today),operation:'normal',items:[sheet(65,today)]};
  await q("UPDATE folha_horarios SET intervals='[{\"period\":\"manha\",\"start\":\"23:00\",\"end\":\"23:15\"},{\"period\":\"tarde\",\"start\":\"23:20\",\"end\":\"23:59\"}]'");
  await assert.rejects(call(a,13,'bulk',future),/FUTURE_TIME/);
  await q("UPDATE folha_horarios SET intervals='[{\"period\":\"manha\",\"start\":\"08:00\",\"end\":\"12:00\"},{\"period\":\"tarde\",\"start\":\"13:00\",\"end\":\"17:00\"}]'");
  const past={...alloc(65),operation:'normal',items:[{...sheet(65),intervals:[{start:'08:00',end:'12:00'},{start:'13:00',end:'17:00'}]}]};await perform(13,'allocate',alloc(65));await perform(10,'bulk',past);
  await q("UPDATE folha_horarios SET intervals='[{\"period\":\"manha\",\"start\":\"09:00\",\"end\":\"13:00\"},{\"period\":\"tarde\",\"start\":\"14:00\",\"end\":\"18:00\"}]'");
 });
 await t.test('obra/pessoa/fornecedor de outra empresa, inativo e papel errado recusados',async()=>{
  await assert.rejects(call(a,13,'allocate',{...alloc(33),work_id:id(103)}),/PERMISSION_DENIED/);
  await assert.rejects(call(a,13,'allocate',alloc(49)),/PERMISSION_DENIED/);
  await assert.rejects(call(a,13,'allocate',alloc(33),'true','falso'),/STALE_PREVIEW/);
  await assert.rejects(call(a,16,'allocate',alloc(33)),/PERMISSION_DENIED/);
  await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(18)]);await assert.rejects(call(a,18,'allocate',alloc(33)),/PERMISSION_DENIED/);
  await assert.rejects(call(a,13,'external_register',{...alloc(),provider_id:id(301),name:'Sintético'}),/PERMISSION_DENIED/);
 });
 await t.test('dia normal exclui ausência, não permite escrita parcial e respeita janela configurada',async()=>{
  for(const n of [66,67,68]){await q("INSERT INTO colaboradores(id,empresa_id,nome,data_admissao) VALUES($1,$2,'Normal janela','2026-01-01')",[id(n),id(1)]);await perform(13,'allocate',alloc(n));}
  await q("INSERT INTO ausencias(colaborador_id,data,tipo) VALUES($1,$2,'ferias')",[id(67),day]);
  const d={...alloc(66),operation:'normal',items:[sheet(66),sheet(67)]};await assert.rejects(call(a,10,'bulk',d),/ABSENCE_CONFLICT/);
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id IN($1,$2)',[id(66),id(67)])).rows[0].n,0);
  await perform(10,'bulk',{...alloc(68),operation:'normal',items:[sheet(68)]});
 });
 await t.test('externo separado, folha/histórico, não entra em colaboradores',async()=>{
  const n=await count('colaboradores');const d={...alloc(),provider_id:id(300),name:'Externo sintético'};await perform(13,'external_register',d);
  await perform(10,'save',{...sheet(),key:{...key(),kind:'external',person_id:d.request_id}});assert.equal(await count('colaboradores'),n);assert.equal(await count('folha_externos'),1);
  const c=await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-26',id(100)]);assert.equal(c.external_rows.length,0);
  await perform(13,'external_register',{...alloc(30,'2026-09-26'),provider_id:id(300),name:'Externo sintético',external_id:d.request_id});
  assert.equal(await count('folha_externos'),1);assert.equal((await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-26',id(100)])).external_rows.length,1);
  await q('INSERT INTO subempreitadas VALUES($1,$2,$3)',[id(303),id(101),id(300)]);
  await perform(13,'external_register',{...alloc(30,'2026-09-27'),work_id:id(101),provider_id:id(300),name:'Externo sintético',external_id:d.request_id});
  assert.equal(await count('folha_externos'),1);assert.equal((await as(a,13,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-27',id(101)])).external_rows[0].person_id,d.request_id);
  await assert.rejects(call(a,13,'external_register',{...alloc(30,'2026-09-28'),work_id:id(101),provider_id:id(300),name:'Externo sintético'}),/EXTERNAL_IDENTITY_EXISTS/);
  await assert.rejects(call(a,13,'external_register',{...alloc(30,'2026-09-28'),provider_id:id(301),name:'Externo sintético',external_id:d.request_id}),e=>e.code==='42501');
  await perform(10,'save',{...sheet(),work_id:id(101),date:'2026-09-27',key:{...key(30,'2026-09-27','external',101),person_id:d.request_id}});
  assert.equal((await as(a,13,'SELECT fn_folha_historico_v2($1) v',[{...key(30,'2026-09-27','external',101),person_id:d.request_id}])).events.length,2);
  await q('UPDATE folha_externos SET ativo=false WHERE id=$1',[d.request_id]);assert.equal((await as(a,10,'SELECT fn_folha_contexto_v2($1,$2) v',['2026-09-27',id(101)])).external_rows[0].can_write,false);await q('UPDATE folha_externos SET ativo=true WHERE id=$1',[d.request_id]);
 });
 await t.test('férias e trabalho são regularização, não removem ausência',async()=>{
  await perform(13,'allocate',alloc(34));await q("INSERT INTO ausencias(colaborador_id,data,tipo) VALUES($1,$2,'ferias')",[id(34),day]);
  await perform(10,'save',sheet(34));assert.equal((await q('SELECT estado FROM folha_registos WHERE colaborador_id=$1',[id(34)])).rows[0].estado,'regularization');assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(34)])).rows[0].n,1);
 });
 await t.test('legado coexistente é bloqueado nos dois sentidos',async()=>{
  await assert.rejects(q("INSERT INTO ponto_pessoal_obra(empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES($1,$2,$3,$4,'presente',$5)",[id(1),id(100),id(30),day,id(10)]),/LEGACY_CONFLICT/);
  await perform(13,'allocate',alloc(35));await q("INSERT INTO ponto_pessoal_obra(empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES($1,$2,$3,$4,'presente',$5)",[id(1),id(100),id(35),day,id(10)]);
  await assert.rejects(call(a,10,'save',sheet(35)),/LEGACY_CONFLICT/);
 });
 await t.test('progressivo próprio dia sem janela e saída futura recusada',async()=>{
  await perform(13,'allocate',alloc(36,today));const d={...sheet(36,today),intervals:[{start:'00:00',end:null}]};await perform(13,'save',d);
  assert.equal((await q('SELECT estado FROM folha_registos WHERE colaborador_id=$1',[id(36)])).rows[0].estado,'open');
  await assert.rejects(call(a,13,'save',{...sheet(36,today),expected_revision:1,intervals:[{start:'00:00',end:'23:59'}]}),/FUTURE_TIME/);
 });
 await t.test('bulk é atómico e preserva ausência/revisões',async()=>{
  await perform(13,'allocate',alloc(37,today));await perform(13,'allocate',alloc(38,today));
  const d={...alloc(37,today),operation:'start',effective_time:'00:00',items:[{...sheet(37,today),intervals:[{start:'00:00',end:null}]},{...sheet(38,today),expected_revision:99,intervals:[{start:'00:00',end:null}]}]};
  await assert.rejects(call(a,13,'bulk',d),/STALE_REVISION/);assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id IN($1,$2)',[id(37),id(38)])).rows[0].n,0);
  d.items[1].expected_revision=0;await perform(13,'bulk',d);assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id IN($1,$2)',[id(37),id(38)])).rows[0].n,2);
  const finish={...d,request_id:id(seq++),operation:'finish',effective_time:'00:01',items:d.items.map(x=>({...x,expected_revision:1,intervals:[{start:'00:00',end:'00:01'}]}))};
  await perform(13,'bulk',finish);
  const closed=(await q('SELECT estado,revision,minutes FROM folha_registos WHERE colaborador_id IN($1,$2)',[id(37),id(38)])).rows;
  assert.ok(closed.every(x=>x.revision===2&&x.minutes===1));
 });
 await t.test('concorrência real: mesma revisão, um commit e um stale, sem duplicação',async()=>{
  await perform(13,'allocate',alloc(39));const d1=sheet(39),d2=sheet(39);const p1=await call(a,10,'save',d1),p2=await call(b,10,'save',d2);
  const r=await Promise.all([result(call(a,10,'save',d1,true,p1.versao)),result(call(b,10,'save',d2,true,p2.versao))]);assert.equal(r.filter(x=>x.value).length,1);assert.equal(r.filter(x=>x.error?.code==='40001').length,1);
 });
 await t.test('concorrência real legado/v2 nos dois sentidos, sem mistura',async()=>{
  const legacy=(c,n)=>c.query("INSERT INTO ponto_pessoal_obra(empresa_id,obra_id,colaborador_id,data,estado,registado_por) VALUES($1,$2,$3,$4,'presente',$5)",[id(1),id(100),id(n),day,id(10)]);
  await perform(13,'allocate',alloc(43));const d=sheet(43),p=await call(a,10,'save',d);
  await a.query('BEGIN');await call(a,10,'save',d,true,p.versao);
  const delayed=result(legacy(b,43));await delay(50);await a.query('COMMIT');assert.match((await delayed).error.message,/LEGACY_CONFLICT/);
  await perform(13,'allocate',alloc(44));const d2=sheet(44),p2=await call(a,10,'save',d2);
  await b.query('BEGIN');await legacy(b,44);const delayed2=result(call(a,10,'save',d2,true,p2.versao));await delay(50);await b.query('COMMIT');assert.match((await delayed2).error.message,/LEGACY_CONFLICT/);
 });
 await t.test('replay concorrente com o mesmo request cria apenas uma folha/história',async()=>{
  await perform(13,'allocate',alloc(48));const d=sheet(48),p=await call(a,10,'save',d);
  const values=await Promise.all([call(a,10,'save',d,true,p.versao),call(b,10,'save',d,true,p.versao)]);
  assert.ok(values.every(x=>x.committed));
  assert.equal((await q('SELECT count(*)::int n FROM folha_historico WHERE request_id=$1',[d.request_id])).rows[0].n,1);
 });
 await t.test('preview invalidado por ausência e permissões; intervalo inválido não escreve',async()=>{
  await perform(13,'allocate',alloc(45));const d=sheet(45),p=await call(a,10,'save',d);const n=await count('folha_registos');
  await q("INSERT INTO ausencias(colaborador_id,data,tipo) VALUES($1,$2,'ausencia')",[id(45),day]);await assert.rejects(call(a,10,'save',d,true,p.versao),/STALE_PREVIEW/);assert.equal(await count('folha_registos'),n);
  await assert.rejects(call(a,10,'save',{...sheet(45),intervals:[{start:'13:00',end:'09:00'}]}),/INTERVAL_CONFLICT/);
  await assert.rejects(call(a,10,'save',{...sheet(45),intervals:null}),/VALIDATION_ERROR/);
  await assert.rejects(call(a,11,'allocate',alloc(46)),/PERMISSION_DENIED/);
 });
 const aux=(user,action,d,confirm=false,token=null)=>as(a,user,'SELECT fn_folha_gestao_v2($1,$2,$3,$4) v',[action,d,confirm,token]);
 const auxDo=async(user,action,d)=>{const p=await aux(user,action,d);return aux(user,action,d,true,p.versao);};
 const auxData=(extra={})=>({version:2,request_id:id(seq++),expected_revision:0,...extra});
 await t.test('configuração com revisão; horário deslocado sem HE presumida',async()=>{
  await auxDo(10,'configure_schedule',auxData({work_id:id(100),expected_revision:1,intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}],expected_minutes:480}));
  await assert.rejects(aux(13,'configure_company',auxData()),/PERMISSION_DENIED/);
  await auxDo(10,'configure_company',auxData({expected_revision:1,correction_days:1,overtime_enabled:true,calendar_complete:true,calendar_validated_years:[2026]}));
 });
 await t.test('HE única por folha/revisão; Diretor/Adjunto e validação ADM sem dinheiro',async()=>{
  await perform(13,'allocate',alloc(40));await perform(10,'save',{...sheet(40),intervals:[{start:'09:00',end:'18:00'}]});
  const h=(await q('SELECT * FROM folha_he WHERE estado=$1',['potential'])).rows[0];assert.ok(h);assert.equal(h.minutes,60);
  const n=await count('folha_he');await auxDo(14,'he_approve',auxData({id:h.id,expected_revision:1}));await auxDo(10,'he_validate',auxData({id:h.id,expected_revision:2}));
  assert.equal((await q('SELECT estado FROM folha_he WHERE id=$1',[h.id])).rows[0].estado,'validated_pending_rule');assert.equal(await count('folha_he'),n);
  await assert.rejects(aux(13,'he_approve',auxData({id:h.id,expected_revision:3})),/PERMISSION_DENIED/);
  await assert.rejects(q('INSERT INTO horas_extraordinarias(colaborador_id,data) VALUES($1,$2)',[id(40),day]),/OVERTIME_ORIGIN_CONFLICT/);
 });
 await t.test('HE rejeitada pelo Adjunto responsável; legado manual impede geração automática',async()=>{
  await perform(13,'allocate',alloc(46));await perform(10,'save',{...sheet(46),intervals:[{start:'09:00',end:'18:00'}]});
  const h=(await q('SELECT h.* FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(46)])).rows[0];
  await auxDo(15,'he_reject',auxData({id:h.id,expected_revision:1}));assert.equal((await q('SELECT estado FROM folha_he WHERE id=$1',[h.id])).rows[0].estado,'rejected');
  await perform(13,'allocate',alloc(47));await q('INSERT INTO horas_extraordinarias(colaborador_id,data) VALUES($1,$2)',[id(47),day]);await perform(10,'save',{...sheet(47),intervals:[{start:'09:00',end:'18:00'}]});
  assert.equal((await q('SELECT count(*)::int n FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(47)])).rows[0].n,0);
 });
 await t.test('férias não contíguas, revisão, replay, remoção e direito sem default',async()=>{
  const d=auxData({person_id:id(41),dates:['2026-09-25','2026-09-27']});const r=await auxDo(10,'vacation_set',d);assert.equal(r.result.consumed_days,1);assert.equal(r.result.calendar_pending,false);
  assert.deepEqual(await auxDo(10,'vacation_set',d),r);
  await auxDo(10,'vacation_remove',auxData({person_id:id(41),dates:['2026-09-27'],expected_revision:1}));
  assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(41)])).rows[0].n,1);
  assert.equal(await count('folha_direitos_ferias'),0);
  await auxDo(10,'vacation_entitlement',auxData({person_id:id(41),year:2026,days:17,source:'Documento sintético explicitamente validado'}));
 });
 await t.test('férias: substituir seleção adiciona/remove numa única operação; cliente real e isolamento',async()=>{
  const {createAttendanceManagementClient}=await import('../src/attendance-client.js');
  const client=createAttendanceManagementClient({requestId:()=>id(seq++),confirm:async()=>true,supabase:async(path,options)=>{
   const d=JSON.parse(options.body);try{const value=path.endsWith('contexto_v2')?await as(a,10,'SELECT fn_folha_gestao_contexto_v2($1,$2,$3) v',[d.p_obra_id,d.p_colaborador_id,d.p_competencia]):await aux(10,d.p_acao,d.p_dados,d.p_confirmar,d.p_versao);return Response.json(value);}catch(e){return Response.json({code:e.code,message:e.message},{status:409});}
  }});
  const c=await client.context({personId:id(41)});assert.equal(c.vacation_revision,2);assert.equal(c.entitlements[0].dias,17);
  const scoped=await client.context({workId:id(100),personId:id(41)});assert.ok(scoped.history.some(x=>x.action==='vacation_set'));assert.ok(scoped.history.some(x=>x.action==='vacation_entitlement'));
  await client.execute('vacation_replace',{person_id:id(41),expected_revision:2,dates:['2026-09-26'],scope_dates:['2026-09-25','2026-09-26','2026-09-27'],reason:null});
  const rows=(await q('SELECT data::text FROM ausencias WHERE colaborador_id=$1',[id(41)])).rows;assert.deepEqual(rows.map(x=>x.data),[]); // Saturday is excluded, while scope still removes the old Friday.
  await assert.rejects(as(a,13,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,NULL) v',[id(41)]),/PERMISSION_DENIED/);
  await assert.rejects(as(a,10,'SELECT fn_folha_gestao_contexto_v2(NULL,$1,NULL) v',[id(49)]),/PERMISSION_DENIED/);
 });
 await t.test('férias com conflito recusam atomicamente; override explícito guarda história',async()=>{
  const d=auxData({person_id:id(30),dates:[day,'2026-09-26']});await assert.rejects(aux(10,'vacation_set',d),/REGULARIZATION_REQUIRED/);
  assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(30)])).rows[0].n,0);
  await auxDo(10,'vacation_set',{...d,admin_override:true});
 });
 await t.test('vencimentos Primeline factos/manuais, validar e fechar bloqueado por ADM',async()=>{
  await auxDo(10,'payroll_save',auxData({person_id:id(30),month:'2026-09-01',manual:{km:2,allowance:0,note:'Sintético'}}));
  const d=auxData({person_id:id(30),month:'2026-09-01',expected_revision:1});await assert.rejects(auxDo(10,'payroll_validate',d),/PAYROLL_PENDING_FACTS/);
  await assert.rejects(aux(10,'payroll_close',{...auxData(),person_id:id(30),month:'2026-09-01',expected_revision:2}),/PAYROLL_PENDING_FACTS/);
  await assert.rejects(aux(10,'payroll_export',{...auxData(),person_id:id(30),month:'2026-09-01',expected_revision:2}),/OFFICIAL_EXPORTER_REQUIRED/);
  assert.equal(await count('folha_vencimentos'),1);assert.equal((await q('SELECT colaborador_id FROM folha_vencimentos')).rows[0].colaborador_id,id(30));
 });
 await t.test('reporte não conclui Planeamento; Diretor confirma depois, alertas preservados',async()=>{
  await auxDo(13,'task_report',auxData({task_id:id(501),work_id:id(100)}));assert.equal((await q('SELECT estado FROM planeamento_itens WHERE id=$1',[id(501)])).rows[0].estado,'em_execucao');
  const d=auxData({task_id:id(501),work_id:id(100),expected_revision:1});await assert.rejects(aux(14,'task_confirm',d),/PLANNING_CONFIRMATION_REQUIRED/);
  await q("SELECT set_config('test.actor',$1,false)",[id(14)]);await q("UPDATE planeamento_itens SET estado='concluido' WHERE id=$1",[id(501)]);
  assert.equal((await q('SELECT estado FROM folha_tarefas_reportes')).rows[0].estado,'confirmed');
  assert.equal((await q('SELECT revision FROM folha_tarefas_reportes')).rows[0].revision,2);
  const context=await as(a,14,'SELECT fn_folha_gestao_contexto_v2($1,NULL,NULL) v',[id(100)]);assert.ok(!context.tasks.some(x=>x.id===id(501)));assert.equal(context.task_reports.find(x=>x.tarefa_id===id(501)).estado,'confirmed');
  const rows=(await q("SELECT estado FROM alertas WHERE tipo='folha_conclusao_reportada'")).rows;assert.equal(rows.length,2);assert.ok(rows.every(x=>x.estado==='resolvido'));
 });
 await t.test('contrato frontend real contra as quatro RPCs PostgreSQL',async()=>{
  const {createSheetClient}=await import('../src/attendance-client.js');
  const rpcSql={fn_folha_contexto_v2:['SELECT fn_folha_contexto_v2($1,$2) v',x=>[x.p_data,x.p_obra_id]],fn_folha_pessoas_v2:['SELECT fn_folha_pessoas_v2($1,$2) v',x=>[x.p_data,x.p_obra_id]],fn_folha_historico_v2:['SELECT fn_folha_historico_v2($1) v',x=>[x.p_chave]],fn_folha_operar_v2:['SELECT fn_folha_operar_v2($1,$2,$3,$4) v',x=>[x.p_acao,x.p_dados,x.p_confirmar,x.p_versao]]};
  const client=createSheetClient({requestId:()=>id(seq++),confirm:async()=>true,supabase:async(path,options)=>{const [sql,params]=rpcSql[path.slice(4)];try{return Response.json(await as(a,10,sql,params(JSON.parse(options.body))));}catch(e){return Response.json({code:e.code,message:e.message},{status:409});}}});
  assert.equal((await client.context(day,id(100))).version,2);assert.ok((await client.candidates(day,id(100))).some(x=>x.person_id===id(42)));
  const d=alloc(42);delete d.request_id;await client.operate('allocate',d);
  const ids=(await q('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(42),day])).rows.map(x=>x.id);
  await client.operate('remove_from_day',{...d,expected_allocation_revision:1,ids});assert.equal((await client.history(key(42))).events.length,2);
 });
 await (await import('./attendance-preserved-audit-cases.mjs')).independentAuditCases(t,{q,a,b,as,call,aux,auxDo,id,today});
 await (await import('./attendance-payload-regression-cases.mjs')).payloadRegressionCases(t,{q,a,as,call,aux,auxDo,id});
 await (await import('./attendance-focused-reaudit-cases.mjs')).focusedReauditCases(t,{q,a,as,aux,id});
 await (await import('./attendance-visible-state-cases.mjs')).visibleStateCases(t,{q,a,as,call,id});
 await (await import('./attendance-adm-rules-cases.mjs')).admRulesCases(t,{q,a,b,as,aux,auxDo,id,today});
 await (await import('./audit-attendance-adm-final-cases.mjs')).auditAdmFinalCases(t,{q,a,b,as,aux,auxDo,id,today});
 await (await import('./attendance-reconciliation-cases.mjs')).reconciliationCases(t,{q,a,b,as,call,aux,auxDo,id});
 await t.test('Fase B pós-hotfix: gate ausente/drift recusa; instalação, v1/RH/hotfix e rollback',async()=>{
  const pre=await read('../supabase/quadro_fase_b_pos_hotfix_precheck.sql');
  await assert.rejects(q(pre),/REAL CATALOG VALIDATION REQUIRED/);await q('ROLLBACK');
  await q(`CREATE FUNCTION fn_encarregado_acesso_direto_bloqueado() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT EXISTS(SELECT 1 FROM utilizadores WHERE id=fn_utilizador_atual_id() AND funcao='encarregado') $$;
  CREATE POLICY encarregado_sem_dml_direto ON quadro_pessoal_alocacao AS RESTRICTIVE FOR ALL TO authenticated USING(NOT fn_encarregado_acesso_direto_bloqueado()) WITH CHECK(NOT fn_encarregado_acesso_direto_bloqueado());
  CREATE SCHEMA primeline_pacote2_gate;REVOKE ALL ON SCHEMA primeline_pacote2_gate FROM PUBLIC,anon,authenticated,service_role;
  CREATE TABLE primeline_pacote2_gate.aprovacao(release_id text,reviewed_by text,reviewed_at timestamptz,consumed_at timestamptz,frontend_assets_sha256 text,frontend_validated boolean,backend_v2_validated boolean,installation_id text,expected_catalog jsonb);
  ALTER TABLE primeline_pacote2_gate.aprovacao ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON primeline_pacote2_gate.aprovacao FROM PUBLIC,anon,authenticated,service_role;`);
  // SYNTHETIC ONLY: models a separately reviewed gate, never manufactures a real production fingerprint.
  const catalogSql=pre.slice(pre.indexOf('actual:=(')+9,pre.indexOf('\n IF actual IS DISTINCT')).replace(/\);\s*$/,'');
  const catalog=(await q(catalogSql)).rows[0].jsonb_build_object;
  await q("INSERT INTO primeline_pacote2_gate.aprovacao VALUES('pacote2_folha_v2_20261005','postgres',now(),NULL,$1,true,true,(SELECT instalacao_id::text FROM primeline_quadro_rollout.controlo WHERE singleton),$2)",['0'.repeat(64),catalog]);
  await q(pre);
  await q('GRANT UPDATE ON folha_registos TO authenticated');await assert.rejects(q(pre),/POST_HOTFIX_CATALOG_DRIFT/);await q('ROLLBACK');await q('REVOKE UPDATE ON folha_registos FROM authenticated');
  await q(pre);await q(await read('../supabase/quadro_fase_b_pos_hotfix_backup.sql'));
  await q(await read('../supabase/quadro_fase_b_pos_hotfix_migration.sql'));await q(await read('../supabase/quadro_fase_b_pos_hotfix_postcheck.sql'));
  await assert.rejects(as(a,10,"INSERT INTO quadro_pessoal_alocacao DEFAULT VALUES"),/permission denied/);
  assert.equal((await q("SELECT count(*)::int n FROM pg_policies WHERE policyname='encarregado_sem_dml_direto'")).rows[0].n,1);
  await q(await read('../supabase/quadro_fase_b_pos_hotfix_rollback.sql'));
  const old=(await q("SELECT definicao FROM primeline_quadro_b_20261005.funcoes WHERE assinatura='fn_quadro_proteger_escrita()'")).rows[0].definicao;
  assert.equal((await q("SELECT pg_get_functiondef('fn_quadro_proteger_escrita()'::regprocedure) d")).rows[0].d,old);
  await assert.rejects(q(pre),/POST_HOTFIX_VALIDATION_REQUIRED/);await q('ROLLBACK');
 });
 await t.test('rollback v2 recusa factos; rollback vazio explicitamente restaura o núcleo v1',async()=>{
  await assert.rejects(q(await read('../supabase/folha_ponto_v2_gestao_rollback.sql')),/ROLLBACK_DATA_PRESENT/);await q('ROLLBACK');
  // Descartar SOMENTE factos sintéticos desta base efémera para verificar a desinstalação vazia.
  await q('TRUNCATE folha_gestao_historico,folha_vencimentos,folha_tarefas_reportes,folha_direitos_ferias,folha_ferias_revisoes,folha_he,folha_historico,folha_registos,folha_externos,folha_externos_dias,folha_config_empresa,folha_horarios,folha_privado.operacoes');
  await q(await read('../supabase/folha_ponto_v2_gestao_rollback.sql'));await q(await read('../supabase/folha_ponto_v2_rollback.sql'));
  assert.equal((await q("SELECT to_regprocedure('fn_folha_operar_v2(text,jsonb,boolean,text)')::text r")).rows[0].r,null);
  assert.doesNotMatch((await q("SELECT prosrc FROM pg_proc WHERE oid='fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)'::regprocedure")).rows[0].prosrc,/folha_privado/);
 });
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
