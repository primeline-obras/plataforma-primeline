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
test('Fecho final Encarregado — PostgreSQL local',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.\d+\b/);
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

 // Installed cutover definition, in a disposable synthetic DB; rollout gates have their own suite.
 const cut=await read('../supabase/folha_v2_legacy_cutover.sql');
 await q(cut.slice(cut.indexOf('CREATE TABLE folha_privado.legacy_cutover')));
 await q(await read('../supabase/folha_equipa_operacional_precheck.sql'));
 await q(await read('../supabase/folha_equipa_operacional_backup.sql'));
 await q(await read('../supabase/folha_equipa_operacional.sql'));
 await q(await read('../supabase/folha_equipa_operacional_postcheck.sql'));
 async function as(c,user,sql,params=[]){await c.query("SELECT set_config('test.actor',$1,false)",[id(user)]);await c.query('SET ROLE authenticated');try{return (await c.query(sql,params)).rows[0]?.v;}finally{await c.query('RESET ROLE');}}
 const call=(c,user,name,args)=>as(c,user,'SELECT '+name+'($1::text,$2::jsonb,$3::boolean,$4::text) v',args);
 let request=9000;
 async function operate(action,people,work=100,date='2026-10-01',user=10){const body={version:2,request_id:id(request++),work_id:id(work),date,people};const preview=await call(a,user,'fn_equipa_operar_v2',[action,body,false,null]);assert.equal(preview.committed,false);const committed=await call(a,user,'fn_equipa_operar_v2',[action,body,true,preview.versao]);return {body,preview,committed};}
 const member=(p,rev=0,source)=>({person_id:id(p),expected_revision:rev,...(source?{source_work_id:id(source)}:{})});
 const context=(user,work,date)=>as(a,user,'SELECT fn_folha_contexto_v2($1::date,$2::uuid) v',[date,id(work)]);

 const agenda=(await read('../supabase/calendario_compromissos.sql'));await q(agenda.slice(agenda.indexOf('create or replace function public.fn_listar_colegas_agenda()'),agenda.indexOf('create or replace function public.fn_pode_ver_compromisso')));
 await q(await read('../supabase/encarregado_fecho_final_precheck.sql'));
 await q(await read('../supabase/encarregado_fecho_final_backup.sql'));
 await t.test('rollout recusa backup desatualizado antes de criar estruturas',async()=>{
  await q('BEGIN');await q('UPDATE quadro_pessoal_alocacao SET descricao_livre=$1 WHERE id=$2',['Alteração sintética posterior ao backup',id(1003)]);
  await assert.rejects(q(await read('../supabase/encarregado_fecho_final.sql')),/BACKUP_OPERATIONAL_DIVERGENCE/);await q('ROLLBACK');
  assert.equal((await q("SELECT to_regclass('public.folha_externos_permanencias') v")).rows[0].v,null);
 });
 await q(await read('../supabase/encarregado_fecho_final.sql'));
 await q(await read('../supabase/encarregado_fecho_final_postcheck.sql'));
 await q(await read('../supabase/encarregado_fecho_final_rollback.sql'));
 await q(await read('../supabase/encarregado_fecho_final.sql'));
 await q(await read('../supabase/encarregado_fecho_final_postcheck.sql'));
 await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao,utilizador_id) VALUES($1,$2,'Próprio sintético encarregado','Encarregado','2026-01-01',$3)",[id(63),id(1),id(13)]);
 const today=(await q("SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date d")).rows[0].d;
 const key=(person,date=today,work=100,kind='primeline')=>({person_id:id(person),kind,date,work_id:id(work)});
 async function write(action,data,user=13,c=a){const body={version:2,date:today,work_id:id(100),request_id:id(request++),...data};const preview=await call(c,user,'fn_folha_operar_v2',[action,body,false,null]);const result=await call(c,user,'fn_folha_operar_v2',[action,body,true,preview.versao]);return {body,preview,result};}
 await t.test('Encarregado próprio integrado, sem permanência; horas reais num dia especial',async()=>{
  assert.ok((await context(13,100,today)).rows.find(x=>x.person_id===id(63)).self);
  await write('save',{key:key(63),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]});
  assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(63)])).rows[0].n,0);
 });
 await t.test('multiobra atómico e replay, períodos sem sobreposição',async()=>{
  const sites=[{work_id:id(100),expected_revision:1,intervals:[{start:'08:00',end:'12:00',period:'manha'}]},{work_id:id(101),expected_revision:0,intervals:[{start:'13:00',end:'17:00',period:'tarde'}]}];
  const r=await write('periods_save',{key:key(63),sites});
  assert.deepEqual(await call(a,13,'fn_folha_operar_v2',['periods_save',r.body,true,r.preview.versao]),r.result);
  assert.equal((await q('SELECT sum(minutes)::int n FROM folha_registos WHERE colaborador_id=$1',[id(63)])).rows[0].n,480);
 });
 await t.test('primeiro horário pode pertencer integralmente a outra obra autorizada sem inventar linha vazia',async()=>{
  const yesterday=(await q("SELECT ((now() AT TIME ZONE 'Europe/Lisbon')::date-1)::text d")).rows[0].d;
  await write('periods_save',{date:yesterday,key:key(63,yesterday),sites:[{work_id:id(101),expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:'manha'},{start:'13:00',end:'17:00',period:'tarde'}]}]});
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2 AND obra_id=$3',[id(63),yesterday,id(100)])).rows[0].n,0);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(63),yesterday])).rows[0].minutes,480);
 });
 await t.test('obra sem âmbito, snapshot stale e sobreposição recusam sem escrita',async()=>{
  const base={version:2,date:today,work_id:id(100),request_id:id(request++),key:key(63),sites:[{work_id:id(100),expected_revision:2,intervals:[{start:'08:00',end:'12:00',period:'manha'}]},{work_id:id(101),expected_revision:1,intervals:[{start:'11:00',end:'17:00'}]}]};
  await assert.rejects(call(a,13,'fn_folha_operar_v2',['periods_save',base,false,null]),/INTERVAL_CONFLICT/);
  const bad={...base,request_id:id(request++),sites:[...base.sites,{work_id:id(103),expected_revision:0,intervals:[]}]};
  await assert.rejects(call(a,13,'fn_folha_operar_v2',['periods_save',bad,false,null]),e=>e.code==='42501');
 });
 await t.test('externo persistente sem horas e retirada preserva ponto',async()=>{
  const r=await write('external_team_add',{provider_id:id(300),name:'Externo sintético final',role:'servente',expected_revision:0});
  const person=r.body.request_id;
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE externo_id=$1',[person])).rows[0].n,0);
  assert.ok((await context(13,100,today)).external_rows.find(x=>x.person_id===person));
  await write('save',{key:{person_id:person,kind:'external',date:today,work_id:id(100)},expected_revision:0,intervals:[{start:'10:00',end:'16:00'}]});
  await write('external_team_remove',{external_id:person,expected_revision:1});
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE externo_id=$1',[person])).rows[0].minutes,360);
 });
 await t.test('horário formal requerido; dia normal sem gate HE; sábado recusado',async()=>{
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await assert.rejects(q("SELECT folha_privado.normal($1,$2,'2026-10-09')",[id(63),id(100)]),/SCHEDULE_REQUIRED/);
  await q("INSERT INTO folha_horarios(obra_id,empresa_id,intervals,expected_minutes) VALUES($1,$2,$3,480)",[id(100),id(1),JSON.stringify([{period:'manha',start:'08:00',end:'12:00'},{period:'tarde',start:'13:00',end:'17:00'}])]);
  assert.equal((await q("SELECT jsonb_array_length(folha_privado.normal($1,$2,'2026-10-09')) n",[id(63),id(100)])).rows[0].n,2);
  await assert.rejects(q("SELECT folha_privado.normal($1,$2,'2026-10-10')",[id(63),id(100)]),/SPECIAL_DAY/);
 });
 await t.test('retirar após ponto preserva facto, movimento válido e histórico',async()=>{
  await operate('team_add',[member(22)],100,today,13);
  await write('save',{key:key(22),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]});
  assert.equal((await context(13,100,today)).rows.find(x=>x.person_id===id(22)).can_remove,true);
  await operate('team_remove',[member(22,1)],100,today,13);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE colaborador_id=$1',[id(22)])).rows[0].minutes,240);
 });

 await t.test('transferência após ponto preserva horas na obra original; ajuda temporária sem transferir',async()=>{
  await operate('team_add',[member(24)],100,today,13);
  await write('save',{key:key(24),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]});
  const people=await as(a,13,'SELECT fn_folha_pessoas_v2($1::date,$2::uuid) v',[today,id(101)]);
  assert.ok(people.people.find(x=>x.person_id===id(24)).help_row);
  const help={version:2,date:today,work_id:id(101),request_id:id(request++),key:key(24,today,101),sites:[{work_id:id(100),expected_revision:1,intervals:[{start:'08:00',end:'12:00',period:'manha'}]},{work_id:id(101),expected_revision:0,intervals:[{start:'13:00',end:'17:00',period:'tarde'}]}]};
  const preview=await call(a,13,'fn_folha_operar_v2',['periods_save',help,false,null]);await call(a,13,'fn_folha_operar_v2',['periods_save',help,true,preview.versao]);
  assert.equal((await q('SELECT obra_id FROM quadro_equipa_permanencias WHERE colaborador_id=$1 AND fim IS NULL',[id(24)])).rows[0].obra_id,id(100));
  await operate('team_transfer',[member(24,1,100)],101,today,13);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE colaborador_id=$1 AND obra_id=$2',[id(24),id(100)])).rows[0].minutes,240);
 });
 await t.test('concurrency: duas confirmações simultâneas só uma passa',async()=>{
  await operate('team_add',[member(23)],100,today,13);
  const first={version:2,date:today,work_id:id(100),request_id:id(request++),key:key(23),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]},second={...first,request_id:id(request++)};
  const pa=await call(a,13,'fn_folha_operar_v2',['save',first,false,null]),pb=await call(b,13,'fn_folha_operar_v2',['save',second,false,null]);
  await a.query('BEGIN');await call(a,13,'fn_folha_operar_v2',['save',first,true,pa.versao]);
  const losing=result(call(b,13,'fn_folha_operar_v2',['save',second,true,pb.versao]));await delay(100);await a.query('COMMIT');const loser=await losing;
  assert.equal(loser.error?.code,'40001');assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(23),today])).rows[0].n,1);
 });
 await t.test('própria Folha Diretor/Adjunto/Preparador preservada; outro próprio negado',async()=>{
  for(const [user,person] of [[14,60],[15,61],[16,62]]){assert.ok((await context(user,100,today)).rows.find(x=>x.person_id===id(person)).self);await write('save',{key:key(person),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]},user);}
  await assert.rejects(write('save',{key:key(60),expected_revision:1,intervals:[{start:'08:00',end:'12:00'}]},13),e=>e.code==='42501');
 });
 await t.test('Escritório multiobra mantém tenant, horas e revisão após deslocação integral',async()=>{
  const plan=[{work_id:id(100),expected_revision:1,intervals:[]},{work_id:null,expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:'manha'}]}];
  await write('periods_save',{key:key(60),sites:plan},14);
  const c=await context(14,100,today),self=c.rows.find(x=>x.person_id===id(60));
  assert.equal(self.day_sheets.find(x=>x.work_id===null).revision,1);
  assert.equal(self.day_revisions.find(x=>x.work_id===id(100)).revision,2);
  const back=[{work_id:id(100),expected_revision:2,intervals:[{start:'08:00',end:'12:00',period:'manha'}]},{work_id:null,expected_revision:1,intervals:[]}];
  await write('periods_save',{key:key(60),sites:back},14);
  assert.equal((await q('SELECT revision,minutes FROM folha_registos WHERE colaborador_id=$1 AND obra_id=$2 AND data=$3',[id(60),id(100),today])).rows[0].revision,3);
  assert.equal((await q('SELECT sum(minutes)::int n FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(60),today])).rows[0].n,240);
  await assert.rejects(write('periods_save',{key:key(63),sites:[{work_id:id(100),expected_revision:2,intervals:[]},{work_id:id(101),expected_revision:1,intervals:[]},{work_id:null,expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:'manha'}]}]},13),e=>e.code==='42501');
 });
 await t.test('intervalos internos já existentes não são truncados; revisão stale não escreve parcialmente',async()=>{
  await operate('team_add',[member(26)],100,today,13);
  const intervals=[{start:'08:00',end:'10:00',period:'manha'},{start:'10:15',end:'12:00',period:'manha'},{start:'13:00',end:'17:00',period:'tarde'}];
  await write('periods_save',{key:key(26),sites:[{work_id:id(100),expected_revision:0,intervals}]});
  const before=(await q('SELECT to_jsonb(f) snapshot FROM folha_registos f WHERE colaborador_id=$1',[id(26)])).rows[0].snapshot;
  assert.equal(before.intervals.length,3);assert.equal(before.minutes,465);assert.equal(before.expected_minutes,480);
  const body={version:2,date:today,work_id:id(100),request_id:id(request++),key:key(26),sites:[{work_id:id(100),expected_revision:1,intervals:[{start:'08:00',end:'12:00',period:'manha'}]},{work_id:id(101),expected_revision:0,intervals:[{start:'13:00',end:'17:00',period:'tarde'}]}]};
  const p=await call(a,13,'fn_folha_operar_v2',['periods_save',body,false,null]);
  await write('save',{key:key(26),expected_revision:1,intervals:[{start:'08:00',end:'11:00'}]});
  await assert.rejects(call(a,13,'fn_folha_operar_v2',['periods_save',body,true,p.versao]),e=>e.code==='40001');
  assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1 AND obra_id=$2',[id(26),id(101)])).rows[0].n,0);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE colaborador_id=$1',[id(26)])).rows[0].minutes,180);
 });
 await t.test('externo: fornecedor cross-tenant e ator inativo recusados sem identidade/permanência',async()=>{
  const before=(await q('SELECT count(*)::int n FROM folha_externos')).rows[0].n;
  await assert.rejects(write('external_team_add',{provider_id:id(301),name:'Externo inválido',role:'servente',expected_revision:0}),e=>e.code==='42501');
  await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(13)]);
  try{await assert.rejects(write('external_team_add',{provider_id:id(300),name:'Externo inválido',role:'servente',expected_revision:0}),e=>e.code==='42501');}finally{await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(13)]);}
  assert.equal((await q('SELECT count(*)::int n FROM folha_externos')).rows[0].n,before);
 });
 await t.test('janela hoje/ontem; ADMIN retroativo exige motivo; datas futuras recusadas',async()=>{
  const old='2026-01-05';await assert.rejects(write('save',{date:old,key:key(63,old),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]},13),/CORRECTION_WINDOW/);
  await assert.rejects(write('save',{date:old,key:key(20,old),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]},12),/CORRECTION_REASON/);
  const future='2099-01-01';await assert.rejects(write('save',{date:future,key:key(63,future),expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]},13),/VALIDATION_ERROR/);
 });
 await t.test('Dia Normal real sintético inclui externo, recusa duplicação e preserva HE desligada',async()=>{
  const date='2026-10-09';await operate('team_add',[member(25)],100,date,10);
  const ext=await write('external_team_add',{date,provider_id:id(300),name:'Externo normal sintético',role:'pedreiro',expected_revision:0,reason:'Teste sintético'},10);
  const intervals=[{start:'08:00',end:'12:00'},{start:'13:00',end:'17:00'}];
  const data={date,operation:'normal',reason:'Teste sintético',items:[{key:key(25,date),expected_revision:0,intervals,reason:'Teste sintético'},{key:{person_id:ext.body.request_id,kind:'external',work_id:id(100),date},expected_revision:0,intervals,reason:'Teste sintético'}]};
  await write('bulk',data,10);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE externo_id=$1',[ext.body.request_id])).rows[0].minutes,480);
  await assert.rejects(write('bulk',data,10),/NORMAL_DAY_CONFLICT/);
  assert.equal((await q('SELECT count(*)::int n FROM folha_he')).rows[0].n,0);
 });
 await t.test('ACL privadas, writer legado CLOSED, sem DML direto, histórico imutável',async()=>{
  await assert.rejects(as(a,13,'SELECT folha_privado.operar_periodos($1,false,NULL) v',[{}]),e=>e.code==='42501');
  await assert.rejects(as(a,13,"INSERT INTO folha_externos_permanencias DEFAULT VALUES RETURNING id v"),e=>e.code==='42501');
  await assert.rejects(q("DELETE FROM ponto_pessoal_obra"),e=>e.code==='42501');
  await assert.rejects(q("UPDATE folha_historico SET reason='alterar'"),/IMMUTABLE/);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,227);
 });
 await t.test('Agenda formal, tenant e superutilizador técnico oculto',async()=>{
  const rows=await as(a,13,"SELECT jsonb_agg(x) v FROM fn_listar_colegas_agenda() x");
  assert.ok(!rows.some(x=>x.funcao==='gestao_plataforma'||x.id===id(17)||x.id===id(12)));
 });
 await assert.rejects(q(await read('../supabase/encarregado_fecho_final_rollback.sql')),/ROLLBACK_DATA_PRESENT/);await q('ROLLBACK');
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
