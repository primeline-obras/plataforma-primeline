import {authorizationCases} from './financeiro-regression-cases.mjs';
import {financialCases} from './financeiro-cross-tenant-cases.mjs';
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
test('PostgreSQL local: catálogo real, RLS, RPCs, perfis e reversão',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
  for(const trigger of integrity.triggers.filter(x=>['obras','mapas_comparativos','planeamento_itens','previsao_financeira_mensal','faturas','faturacao'].includes(x.table)))await q(trigger.definition);
  const rebuilt=(await q(snapshotQuery)).rows[0].jsonb_build_object;
  for(const a of rebuilt.tables){
   const original=fixture.catalog.tables.find(t=>t.name===a.name);
   const expected={...original,columns:original.columns.map(({name,type,acl})=>({name,type,acl}))};
   assert.deepEqual(a,expected,'catálogo da tabela '+a.name);
  }
  for(const a of rebuilt.functions){const f=fixture.catalog.functions.find(f=>f.signature===a.signature);assert.deepEqual(a,{signature:f.signature,owner:f.owner,acl:'{'+(f.acl||'{=X/postgres,postgres=X/postgres}').slice(1,-1).split(',').sort().join(',')+'}',definition:fixture.details.definitions[f.signature].replaceAll('\r','')},a.signature);}
  await t.test('precheck exato contra catálogo real reconstruído',async()=>{await q(scripts.precheck);});
  const before=(await q(snapshotQuery)).rows[0].jsonb_build_object;
  const snapshot=async()=>(await q(snapshotQuery)).rows[0].jsonb_build_object;
  const rejected=async(s,re)=>{try{await assert.rejects(()=>q(s),re);}finally{await q('ROLLBACK');}};
  await t.test('drift de coluna/policy/grant/definer aborta',async()=>{
   for(const change of ["GRANT SELECT(nif) ON colaboradores TO anon","CREATE POLICY adversarial ON colaboradores FOR SELECT TO authenticated USING(true)","ALTER FUNCTION fn_quadro_contexto_v1(date,date) SECURITY INVOKER"]){
    await q('BEGIN;'+change);await assert.rejects(()=>q(scripts.precheck.replace('BEGIN READ ONLY;','')),/CATALOG_DRIFT/);await q('ROLLBACK');
   }
  });
  await t.test('migration sem backup privado recusa',async()=>{await rejected(scripts.migration,/PRIVATE_BACKUP_REQUIRED|does not exist/);});
  await q(scripts.backup);
  for(const [n,role,company] of [[10,'encarregado',1],[11,'administrativo',1],[12,'gestao_plataforma',1],[13,'gerencia',1],[14,'diretor_obra',1],[15,'adjunto',1],[16,'preparador',1],[17,'financeiro',1],[18,'encarregado',2]]){
   await q('INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo,nome) VALUES($1,$1,$2,$3,true,$4)',[id(n),id(company),role,'Perfil sintético '+n]);
  }
  for(const [n,company] of [[120,1],[118,1],[122,1],[200,2]])await q("INSERT INTO obras(id,empresa_id,numero,nome,situacao) VALUES($1,$2,$3,'Obra sintética','em_curso')",[id(n),id(company),n]);
  for(const [n,papel,work] of [[10,'encarregado',120],[18,'encarregado',200],[14,'diretor_obra',120],[15,'adjunto',120],[16,'preparador',120]])await q('INSERT INTO obra_responsaveis(id,obra_id,utilizador_id,papel) VALUES(gen_random_uuid(),$1,$2,$3)',[id(work),id(n),papel]);
  for(const [n,work] of [[30,120],[31,118],[32,122],[33,null],[34,120],[35,200]]){
   await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao,data_saida,nif,morada,valor_hora) VALUES($1,$2,$3,'Pedreiro','2026-01-01',$4,'PII_SYNTHETIC','ADDRESS_SYNTHETIC',99)",[id(n),id(n===35?2:1),'Pessoa sintética '+n,n===34?'2026-09-01':null]);
   if(work)await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao,criado_em) VALUES($1,$2,$3,current_date,current_date,'dia_inteiro','obra',now())",[id(n+1000),id(n),id(work)]);
  }
  for(const [n,work] of [[40,120],[41,118],[42,122],[43,200]]){
   await q("INSERT INTO subempreitadas(id,obra_id,fornecedor_id,especialidade,valor_adjudicado,tipo_pagamento,condicao_pagamento) VALUES($1,$2,$3,'Trabalho sintético',999,'SENSITIVE','SENSITIVE')",[id(n),id(work),id(500)]);
   await q('INSERT INTO pagamentos_subempreitada(id,subempreitada_id,valor) VALUES($1,$2,999)',[id(n+200),id(n)]);
   await q('INSERT INTO avaliacoes_subempreiteiro(id,obra_id,subempreitada_id,fornecedor_id) VALUES($1,$2,$3,$4)',[id(n+300),id(work),id(n),id(500)]);
  }
  await q("INSERT INTO medicina_trabalho(id,colaborador_id,data_ultima_consulta,resultado,revisao,criado_em) VALUES($1,$2,current_date,'apto',1,now())",[id(600),id(30)]);
  const asRole=async(n,sql,params=[])=>{await q('BEGIN');try{await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(n)]);await q('SET LOCAL ROLE authenticated');return await q(sql,params);}finally{await q('ROLLBACK');}};
  const counts=async n=>[...(await asRole(n,'SELECT count(*)::int n FROM colaboradores')).rows.map(x=>x.n),...(await asRole(n,'SELECT count(*)::int n FROM subempreitadas')).rows.map(x=>x.n)];
  const rolesBefore=new Map();for(let n=11;n<=17;n++)rolesBefore.set(n,await counts(n));
  await t.test('reproduz P1 no catálogo anterior',async()=>{assert.deepEqual(await counts(10),[5,4]);});
  await authorizationCases({t,q,asRole,stage:'before'});
  await financialCases({t,q,port,stage:'before'});
  const allData=async()=>{const result={};for(const table of fixture.catalog.tables.filter(x=>x.kind==='r'))result[table.name]=(await q('SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) v FROM public.'+qi(table.name)+' t')).rows[0].v;return result;};
  const allDataBefore=await allData();
  const dataBefore=(await q("SELECT jsonb_build_object('c',(SELECT jsonb_agg(to_jsonb(c)) FROM colaboradores c),'s',(SELECT jsonb_agg(to_jsonb(s)) FROM subempreitadas s),'q',(SELECT jsonb_agg(to_jsonb(q)) FROM quadro_pessoal_alocacao q)) v")).rows[0].v;
  await q(scripts.migration);await q(scripts.postcheck);
  await authorizationCases({t,q,asRole,stage:'after'});
  await financialCases({t,q,port,stage:'after'});
  await restCases({t,port});
  await t.test('Encarregado: SELECT direto, PII e económico vazio',async()=>{
   assert.deepEqual(await counts(10),[0,0]);
   for(const sql of ['SELECT nif,morada,valor_hora FROM colaboradores','SELECT valor_adjudicado,tipo_pagamento,condicao_pagamento FROM subempreitadas','SELECT * FROM pagamentos_subempreitada'])assert.equal((await asRole(10,sql)).rowCount,0);
  });
  await t.test('policies OR e grants de coluna não contornam guarda',async()=>{
   await q('CREATE POLICY adversarial ON colaboradores FOR SELECT TO authenticated USING(true); GRANT SELECT(nif) ON colaboradores TO authenticated');
   assert.equal((await asRole(10,'SELECT nif FROM colaboradores')).rowCount,0);
   await q('DROP POLICY adversarial ON colaboradores; REVOKE SELECT(nif) ON colaboradores FROM authenticated');
  });
  await t.test('RPC operacional só Obra 120 e quatro campos, sem outra empresa',async()=>{
   const rows=(await asRole(10,'SELECT * FROM fn_subempreitadas_operacionais_obra($1)',[id(120)])).rows;
   assert.equal(rows.length,1);assert.deepEqual(Object.keys(rows[0]),['id','obra_id','fornecedor_id','especialidade']);
   for(const n of [118,122,200])await assert.rejects(()=>asRole(10,'SELECT * FROM fn_subempreitadas_operacionais_obra($1)',[id(n)]),/PERMISSION_DENIED/);
  });
  await t.test('contexto v1 não devolve pessoas externas, livres ou inativas',async()=>{
   const v=(await asRole(10,'SELECT fn_quadro_contexto_v1(current_date,current_date) v')).rows[0].v;
   assert.deepEqual(v.people.map(p=>p.id),[id(30)]);assert.deepEqual(v.read_work_ids,[id(120)]);
   assert.ok(v.allocations.every(a=>a.obra_id===id(120)));
  });
  await t.test('RPCs globais antigas sem EXECUTE; definer financeiro recusa',async()=>{
   for(const sql of ['SELECT fn_quadro_ferias_encarregado_global(current_date,current_date)','SELECT fn_equipa_obra_encarregado(current_date,NULL)'])await assert.rejects(()=>asRole(10,sql),/permission denied/);
   for(const name of ['fn_resumo_custos_obra','fn_resumo_controle_subempreitadas_obra','fn_resumo_componentes_custo_obra'])await assert.rejects(()=>asRole(10,`SELECT ${name}($1)`,[id(120)]),/permiss/i);
  });
  await t.test('Medicina autorizada só leitura; fora do âmbito recusada',async()=>{
   const v=(await asRole(10,'SELECT fn_medicina_consultar_colaborador(1,$1) v',[id(30)])).rows[0].v;
   assert.equal(v.can_write,false);assert.equal(v.atual.colaborador_id,id(30));
   for(const person of [31,32,33,35])await assert.rejects(()=>asRole(10,'SELECT fn_medicina_consultar_colaborador(1,$1)',[id(person)]),/PERMISSION_DENIED/);
  });
  await t.test('Ponto continua a consultar equipa e recusa obra externa',async()=>{
   const v=(await asRole(10,'SELECT fn_listar_ponto_obra(current_date,$1) v',[id(120)])).rows[0].v;
   assert.ok(v.linhas.some(p=>p.colaborador_id===id(30)));
   assert.ok(!v.linhas.some(p=>[id(31),id(32),id(33),id(34),id(35)].includes(p.colaborador_id)));
   await assert.rejects(()=>asRole(10,'SELECT fn_listar_ponto_obra(current_date,$1)',[id(118)]),/permiss|autoriza/i);
  });
  await t.test('anon não obtém as RPCs novas nem SELECT de coluna',async()=>{
   await q('BEGIN; SET LOCAL ROLE anon');try{await assert.rejects(()=>q('SELECT * FROM fn_subempreitadas_operacionais_obra($1)',[id(120)]),/permission denied/);}finally{await q('ROLLBACK');}
   assert.equal((await q("SELECT has_function_privilege('anon','fn_subempreitadas_operacionais_obra(uuid)','EXECUTE') v")).rows[0].v,false);
  });
  await t.test('demais sete perfis mantêm exatamente contagens anteriores',async()=>{for(let n=11;n<=17;n++)assert.deepEqual(await counts(n),rolesBefore.get(n),'perfil '+n);});
  await t.test('avaliações internas sem exposição global',async()=>{assert.equal((await asRole(10,'SELECT * FROM avaliacoes_subempreiteiro')).rowCount,0);});
  await t.test('linhas operacionais intactas',async()=>{assert.deepEqual((await q("SELECT jsonb_build_object('c',(SELECT jsonb_agg(to_jsonb(c)) FROM colaboradores c),'s',(SELECT jsonb_agg(to_jsonb(s)) FROM subempreitadas s),'q',(SELECT jsonb_agg(to_jsonb(q)) FROM quadro_pessoal_alocacao q)) v")).rows[0].v,dataBefore);});
  await t.test('todas as tabelas operacionais sintéticas intactas após SQL/REST',async()=>{assert.deepEqual(await allData(),allDataBefore);});
  await t.test('postcheck recusa drift posterior',async()=>{await q('BEGIN; GRANT SELECT ON colaboradores TO anon');await assert.rejects(()=>q(scripts.postcheck.replace('BEGIN READ ONLY;','')),/POSTCHECK_CATALOG_DRIFT/);await q('ROLLBACK');});
  await t.test('rollback restaura exatamente catálogo e acesso anteriores',async()=>{await q(scripts.rollback);assert.deepEqual(await snapshot(),before);assert.deepEqual(await counts(10),[5,4]);});
 }finally{if(db)await db.end();if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
