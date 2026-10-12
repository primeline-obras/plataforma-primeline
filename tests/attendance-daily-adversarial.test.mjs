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
test('Auditoria adversarial — candidato a273227, PostgreSQL 17.6',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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

 // Captured real definitions and ACL; preserve CRLF and exclude production data/OIDs.
 const realBaseline=JSON.parse(await read('./fixtures/encarregado-final-baseline-real-20261011.json'));
 async function installRealBaseline(normalize=false){for(const f of realBaseline.functions){
  await q(normalize?f.definicao.replace(/\r\n/g,'\n'):f.definicao);
  await q('REVOKE ALL ON FUNCTION '+f.assinatura+' FROM PUBLIC,anon,authenticated,service_role');
  for(const acl of f.metadata.acl_efetiva)await q('GRANT EXECUTE ON FUNCTION '+f.assinatura+' TO '+acl.grantee);
 }}
 await installRealBaseline();
 await q(await read('../supabase/encarregado_fecho_final_precheck.sql'));
 await q(await read('../supabase/encarregado_fecho_final_backup.sql'));
 await q(await read('../supabase/encarregado_fecho_final.sql'));
 await q(await read('../supabase/encarregado_fecho_final_postcheck.sql'));
 await admin.query("SELECT set_config('test.actor',$1,false)",[id(10)]);
 await q('INSERT INTO folha_config_empresa(empresa_id) VALUES($1) ON CONFLICT DO NOTHING',[id(1)]);

 // Nonempty previous operational data, created through baseline RPCs; entirely synthetic.
 const seedDate='2026-10-09';
 await q("UPDATE folha_config_empresa SET overtime_enabled=true,calendar_complete=true,calendar_validated_years=ARRAY[2026] WHERE empresa_id=$1",[id(1)]);
 const scheduleBody={version:2,request_id:id(700001),work_id:id(100),expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:'manha'},{start:'13:00',end:'17:00',period:'tarde'}],expected_minutes:480};
 const schedulePreview=await call(a,10,'fn_folha_gestao_v2',['configure_schedule',scheduleBody,false,null]);await call(a,10,'fn_folha_gestao_v2',['configure_schedule',scheduleBody,true,schedulePreview.versao]);
 await operate('team_add',[member(45)],100,seedDate);
 const seedBody={version:2,request_id:id(700002),work_id:id(100),date:seedDate,key:{kind:'primeline',person_id:id(45),work_id:id(100),date:seedDate},reason:'Factos anteriores sintéticos',sites:[{work_id:id(100),expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:'manha'},{start:'13:00',end:'18:00',period:'tarde'}]}]};
 const seedPreview=await call(a,10,'fn_folha_operar_v2',['periods_save',seedBody,false,null]);await call(a,10,'fn_folha_operar_v2',['periods_save',seedBody,true,seedPreview.versao]);
 const payrollBody={version:2,request_id:id(700003),person_id:id(45),month:'2026-10-01',expected_revision:0,manual:{km:0,allowance:0}};const payrollPreview=await call(a,10,'fn_folha_gestao_v2',['payroll_save',payrollBody,false,null]);await call(a,10,'fn_folha_gestao_v2',['payroll_save',payrollBody,true,payrollPreview.versao]);
 const seededRecord=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(45)])).rows[0];assert.equal(seededRecord.expected_minutes,480);assert.equal(seededRecord.minutes,540);assert.equal((await q('SELECT count(*)::int n FROM folha_he WHERE folha_id=$1',[seededRecord.id])).rows[0].n,1);
 await q(await read('../supabase/folha_avaliacao_diaria_precheck.sql'));
 await q(await read('../supabase/folha_avaliacao_diaria_backup.sql'));
 await t.test('adversarial: falha depois de DDL reverte colunas/tabela integralmente',async()=>{
  const raw=await read('../supabase/folha_avaliacao_diaria.sql');
  const fault=raw.replace('CREATE TABLE public.folha_avaliacoes_diarias(',()=>"DO $$ BEGIN RAISE EXCEPTION 'AUDIT_MIDDLE_FAILURE'; END $$;\nCREATE TABLE public.folha_avaliacoes_diarias(");
  await assert.rejects(q(fault),/AUDIT_MIDDLE_FAILURE/);await q('ROLLBACK');
  assert.equal((await q("SELECT to_regclass('public.folha_horarios_versoes') v")).rows[0].v,null);
  assert.equal((await q("SELECT count(*)::int n FROM pg_attribute WHERE attrelid='public.folha_config_empresa'::regclass AND attname='avaliacao_diaria_data_ativacao' AND NOT attisdropped")).rows[0].n,0);
 });
 await t.test('adversarial: nome de tabela ocupado recusa sem DDL parcial',async()=>{
  await q('BEGIN');await q('CREATE TABLE public.folha_horarios_versoes(id integer)');await assert.rejects(q(await read('../supabase/folha_avaliacao_diaria.sql')),/DAILY_ALREADY_INSTALLED/);await q('ROLLBACK');assert.equal((await q("SELECT to_regclass('public.folha_horarios_versoes') v")).rows[0].v,null);
 });

 await t.test('migration recusa ACL de função alterada após backup, sem instalação parcial',async()=>{
  await q('BEGIN');await q('GRANT EXECUTE ON FUNCTION folha_privado.save(jsonb,uuid,date,uuid,boolean) TO anon');await assert.rejects(q(await read('../supabase/folha_avaliacao_diaria.sql')),/DAILY_BACKUP_FUNCTION_DRIFT/);await q('ROLLBACK');assert.equal((await q("SELECT to_regclass('public.folha_avaliacoes_diarias') v")).rows[0].v,null);
 });

 await q(await read('../supabase/folha_avaliacao_diaria.sql'));
 await q(await read('../supabase/folha_avaliacao_diaria_postcheck.sql'));
 await q(await read('../supabase/folha_avaliacao_diaria_rollback.sql'));
 await q(await read('../supabase/folha_avaliacao_diaria.sql'));
 await q(await read('../supabase/folha_avaliacao_diaria_postcheck.sql'));


 await t.test('adversarial: dados prévios não vazios preservados em instalação e rollback',async()=>{
  const current=(await q('SELECT * FROM folha_registos WHERE id=$1',[seededRecord.id])).rows[0];assert.deepEqual(current,seededRecord);
  await q(await read('../supabase/folha_avaliacao_diaria_postcheck.sql'));
  console.log('AUDIT_EXISTING_DATA '+JSON.stringify({folha_registos:(await q('SELECT count(*)::int n FROM folha_registos')).rows[0].n,folha_he:(await q('SELECT count(*)::int n FROM folha_he')).rows[0].n,folha_vencimentos:(await q('SELECT count(*)::int n FROM folha_vencimentos')).rows[0].n,record_expected_unchanged:480,record_minutes_unchanged:540,backup_comparison:'ALL_TABLE_ROWS_IDENTICAL',activated_companies:0}));
 });

 await t.test('adversarial: DELETE owner de horário é silenciosamente cancelado antes de ativar',async()=>{
  await q('BEGIN');const before=(await q('SELECT count(*)::int n FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0].n;assert.equal(before,1);
  const deleted=await q('DELETE FROM folha_horarios WHERE obra_id=$1 RETURNING obra_id',[id(100)]);assert.equal(deleted.rowCount,0);assert.equal((await q('SELECT count(*)::int n FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0].n,1);await q('ROLLBACK');console.log('AUDIT_DELETE_INACTIVE '+JSON.stringify({existing:1,deleted:0,activated:false,scope:'owner maintenance',contract:'FAIL'}));
 });
 const postSQL=await read('../supabase/folha_avaliacao_diaria_postcheck.sql');
 for(const [name,attack,pattern] of [
  ['ACL tabela','GRANT SELECT ON folha_avaliacoes_diarias TO authenticated',/DAILY_ACL_OR_POLICY_DIVERGENCE/],
  ['ACL coluna','GRANT SELECT (horario_snapshot) ON folha_avaliacoes_diarias TO anon',/DAILY_ACL_OR_POLICY_DIVERGENCE/],
  ['trigger disabled','ALTER TABLE folha_registos DISABLE TRIGGER folha_diaria_factos',/DAILY_TRIGGER_MISSING_OR_DISABLED/],
  ['função alterada',"CREATE OR REPLACE FUNCTION folha_privado.diaria_pessoal(p uuid,d date) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$ SELECT false $$",/DAILY_FUNCTION_DIVERGENCE/],
  ['CHECK retirado','ALTER TABLE folha_avaliacoes_diarias DROP CONSTRAINT folha_avaliacoes_diarias_modo_dia_check',/DAILY_SCHEMA_DIVERGENCE/],
  ['backup público','GRANT USAGE ON SCHEMA primeline_diaria_backup TO PUBLIC',/DAILY_BACKUP_NOT_PRIVATE/]
 ]) await t.test('postcheck negativo: '+name,async()=>{await q('BEGIN');await q(attack);await assert.rejects(q(postSQL),pattern);await q('ROLLBACK');await q(postSQL);});

 await t.test('adversarial: reexecução recusa sem alterar instalação',async()=>{
  const migrationSQL=await read('../supabase/folha_avaliacao_diaria.sql');
  await assert.rejects(q(migrationSQL),/DAILY_ALREADY_INSTALLED/);await q('ROLLBACK');await q(postSQL);
 });
 const readRollback=await read('../supabase/folha_avaliacao_diaria_rollback.sql');
 const today=(await q("SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date::text d")).rows[0].d;
 let seq=100000;
 const custom=(start,end)=>({start,end,period:null,mode:'personalizado'});
 const normal=(start,end,period)=>({start,end,period});
 const schedule=[normal('08:00','12:00','manha'),normal('13:00','17:00','tarde')];
 async function adminOp(action,body){const payload={version:2,request_id:id(seq++),...body};const preview=await call(a,10,'fn_folha_diaria_gestao_v2',[action,payload,false,null]);const committed=await call(a,10,'fn_folha_diaria_gestao_v2',[action,payload,true,preview.versao]);return {payload,preview,committed};}
 const daily=async p=>(await q('SELECT * FROM folha_avaliacoes_diarias WHERE colaborador_id=$1 AND data=$2',[id(p),today])).rows[0];
 async function team(p){await operate('team_add',[member(p)],100,today);}
 async function plan(p,sites,date=today){
  const rows=(await q('SELECT obra_id,revision FROM folha_registos WHERE colaborador_id=$1 AND data=$2',[id(p),date])).rows;
  const ev=(await q('SELECT revision FROM folha_avaliacoes_diarias WHERE colaborador_id=$1 AND data=$2',[id(p),date])).rows[0];
  return {version:2,request_id:id(seq++),work_id:id(100),date,key:{kind:'primeline',person_id:id(p),work_id:id(100),date},expected_daily_revision:ev?.revision||0,reason:'Teste administrativo sintético',sites:sites.map(([work,intervals])=>({work_id:work?id(work):null,intervals,expected_revision:rows.find(x=>x.obra_id===(work?id(work):null))?.revision||0}))};
 }
 const periodCall=(body,confirm=false,token=null,c=a)=>call(c,10,'fn_folha_operar_v2',['periods_save',body,confirm,token]);
 async function savePlan(p,sites,date=today){const body=await plan(p,sites,date);const pre=await periodCall(body);assert.equal(pre.committed,false);const result=await periodCall(body,true,pre.versao);return {body,pre,result};}
 // Configure baseline schedules before activation, through the existing contract wrapper.
 for(const work of [100,101,102]){
  const h=(await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(work)])).rows[0];
  await adminOp('configure_schedule',{work_id:id(work),expected_revision:h?.revision||0,intervals:schedule,expected_minutes:480});
 }
 await t.test('migration mantém factos existentes e não ativa empresas',async()=>{assert.equal((await q('SELECT count(*)::int n FROM folha_avaliacoes_diarias')).rows[0].n,0);assert.equal((await q('SELECT count(*)::int n FROM folha_horarios_versoes')).rows[0].n,0);assert.equal((await q('SELECT count(*)::int n FROM folha_config_empresa WHERE avaliacao_diaria_data_ativacao IS NOT NULL')).rows[0].n,0);});
 const cfg=(await q('SELECT revision FROM folha_config_empresa WHERE empresa_id=$1',[id(1)])).rows[0];
 await adminOp('daily_activation',{date:today,expected_revision:cfg.revision});
 await t.test('ativação explícita cria versões-base, sem factos ou avaliações',async()=>{assert.equal((await q('SELECT count(*)::int n FROM folha_horarios_versoes')).rows[0].n,3);assert.equal((await q('SELECT count(*)::int n FROM folha_avaliacoes_diarias')).rows[0].n,0);});
 await t.test('dias exclusivamente normais não criam avaliação diária',async()=>{await team(30);const normalSaved=await savePlan(30,[[100,schedule]]);assert.ok(!('daily_evaluation' in normalSaved.result));assert.equal(await daily(30),undefined);const row=await context(10,100,today);assert.ok(!('daily_evaluation' in row.rows.find(x=>x.person_id===id(30))));const f=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(30)])).rows[0];assert.equal(f.expected_minutes,480);assert.equal(f.estado,'registered');});
 await t.test('personalizado 8h regular, period NULL e expected factual NULL',async()=>{await team(31);await savePlan(31,[[100,[custom('09:00','17:00')]]]);const d=await daily(31);assert.equal(d.estado,'regular');assert.equal(d.expected_minutes,480);assert.equal(d.realizado_minutes,480);const f=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(31)])).rows[0];assert.equal(f.expected_minutes,null);assert.equal(f.intervals.length,1);assert.equal(f.intervals[0].period,null);});
 await t.test('7h30 em jornada 8h falta 30min',async()=>{await team(32);await savePlan(32,[[100,[custom('09:00','16:30')]]]);const d=await daily(32);assert.equal(d.falta_minutes,30);assert.equal(d.estado,'horas_em_falta');});
 await t.test('9h potencial HE 1h sem folha_he',async()=>{await team(33);await savePlan(33,[[100,[custom('08:00','17:00')]]]);const d=await daily(33);assert.equal(d.excedente_minutes,60);assert.equal(d.estado,'potencial_he');assert.equal(d.he_estado,'pendente');assert.ok(d.pendencias.includes('he_diaria_pendente'));assert.equal((await q('SELECT count(*)::int n FROM folha_he h JOIN folha_registos f ON f.id=h.folha_id WHERE f.colaborador_id=$1',[id(33)])).rows[0].n,0);});
 const closeAttempt=p=>call(a,10,'fn_folha_gestao_v2',['payroll_validate',{version:2,request_id:id(seq++),person_id:id(p),month:today.slice(0,7)+'-01',expected_revision:0},false,null]);
 await t.test('HE pendente bloqueia gate',async()=>{await assert.rejects(closeAttempt(33),/PAYROLL_DAILY_PENDING/);});
 await t.test('HE validada permanece potencial e bloqueia aguardando processamento',async()=>{await adminOp('daily_he_validate',{person_id:id(33),date:today,expected_revision:(await daily(33)).revision,reason:'Reconhecimento sintético'});const d=await daily(33);assert.equal(d.estado,'potencial_he');assert.equal(d.he_estado,'validada');assert.ok(d.pendencias.includes('he_validada_aguarda_processamento'));await assert.rejects(closeAttempt(33),/PAYROLL_DAILY_PENDING/);});
 await t.test('não considerar remove somente a pendência HE',async()=>{await q('UPDATE folha_avaliacoes_diarias SET pendencias=pendencias||ARRAY[\'outra_pendencia_sintetica\'] WHERE colaborador_id=$1',[id(33)]);await adminOp('daily_he_disregard',{person_id:id(33),date:today,expected_revision:(await daily(33)).revision,reason:'Não considerada no teste'});const d=await daily(33);assert.equal(d.he_estado,'nao_considerada');assert.deepEqual(d.pendencias,['outra_pendencia_sintetica']);await assert.rejects(closeAttempt(33),/PAYROLL_DAILY_PENDING/);});
 await t.test('dia misto agrega normal e personalizado uma vez',async()=>{await team(34);await savePlan(34,[[100,[normal('08:00','12:00','manha')]],[101,[custom('13:00','17:00')]]]);const d=await daily(34);assert.equal(d.modo_dia,'misto');assert.equal(d.realizado_minutes,480);assert.equal(d.expected_minutes,480);assert.equal(d.estado,'regular');});
 await t.test('multiobra 4h + 1h30 + 1h30 = 7h, esperado único 8h',async()=>{await team(35);await savePlan(35,[[100,[custom('08:00','10:00'),custom('15:00','17:00')]],[101,[custom('10:30','12:00')]],[102,[custom('13:00','14:30')]]]);const d=await daily(35);assert.equal(d.realizado_minutes,420);assert.equal(d.expected_minutes,480);assert.equal(d.falta_minutes,60);assert.equal((await q('SELECT count(*)::int n FROM folha_registos WHERE colaborador_id=$1',[id(35)])).rows[0].n,3);});
 await t.test('10:30–14:30 permanece intervalo único',async()=>{await team(36);await savePlan(36,[[100,[custom('10:30','14:30')]]]);const f=(await q('SELECT intervals FROM folha_registos WHERE colaborador_id=$1',[id(36)])).rows[0];assert.deepEqual(f.intervals,[custom('10:30','14:30')]);assert.equal((await daily(36)).realizado_minutes,240);});
 await t.test('edição preserva snapshot e invalida decisão HE anterior',async()=>{const old=await daily(33);await savePlan(33,[[100,[custom('08:00','17:30')]]]);const d=await daily(33);assert.deepEqual(d.horario_snapshot,old.horario_snapshot);assert.equal(d.he_estado,'pendente');assert.equal(d.he_decidido_por,null);assert.ok((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE entidade_id=$1 AND action='daily_he_invalidate'",[d.id])).rows[0].n>0);});
 await t.test('remover último personalizado desativa e reintroduzir reativa mesma referência',async()=>{const old=await daily(31);await savePlan(31,[[100,schedule]]);let d=await daily(31);assert.equal(d.ativa,false);assert.equal(d.estado,'inativa');await savePlan(31,[[100,[custom('09:00','17:00')]]]);d=await daily(31);assert.equal(d.ativa,true);assert.equal(d.id,old.id);assert.equal(d.horario_versao_id,old.horario_versao_id);assert.deepEqual(d.horario_snapshot,old.horario_snapshot);});
 await t.test('mudança de equipa posterior não recaptura referência',async()=>{const old=await daily(31);await q('UPDATE quadro_equipa_permanencias SET fim=$1::date+1 WHERE colaborador_id=$2 AND fim IS NULL',[today,id(31)]);await savePlan(31,[[100,[custom('09:30','17:30')]]]);const d=await daily(31);assert.equal(d.permanencia_id,old.permanencia_id);assert.deepEqual(d.permanencia_snapshot,old.permanencia_snapshot);});
 await t.test('alteração de horário hoje cria versão, referência antiga permanece',async()=>{const old=await daily(31);const h=(await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0];await adminOp('configure_schedule',{work_id:id(100),expected_revision:h.revision,intervals:[normal('08:00','12:00','manha'),normal('13:00','16:30','tarde')],expected_minutes:450});await savePlan(31,[[100,[custom('09:00','17:00')]]]);assert.deepEqual((await daily(31)).horario_snapshot,old.horario_snapshot);await team(37);await savePlan(37,[[100,[custom('09:00','16:30')]]]);assert.equal((await daily(37)).expected_minutes,450);});
 await t.test('horário futuro recusado',async()=>{const h=(await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0];const future=(await q('SELECT ($1::date+1)::text d',[today])).rows[0].d;await assert.rejects(adminOp('configure_schedule',{work_id:id(100),expected_revision:h.revision,vigente_desde:future,intervals:schedule,expected_minutes:480}),/SCHEDULE_EFFECTIVE_TODAY_ONLY/);});
 await t.test('data anterior ao corte não usa horário atual',async()=>{const previous=(await q('SELECT ($1::date-1)::text d',[today])).rows[0].d;await operate('team_add',[member(38)],100,previous);await savePlan(38,[[100,[custom('09:00','17:00')]]],previous);const d=(await q('SELECT * FROM folha_avaliacoes_diarias WHERE colaborador_id=$1 AND data=$2',[id(38),previous])).rows[0];assert.equal(d.referencia_estado,'pendente');assert.equal(d.expected_minutes,null);assert.equal(d.referencia_motivo,'historico_anterior_ao_corte');});
 await t.test('sem origem inequívoca fica pendente sem inventar jornada',async()=>{await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,semana_inicio,data,periodo,criado_por) VALUES($1,$2,$3,$4,$4,'dia_inteiro',$5)",[id(seq++),id(39),id(100),today,id(10)]);await savePlan(39,[[100,[custom('09:00','17:00')]]]);assert.equal((await daily(39)).referencia_estado,'pendente');assert.equal((await daily(39)).expected_minutes,null);});
 await t.test('revisão antiga e token stale não gravam',async()=>{const body=await plan(31,[[100,[custom('08:30','16:30')]]]);const pre=await periodCall(body);await savePlan(31,[[100,[custom('09:00','17:30')]]]);await assert.rejects(periodCall(body,true,pre.versao),/STALE_REVISION/);const fresh=await plan(31,[[100,[custom('08:30','16:30')]]]);await assert.rejects(periodCall(fresh,true,'0'.repeat(64)),/STALE_PREVIEW/);});
 await t.test('replay é idempotente e payload diferente recusado',async()=>{const x=await savePlan(31,[[100,[custom('09:00','17:00')]]]);assert.deepEqual(await periodCall(x.body,true,x.pre.versao),x.result);await assert.rejects(periodCall({...x.body,note:'diferente'},true,x.pre.versao),/IDEMPOTENCY_CONFLICT/);});
 await t.test('DML direto e GUC falsificado não autorizam escrita',async()=>{await a.query("SELECT set_config('folha.diaria_rpc','on',false)");await a.query('SET ROLE authenticated');try{await assert.rejects(a.query('UPDATE folha_avaliacoes_diarias SET estado=\'regular\''),/permission denied/);await assert.rejects(a.query('UPDATE folha_horarios_versoes SET vigente_ate=NULL'),/permission denied/);}finally{await a.query('RESET ROLE');}});

 await t.test('duas ligações: mesma revisão, apenas uma confirmação',async()=>{
  const one=await plan(31,[[100,[custom('09:00','16:30')]]]),two=await plan(31,[[100,[custom('09:00','16:00')]]]);
  const pa=await periodCall(one),pb=await periodCall(two,false,null,b);
  await a.query('BEGIN');await periodCall(one,true,pa.versao);
  const pending=result(periodCall(two,true,pb.versao,b));await delay(100);
  const activity=await q("SELECT count(*)::int n FROM pg_stat_activity WHERE pid=$1 AND wait_event_type='Lock'",[b.processID]);assert.equal(activity.rows[0].n,1,'segunda ligação aguarda lock real');
  await a.query('COMMIT');const r=await pending;assert.match(r.error?.message||'',/STALE_REVISION/);
 });
 await t.test('duas ligações: mesmo request/payload produz um histórico de lote',async()=>{
  const body=await plan(31,[[100,[custom('09:00','17:00')]]]),pre=await periodCall(body);
  const before=(await q('SELECT count(*)::int n FROM folha_historico WHERE request_id=$1',[body.request_id])).rows[0].n;
  await a.query('BEGIN');const first=await periodCall(body,true,pre.versao);const pending=result(periodCall(body,true,pre.versao,b));await delay(100);await a.query('COMMIT');const r=await pending;assert.equal(r.error,undefined);assert.deepEqual(r.value,first);
  const after=(await q('SELECT count(*)::int n FROM folha_historico WHERE request_id=$1',[body.request_id])).rows[0].n;assert.equal(after-before,1);
 });
 await t.test('duas ligações: mesmo request/payload diferente é conflito',async()=>{
  const body=await plan(31,[[100,[custom('09:00','17:30')]]]),pre=await periodCall(body);
  await a.query('BEGIN');await periodCall(body,true,pre.versao);const pending=result(periodCall({...body,note:'payload divergente'},true,pre.versao,b));await delay(100);await a.query('COMMIT');const r=await pending;assert.match(r.error?.message||'',/IDEMPOTENCY_CONFLICT/);
 });
 await t.test('competência fechada recusa factos e decisão sem alteração parcial',async()=>{
  const old=await daily(31);await q("INSERT INTO folha_vencimentos(empresa_id,colaborador_id,competencia,factos,manuais,estado,criado_por,atualizado_por) VALUES($1,$2,date_trunc('month',$3::date),folha_privado.payroll_facts($2,date_trunc('month',$3::date)::date),'{}','closed',$4,$4)",[id(1),id(31),today,id(10)]);
  await assert.rejects(savePlan(31,[[100,[custom('09:00','16:00')]]]),/PAYROLL_CLOSED_FACTS_CHANGED/);
  assert.deepEqual(await daily(31),old);
  await assert.rejects(adminOp('daily_he_validate',{person_id:id(31),date:today,expected_revision:old.revision,reason:'Teste fechado'}),/PAYROLL_CLOSED_FACTS_CHANGED/);
 });
 await t.test('referência administrativa comprovada regulariza pré-corte sem mudar factos',async()=>{
  const yesterday=(await q('SELECT ($1::date-1)::text d',[today])).rows[0].d;
  const d=(await q('SELECT * FROM folha_avaliacoes_diarias WHERE colaborador_id=$1 AND data=$2',[id(38),yesterday])).rows[0];
  const before=(await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(38)])).rows;
  await adminOp('daily_reference_correct',{person_id:id(38),date:yesterday,work_id:id(100),expected_revision:d.revision,schedule:{intervals:schedule,expected_minutes:480},evidence:{document:'prova sintética'},reason:'Confirmação documental sintética'});
  const after=(await q('SELECT * FROM folha_avaliacoes_diarias WHERE id=$1',[d.id])).rows[0];assert.equal(after.referencia_origem,'administrativo');assert.equal(after.expected_minutes,480);assert.equal(after.referencia_estado,'capturada');assert.equal(after.falta_minutes,0);assert.ok(after.pendencias.includes('dia_especial_pendente'));assert.deepEqual((await q('SELECT * FROM folha_registos WHERE colaborador_id=$1',[id(38)])).rows,before);
 });
 await t.test('intervalo aberto fica pendente sem inventar duração final',async()=>{await team(40);await savePlan(40,[[100,[custom('09:00',null)]]]);const d=await daily(40);assert.equal(d.estado,'intervalo_aberto');assert.equal(d.falta_minutes,null);assert.equal(d.excedente_minutes,null);assert.equal(d.he_estado,'nao_avaliavel');});
 await t.test('limites 4 destinos/16 intervalos e sobreposição preservados',async()=>{
  const bad=await plan(35,[[100,[custom('08:00','10:00')]],[101,[custom('09:00','11:00')]],[102,[]]]);await assert.rejects(periodCall(bad),/INTERVAL_CONFLICT/);
  const tooMany=await plan(35,[[100,Array.from({length:17},(_,i)=>custom(String(i).padStart(2,'0')+':00',String(i).padStart(2,'0')+':30'))],[101,[]],[102,[]]]);await assert.rejects(periodCall(tooMany),/VALIDATION_ERROR: intervalos/);
  const five=await plan(35,[[100,[custom('08:00','09:00')]],[101,[]],[102,[]],[103,[]],[null,[]]]);await assert.rejects(periodCall(five),/VALIDATION_ERROR: períodos/);
 });
 await t.test('preview é read-only e token inclui referência candidata',async()=>{
  const body=await plan(37,[[100,[custom('09:00','17:00')]]]);const before=await daily(37);const pre=await periodCall(body);assert.deepEqual(await daily(37),before);assert.ok(pre.daily_reference);assert.match(pre.versao,/^[0-9a-f]{64}$/);
 });
 await t.test('rollback após ativação recusa destruir referência/histórico',async()=>{await assert.rejects(q(readRollback),/DAILY_ROLLBACK_UNSAFE_AFTER_ACTIVATION/);await q('ROLLBACK');});

 await t.test('retroativo usa versão vigente na data, nunca horário atual',async()=>{
  const dates=(await q("SELECT ($1::date-10)::text cut,($1::date-7)::text point_date,($1::date-5)::text change",[today])).rows[0];
  await q('INSERT INTO folha_config_empresa(empresa_id,avaliacao_diaria_data_ativacao,avaliacao_diaria_ativada_em,avaliacao_diaria_ativada_por,avaliacao_diaria_ativacao_request_id) VALUES($1,$2,now(),$3,$4)',[id(2),dates.cut,id(17),id(seq++)]);
  const first=(await q('INSERT INTO folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,vigente_ate,criado_por,request_id) VALUES($1,$2,1,$3,$4,$5,$6,$7) RETURNING id',[id(2),id(103),{intervals:schedule,expected_minutes:480},dates.cut,dates.change,id(17),id(seq++)])).rows[0].id;
  const newSchedule=[normal('08:00','12:00','manha'),normal('13:00','16:30','tarde')];
  await q('INSERT INTO folha_horarios_versoes(empresa_id,obra_id,revision,snapshot,vigente_desde,criado_por,request_id) VALUES($1,$2,2,$3,$4,$5,$6)',[id(2),id(103),{intervals:newSchedule,expected_minutes:450},dates.change,id(17),id(seq++)]);
  await q('INSERT INTO folha_horarios VALUES($1,$2,$3,450,2)',[id(103),id(2),JSON.stringify(newSchedule)]);
  await operate('team_add',[member(49)],103,dates.cut,17);
  const body={version:2,request_id:id(seq++),work_id:id(103),date:dates.point_date,key:{kind:'primeline',person_id:id(49),work_id:id(103),date:dates.point_date},expected_daily_revision:0,sites:[{work_id:id(103),expected_revision:0,intervals:[custom('09:00','17:00')]}],reason:'Retroativo sintético'};
  const pre=await call(b,17,'fn_folha_operar_v2',['periods_save',body,false,null]);await call(b,17,'fn_folha_operar_v2',['periods_save',body,true,pre.versao]);
  const old=(await q('SELECT * FROM folha_avaliacoes_diarias WHERE colaborador_id=$1',[id(49)])).rows[0];assert.equal(old.horario_versao_id,first);assert.equal(old.expected_minutes,480);assert.equal(old.estado,'regular');
  const correctionDate=(await q('SELECT ($1::date-8)::text d',[today])).rows[0].d;
  const correction={version:2,request_id:id(seq++),work_id:id(103),version_id:first,expected_revision:1,vigente_desde:correctionDate,intervals:[normal('08:00','12:00','manha'),normal('13:00','16:00','tarde')],expected_minutes:420,reason:'Correção administrativa sintética'};
  const cp=await call(b,17,'fn_folha_diaria_gestao_v2',['schedule_retro_correct',correction,false,null]);assert.equal(cp.preview.affected_evaluations.length,1);
  await call(b,17,'fn_folha_diaria_gestao_v2',['schedule_retro_correct',correction,true,cp.versao]);
  assert.deepEqual((await q('SELECT * FROM folha_avaliacoes_diarias WHERE id=$1',[old.id])).rows[0],old,'referência congelada não é reescrita');
  await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Pessoa sintética retroativa','Pedreiro','2026-01-01')",[id(50),id(2)]);await operate('team_add',[member(50)],103,dates.cut,17);
  const second={...body,request_id:id(seq++),key:{...body.key,person_id:id(50)}};const sp=await call(b,17,'fn_folha_operar_v2',['periods_save',second,false,null]);await call(b,17,'fn_folha_operar_v2',['periods_save',second,true,sp.versao]);assert.equal((await q('SELECT expected_minutes FROM folha_avaliacoes_diarias WHERE colaborador_id=$1',[id(50)])).rows[0].expected_minutes,420);
 });
 await t.test('Dia Normal recusa autofill sobre dia personalizado e mantém equipa',async()=>{await assert.rejects(as(a,10,'SELECT folha_privado.normal($1,$2,$3) v',[id(37),id(100),today]),/permission denied/);await assert.rejects(q('SELECT folha_privado.normal($1,$2,$3)',[id(37),id(100),today]),/PERSONALIZED_DAY_REQUIRES_EDITOR/);assert.equal((await q('SELECT count(*)::int n FROM quadro_equipa_permanencias WHERE colaborador_id=$1 AND fim IS NULL',[id(37)])).rows[0].n,1);});

 await t.test('decisão diária exige Administrativo/Gestão; replay respeita permissão corrente',async()=>{
  const d=await daily(33),body={version:2,request_id:id(seq++),person_id:id(33),date:today,expected_revision:d.revision,reason:'Prova de permissão'};
  for(const role of [11,13,14])await assert.rejects(call(b,role,'fn_folha_diaria_gestao_v2',['daily_he_validate',body,false,null]),/PERMISSION_DENIED/);
  await assert.rejects(call(b,13,'fn_folha_gestao_v2',['payroll_validate',{...body,month:today.slice(0,7)+'-01'},false,null]),/PERMISSION_DENIED/);
 });

 await t.test('cliente administrativo atual configura horário e aceita revisão +1',async()=>{
  const {createAttendanceManagementClient}=await import('../src/attendance-client.js');const before=(await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0];
  const client=createAttendanceManagementClient({confirm:async()=>true,requestId:()=>id(seq++),supabase:async(name,opts)=>{const body=JSON.parse(opts.body);assert.equal(name,'rpc/fn_folha_gestao_v2');const v=await call(a,10,'fn_folha_gestao_v2',[body.p_acao,body.p_dados,body.p_confirmar,body.p_versao]);return Response.json(v);}});
  const r=await client.execute('configure_schedule',{work_id:id(100),expected_revision:before.revision,intervals:schedule,expected_minutes:480});assert.equal(r.committed,true);assert.equal(r.revision,before.revision+1);assert.equal((await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(100)])).rows[0].revision,r.revision);
 });
 await t.test('configuração corrente mantém revisão cliente +1 depois de correção histórica',async()=>{
  const h=(await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(103)])).rows[0];const body={version:2,request_id:id(seq++),work_id:id(103),expected_revision:h.revision,intervals:schedule,expected_minutes:480};const pre=await call(b,17,'fn_folha_gestao_v2',['configure_schedule',body,false,null]);const r=await call(b,17,'fn_folha_gestao_v2',['configure_schedule',body,true,pre.versao]);assert.equal(r.revision,h.revision+1);assert.equal((await q('SELECT revision FROM folha_horarios WHERE obra_id=$1',[id(103)])).rows[0].revision,r.revision);assert.ok(r.result.version_revision>r.revision);
 });
 await t.test('replay administrativo não duplica decisão e recusa papel reduzido',async()=>{
  const saved=await adminOp('daily_he_validate',{person_id:id(33),date:today,expected_revision:(await daily(33)).revision,reason:'Validação sintética auditada'});
  const count=async()=>(await q('SELECT count(*)::int n FROM folha_gestao_historico WHERE request_id=$1',[saved.payload.request_id])).rows[0].n;const before=await count();assert.deepEqual(await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',saved.payload,true,saved.preview.versao]),saved.committed);assert.equal(await count(),before);
  await q("UPDATE utilizadores SET funcao='encarregado' WHERE id=$1",[id(10)]);try{await assert.rejects(call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',saved.payload,true,saved.preview.versao]),/PERMISSION_DENIED/);}finally{await q("UPDATE utilizadores SET funcao='administrativo' WHERE id=$1",[id(10)]);}
 });

 const observations=[];
 async function rejectProbe(name,sql,params,shouldReject){
  await q('BEGIN');let error=null;try{await q(sql,params);}catch(e){error=e;}
  await q('ROLLBACK');const row={name,rejected:!!error,error:error?.message||null,contract:!!error?'PASS':'FAIL'};observations.push(row);console.log('AUDIT '+JSON.stringify(row));assert.equal(!!error,shouldReject,name+' reprodução divergiu');
 }
 await t.test('adversarial: matriz completa de estados impossíveis',async()=>{
  const update='UPDATE public.folha_avaliacoes_diarias SET ';
  await rejectProbe('capturada_sem_snapshot_SQL_NULL',update+'horario_snapshot=NULL WHERE colaborador_id=$1',[id(33)],true);
  await rejectProbe('capturada_sem_snapshot_JSON_NULL',update+"horario_snapshot='null'::jsonb WHERE colaborador_id=$1",[id(33)],false);
  await rejectProbe('pendente_expected_preenchido',update+"referencia_estado='pendente',referencia_motivo='teste' WHERE colaborador_id=$1",[id(33)],true);
  await rejectProbe('regular_com_falta_30',update+"estado='regular' WHERE colaborador_id=$1",[id(32)],false);
  await rejectProbe('regular_excedente_pendente',update+"estado='regular',he_estado='pendente',pendencias=ARRAY['he_diaria_pendente'],decisao_fingerprint=NULL,he_decidido_por=NULL,he_decidido_em=NULL,he_motivo=NULL WHERE colaborador_id=$1",[id(33)],false);
  await rejectProbe('he_validada_sem_autor',update+'he_decidido_por=NULL WHERE colaborador_id=$1',[id(33)],true);
  await rejectProbe('he_nao_considerada_sem_decisao',update+"he_estado='nao_considerada',decisao_fingerprint=NULL,he_decidido_por=NULL,he_decidido_em=NULL,he_motivo=NULL WHERE colaborador_id=$1",[id(33)],true);
  await rejectProbe('inativa_false_sem_estado',update+"ativa=false,estado='regular' WHERE colaborador_id=$1",[id(33)],true);
  await rejectProbe('duplicada_pessoa_data',"INSERT INTO public.folha_avaliacoes_diarias SELECT (jsonb_populate_record(NULL::public.folha_avaliacoes_diarias,to_jsonb(e)||jsonb_build_object('id',$2::uuid))).* FROM public.folha_avaliacoes_diarias e WHERE e.colaborador_id=$1",[id(33),id(seq++)],true);
  await rejectProbe('fingerprint_invalido',update+"factos_fingerprint='invalido' WHERE colaborador_id=$1",[id(33)],true);
  await rejectProbe('tenant_cruzado',update+'empresa_id=$2 WHERE colaborador_id=$1',[id(33),id(2)],true);
  await rejectProbe('he_validada_excedente_NULL',update+'falta_minutes=NULL,excedente_minutes=NULL WHERE colaborador_id=$1',[id(33)],false);
 });
 await t.test('adversarial: quatro perfis próprios sem permanência ficam sem referência',async()=>{
  for(const [p,user,role] of [[170,13,'Encarregado'],[60,14,'Diretor de obra'],[61,15,'Adjunto'],[62,16,'Preparador']]){
   if(p===170)await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao,utilizador_id) VALUES($1,$2,'Perfil próprio sintético',$3,'2026-01-01',$4)",[id(p),id(1),role,id(user)]);
   const body={version:2,request_id:id(seq++),work_id:id(100),date:today,key:{kind:'primeline',person_id:id(p),work_id:id(100),date:today},expected_daily_revision:0,sites:[{work_id:id(100),expected_revision:0,intervals:[custom('09:00','17:00')]}]};
   const pre=await call(a,user,'fn_folha_operar_v2',['periods_save',body,false,null]);const r=await call(a,user,'fn_folha_operar_v2',['periods_save',body,true,pre.versao]);assert.equal(r.committed,true);
   const d=await daily(p);assert.equal(d.expected_minutes,null);assert.equal(d.referencia_estado,'pendente');assert.equal(d.referencia_motivo,'origem_principal_nao_inequivoca');console.log('AUDIT_PROFILE '+JSON.stringify({role,reference:d.referencia_estado,expected:d.expected_minutes,reason:d.referencia_motivo}));
  }
 });
 await t.test('adversarial: ativação aceita configuração base incoerente com duração',async()=>{
  await q('BEGIN');
  await q('INSERT INTO empresas VALUES($1)',[id(3)]);await q("INSERT INTO utilizadores(id,empresa_id,nome,email,funcao,ativo,auth_user_id) VALUES($1,$2,'Ator sintético','activation@synthetic.test','administrativo',true,$1)",[id(180),id(3)]);
  await q("INSERT INTO obras(id,empresa_id,numero,nome,tipo) VALUES($1,$2,999,'Obra sintética','reabilitacao')",[id(110),id(3)]);await q('INSERT INTO folha_config_empresa(empresa_id) VALUES($1)',[id(3)]);
  await q('INSERT INTO folha_horarios VALUES($1,$2,$3,480,1)',[id(110),id(3),JSON.stringify([normal('08:00','12:00','manha')])]);
  // All setup and the RPC share the SAME synthetic connection, so rollback truly isolates the attack.
  await q("SELECT set_config('test.actor',$1,false)",[id(180)]);await q('SET ROLE authenticated');
  const body={version:2,request_id:id(seq++),date:today,expected_revision:1};
  const pre=(await q('SELECT public.fn_folha_diaria_gestao_v2($1,$2,false,NULL) v',['daily_activation',body])).rows[0].v;
  const result=(await q('SELECT public.fn_folha_diaria_gestao_v2($1,$2,true,$3) v',['daily_activation',body,pre.versao])).rows[0].v;assert.equal(result.committed,true);
  await q('RESET ROLE');const version=(await q('SELECT * FROM folha_horarios_versoes WHERE obra_id=$1',[id(110)])).rows[0];assert.equal(version.snapshot.expected_minutes,480);assert.equal(version.snapshot.intervals.length,1);
  console.log('AUDIT_ACTIVATION '+JSON.stringify({committed:result.committed,expected:480,actual_schedule_minutes:240,intervals:1,contract:'FAIL'}));await q('ROLLBACK');await q("SELECT set_config('test.actor',$1,false)",[id(10)]);
 });
 await t.test('adversarial: captura de origem imutável; reabertura não recaptura',async()=>{
  const old=await daily(31);const v=(await q('SELECT * FROM folha_vencimentos WHERE colaborador_id=$1',[id(31)])).rows[0];const body={version:2,request_id:id(seq++),person_id:id(31),month:v.competencia,expected_revision:v.revision};
  const pre=await call(a,10,'fn_folha_gestao_v2',['payroll_reopen',body,false,null]);await call(a,10,'fn_folha_gestao_v2',['payroll_reopen',body,true,pre.versao]);const after=await daily(31);assert.equal(after.horario_versao_id,old.horario_versao_id);assert.deepEqual(after.horario_snapshot,old.horario_snapshot);assert.equal(after.expected_minutes,old.expected_minutes);
 });
 await t.test('adversarial: fronteira de vigência X antes da troca, Y na data da troca',async()=>{
  const versions=(await q('SELECT * FROM folha_horarios_versoes WHERE obra_id=$1 ORDER BY vigente_desde,revision',[id(103)])).rows;
  const active=versions.filter(v=>v.vigente_ate!==v.vigente_desde);for(const v of active){const atStart=(await q('SELECT id FROM folha_horarios_versoes WHERE obra_id=$1 AND vigente_desde<=$2 AND (vigente_ate IS NULL OR vigente_ate>$2)',[id(103),v.vigente_desde])).rows;assert.deepEqual(atStart.map(r=>r.id),[v.id]);}
  console.log('AUDIT_BOUNDARY '+JSON.stringify({ranges:active.map(v=>({since:v.vigente_desde,until:v.vigente_ate,expected:v.snapshot.expected_minutes})),contract:'PASS'}));
 });

 await t.test('adversarial: ativação replay, uma vez por empresa e corte imutável',async()=>{
  const op=(await q("SELECT * FROM folha_privado.operacoes WHERE empresa_id=$1 AND ator_id=$2 AND payload->>'action'='daily_activation'",[id(1),id(10)])).rows[0];
  const before=(await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE action='daily_activation' AND empresa_id=$1",[id(1)])).rows[0].n;
  assert.deepEqual(await call(a,10,'fn_folha_diaria_gestao_v2',['daily_activation',op.payload.data,true,op.token]),op.resultado);
  assert.equal((await q("SELECT count(*)::int n FROM folha_gestao_historico WHERE action='daily_activation' AND empresa_id=$1",[id(1)])).rows[0].n,before);
  await assert.rejects(adminOp('daily_activation',{date:today,expected_revision:2}),/DAILY_ALREADY_ACTIVATED/);
  await q('BEGIN');await assert.rejects(q('UPDATE folha_config_empresa SET avaliacao_diaria_data_ativacao=avaliacao_diaria_data_ativacao-1 WHERE empresa_id=$1',[id(1)]),/DAILY_ACTIVATION_IMMUTABLE/);await q('ROLLBACK');
  assert.equal((await q("SELECT avaliacao_diaria_data_ativacao=(now() AT TIME ZONE 'Europe/Lisbon')::date same FROM folha_config_empresa WHERE empresa_id=$1",[id(1)])).rows[0].same,true);
 });

 await t.test('adversarial: avaliação inativa não interfere no gate normal',async()=>{
  await savePlan(31,[[100,schedule]]);assert.equal((await daily(31)).ativa,false);
  const m=today.slice(0,7)+'-01';const facts=(await q('SELECT folha_privado.payroll_facts($1,$2) v',[id(31),m])).rows[0].v;
  assert.equal('daily_evaluations' in facts,false);assert.equal(facts.sheets[0].state,'registered');
  const v=(await q('SELECT revision FROM folha_vencimentos WHERE colaborador_id=$1',[id(31)])).rows[0];
  await assert.rejects(call(a,10,'fn_folha_gestao_v2',['payroll_validate',{version:2,request_id:id(seq++),person_id:id(31),month:m,expected_revision:v.revision},false,null]),e=>e.message.includes('PAYROLL_PENDING_FACTS')&&!e.message.includes('PAYROLL_DAILY_PENDING'));
 });
 await t.test('adversarial: payload de autor forjado não altera autor real',async()=>{
  await a.query('BEGIN');const d=await daily(33);const body={version:2,request_id:id(seq++),person_id:id(33),date:today,expected_revision:d.revision,reason:'Auditoria de autoria',ator_id:id(17),he_decidido_por:id(17),empresa_id:id(2)};
  const pre=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_disregard',body,false,null]);await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_disregard',body,true,pre.versao]);
  const result=(await a.query('SELECT empresa_id,he_decidido_por FROM folha_avaliacoes_diarias WHERE colaborador_id=$1',[id(33)])).rows[0];assert.equal(result.empresa_id,id(1));assert.equal(result.he_decidido_por,id(10));await a.query('ROLLBACK');
 });
 await t.test('adversarial: fronteira literal 12/10 X; 20/10 Y, registada a 25/10',async()=>{
  // Literal future dates are a temporal-predicate proof, NOT permission to schedule a future version.
  const rows=(await q("WITH versions(config,since,until) AS (VALUES ('X','2026-10-12'::date,'2026-10-20'::date),('Y','2026-10-20'::date,NULL::date)), points(d) AS (VALUES ('2026-10-15'::date),('2026-10-20'::date),('2026-10-25'::date)) SELECT points.d::text,versions.config FROM points JOIN versions ON versions.since<=points.d AND (versions.until IS NULL OR versions.until>points.d) ORDER BY points.d")).rows;
  assert.deepEqual(rows,[{d:'2026-10-15',config:'X'},{d:'2026-10-20',config:'Y'},{d:'2026-10-25',config:'Y'}]);console.log('AUDIT_LITERAL_DATES '+JSON.stringify(rows));
 });

 await t.test('adversarial: RPC HE diária aceita obra de outro tenant no histórico',async()=>{
  await a.query('BEGIN');const d=await daily(33);const body={version:2,request_id:id(seq++),person_id:id(33),date:today,expected_revision:d.revision,reason:'Prova adversarial de contexto',work_id:id(103)};
  const pre=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',body,false,null]);const result=await call(a,10,'fn_folha_diaria_gestao_v2',['daily_he_validate',body,true,pre.versao]);assert.equal(result.committed,true);
  const row=(await a.query('SELECT h.empresa_id,h.obra_id,o.empresa_id work_company FROM folha_gestao_historico h JOIN obras o ON o.id=h.obra_id WHERE h.request_id=$1',[body.request_id])).rows[0];assert.equal(row.empresa_id,id(1));assert.equal(row.work_company,id(2));console.log('AUDIT_HISTORY_TENANT '+JSON.stringify({committed:true,history_company:1,work_company:2,contract:'FAIL'}));await a.query('ROLLBACK');
 });
 console.log('AUDIT_OBSERVATIONS '+JSON.stringify(observations));
 }finally{for(const c of clients)try{await c.end();}catch{}if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});