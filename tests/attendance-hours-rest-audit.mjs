import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHmac,randomBytes} from 'node:crypto';
import {localPostgrestPort} from './local-postgrest-port.mjs';
export async function runHoursRestAudit({t,q,port,id,today,auditMonth,roles,auditEvidence}) {
 const saved=[];for(const signature of ['auth.uid()','public.fn_utilizador_atual_id()','public.fn_e_admin()','public.fn_e_administrativo()'])saved.push((await q('SELECT pg_get_functiondef($1::regprocedure) definition',[signature])).rows[0].definition);
 const mappings=(await q('SELECT id,auth_user_id FROM utilizadores')).rows;
 await q('CREATE ROLE hours_audit_authenticator LOGIN NOINHERIT NOBYPASSRLS; GRANT anon,authenticated TO hours_audit_authenticator');
 await q("CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claims',true)::jsonb->>'sub','')::uuid $$");
 await q('CREATE OR REPLACE FUNCTION public.fn_utilizador_atual_id() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT id FROM public.utilizadores WHERE auth_user_id=auth.uid() $$');
 await q("CREATE OR REPLACE FUNCTION public.fn_e_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT EXISTS(SELECT 1 FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo AND funcao IN('gestao_plataforma','gerencia')) $$");
 await q("CREATE OR REPLACE FUNCTION public.fn_e_administrativo() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$ SELECT public.fn_e_admin() OR EXISTS(SELECT 1 FROM public.utilizadores WHERE id=public.fn_utilizador_atual_id() AND ativo AND funcao='administrativo') $$");
 for(const row of mappings)await q('UPDATE utilizadores SET auth_user_id=$1 WHERE id=$2',[id(600000+Number(row.id.slice(-12))),row.id]);
 const secret=randomBytes(48).toString('base64url'),hp=await localPostgrestPort();
 const token=(actor,extra={})=>{const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),p=Buffer.from(JSON.stringify({role:'authenticated',sub:id(600000+actor),iat:Math.floor(Date.now()/1000)-1,exp:Math.floor(Date.now()/1000)+600,...extra})).toString('base64url');return h+'.'+p+'.'+createHmac('sha256',secret).update(h+'.'+p).digest('base64url');};
 const child=spawn(process.env.QUADRO_POSTGREST,[],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,PGRST_DB_URI:`postgresql://hours_audit_authenticator@127.0.0.1:${port}/postgres`,PGRST_DB_SCHEMAS:'public',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:secret,PGRST_SERVER_HOST:'127.0.0.1',PGRST_SERVER_PORT:String(hp),PGRST_LOG_LEVEL:'warn'}});
 let output='';for(const stream of [child.stdout,child.stderr])stream.on('data',b=>output+=b);
 const url='http://127.0.0.1:'+hp,request=(path,jwt,body)=>fetch(url+'/'+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(jwt?{Authorization:'Bearer '+jwt}:{})},...(body?{body:JSON.stringify(body)}:{})});
 const rpc=(actor,work=99002,jwt=token(actor))=>request('rpc/fn_folha_custos_operacionais_contexto_v3',jwt,{p_obra_id:id(work),p_competencia:auditMonth});
 try {
  let ready=false;for(let i=0;i<100;i++){try{if((await request('',null)).ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}assert.ok(ready,'Local PostgREST startup: '+output);
  await t.test('JWT/PostgREST: synthetic distinct Auth identity maps to authorized technical profiles',async()=>{for(const actor of roles){const r=await rpc(actor);const body=await r.json();assert.equal(r.status,200,JSON.stringify(body));assert.equal(body.individual_costs_included,false);}});
  await t.test('JWT/PostgREST: foreman and cross-company actor denied operational costs',async()=>{for(const [actor,work]of[[13,99002],[17,99002],[14,103]]){const r=await rpc(actor,work);assert.equal(r.status,403);assert.equal((await r.json()).code,'42501');}});
  await t.test('JWT/PostgREST: private tariff denied to technical profiles',async()=>{for(const actor of roles){const r=await request('rpc/fn_folha_custo_hora_contexto_v3',token(actor),{p_colaborador_id:id(99010)});assert.equal(r.status,403,JSON.stringify(await r.json()));}});
  await t.test('JWT/PostgREST: expired token and forged business profile cannot grant access',async()=>{assert.equal((await rpc(14,99002,token(14,{exp:1}))).status,401);assert.equal((await rpc(13,99002,token(13,{funcao:'gestao_plataforma'}))).status,403);});
  await t.test('JWT/PostgREST: same token respects immediate work revocation',async()=>{const jwt=token(14);await q('DELETE FROM obra_responsaveis WHERE obra_id=$1 AND utilizador_id=$2',[id(99002),id(14)]);try{assert.equal((await rpc(14,99002,jwt)).status,403);}finally{await q("INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,'diretor_obra')",[id(99002),id(14)]);}});
  await t.test('JWT/PostgREST: signature, DB role and inactive actor remain authoritative',async()=>{
   const valid=token(14),parts=valid.split('.');parts[2]=(parts[2][0]==='A'?'B':'A')+parts[2].slice(1);assert.equal((await rpc(14,99002,parts.join('.'))).status,401);
   assert.ok([401,403].includes((await rpc(14,99002,token(14,{role:'postgres'}))).status));
   await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(14)]);try{assert.equal((await rpc(14,99002,valid)).status,403);}finally{await q('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(14)]);}
  });
  await t.test('JWT/PostgREST: product client reads scoped aggregate and foreman team with actual HTTP',async()=>{
   const {createHoursPreparationClient}=await import('../src/attendance-hours-client.js');
   const client=actor=>createHoursPreparationClient({supabase:(path,opts)=>fetch(url+'/'+path,{...opts,headers:{Authorization:'Bearer '+token(actor),'Content-Type':'application/json'}}),confirm:async()=>false});
   const data=await client(14).operationalMap(id(99002),auditMonth);assert.equal(data.scope,'work_aggregate');assert.ok(data.known_provisional_estimate>0);
   const team=await client(13).team(today,id(100));assert.equal(team.work_id,id(100));
   await assert.rejects(client(13).operationalMap(id(99002),auditMonth));
  });
  await t.test('JWT/PostgREST: integrated writer previews without facts, commits synthetic fact once and replays',async()=>{
   await q("INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES($1,$2,'Pessoa REST sintética','Pedreiro','2026-01-01')",[id(99030),id(1)]);
   const body={version:3,request_id:id(99031),kind:'primeline',person_id:id(99030),date:today,work_id:id(100),expected_daily_revision:0,sites:[{type:'obra',work_id:id(100),expected_revision:0,intervals:[{start:'08:00',end:'12:00',period:null,mode:'personalizado'}]}]};
   const send=(confirm,version)=>request('rpc/fn_folha_plano_integrado_v3',token(10),{p_dados:body,p_confirmar:confirm,p_versao:version});
   const preview=await send(false,null),p=await preview.json();assert.equal(preview.status,200,JSON.stringify(p));assert.equal((await q('SELECT count(*)::integer n FROM folha_registos WHERE colaborador_id=$1',[id(99030)])).rows[0].n,0);
   const response=await send(true,p.versao),done=await response.json();assert.equal(response.status,200,JSON.stringify(done));assert.equal(done.committed,true);
   const replay=await send(true,p.versao);assert.equal(replay.status,200);assert.deepEqual(await replay.json(),done);
   assert.equal((await q('SELECT count(*)::integer n FROM folha_registos WHERE colaborador_id=$1',[id(99030)])).rows[0].n,1);
  });
  auditEvidence.push({case:'local_authenticated_transport',postgrest:'16.4',signed_synthetic_jwt:true,distinct_auth_subject:true,least_privilege_authenticator:true,hosted_supabase_auth_tested:false});
 } finally {
  child.kill();await new Promise(r=>child.exitCode!==null?r():child.once('exit',r));for(const definition of saved)await q(definition);for(const row of mappings)await q('UPDATE utilizadores SET auth_user_id=$1 WHERE id=$2',[row.auth_user_id,row.id]);
 }
}
