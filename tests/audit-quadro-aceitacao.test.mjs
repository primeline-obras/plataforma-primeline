// Independent acceptance audit: reuse only local PG fixture setup; new adversarial assertions.
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
test('Aceitação independente: PostgreSQL 17.6',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 // Reconstituir constraints capturados, para não esconder FK/overlaps de concorrência.
 for(const table of meta.tables)for(const c of table.constraints||[]){if(!/PRIMARY KEY/.test(c.definition))await q('ALTER TABLE public.'+table.name+' ADD CONSTRAINT '+c.name+' '+c.definition);}
 for(const tr of meta.tables.find(x=>x.name==='ausencias').triggers){await q(tr.function);await q(tr.definition);}
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

 await q(await read('../supabase/quadro_controlado_backup.sql'));
 await q(migration);await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));
 const realIndex=JSON.parse(await read('./fixtures/quadro-alertas-indice-real.json'));
 assert.equal((await q("SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='alertas' AND column_name='ocorrencia_chave'")).rows[0].column_default,null);
 await q(realIndex.index.definition);

 const script=async name=>read('../supabase/'+name+'.sql');
 const postA=await script('quadro_controlado_fase_a_postcheck');
 const mark=await script('quadro_controlado_marcar_frontend_validado');
 const backupB=await script('quadro_controlado_fase_b_backup');
 const phaseB=await script('quadro_controlado_fase_b');
 const postB=await script('quadro_controlado_fase_b_postcheck');
 const alias=await script('quadro_controlado_postcheck');
 assert.equal(alias,postB,'Alias must be byte-equivalent after LF normalization');
 const original=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v;
 await t.test('A íntegra; prova privada criada para esta instalação',async()=>{await q(postA);await q(mark);});
 const changeBody=async signature=>{const f=(await q('SELECT pg_get_functiondef($1::regprocedure) def,prosrc FROM pg_proc WHERE oid=$1::regprocedure',[signature])).rows[0];await q(f.def.replace(f.prosrc,()=>f.prosrc+'\n-- deliberate acceptance drift'));};

 for(const signature of ['public.fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)','public.fn_quadro_operar_v1(text,jsonb,boolean,text)'])await t.test('Backup B recusa drift antes de capturar '+signature,async()=>{
  await q('BEGIN');try{await changeBody(signature);await assert.rejects(()=>q(backupB),/ROLLOUT_DRIFT/);}finally{await q('ROLLBACK');}await q(postA);
 });
 await q(backupB);await q(phaseB);
 await t.test('B íntegra e alias passam; dados baseline inalterados',async()=>{
  await q(postB);await q(alias);assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v,original);
 });
 const attacks=[
 ['referência ausente','DROP TABLE primeline_backup.quadro_fase_b_estrutura_20261001'],
 ['referência vazia','DELETE FROM primeline_backup.quadro_fase_b_estrutura_20261001'],
 ['referência duplicada','INSERT INTO primeline_backup.quadro_fase_b_estrutura_20261001 SELECT * FROM primeline_backup.quadro_fase_b_estrutura_20261001'],
 ['índice global ausente','DROP INDEX alertas_ocorrencia_unica_idx'],
 ['índice global redefinido',"DROP INDEX alertas_ocorrencia_unica_idx; CREATE UNIQUE INDEX alertas_ocorrencia_unica_idx ON alertas(id)"],
 ['policy eliminada','DROP POLICY quadro_controlado_historico ON quadro_pessoal_movimentos'],
 ['policy extra',"CREATE POLICY acceptance_extra ON quadro_pessoal_movimentos FOR SELECT TO authenticated USING(true)"],
 ['RLS histórico desativada','ALTER TABLE quadro_pessoal_movimentos DISABLE ROW LEVEL SECURITY'],
 ['coluna revisão removida','ALTER TABLE quadro_dias_revisoes DROP COLUMN revisao'],
 ['default revisão alterado','ALTER TABLE quadro_dias_revisoes ALTER COLUMN revisao SET DEFAULT 42'],
 ['coluna data tipo alterado','ALTER TABLE quadro_dias_revisoes ALTER COLUMN data TYPE timestamp'],
 ['tabela operações removida','DROP TABLE quadro_operacoes'],
 ['helper contexto ausente','DROP FUNCTION fn_quadro_contexto_v1(date,date)'],
 ['trigger extra',"CREATE TRIGGER acceptance_extra AFTER INSERT ON quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_registar_movimento_quadro()"],
 ['histórico disabled','ALTER TABLE quadro_pessoal_alocacao DISABLE TRIGGER trg_quadro_pessoal_movimentos'],
 ['histórico eliminado','DROP TRIGGER trg_quadro_pessoal_movimentos ON quadro_pessoal_alocacao'],
 ['histórico rebound',"DROP TRIGGER trg_quadro_pessoal_movimentos ON quadro_pessoal_alocacao; CREATE TRIGGER trg_quadro_pessoal_movimentos AFTER INSERT OR DELETE OR UPDATE ON quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION fn_quadro_proteger_escrita()"],
 ['histórico definição divergente',"DROP TRIGGER trg_quadro_pessoal_movimentos ON quadro_pessoal_alocacao; CREATE TRIGGER trg_quadro_pessoal_movimentos AFTER INSERT OR DELETE OR UPDATE ON quadro_pessoal_alocacao FOR EACH ROW WHEN (pg_trigger_depth() < 10) EXECUTE FUNCTION fn_registar_movimento_quadro()"],
 ['ACL schema privado','GRANT USAGE ON SCHEMA primeline_quadro_rollout TO authenticated'],
 ['marker consumido removido','DELETE FROM primeline_quadro_rollout.validacoes'],
 ['marker invalidado','UPDATE primeline_quadro_rollout.validacoes SET invalidada_em=now()'],
 ['marker consumo removido','UPDATE primeline_quadro_rollout.validacoes SET consumida_em=NULL']
 ];
 for(const [name,sql] of attacks)await t.test('Rejeição independente pós-check/alias: '+name,async()=>{
  for(const check of [postB,alias]){await q('BEGIN');try{await q(sql);await assert.rejects(()=>q(check));}finally{await q('ROLLBACK');}await q(check);}
 });
 for(const privilege of ['SELECT','INSERT','UPDATE','REFERENCES'])await t.test('ACEITAÇÃO FAIL se ACL coluna privada não detetada: '+privilege,async()=>{
  const checks=[];
  for(const [name,check] of [['B',postB],['alias',alias]]){
   await q('BEGIN');try{
    await q('GRANT '+privilege+'(estrutura) ON primeline_backup.quadro_fase_b_estrutura_20261001 TO authenticated');
    const facts=(await q("SELECT has_schema_privilege('authenticated','primeline_backup','USAGE') schema_usage,has_column_privilege('authenticated','primeline_backup.quadro_fase_b_estrutura_20261001','estrutura',$1) column_grant",[privilege])).rows[0];
    assert.equal(facts.schema_usage,false);assert.equal(facts.column_grant,true);
    let error=null;try{await q(check);}catch(e){error=e;}
    checks.push({name,rejected:!!error,code:error?.code,...facts});
   }finally{await q('ROLLBACK');}await q(check);
  }
  console.log('ACCEPTANCE_COLUMN_ACL '+JSON.stringify({privilege,checks}));
  assert.ok(checks.every(x=>x.rejected),'Postcheck B e alias devem recusar grant de coluna da referência privada');
 });
 for(const signature of ['public.fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)','public.fn_registar_movimento_quadro()','public.fn_quadro_operar_v1(text,jsonb,boolean,text)','public.fn_quadro_contexto_v1(date,date)','primeline_quadro_rollout.exigir_validacao()'])await t.test('Corpo crítico alterado mesma assinatura: '+signature,async()=>{
  await q('BEGIN');try{await changeBody(signature);await assert.rejects(()=>q(postB),/POSTCHECK_FAILED/);}finally{await q('ROLLBACK');}await q(alias);
 });
 await t.test('Notifier no-op preservando assinatura/atributos é recusado',async()=>{
  await q('BEGIN');try{const sig='public.fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)',f=(await q('SELECT pg_get_functiondef($1::regprocedure) def,prosrc FROM pg_proc WHERE oid=$1::regprocedure',[sig])).rows[0];await q(f.def.replace(f.prosrc,()=> 'BEGIN RETURN; END'));await assert.rejects(()=>q(postB),/POSTCHECK_FAILED/);}finally{await q('ROLLBACK');}await q(alias);
 });
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
