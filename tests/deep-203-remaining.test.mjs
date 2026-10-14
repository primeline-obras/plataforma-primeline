import{installCurrentVehicle,installCurrentRnc}from'./deep-current-documental.mjs';
import {authorizationCases} from './financeiro-regression-cases.mjs';
import {financialCases} from './financeiro-cross-tenant-cases.mjs';
import {economicWriterCases} from './writers-economicos-cases.mjs';
import {finalEconomicCases} from './writers-economicos-final-cases.mjs';
import {finalAuditCases} from './writers-economicos-final-audit-cases.mjs';
import {budgetTargetCases} from './orcamento-fases-target-cases.mjs';
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
test('PostgreSQL local: catÃ¡logo real, RLS, RPCs, perfis e reversÃ£o',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
  // Reproduz TODOS os tipos, policies, grants, views e funÃ§Ãµes do catÃ¡logo real.
  // Sem linhas reais, defaults/triggers/FKs operacionais nÃ£o sÃ£o disparados nesta fixture.
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
   assert.deepEqual(a,expected,'catÃ¡logo da tabela '+a.name);
  }
  for(const a of rebuilt.functions){const f=fixture.catalog.functions.find(f=>f.signature===a.signature);assert.deepEqual(a,{signature:f.signature,owner:f.owner,acl:'{'+(f.acl||'{=X/postgres,postgres=X/postgres}').slice(1,-1).split(',').sort().join(',')+'}',definition:fixture.details.definitions[f.signature].replaceAll('\r','')},a.signature);}
  await t.test('precheck exato contra catÃ¡logo real reconstruÃ­do',async()=>{await q(scripts.precheck);});
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
   await q('INSERT INTO utilizadores(id,auth_user_id,empresa_id,funcao,ativo,nome) VALUES($1,$1,$2,$3,true,$4)',[id(n),id(company),role,'Perfil sintÃ©tico '+n]);
  }
  for(const [n,company] of [[120,1],[118,1],[122,1],[200,2]])await q("INSERT INTO obras(id,empresa_id,numero,nome,situacao) VALUES($1,$2,$3,'Obra sintÃ©tica','em_curso')",[id(n),id(company),n]);
  for(const [n,papel,work] of [[10,'encarregado',120],[18,'encarregado',200],[14,'diretor_obra',120],[15,'adjunto',120],[16,'preparador',120]])await q('INSERT INTO obra_responsaveis(id,obra_id,utilizador_id,papel) VALUES(gen_random_uuid(),$1,$2,$3)',[id(work),id(n),papel]);
  for(const [n,work] of [[30,120],[31,118],[32,122],[33,null],[34,120],[35,200]]){
   await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao,data_saida,nif,morada,valor_hora) VALUES($1,$2,$3,'Pedreiro','2026-01-01',$4,'PII_SYNTHETIC','ADDRESS_SYNTHETIC',99)",[id(n),id(n===35?2:1),'Pessoa sintÃ©tica '+n,n===34?'2026-09-01':null]);
   if(work)await q("INSERT INTO quadro_pessoal_alocacao(id,colaborador_id,obra_id,data,semana_inicio,periodo,tipo_alocacao,criado_em) VALUES($1,$2,$3,current_date,current_date,'dia_inteiro','obra',now())",[id(n+1000),id(n),id(work)]);
  }
  for(const [n,work] of [[40,120],[41,118],[42,122],[43,200]]){
   await q("INSERT INTO subempreitadas(id,obra_id,fornecedor_id,especialidade,valor_adjudicado,tipo_pagamento,condicao_pagamento) VALUES($1,$2,$3,'Trabalho sintÃ©tico',999,'SENSITIVE','SENSITIVE')",[id(n),id(work),id(500)]);
   await q('INSERT INTO pagamentos_subempreitada(id,subempreitada_id,valor) VALUES($1,$2,999)',[id(n+200),id(n)]);
   await q('INSERT INTO avaliacoes_subempreiteiro(id,obra_id,subempreitada_id,fornecedor_id) VALUES($1,$2,$3,$4)',[id(n+300),id(work),id(n),id(500)]);
  }
  await q("INSERT INTO medicina_trabalho(id,colaborador_id,data_ultima_consulta,resultado,revisao,criado_em) VALUES($1,$2,current_date,'apto',1,now())",[id(600),id(30)]);
  const asRole=async(n,sql,params=[])=>{await q('BEGIN');try{await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(n)]);await q('SET LOCAL ROLE authenticated');return await q(sql,params);}finally{await q('ROLLBACK');}};


  await q(scripts.migration);await q(scripts.postcheck);await installCurrentVehicle(q);await installCurrentRnc(q);const fs=await import('node:fs'),proofs=[];
  const roles=[[12,'gestao_plataforma'],[13,'gerencia'],[11,'administrativo'],[17,'financeiro'],[14,'diretor_obra'],[15,'adjunto'],[16,'preparador'],[10,'encarregado']];
  const actions=[['CUSTOMER_CREATE',[12,13,14,15,16]],['MEDICINE',[12,13,11,10]],['VEHICLE',[12,13,11]],['CONSULT_CREATE',[12,13,14,15,16]],['COMPARATIVE_DELETE',[12,13,14,15,16]],['ALERT_RESOLVE',[12,13,11,17,14,15,16]],['RNC_CREATE',[12,13,14,15,16,10]]];
  const state=async()=>{const result={};for(const table of fixture.catalog.tables.filter(x=>x.kind==='r'))result[table.name]=(await q('SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) v FROM public.'+qi(table.name)+' t')).rows[0].v;return JSON.stringify(result)};
  try{for(const[action,allowed]of actions)for(const[actor,profile]of roles)await t.test('203 '+action+' / '+profile,async()=>{
   await q('BEGIN');try{let sql,params,check;
    if(action==='CUSTOMER_CREATE'){sql="INSERT INTO faturacao(id,obra_id,valor,estado,estado_aprovacao,estado_pagamento) VALUES($1,$2,543,'rascunho','pendente','por_pagar') RETURNING to_jsonb(faturacao) v";params=[id(9880),id(120)];check=r=>assert.equal(r.rows[0].v.estado,'rascunho')}
    if(action==='MEDICINE'){sql='SELECT fn_medicina_consultar_colaborador(1,$1) v';params=[id(30)];check=r=>{assert.equal(r.rows[0].v.version,1);if(actor===10)assert.equal(r.rows[0].v.can_write,false)}}
    if(action==='VEHICLE'){await q('ALTER TABLE viaturas_atribuicoes_historico ALTER COLUMN id SET DEFAULT gen_random_uuid()');await q('INSERT INTO viaturas(id,empresa_id,atribuicao_revisao) VALUES($1,$2,0)',[id(9880),id(1)]);sql='SELECT fn_alterar_responsavel_viatura(1,$1,$2,0,$3,\'Atribuição sintética\') v';params=[id(9880),id(30),id(9881)];check=r=>assert.equal(r.rows[0].v.atribuicao_revisao,1)}
    if(action==='CONSULT_CREATE'){for(const table of ['consultas_subempreitada','consultas_subempreitada_itens'])await q('ALTER TABLE '+table+' ALTER COLUMN id SET DEFAULT gen_random_uuid()');await q("INSERT INTO especialidades(id,nome) VALUES($1,'Especialidade sintética')",[id(9889)]);await q('INSERT INTO fases(id,obra_id) VALUES($1,$2)',[id(9882),id(120)]);await q("INSERT INTO planeamento_itens(id,fase_id,especialidade_id,executado_por,estado) VALUES($1,$2,$3,'subempreitada','por_iniciar')",[id(9883),id(9882),id(9889)]);await q('INSERT INTO itens_orcamento(id,fase_id,quantidade) VALUES($1,$2,1)',[id(9884),id(9882)]);sql="SELECT to_jsonb(fn_criar_consulta_planeamento($1,$2,'Especialidade sintética',$3,$4)) v";params=[id(120),id(9882),[id(9884)],id(9883)];check=r=>assert.equal(r.rows[0].v.planeamento_item_id,id(9883))}
    if(action==='COMPARATIVE_DELETE'){await q('INSERT INTO mapas_comparativos(id,obra_id) VALUES($1,$2)',[id(9880),id(120)]);sql='SELECT fn_eliminar_mapa_comparativo($1) v';params=[id(9880)];check=async r=>assert.equal((await q('SELECT count(*)::int n FROM mapas_comparativos WHERE id=$1',[id(9880)])).rows[0].n,0)}
    if(action==='ALERT_RESOLVE'){await q("INSERT INTO alertas(id,empresa_id,obra_id,destinatario_role,destinatario_utilizador_id,estado) VALUES($1,$2,$3,$4,$5,'pendente')",[id(9880),id(1),id(120),profile,id(actor)]);sql='SELECT to_jsonb(fn_resolver_alerta($1)) v';params=[id(9880)];check=r=>assert.equal(r.rows[0].v.estado,'resolvido')}
    if(action==='RNC_CREATE'){await q('ALTER TABLE rnc ALTER COLUMN id SET DEFAULT gen_random_uuid()');sql="SELECT to_jsonb(fn_criar_rnc($1,current_date,NULL,'Local sintético','Descrição sintética','execucao_propria',NULL,'menor')) v";params=[id(120)];check=r=>assert.ok(r.rows[0].v.id)}
    const before=await state();await q('SAVEPOINT operation');await q("SELECT set_config('request.jwt.claim.sub',$1,true)",[id(actor)]);await q('SET LOCAL ROLE authenticated');let r,error;
    try{r=await q(sql,params);await q('RESET ROLE');await check(r)}catch(e){error={code:e.code||'ASSERT',message:e.message};await q('ROLLBACK TO SAVEPOINT operation')}
    const after=await state(),unchanged=before===after,expect=allowed.includes(actor),authError=error&&(error.code==='42501'||error.code==='P0001'&&/permiss|FORBIDDEN/i.test(error.message));const result=error&&!authError?'BLOQUEADO':expect?(!error&&(action==='MEDICINE'?unchanged:!unchanged)?'PASS':'FAIL'):(authError&&unchanged?'PASS':'FAIL');
    proofs.push({action,profile,expected:expect?'PERMITIR':'RECUSAR',observed:error||r.rows[0],result,no_write_on_denial:expect?null:unchanged,environment:'PostgreSQL local; captura estrutural/RLS/ACL + migration consolidada',limit:action==='CUSTOMER_CREATE'?'INSERT do cabeçalho real; cadeia frontend Storage/links não exercitada':'Gatilhos/defaults só os necessários à operação; Viaturas inclui o corpo/helper documental posterior; não catálogo de produção atual'});assert.notEqual(result,'FAIL',JSON.stringify(proofs.at(-1)));
   }finally{await q('ROLLBACK')}
  })}finally{fs.writeFileSync('docs/auditorias/validacao-profunda-20261014/EVIDENCIAS-RESTANTES-PERFIS.json',JSON.stringify({synthetic_only:true,production_access:false,proofs},null,2)+'\n')}
 }finally{if(db)await db.end();if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
