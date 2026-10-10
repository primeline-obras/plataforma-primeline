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
test('Equipa persistente / Folha operacional — PostgreSQL local',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 await t.test('estrutura vazia e legado integral preservado; rollback vazio e reinstalação',async()=>{
  await q(await read('../supabase/folha_equipa_operacional_rollback.sql'));
  assert.equal((await q("SELECT to_regclass('quadro_equipa_permanencias') v")).rows[0].v,null);
  await q(await read('../supabase/folha_equipa_operacional.sql'));await q(await read('../supabase/folha_equipa_operacional_postcheck.sql'));
 });
 let added;
 await t.test('Quadro e Folha usam o mesmo writer/projeção; replay preserva resultado',async()=>{
  const body={version:1,request_id:id(request++),colaborador_id:id(29),obra_id:id(100),data:'2026-10-01',periodo:'dia_inteiro',tipo_alocacao:'obra',expected_revision:0};
  const preview=await call(a,10,'fn_quadro_operar_v1',['alocar',body,false,null]);assert.equal(preview.version,1);
  const committed=await call(a,10,'fn_quadro_operar_v1',['alocar',body,true,preview.versao]);assert.equal(committed.revision,1);
  assert.deepEqual(await call(a,10,'fn_quadro_operar_v1',['alocar',body,true,preview.versao]),committed);
  const c=await as(a,13,'SELECT fn_quadro_contexto_v1($1::date,$2::date) v',['2026-10-01','2026-10-02']);
  assert.equal(c.allocations.filter(x=>x.colaborador_id===id(29)).length,2);
  assert.ok(!c.allocations.some(x=>x.obra_id===id(103)));
  // End the test membership without deleting history, so the next assertions have an isolated team.
  await operate('team_remove',[member(29,1)],100,'2026-10-01');
 });
 await t.test('A/B — inclusão múltipla persiste sem gerar linhas diárias; entrada histórica',async()=>{
  added=await operate('team_add',[member(22),member(23)]);
  assert.equal(added.committed.changed_keys.length,2);
  for(const date of ['2026-10-01','2026-10-02','2026-10-19'])assert.equal((await context(13,100,date)).rows.length,2);
  assert.equal((await context(13,100,'2026-09-30')).rows.length,0);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,227);
 });
 await t.test('D — transferência encerra/inicia; datas históricas coerentes',async()=>{
  await operate('team_transfer',[member(22,1,100)],101,'2026-10-20');
  assert.ok((await context(13,100,'2026-10-19')).rows.some(x=>x.person_id===id(22)));
  assert.ok(!(await context(13,100,'2026-10-25')).rows.some(x=>x.person_id===id(22)));
  assert.ok((await context(13,101,'2026-10-25')).rows.some(x=>x.person_id===id(22)));
 });
 await t.test('C — retirada mantém permanência e movimentos históricos',async()=>{
  await operate('team_remove',[member(22,2)],101,'2026-10-30');
  assert.ok(!(await context(13,101,'2026-11-01')).rows.some(x=>x.person_id===id(22)));
  assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(22)])).rows[0].n,2);
 });
 await t.test('E/F/L — elegibilidade, tenant e lote atómico',async()=>{
  for(const person of [60,49])await assert.rejects(operate('team_add',[member(person)]),e=>e.code==='42501');
  await assert.rejects(operate('team_add',[member(24),member(60)]),e=>e.code==='42501');
  assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(24)])).rows[0].n,0);
  await assert.rejects(operate('team_add',[member(24)],103),e=>e.code==='42501');
  await assert.rejects(operate('team_add',[member(24)],100,'2026-10-01',14),e=>e.code==='42501');
  await q("UPDATE colaboradores SET funcao='Servente' WHERE id=$1",[id(31)]);
  await operate('team_add',[member(31)],100,'2026-10-01',13);
  const candidates=await as(a,13,'SELECT fn_folha_pessoas_v2($1::date,$2::uuid) v',['2026-10-09',id(100)]);
  assert.ok(candidates.people.every(x=>['Pedreiro','Servente'].includes(x.role)));
  assert.ok(!candidates.people.some(x=>x.person_id===id(31)));
  await assert.rejects(operate('team_add',[member(32)],102,'2026-10-01',13),e=>e.code==='42501');
  await q("UPDATE colaboradores SET data_saida='2026-09-30' WHERE id=$1",[id(32)]);
  await assert.rejects(operate('team_add',[member(32)]),e=>e.code==='42501');
  await q("UPDATE utilizadores SET ativo=false WHERE id=$1",[id(18)]);
  await assert.rejects(operate('team_add',[member(33)],102,'2026-10-01',18),e=>e.code==='42501');
 });
 await t.test('replay idempotente; revisão stale; resposta antiga não escreve',async()=>{
  const x=await operate('team_add',[member(25)]);
  const replay=await call(a,10,'fn_equipa_operar_v2',['team_add',x.body,true,x.preview.versao]);assert.deepEqual(replay,x.committed);
  await assert.rejects(operate('team_remove',[member(25,0)]),e=>e.code==='40001');
  const body={version:2,request_id:id(request++),date:'2026-10-01',work_id:id(100),people:[member(26)]};
  const old=await call(a,10,'fn_equipa_operar_v2',['team_add',body,false,null]);await operate('team_add',[member(26)]);
  await assert.rejects(call(a,10,'fn_equipa_operar_v2',['team_add',body,true,old.versao]),e=>e.code==='40001');
 });
 await t.test('G — horas próprias do Diretor não criam equipa física',async()=>{
  const body={version:2,request_id:id(request++),date:'2026-10-09',work_id:id(100),key:{kind:'primeline',person_id:id(60),work_id:id(100),date:'2026-10-09'},expected_revision:0,intervals:[{start:'08:00',end:'11:00'}]};
  const preview=await call(a,14,'fn_folha_operar_v2',['save',body,false,null]);await call(a,14,'fn_folha_operar_v2',['save',body,true,preview.versao]);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(60)])).rows[0].n,0);
  assert.ok(!(await context(13,100,'2026-10-09')).rows.some(x=>x.person_id===id(60)));
  assert.ok((await context(14,100,'2026-10-09')).rows.some(x=>x.person_id===id(60)));
  assert.equal((await context(14,100,'2026-10-09')).management,true);
  assert.equal((await context(13,100,'2026-10-09')).management,false);
  for(const [person,user] of [[61,15],[62,16]]){
   const own={...body,request_id:id(request++),key:{...body.key,person_id:id(person)}};
   const p=await call(a,user,'fn_folha_operar_v2',['save',own,false,null]);await call(a,user,'fn_folha_operar_v2',['save',own,true,p.versao]);
   assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(person)])).rows[0].n,0);
  }
 });
 await t.test('H/I/J/K — externo factual 6h/7h, função obrigatória, sem payroll/HE',async()=>{
  for(const [n,intervals,total] of [[1,[{start:'10:00',end:'16:00'}],360],[2,[{start:'08:00',end:'12:00'},{start:'13:00',end:'16:00'}],420]]){
   const body={version:2,request_id:id(request++),date:'2026-10-09',work_id:id(100),provider_id:id(300),name:'Externo sintético '+n,role:'servente',intervals};
   const preview=await call(a,10,'fn_folha_operar_v2',['external_register',body,false,null]);await call(a,10,'fn_folha_operar_v2',['external_register',body,true,preview.versao]);
   assert.equal((await q('SELECT minutes FROM folha_registos WHERE externo_id=$1',[body.request_id])).rows[0].minutes,total);
   const factual=(await q('SELECT estado,expected_minutes FROM folha_registos WHERE externo_id=$1',[body.request_id])).rows[0];assert.equal(factual.estado,'registered');assert.equal(factual.expected_minutes,null);
   assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id IN(SELECT id FROM folha_registos WHERE externo_id=$1)',[body.request_id])).rows[0].n,0);
   const normal={version:2,request_id:id(request++),date:body.date,work_id:body.work_id,operation:'normal',items:[{key:{kind:'external',person_id:body.request_id,work_id:body.work_id,date:body.date},expected_revision:1,intervals}]};
   await assert.rejects(call(a,10,'fn_folha_operar_v2',['bulk',normal,false,null]),/ABSENCE_CONFLICT/);
   assert.equal((await q('SELECT count(*)::int n FROM folha_vencimentos WHERE colaborador_id=$1',[body.request_id])).rows[0].n,0);
  }
  const invalid={version:2,request_id:id(request++),date:'2026-10-09',work_id:id(100),provider_id:id(300),name:'Inválido',role:'diretor_obra',intervals:[{start:'10:00',end:'16:00'}]};
  await assert.rejects(call(a,10,'fn_folha_operar_v2',['external_register',invalid,false,null]),/função externa/);
 });
 await t.test('M/N — delegações explícitas/NULL; férias globais mínimas sem escrita',async()=>{
  await q("UPDATE colaboradores SET delegacao='algarve' WHERE id=$1",[id(24)]);
  const people=await as(a,13,'SELECT fn_folha_pessoas_v2($1::date,$2::uuid) v',['2026-10-09',id(100)]);
  assert.equal(people.people.find(x=>x.person_id===id(24)).delegation,'algarve');
  assert.equal(people.people.find(x=>x.person_id===id(27)).delegation,null);
  const map=await as(a,13,'SELECT fn_folha_ferias_mapa_v2($1::date,$2::date) v',['2026-10-01','2026-10-31']);
  assert.ok(map.people.some(x=>x.id===id(60)));assert.ok(!map.people.some(x=>x.id===id(49)));
  assert.deepEqual(Object.keys(map.people[0]).sort(),['funcao','id','nome']);
  const body={version:2,request_id:id(request++),person_id:id(60),dates:['2026-10-12'],expected_revision:0};
  await assert.rejects(call(a,13,'fn_folha_gestao_v2',['vacation_set',body,false,null]),e=>e.code==='42501');
 });
 await t.test('O/P/Q — reporte, alerta existente, fecho oficial pelo Diretor',async()=>{
  const body={version:2,request_id:id(request++),task_id:id(501),work_id:id(100),expected_revision:0};
  const preview=await call(a,13,'fn_folha_gestao_v2',['task_report',body,false,null]);await call(a,13,'fn_folha_gestao_v2',['task_report',body,true,preview.versao]);
  await call(a,13,'fn_folha_gestao_v2',['task_report',body,true,preview.versao]);
  assert.equal((await q('SELECT count(*)::int n FROM folha_tarefas_reportes WHERE tarefa_id=$1',[id(501)])).rows[0].n,1);
  assert.equal((await q('SELECT estado FROM planeamento_itens WHERE id=$1',[id(501)])).rows[0].estado,'em_execucao');
  const ctx=await as(a,14,'SELECT fn_folha_gestao_contexto_v2($1::uuid,NULL,NULL) v',[id(100)]);
  assert.equal(ctx.task_reports[0].reportado_nome,'Perfil sintético 13');
  assert.ok((await q("SELECT count(*)::int n FROM alertas WHERE tipo='folha_conclusao_reportada' AND destinatario_utilizador_id=$1",[id(14)])).rows[0].n>0);
  await assert.rejects(call(a,13,'fn_folha_gestao_v2',['task_confirm',{...body,request_id:id(request++),expected_revision:1},false,null]),e=>e.code==='42501');
  await q("SELECT set_config('test.actor',$1,false)",[id(14)]);await q("UPDATE planeamento_itens SET estado='concluido' WHERE id=$1",[id(501)]);
  assert.equal((await q('SELECT estado FROM folha_tarefas_reportes WHERE tarefa_id=$1',[id(501)])).rows[0].estado,'confirmed');
 });
 await t.test('R — writer legado CLOSED; DML direto e fontes alternativas recusados',async()=>{
  await assert.rejects(q('INSERT INTO ponto_pessoal_obra DEFAULT VALUES'),/LEGACY_WRITER_CLOSED/);
  await assert.rejects(as(a,13,'INSERT INTO quadro_equipa_permanencias DEFAULT VALUES'),/permission denied/);
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await assert.rejects(q("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,semana_inicio,data) VALUES($1,$2,'2026-10-01','2026-10-09')",[id(23),id(101)]),/TEAM_PERSISTENT/);
  const body={version:2,request_id:id(request++),date:'2026-10-09',work_id:id(100),person_id:id(27),period:'dia_inteiro',expected_allocation_revision:0};
  await assert.rejects(call(a,13,'fn_folha_operar_v2',['allocate',body,false,null]),/TEAM_CONTRACT_REQUIRED/);
  const quad={version:1,request_id:id(request++),colaborador_id:id(60),obra_id:id(100),data:'2026-10-09',periodo:'dia_inteiro',tipo_alocacao:'obra',expected_revision:0};
  await assert.rejects(call(a,13,'fn_quadro_operar_v1',['alocar',quad,false,null]),e=>e.code==='42501');
  const own={version:2,request_id:id(request++),date:'2026-10-09',work_id:id(100),key:{kind:'primeline',person_id:id(60),work_id:id(100),date:'2026-10-09'},expected_revision:1,intervals:[{start:'08:00',end:'11:00'}]};
  await assert.rejects(call(a,13,'fn_folha_operar_v2',['save',own,false,null]),e=>e.code==='42501');
 });
 await t.test('manual sem calendário funciona; automático exige calendário; sem dados futuros inventados',async()=>{
  const date='2026-10-09',body={version:2,request_id:id(request++),date,work_id:id(100),key:{kind:'primeline',person_id:id(23),work_id:id(100),date},expected_revision:0,intervals:[{start:'08:00',end:'12:00'}]};
  const preview=await call(a,13,'fn_folha_operar_v2',['save',body,false,null]);await call(a,13,'fn_folha_operar_v2',['save',body,true,preview.versao]);
  assert.equal((await q('SELECT minutes FROM folha_registos WHERE colaborador_id=$1',[id(23)])).rows[0].minutes,240);
  await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
  await assert.rejects(q('SELECT folha_privado.normal($1,$2,$3)',[id(23),id(100),date]),/CALENDAR_REQUIRED/);
  const map=await context(13,100,date);assert.equal(map.calendar_verified,false);
 });
 await t.test('concorrência: mesmo colaborador, duas obras → só uma confirmação',async()=>{
  const data={version:2,request_id:id(request++),date:'2026-10-01',work_id:id(100),people:[member(28)]},other={...data,request_id:id(request++),work_id:id(101)};
  const pa=await call(a,10,'fn_equipa_operar_v2',['team_add',data,false,null]),pb=await call(b,10,'fn_equipa_operar_v2',['team_add',other,false,null]);
  const outcomes=await Promise.allSettled([call(a,10,'fn_equipa_operar_v2',['team_add',data,true,pa.versao]),call(b,10,'fn_equipa_operar_v2',['team_add',other,true,pb.versao])]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1',[id(28)])).rows[0].n,1);
 });
 await t.test('concorrência de replay Quadro e isolamento: uma única permanência/movimento',async()=>{
  const body={version:1,request_id:id(request++),colaborador_id:id(34),obra_id:id(100),data:'2026-10-01',periodo:'dia_inteiro',tipo_alocacao:'obra',expected_revision:0};
  const p=await call(a,10,'fn_quadro_operar_v1',['alocar',body,false,null]);
  const results=await Promise.all([call(a,10,'fn_quadro_operar_v1',['alocar',body,true,p.versao]),call(b,10,'fn_quadro_operar_v1',['alocar',body,true,p.versao])]);
  assert.deepEqual(results[0],results[1]);assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_movimentos WHERE request_id=$1',[body.request_id])).rows[0].n,1);
  await a.query("SELECT set_config('test.actor',$1,false)",[id(10)]);await a.query('SET ROLE authenticated');await a.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
  await assert.rejects(a.query('SELECT fn_equipa_operar_v2($1,$2::jsonb,false,NULL)',['team_add',{version:2,request_id:id(request++),work_id:id(100),date:'2026-10-01',people:[member(35)]}]),e=>e.code==='40001');
  await a.query('ROLLBACK');await a.query('RESET ROLE');
 });
 await t.test('alocação diária existente exige confirmação explícita; permanece sem backfill',async()=>{
  const c=await as(a,13,'SELECT fn_folha_pessoas_v2($1::date,$2::uuid) v',['2026-01-04',id(100)]);
  assert.equal(c.people.find(x=>x.person_id===id(20)).can_allocate,true);
  await operate('team_add',[member(20)],100,'2026-01-04');
  assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,227);
  assert.ok((await context(13,100,'2026-12-01')).rows.some(x=>x.person_id===id(20)));
 });
 await t.test('rollback com dados recusa perda; 227 originais continuam intactas',async()=>{
  await assert.rejects(q(await read('../supabase/folha_equipa_operacional_rollback.sql')),/ROLLBACK_DATA_PRESENT/);await q('ROLLBACK');
  assert.equal((await q("SELECT (SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text COLLATE \"C\"),'[]') FROM quadro_pessoal_alocacao x)=(SELECT linhas FROM primeline_equipa_backup.legado WHERE tabela='quadro_pessoal_alocacao') v")).rows[0].v,true);
 });
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
