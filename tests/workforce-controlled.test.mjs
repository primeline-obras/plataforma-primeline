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
test('Fase A preserva Ponto e API antiga; Fase B é separada',()=>{assert.doesNotMatch(migration,/CREATE OR REPLACE FUNCTION public\.(fn_listar_ponto_obra|fn_guardar_ponto_obra)\(/);assert.match(migration,/CREATE OR REPLACE FUNCTION public.fn_quadro_operar_v1/);});
test('PostgreSQL 17.6: operações, Cadastro RH, RLS e concorrência real',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client,types}=require(join(deps,'pg'));types.setTypeParser(1082,value=>value);const folder=await mkdtemp(join(tmpdir(),'primeline-quadro-pg176-')),data=join(folder,'data');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false;const clients=[];
 async function connect(database='postgres'){const c=new Client({host:'127.0.0.1',port,user:'postgres',database,password:'',ssl:false});await c.connect();clients.push(c);return c;}
 try {
 run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
 const admin=await connect(),a=await connect(),b=await connect(),q=(s,p=[])=>admin.query(s,p);
 await q(await read('./fixtures/quadro-base.sql'));await q('GRANT SELECT ON alertas TO authenticated');
 // Funções realmente instaladas, sem dados reais. Helpers periféricos não exercitados são stubs explícitos na fixture.
 const all=[...meta.functions,...meta.rhFunctions];const unique=new Map(all.map(f=>[f.signature,f]));
 for(const f of unique.values()){await q(f.definition);if(f.acl){await q('REVOKE ALL ON FUNCTION '+f.signature+' FROM PUBLIC,anon,authenticated,service_role');for(const acl of f.acl){const grantee=acl.slice(0,acl.indexOf('='));if(acl.includes('=X/'))await q('GRANT EXECUTE ON FUNCTION '+f.signature+' TO '+(grantee||'PUBLIC'));}}}
 await q('INSERT INTO empresas VALUES($1),($2)',[id(1),id(2)]);
 for(const [n,role,company] of [[10,'administrativo',1],[11,'gerencia',1],[12,'gestao_plataforma',1],[13,'encarregado',1],[14,'diretor_obra',1],[15,'adjunto',1],[16,'preparador',1],[17,'administrativo',2],[18,'encarregado',1]])
  await q('INSERT INTO utilizadores(id,empresa_id,nome,email,funcao,ativo,auth_user_id) VALUES($1,$2,$3,$4,$5,true,$1)',[id(n),id(company),'Perfil sintético '+n,'user'+n+'@synthetic.test',role]);
 for(let n=20;n<=49;n++)await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,$3,'Pedreiro','2026-01-01')",[id(n),id(n===49?2:1),'Pessoa sintética '+n]);
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
 const before=(await q('SELECT jsonb_agg(to_jsonb(q) ORDER BY id) rows FROM quadro_pessoal_alocacao q')).rows[0].rows;
 await q(await read('../supabase/quadro_controlado_precheck.sql'));
 await t.test('frontend antigo + backend antigo: DML legítimo continua funcional',async()=>{
  await q('BEGIN');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);await q('SET LOCAL ROLE authenticated');
  await q("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,periodo,semana_inicio) VALUES($1,$2,'2026-10-05','manha','2026-10-05')",[id(30),id(100)]);await q('ROLLBACK');
 });
 await t.test('migration exige backup privado; falha não instala objetos',async()=>{await assert.rejects(()=>q(migration),/backup privado/);await q('ROLLBACK');assert.equal((await q("SELECT to_regclass('public.quadro_operacoes') value")).rows[0].value,null);});
 await q(await read('../supabase/quadro_controlado_backup.sql'));
 await q(migration);await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));
 await t.test('frontend antigo + backend A: INSERT/PATCH/DELETE e RPC antiga funcionam',async()=>{
  await q('BEGIN');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);await q('SET LOCAL ROLE authenticated');
  const row=(await q("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,periodo,semana_inicio) VALUES($1,$2,'2026-10-05','manha','2026-10-05') RETURNING id",[id(30),id(100)])).rows[0];
  await q('UPDATE quadro_pessoal_alocacao SET obra_id=$1 WHERE id=$2',[id(101),row.id]);await q('DELETE FROM quadro_pessoal_alocacao WHERE id=$1',[row.id]);
  const d={colaborador_id:id(30),data:'2026-10-05',periodo:'dia_inteiro',tipo_alocacao:'obra',obra_id:id(100)};
  const preview=(await q("SELECT fn_quadro_operar('adicionar',$1::jsonb,false,NULL) v",[JSON.stringify(d)])).rows[0].v;
  const result=(await q("SELECT fn_quadro_operar('adicionar',$1::jsonb,true,$2) v",[JSON.stringify(d),preview.versao])).rows[0].v;assert.ok(result);await q('ROLLBACK');
 });
 await t.test('frontend novo + backend A: contrato v1 funcional e revisão após escrita antiga',async()=>{
  await q('BEGIN');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);await q('SET LOCAL ROLE authenticated');
  const d={version:1,colaborador_id:id(30),data:'2026-10-05',periodo:'manha',tipo_alocacao:'obra',obra_id:id(100),expected_revision:0,request_id:id(2990)};
  const preview=(await q("SELECT fn_quadro_operar_v1('alocar',$1::jsonb,false,NULL) v",[JSON.stringify(d)])).rows[0].v;
  const value=(await q("SELECT fn_quadro_operar_v1('alocar',$1::jsonb,true,$2) v",[JSON.stringify(d),preview.versao])).rows[0].v;assert.equal(value.committed,true);assert.equal(value.revision,1);await q('ROLLBACK');
 });
 const markFrontend=async()=>q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));
 const requireB=async()=>q(await read('../supabase/quadro_controlado_fase_b.sql'));
 const rejectedScript=async(script,pattern)=>{try{await assert.rejects(()=>q(script),pattern);}finally{await q('ROLLBACK');}};
 await t.test('gate: GUC falsificado não substitui marcador ausente',async()=>{
  await q("SELECT set_config('primeline.quadro.frontend_validado','not-a-sha',false)");
  await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/FRONTEND_VALIDATION_REQUIRED/);
  assert.equal((await q("SELECT estado FROM primeline_quadro_rollout.controlo")).rows[0].estado,'a');
 });
 for(const role of ['authenticated','anon','service_role']){
  for(const sql of ["SELECT * FROM primeline_quadro_rollout.controlo","SELECT * FROM primeline_quadro_rollout.validacoes","INSERT INTO primeline_quadro_rollout.controlo(singleton,estado,identidade_a) VALUES(true,'a','spoof')","UPDATE primeline_quadro_rollout.controlo SET estado='b' WHERE singleton","DELETE FROM primeline_quadro_rollout.controlo WHERE singleton","INSERT INTO primeline_quadro_rollout.validacoes(instalacao_id,tentativa,contract_version,frontend_release_id,frontend_validado_por,identidade_a) VALUES(gen_random_uuid(),1,1,'quadro_frontend_contract_v1','postgres','spoof')","UPDATE primeline_quadro_rollout.validacoes SET frontend_release_id='spoof'","DELETE FROM primeline_quadro_rollout.validacoes","SELECT primeline_quadro_rollout.exigir_validacao()"]){
   await t.test('gate: '+role+' não acede '+sql.split(' ')[0]+' '+sql.split(' ')[2],async()=>{
    await q('BEGIN; SET LOCAL ROLE '+role);await q("SELECT set_config('primeline.quadro.frontend_validado','quadro_frontend_contract_v1',true)");
    await assert.rejects(()=>q(sql),/permission denied/);await q('ROLLBACK');
   });
  }
  await t.test('gate: script de marcação recusa '+role,async()=>{await q('SET ROLE '+role);await rejectedScript(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'),/ROLLOUT_OWNER_REQUIRED/);await q('RESET ROLE');});
 }
 await t.test('gate: controlo ausente recusa B',async()=>{
  await q('ALTER TABLE primeline_quadro_rollout.controlo RENAME TO controlo_temporario');
  await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/controlo privado ausente/);
  await q('ALTER TABLE primeline_quadro_rollout.controlo_temporario RENAME TO controlo');
 });
 await t.test('gate: payload não substitui marcador ausente',async()=>{
  await q('BEGIN; SET LOCAL ROLE authenticated');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);
  const d={version:1,colaborador_id:id(30),data:'2026-10-05',periodo:'manha',tipo_alocacao:'obra',obra_id:id(100),expected_revision:0,request_id:id(2988),frontend_validado:true,contract_version:1,frontend_release_id:'quadro_frontend_contract_v1'};
  await q("SELECT fn_quadro_operar_v1('alocar',$1::jsonb,false,NULL)",[JSON.stringify(d)]);await q('ROLLBACK');
  assert.equal((await q('SELECT count(*)::int n FROM primeline_quadro_rollout.validacoes')).rows[0].n,0);
  await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/FRONTEND_VALIDATION_REQUIRED/);
 });
 await t.test('gate: operador não marca release errado',async()=>{
  const sql=(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql')).replace("v_frontend_release_id text := 'quadro_frontend_contract_v1'","v_frontend_release_id text := 'wrong-release'");
  await rejectedScript(sql,/FRONTEND_VALIDATION_INVALID/);
 });
 await markFrontend();
 for(const [field,value] of [['contract_version','2'],['frontend_release_id',"'wrong-release'"],['instalacao_id','gen_random_uuid()'],['frontend_validado_em',"'2000-01-01'::timestamptz"],['identidade_a',"'wrong-identity'"]]){
  await t.test('gate: marcador errado '+field+' recusa B',async()=>{
   const saved=(await q('SELECT * FROM primeline_quadro_rollout.validacoes')).rows[0];
   await q('UPDATE primeline_quadro_rollout.validacoes SET '+field+'='+value+' WHERE id=$1',[saved.id]);
   await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/FRONTEND_VALIDATION_(INVALID|REQUIRED)/);
   await q('UPDATE primeline_quadro_rollout.validacoes SET '+field+'=$1 WHERE id=$2',[saved[field],saved.id]);
  });
 }
 await t.test('gate: grant divergente da Fase A recusa B',async()=>{
  await q('GRANT INSERT ON public.quadro_operacoes TO authenticated');
  await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/ROLLOUT_DRIFT/);
  await q('REVOKE INSERT ON public.quadro_operacoes FROM authenticated');
 });
 await t.test('gate: alteração de helper privado recusa B',async()=>{
  const def=(await q("SELECT pg_get_functiondef('primeline_quadro_rollout.exigir_validacao()'::regprocedure) v")).rows[0].v;
  await q("CREATE OR REPLACE FUNCTION primeline_quadro_rollout.exigir_validacao() RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS 'SELECT NULL::uuid'");
  await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/ROLLOUT_DRIFT/);
  await q(def);
 });
 await t.test('gate: payload RPC não marca validação',async()=>{
  const n=(await q('SELECT count(*)::int n FROM primeline_quadro_rollout.validacoes')).rows[0].n;
  await q('BEGIN; SET LOCAL ROLE authenticated');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);
  const d={version:1,colaborador_id:id(30),data:'2026-10-05',periodo:'manha',tipo_alocacao:'obra',obra_id:id(100),expected_revision:0,request_id:id(2989),frontend_release_id:'quadro_frontend_contract_v1',frontend_validado:true};
  await q("SELECT fn_quadro_operar_v1('alocar',$1::jsonb,false,NULL)",[JSON.stringify(d)]);await q('ROLLBACK');
  assert.equal((await q('SELECT count(*)::int n FROM primeline_quadro_rollout.validacoes')).rows[0].n,n);
 });
 await t.test('gate: segundo registo na mesma tentativa não substitui o primeiro',async()=>{await rejectedScript(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'),/duplicate key/);});
 await q(await read('../supabase/quadro_controlado_fase_b_precheck.sql'));
 await q(await read('../supabase/quadro_controlado_fase_b_backup.sql'));

 await t.test('gate: falha depois do consumo reverte marcador e alterações B',async()=>{
  const sql=(await read('../supabase/quadro_controlado_fase_b.sql')).replace('CREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()',()=> 'SELECT 1/0;\nCREATE OR REPLACE FUNCTION public.fn_quadro_proteger_escrita()');
  await rejectedScript(sql,/division by zero/);
  assert.equal((await q('SELECT estado FROM primeline_quadro_rollout.controlo')).rows[0].estado,'a');
  assert.equal((await q('SELECT consumida_em FROM primeline_quadro_rollout.validacoes')).rows[0].consumida_em,null);
  await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));
 });
 await q(await read('../supabase/quadro_controlado_fase_b.sql'));await q(await read('../supabase/quadro_controlado_fase_b_postcheck.sql'));
 await t.test('gate: B consumiu validação, repetição sem rollback é recusada',async()=>{assert.ok((await q('SELECT consumida_em FROM primeline_quadro_rollout.validacoes')).rows[0].consumida_em);await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/ROLLOUT_INVALID/);});
 const actor=async(c,n=10)=>{await c.query('RESET ROLE');await c.query("SELECT set_config('test.actor',$1,false)",[id(n)]);await c.query('SET ROLE authenticated');};
 const call=async(c,acao,body,confirm=false,versao=null)=>(await c.query('SELECT fn_quadro_operar_v1($1,$2::jsonb,$3,$4) value',[acao,JSON.stringify(body),confirm,versao])).rows[0].value;
 const body=(person=30,work=100,rev=0,req=3000,period='dia_inteiro',date='2026-10-05')=>({version:1,colaborador_id:id(person),data:date,periodo:period,tipo_alocacao:'obra',obra_id:id(work),descricao_livre:null,expected_revision:rev,request_id:id(req)});
 const commit=async(c,values,acao='alocar')=>{const p=await call(c,acao,values);return {...await call(c,acao,values,true,p.versao),_previewVersion:p.versao};};
 const day=async(person=30,date='2026-10-05')=>(await q('SELECT * FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2 ORDER BY id',[id(person),date])).rows;
 const unit=(name,fn)=>t.test(name,async()=>{await a.query('BEGIN');await actor(a);try{await fn();}finally{await a.query('ROLLBACK');await a.query('RESET ROLE');}});
 const reject=async(c,fn,re)=>{await c.query('SAVEPOINT expected');try{await assert.rejects(fn,e=>re.test(e.message));}finally{await c.query('ROLLBACK TO expected; RELEASE expected');}};
 for(const [name,sql] of [
 ['grant em tabela privada',"GRANT SELECT ON quadro_dias_revisoes TO service_role"],
 ['grant em helper privado',"GRANT EXECUTE ON FUNCTION fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean) TO authenticated"],
 ['policy permissiva',"ALTER POLICY quadro_controlado_leitura ON quadro_pessoal_alocacao USING (true)"]
 ])await t.test('postcheck recusa '+name,async()=>{await q('BEGIN');try{await q(sql);await assert.rejects(()=>q(requirePost()),/POSTCHECK_FAILED/);}finally{await q('ROLLBACK');}});
 function requirePost(){return postFinal;}
 await unit('instalação preserva 227 alocações, 98 movimentos e conflitos legados',async()=>{assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(q) ORDER BY id) rows FROM quadro_pessoal_alocacao q')).rows[0].rows,before);assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_movimentos')).rows[0].n,98);});
 await unit('preview não grava e não herda ontem',async()=>{const p=await call(a,'alocar',body());assert.equal(p.committed,false);assert.equal((await day()).length,0);const r=await commit(a,body());assert.equal(r.committed,true);assert.equal((await day(30,'2026-10-06')).length,0);});
 await unit('Ponto legado mantém herança temporária; Quadro exige data explícita',async()=>{
 await commit(a,body());
 const today=(await a.query("SELECT fn_listar_ponto_obra('2026-10-05',$1) v",[id(100)])).rows[0].v;
 for(let d=3;d<=14;d++){const result=(await a.query('SELECT fn_listar_ponto_obra($1,$2) v',['2026-10-'+String(d).padStart(2,'0'),id(100)])).rows[0].v;assert.ok(result.linhas.some(x=>x.colaborador_id===id(20)));}
 const tomorrow=(await a.query("SELECT fn_listar_ponto_obra('2026-10-06',$1) v",[id(100)])).rows[0].v;
 assert.ok(today.linhas.some(x=>x.colaborador_id===id(30)));assert.ok(tomorrow.linhas.some(x=>x.colaborador_id===id(30)));

 });
 await unit('mover Obra A → B: uma revisão, origem/destino e histórico corretos',async()=>{let r=await commit(a,body());const allocation=r.allocations[0].id;r=await commit(a,body(30,101,1,3001));assert.equal(r.allocations[0].id,allocation);assert.equal(r.allocations[0].obra_id,id(101));assert.equal(r.revision,2);const h=(await a.query('SELECT * FROM quadro_pessoal_movimentos WHERE colaborador_id=$1 ORDER BY alterado_em,id',[id(30)])).rows.find(x=>x.acao==='alterada');assert.equal(h.antes.obra_id,id(100));assert.equal(h.depois.obra_id,id(101));assert.equal(h.alterado_por,id(10));assert.equal(h.origem_operacao,'quadro');assert.equal(h.request_id,id(3001));});
 await unit('destino inválido falha e mantém origem',async()=>{await commit(a,body());await reject(a,()=>commit(a,body(30,103,1,3001)),/PERMISSION_DENIED/);assert.equal((await a.query('SELECT obra_id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(30)])).rows[0].obra_id,id(100));});
 await unit('manhã/tarde distintas permitidas; split de dia inteiro é atómico',async()=>{await commit(a,body());const r=await commit(a,body(30,101,1,3001,'manha'));assert.equal(r.allocations.length,2);assert.equal(r.allocations.find(x=>x.periodo==='tarde').obra_id,id(100));assert.equal(r.allocations.find(x=>x.periodo==='manha').obra_id,id(101));});
 await unit('dia inteiro substitui manhã+tarde sem duas origens persistidas',async()=>{await commit(a,body(30,100,0,3000,'manha'));await commit(a,body(30,101,1,3001,'tarde'));const r=await commit(a,body(30,100,2,3002));assert.equal(r.allocations.length,1);assert.equal(r.allocations[0].periodo,'dia_inteiro');});
 await unit('sobreposição legada recusada sem reinterpretar encarregado/multiobra',async()=>{await reject(a,()=>commit(a,body(21,100,0,3000,'manha','2026-09-29')),/LEGACY_CONFLICT/);assert.equal((await a.query('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(21)])).rows[0].n,2);});
 await unit('ausência confirmada bloqueia nova alocação',async()=>{await q("INSERT INTO ausencias(colaborador_id,data,tipo,estado) VALUES($1,'2026-10-05','ferias','confirmada')",[id(30)]);await reject(a,()=>commit(a,body()),/ABSENCE_CONFLICT/);assert.equal((await day()).length,0);await q("DELETE FROM ausencias WHERE colaborador_id=$1 AND data='2026-10-05'",[id(30)]);});
 await unit('escritório permitido com obra_id NULL; obra no escritório é recusada',async()=>{const d={...body(),tipo_alocacao:'escritorio',obra_id:null,descricao_livre:'Escritório'};assert.equal((await commit(a,d)).allocations[0].obra_id,null);await reject(a,()=>commit(a,{...d,obra_id:id(100),expected_revision:1,request_id:id(3001)}),/VALIDATION_ERROR/);});
 await unit('colaborador de outra empresa recusado',async()=>{await reject(a,()=>commit(a,body(49)),/PERMISSION_DENIED/);});
 for(const [n,name] of [[10,'Administrativo'],[12,'Gestão']])await unit(name+' gere alocação dentro da empresa',async()=>{await actor(a,n);assert.equal((await commit(a,body())).committed,true);});
 await unit('Encarregado autorizado move entre as suas duas obras',async()=>{await actor(a,13);await commit(a,body());assert.equal((await commit(a,body(30,101,1,3001))).committed,true);});
 await unit('Encarregado não pode retirar origem fora do seu âmbito',async()=>{await commit(a,body(30,102));await actor(a,13);await reject(a,()=>commit(a,body(30,100,1,3001)),/PERMISSION_DENIED/);});
 await unit('Encarregado sem autorização não edita nem usa escritório',async()=>{await actor(a,18);await reject(a,()=>commit(a,body()),/PERMISSION_DENIED/);await reject(a,()=>commit(a,{...body(),obra_id:null,tipo_alocacao:'escritorio',descricao_livre:'Escritório'}),/PERMISSION_DENIED/);});
 for(const [n,name] of [[14,'Diretor'],[15,'Adjunto']])await unit(name+' consulta apenas obra autorizada e não movimenta',async()=>{await commit(a,body());await actor(a,n);const c=(await a.query("SELECT fn_quadro_contexto_v1('2026-10-01','2026-10-31') value")).rows[0].value;assert.deepEqual(c.edit_work_ids,[]);assert.deepEqual(c.read_work_ids,[id(100)]);assert.equal(c.allocations.length,1);await reject(a,()=>commit(a,body(31,100,0,3001)),/PERMISSION_DENIED/);});
 await unit('Preparador mantém ausência de poderes de Quadro',async()=>{await actor(a,16);await reject(a,()=>a.query("SELECT fn_quadro_contexto_v1('2026-10-01','2026-10-31')"),/PERMISSION_DENIED/);await reject(a,()=>commit(a,body()),/PERMISSION_DENIED/);});
 await unit('utilizador inativo recusado',async()=>{await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(10)]);await reject(a,()=>commit(a,body()),/PERMISSION_DENIED/);await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(10)]);});
 await unit('RLS não permite leituras de outra empresa',async()=>{await commit(a,body());await actor(a,17);assert.equal((await a.query('SELECT count(*)::int n FROM quadro_pessoal_alocacao')).rows[0].n,0);const c=(await a.query("SELECT fn_quadro_contexto_v1('2026-10-01','2026-10-31') value")).rows[0].value;assert.equal(c.allocations.length,0);assert.equal(c.people.length,1);});
 await unit('replay do mesmo request não duplica histórico; outro payload é recusado',async()=>{const d=body(),p=await call(a,'alocar',d);await call(a,'alocar',d,true,p.versao);const r=await call(a,'alocar',d,true,p.versao);assert.equal(r.idempotent,true);assert.equal((await a.query('SELECT count(*)::int n FROM quadro_pessoal_movimentos WHERE request_id=$1',[d.request_id])).rows[0].n,1);await reject(a,()=>call(a,'alocar',{...d,obra_id:id(101)},true,p.versao),/IDEMPOTENCY_CONFLICT/);});
 await unit('revisão antiga e sequência A → B → A detetáveis',async()=>{await commit(a,body());await commit(a,body(30,101,1,3001));await commit(a,body(30,100,2,3002));await reject(a,()=>commit(a,body(30,101,1,3003)),/STALE_REVISION/);});
 await unit('remover apenas IDs selecionados; sem reativação de dia anterior',async()=>{const r=await commit(a,body(30,100,0,3000,'manha'));await commit(a,body(30,101,1,3001,'tarde'));const removed=await commit(a,{...body(30,100,2,3002),ids:[r.allocations[0].id]},'remover');assert.equal(removed.allocations.length,1);assert.equal(removed.allocations[0].periodo,'tarde');});
 await unit('DML direto INSERT/PATCH/DELETE e sinalizador falsificado recusados',async()=>{await commit(a,body());await a.query("SELECT set_config('primeline.quadro_rpc','on',true)");for(const sql of ["UPDATE quadro_pessoal_alocacao SET obra_id=$1 WHERE colaborador_id=$2","DELETE FROM quadro_pessoal_alocacao WHERE obra_id=$1 AND colaborador_id=$2","INSERT INTO quadro_pessoal_alocacao(obra_id,colaborador_id,semana_inicio,data) VALUES($1,$2,'2026-10-05','2026-10-05')"])await reject(a,()=>a.query(sql,[id(101),id(30)]),/permission denied/);await reject(a,()=>a.query("SELECT fn_quadro_aplicar_interno($1,'2026-10-05','[]','[]','quadro')",[id(30)]),/permission denied/);});
 await unit('mesmo owner via SQL também exige núcleo interno, sem bypass GUC',async()=>{await reject(a,()=>a.query('RESET ROLE; UPDATE quadro_pessoal_alocacao SET obra_id=obra_id WHERE id=\''+id(1002)+'\''),/CONTROLLED_WRITE_REQUIRED/);await actor(a);});
 await unit('cadastro com alocação inicial continua após fechar DML, histórico e data explícita',async()=>{const v=(await a.query("SELECT fn_rh_guardar($1::jsonb,false) value",[JSON.stringify({campos:{nome:'Nova Pessoa',funcao:'Servente',data_admissao:'2026-10-05'},alocacao_tipo:'escritorio'})])).rows[0].value;const c=v.id;const rows=(await a.query('SELECT * FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[c])).rows;assert.equal(rows.length,1);assert.equal(rows[0].data,'2026-10-05');assert.equal(rows[0].obra_id,null);const history=(await a.query('SELECT * FROM quadro_pessoal_movimentos WHERE colaborador_id=$1',[c])).rows;assert.equal(history[0].origem_operacao,'cadastro_rh');assert.equal(history[0].antes,null);assert.equal(history[0].depois.colaborador_id,c);});
 await unit('cadastro sem alocação explícita não inventa destino/data',async()=>{const v=(await a.query('SELECT fn_rh_guardar($1::jsonb,false) value',[JSON.stringify({campos:{nome:'Sem Alocação',funcao:'Servente',data_admissao:'2026-10-05'},alocacao_tipo:null})])).rows[0].value;assert.equal((await a.query('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[v.id])).rows[0].n,0);});
 await unit('falha na alocação inicial reverte colaborador, contratos e auditoria RH',async()=>{const before=(await a.query('SELECT count(*)::int n FROM colaboradores')).rows[0].n;await reject(a,()=>a.query("SELECT fn_criar_colaborador_com_alocacao('Falha','Pedreiro','2026-10-05',NULL,'obra',$1) value",[id(103)]),/empresa|válida|PERMISSION_DENIED/);assert.equal((await a.query('SELECT count(*)::int n FROM colaboradores')).rows[0].n,before);});
 for(const [suffix,mode,expected] of [['Ausência','absence',/ABSENCE_CONFLICT/],['Conflito','conflict',/STALE_REVISION/]]) await unit('falha depois do INSERT do colaborador reverte toda a criação: '+suffix,async()=>{
 const name='Falha sintética '+suffix;
 await q(`CREATE FUNCTION public.test_initial_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.nome = '${name}' THEN
 ${mode==='absence'?"INSERT INTO public.ausencias(colaborador_id,data,tipo,estado) VALUES(NEW.id,NEW.data_admissao,'ferias','confirmada');":"PERFORM public.fn_quadro_aplicar_interno(NEW.id,NEW.data_admissao,'[]'::jsonb,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'colaborador_id',NEW.id,'data',NEW.data_admissao,'periodo','dia_inteiro','tipo_alocacao','escritorio','obra_id',NULL,'descricao_livre','Sintético')),'cadastro_rh',NULL,false);"}
 END IF; RETURN NEW; END $$;
 CREATE TRIGGER test_initial_failure AFTER INSERT ON public.colaboradores FOR EACH ROW EXECUTE FUNCTION public.test_initial_failure();`);
 try {
 const snapshot=(await q("SELECT jsonb_build_object('c',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM colaboradores x),'a',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM ausencias x),'q',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM quadro_pessoal_alocacao x),'h',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM quadro_pessoal_movimentos x)) v")).rows[0].v;
 await reject(a,()=>a.query('SELECT fn_rh_guardar($1::jsonb,false)',[JSON.stringify({campos:{nome:name,funcao:'Servente',data_admissao:'2026-10-05'},alocacao_tipo:'escritorio'})]),expected);
 assert.deepEqual((await q("SELECT jsonb_build_object('c',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM colaboradores x),'a',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM ausencias x),'q',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM quadro_pessoal_alocacao x),'h',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM quadro_pessoal_movimentos x)) v")).rows[0].v,snapshot);
 } finally {await q('DROP TRIGGER test_initial_failure ON public.colaboradores; DROP FUNCTION public.test_initial_failure()');}
 });
 await unit('renomeação de linha usa núcleo e é atómica',async()=>{await commit(a,{...body(),tipo_alocacao:'pontual',obra_id:null,descricao_livre:'Linha antiga'});const d={version:1,request_id:id(3001),tipo_alocacao:'pontual',descricao_anterior:'Linha antiga',descricao_nova:'Linha nova'};const r=await commit(a,d,'renomear_linha');assert.equal(r.days,1);assert.equal((await a.query('SELECT descricao_livre FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(30)])).rows[0].descricao_livre,'Linha nova');});
 await unit('importação de IDs existentes com/sem alocação mantém alocações e atomicidade',async()=>{await actor(a,12);await commit(a,body());const snapshot=(await a.query('SELECT jsonb_agg(to_jsonb(q) ORDER BY id) value FROM quadro_pessoal_alocacao q')).rows[0].value;const records=(await a.query('SELECT fn_rh_consultar(NULL) value')).rows[0].value;const payload=[30,31].map(n=>({id:id(n),versao:records.find(r=>r.colaborador.id===id(n)).versao,campos:{observacoes:'Importação sintética'}}));const r=(await a.query('SELECT fn_rh_importar($1::jsonb,true) value',[JSON.stringify(payload)])).rows[0].value;assert.equal(r.erros,0);assert.deepEqual((await a.query('SELECT jsonb_agg(to_jsonb(q) ORDER BY id) value FROM quadro_pessoal_alocacao q')).rows[0].value,snapshot);await reject(a,()=>a.query('SELECT fn_rh_importar($1::jsonb,true)',[JSON.stringify([{campos:{nome:'Novo proibido'}}])]),/Lote cancelado/);});
 await unit('importação: erro na segunda linha reverte a primeira e preserva alocações',async()=>{
 await actor(a,12);await commit(a,body());
 const records=(await a.query('SELECT fn_rh_consultar(NULL) value')).rows[0].value;
 const prior=(await a.query('SELECT observacoes FROM colaboradores WHERE id=$1',[id(30)])).rows[0];
 const allocations=await day();
 const payload=[{id:id(30),versao:records.find(r=>r.colaborador.id===id(30)).versao,campos:{observacoes:'Não pode persistir'}},{id:id(31),versao:'versão inválida',campos:{observacoes:'Falha'}}];
 await reject(a,()=>a.query('SELECT fn_rh_importar($1::jsonb,true)',[JSON.stringify(payload)]),/Lote cancelado/);
 assert.deepEqual((await a.query('SELECT observacoes FROM colaboradores WHERE id=$1',[id(30)])).rows[0],prior);assert.deepEqual(await day(),allocations);
 });
 await unit('Gerência preserva consulta/RH mas não recebe escrita global',async()=>{
  await actor(a,11);const ctx=(await a.query("SELECT fn_quadro_contexto_v1('2026-10-05','2026-10-05') v")).rows[0].v;
  assert.equal(ctx.can_manage_global,false);assert.deepEqual(ctx.edit_work_ids,[]);assert.equal(ctx.read_work_ids.length,3);
  await reject(a,()=>commit(a,body()),/PERMISSION_DENIED/);
  const r=(await a.query("SELECT fn_criar_colaborador_com_alocacao('Cadastro Gerência','Pedreiro','2026-10-05',NULL,'obra',$1) v",[id(100)])).rows[0].v;assert.ok(r);
 });
 for(const period of ['manha','tarde','dia_inteiro'])await unit('última '+period+' → vazio → reload → nova operação e replay',async()=>{
  await actor(a,13);await commit(a,body(30,100,0,3000,period));
  const d={version:1,colaborador_id:id(30),data:'2026-10-05',ids:(await a.query('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(30),'2026-10-05'])).rows.map(r=>r.id),expected_revision:1,request_id:id(3001)};
  const removed=await commit(a,d,'remover');assert.equal(removed.revision,2);assert.deepEqual(removed.allocations,[]);
  const ctx=(await a.query("SELECT fn_quadro_contexto_v1('2026-10-05','2026-10-05') v")).rows[0].v;
  assert.equal(ctx.revisions.find(r=>r.colaborador_id===id(30)).revisao,2);
  const replay=await call(a,'remover',d,true,removed._previewVersion);assert.equal(replay.idempotent,true);
  const fresh=await commit(a,body(30,100,2,3002,period));assert.equal(fresh.revision,3);
 });
 await unit('notificações: preview zero, commit correto, replay zero extra, remoção sem alerta',async()=>{
  await actor(a,13);const count=async()=>+(await a.query('SELECT count(*) n FROM alertas')).rows[0].n;
  const initial=await count();const d=body();await call(a,'alocar',d);assert.equal(await count(),initial);
  const first=await commit(a,d);const after=await count();assert.equal(after-initial,2);
  await call(a,'alocar',d,true,first._previewVersion);assert.equal(await count(),after);
  await commit(a,body(30,101,1,3001));const rows=(await a.query("SELECT * FROM alertas WHERE descricao LIKE '%movimentado%'")).rows;
  assert.equal(rows.length,2);assert.ok(rows.every(r=>r.descricao.includes('100')&&r.descricao.includes('101')));
  assert.deepEqual(new Set(rows.map(r=>r.destinatario_utilizador_id)),new Set([id(10),id(14)]));
  const moved=await count();await commit(a,{version:1,colaborador_id:id(30),data:'2026-10-05',ids:(await a.query('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data=$2',[id(30),'2026-10-05'])).rows.map(r=>r.id),expected_revision:2,request_id:id(3002)},'remover');assert.equal(await count(),moved);
 });
 await t.test('notificações com rollback não são persistidas',async()=>{const count=(await q('SELECT count(*)::int n FROM alertas')).rows[0].n;await a.query('BEGIN');await actor(a,13);await commit(a,body());await a.query('ROLLBACK');assert.equal((await q('SELECT count(*)::int n FROM alertas')).rows[0].n,count);});
 await unit('frontend antigo + backend B: escrita recusada antes de corrupção',async()=>{await reject(a,()=>a.query("SELECT fn_quadro_operar('adicionar',$1::jsonb,true,NULL)",[JSON.stringify(body())]),/permission denied/);assert.deepEqual(await day(),[]);});
 // Concorrência: duas ligações, commits controlados apenas na base sintética.
 async function concurrent(d1,d2,pattern,profile=10){await actor(a,profile);await actor(b,profile);const p1=await call(a,'alocar',d1),p2=await call(b,'alocar',d2);await a.query('BEGIN');await b.query('BEGIN');const r1=await call(a,'alocar',d1,true,p1.versao);let finished=false;const pending=result(call(b,'alocar',d2,true,p2.versao)).then(r=>{finished=true;return r;});await delay(150);assert.equal(finished,false,'segunda ligação deve esperar pelo lock');await a.query('COMMIT');const r2=await pending;if(pattern){assert.match(r2.error?.message||'',pattern);await b.query('ROLLBACK');}else{assert.equal(r2.value.idempotent,true);await b.query('COMMIT');}return [r1,r2];}
 await t.test('duas trocas simultâneas com mesma revisão: uma confirma e outra STALE',async()=>{await concurrent(body(40,100,0,4000),body(40,101,0,4001),/STALE_REVISION/);assert.equal((await day(40)).length,1);});
 await t.test('request simultâneo igual: uma escrita, segunda idempotente, um movimento',async()=>{const d=body(41,100,0,4002);await concurrent(d,d);assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_movimentos WHERE request_id=$1',[id(4002)])).rows[0].n,1);});
 await t.test('request simultâneo com payload diferente: IDEMPOTENCY_CONFLICT',async()=>{await concurrent(body(42,100,0,4003),body(42,101,0,4003),/IDEMPOTENCY_CONFLICT/);assert.equal((await day(42)).length,1);});
 await t.test('duas sessões de Encarregado após estado vazio mantêm revisão e detetam concorrência',async()=>{
  await actor(a,13);await commit(a,body(43,100,0,4100));
  const ids=(await a.query('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(43)])).rows.map(r=>r.id);
  await commit(a,{version:1,colaborador_id:id(43),data:'2026-10-05',ids,expected_revision:1,request_id:id(4101)},'remover');
  await actor(b,13);for(const c of [a,b]){const ctx=(await c.query("SELECT fn_quadro_contexto_v1('2026-10-05','2026-10-05') v")).rows[0].v;assert.equal(ctx.revisions.find(r=>r.colaborador_id===id(43)).revisao,2);}
  await concurrent(body(43,100,2,4102),body(43,101,2,4103),/STALE_REVISION/,13);
 });
 await t.test('rollback B preserva operações e restaura compatibilidade A',async()=>{const before=(await q('SELECT count(*)::int n FROM quadro_operacoes')).rows[0].n;await q(await read('../supabase/quadro_controlado_fase_b_rollback.sql'));assert.equal((await q('SELECT count(*)::int n FROM quadro_operacoes')).rows[0].n,before);await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));});
 await t.test('forward-fix B preserva dados e reinstala proteções finais',async()=>{const before=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v;await rejectedScript(await read('../supabase/quadro_controlado_fase_b_forward_fix.sql'),/FRONTEND_VALIDATION_REQUIRED/);assert.equal((await q('SELECT count(*)::int n FROM primeline_quadro_rollout.validacoes WHERE invalidada_em IS NOT NULL')).rows[0].n,1);await markFrontend();await q(await read('../supabase/quadro_controlado_fase_b_forward_fix.sql'));assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v,before);await q(await read('../supabase/quadro_controlado_fase_b_postcheck.sql'));await q(await read('../supabase/quadro_controlado_fase_b_rollback.sql'));});
 await t.test('rollback A preserva histórico/revisões e restaura definições antigas',async()=>{const before=(await q('SELECT count(*)::int n FROM quadro_pessoal_movimentos')).rows[0].n;await q(await read('../supabase/quadro_controlado_fase_a_rollback.sql'));assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_movimentos')).rows[0].n,before);assert.equal((await q("SELECT has_table_privilege('authenticated','quadro_pessoal_alocacao','UPDATE') v")).rows[0].v,true);});
 await t.test('forward-fix A conserva dados após rollback e invalida previews antigos',async()=>{const before=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v;await q(await read('../supabase/quadro_controlado_fase_a_forward_fix.sql'));assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v,before);await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));await rejectedScript(await read('../supabase/quadro_controlado_fase_b.sql'),/FRONTEND_VALIDATION_REQUIRED/);});
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
