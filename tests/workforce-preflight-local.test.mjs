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
test('PostgreSQL 17.6: pré-varredura adversarial local do Quadro',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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

 await q(await read('../supabase/quadro_controlado_backup.sql'));
 await q(migration);await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));
 const realIndex=JSON.parse(await read('./fixtures/quadro-alertas-indice-real.json'));
 assert.equal((await q("SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='alertas' AND column_name='ocorrencia_chave'")).rows[0].column_default,null);
 await q(realIndex.index.definition);
 const actor=async(c,n=10)=>{await c.query('RESET ROLE');await c.query("SELECT set_config('test.actor',$1,false)",[id(n)]);await c.query('SET ROLE authenticated');};
 const call=async(c,acao,dados,confirm=false,versao=null)=>(await c.query('SELECT fn_quadro_operar_v1($1,$2::jsonb,$3,$4) v',[acao,JSON.stringify(dados),confirm,versao])).rows[0].v;
 const op=(work=100,rev=0,req=8000,period='dia_inteiro')=>({version:1,colaborador_id:id(30),data:'2026-10-05',periodo:period,tipo_alocacao:'obra',obra_id:id(work),expected_revision:rev,request_id:id(req)});
 const save=async(d,acao='alocar')=>{const p=await call(a,acao,d);return {p,r:await call(a,acao,d,true,p.versao)};};
 const attempted=[];a.on('notice',notice=>{if(notice.message.startsWith('P1_ALERT_ROW:'))attempted.push(JSON.parse(notice.message.slice(13)));});
 await a.query('CREATE TEMP TABLE p1_trace_placeholder(i int)');
 await a.query("CREATE FUNCTION pg_temp.p1_trace() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RAISE NOTICE ''P1_ALERT_ROW:%'',row_to_json(NEW); RETURN NEW; END'");
 await a.query('CREATE TRIGGER p1_trace_alert BEFORE INSERT ON public.alertas FOR EACH ROW EXECUTE FUNCTION pg_temp.p1_trace()');
 const snap=async()=>{
  await a.query('RESET ROLE');return (await a.query("SELECT jsonb_build_object('allocations',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM quadro_pessoal_alocacao x),'revisions',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY colaborador_id,data),'[]') FROM quadro_dias_revisoes x),'history',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM quadro_pessoal_movimentos x),'alerts',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM alertas x),'operations',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY request_id),'[]') FROM quadro_operacoes x),'audit',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),'[]') FROM log_auditoria x),'permits',(SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY transacao,colaborador_id,data),'[]') FROM quadro_escrita_interna x)) v")).rows[0].v;
 };
 const unit=async(name,fn)=>t.test(name,async()=>{await a.query('BEGIN');attempted.length=0;try{await fn();}finally{await a.query('ROLLBACK');await a.query('RESET ROLE');}});
 const seed=async(d)=>{await actor(a,10);await save(d);await a.query('RESET ROLE');};
 const single=async()=>a.query("DELETE FROM obra_responsaveis WHERE papel='diretor_obra'");

 const eqKey=async(d,orig,dest,recipient)=>(await a.query("SELECT md5(jsonb_build_array('quadro_movimento_alerta_v1',$1::uuid,$2::uuid,$3::uuid,$4::date,$5::uuid,$6::uuid,$7::uuid)::text)::uuid v",[id(1),d.request_id,d.colaborador_id,d.data,orig,dest,recipient])).rows[0].v;

 const reject=async(fn,re)=>{await a.query('SAVEPOINT denied');try{await assert.rejects(fn,re);}finally{await a.query('ROLLBACK TO denied; RELEASE denied');}};
 for(const phase of ['A','B']){
  if(phase==='B'){await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await q(await read('../supabase/quadro_controlado_fase_b_backup.sql'));await q(await read('../supabase/quadro_controlado_fase_b.sql'));await q(postFinal);}
  await unit(phase+': tenant/autor/requests não permitem leitura ou escrita cruzada',async()=>{
   await actor(a,13);const d=op(),p=await call(a,'alocar',d);await call(a,'alocar',d,true,p.versao);
   await actor(a,17);await reject(()=>call(a,'alocar',d,true,p.versao),/IDEMPOTENCY_CONFLICT/);await reject(()=>call(a,'alocar',op(100,0,8300)),/PERMISSION_DENIED/);
   await actor(a,18);await reject(()=>call(a,'alocar',d,true,p.versao),/IDEMPOTENCY_CONFLICT/);await reject(()=>save(op(100,1,8301)),/PERMISSION_DENIED/);
  });
  await unit(phase+': colaboradores/obras de outra empresa; origem alheia não é retirada',async()=>{
   await actor(a,10);await reject(()=>save({...op(),colaborador_id:id(49)}),/PERMISSION_DENIED/);await reject(()=>save(op(103)),/PERMISSION_DENIED/);await save(op(102));
   await actor(a,13);await reject(()=>save(op(100,1,8301)),/PERMISSION_DENIED/);assert.equal((await snap()).allocations.find(r=>r.colaborador_id===id(30)).obra_id,id(102));
  });
  for(const who of [11,14,15,16])await unit(phase+': perfil '+who+' não adquire escrita global com GUC/payload',async()=>{
   await actor(a,who);await a.query("SELECT set_config('primeline.quadro_rpc','on',true)");await a.query("SELECT set_config('primeline.quadro.frontend_validado','anything',true)");await reject(()=>save({...op(),can_manage_global:true,origem:'cadastro_rh',utilizador_id:id(10)}),/PERMISSION_DENIED/);
  });
  await unit(phase+': helpers/permits privados e CREATE no schema público inacessíveis',async()=>{
   await actor(a,13);await reject(()=>a.query("SELECT fn_quadro_aplicar_interno($1,'2026-10-05','[]','[]','quadro',$2,false)",[id(30),id(8000)]),/permission denied/);
   await reject(()=>a.query('SELECT * FROM quadro_escrita_interna'),/permission denied/);await reject(()=>a.query('SELECT * FROM primeline_quadro_rollout.validacoes'),/permission denied/);
   await reject(()=>a.query('CREATE TABLE public.quadro_spoof(i int)'),/permission denied/);
  });
  await unit(phase+': inativo/ausente/antes da admissão recusados; remoção explícita ainda funciona',async()=>{
   await actor(a,10);await save(op());await a.query('RESET ROLE');await a.query("UPDATE colaboradores SET data_saida='2026-10-01' WHERE id=$1",[id(30)]);await actor(a,10);await reject(()=>save(op(101,1,8301)),/indisponível/);
   const rows=(await snap()).allocations.filter(r=>r.colaborador_id===id(30));await actor(a,10);await save({version:1,colaborador_id:id(30),data:'2026-10-05',ids:rows.map(r=>r.id),expected_revision:1,request_id:id(8302)},'remover');
   await a.query('RESET ROLE');await a.query("UPDATE colaboradores SET data_saida=NULL,data_admissao='2026-10-06' WHERE id=$1",[id(30)]);await actor(a,10);await reject(()=>save(op(100,2,8303)),/indisponível/);
   await a.query('RESET ROLE');await a.query("UPDATE colaboradores SET data_admissao='2026-01-01' WHERE id=$1",[id(30)]);await a.query("INSERT INTO ausencias(colaborador_id,data,tipo,estado) VALUES($1,'2026-10-05','ferias','confirmada')",[id(30)]);await actor(a,10);await reject(()=>save(op(100,2,8304)),/ABSENCE_CONFLICT/);
  });
  await unit(phase+': destinatários inativos/sem login/outro tenant não recebem',async()=>{
   await a.query('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(14)]);await a.query('UPDATE utilizadores SET auth_user_id=NULL WHERE id=$1',[id(10)]);await a.query("INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,'diretor_obra')",[id(100),id(17)]);await actor(a,13);await save(op());assert.equal((await snap()).alerts.length,0);
  });
  await unit(phase+': rename por Encarregado recusado; nenhum legado sobreposto é corrigido em silêncio',async()=>{
   await actor(a,13);await reject(()=>save({version:1,request_id:id(8400),tipo_alocacao:'pontual',descricao_anterior:'A',descricao_nova:'B'},'renomear_linha'),/PERMISSION_DENIED/);
   await actor(a,10);await reject(()=>save({...op(),colaborador_id:id(21),data:'2026-09-29'}),/LEGACY_CONFLICT/);
  });
  await unit(phase+': inputs incompletos, NULL e IDs inexistentes não criam escrita parcial',async()=>{
   await actor(a,10);for(const d of [{...op(),version:2},{...op(),request_id:null},{...op(),periodo:null},{...op(),tipo_alocacao:null},{...op(),data:null}])await reject(()=>save(d),/CONTRACT_VERSION|VALIDATION_ERROR|PERMISSION_DENIED/);
   await reject(()=>save({version:1,colaborador_id:id(30),data:'2026-10-05',ids:[id(99999)],expected_revision:0,request_id:id(8400)},'remover'),/STALE_REVISION/);assert.equal((await snap()).operations.length,0);
  });
  await unit(phase+': caracterização P2 — replay devolve snapshot original após perda de papel/âmbito',async()=>{
   await actor(a,13);const d=op(),p=await call(a,'alocar',d);const r=await call(a,'alocar',d,true,p.versao);await a.query('RESET ROLE');await a.query("UPDATE utilizadores SET funcao='preparador' WHERE id=$1",[id(13)]);await a.query('DELETE FROM obra_responsaveis WHERE utilizador_id=$1',[id(13)]);await actor(a,13);
   await reject(()=>a.query("SELECT fn_quadro_contexto_v1('2026-10-05','2026-10-05')"),/PERMISSION_DENIED/);const replay=await call(a,'alocar',d,true,p.versao);assert.equal(replay.idempotent,true);assert.deepEqual(replay.allocations,r.allocations);assert.equal((await snap()).operations.length,1);
  });
  await unit(phase+': caracterização P2 — alerta histórico preservado após eliminar origem',async()=>{
   await actor(a,13);const {r}=await save(op());await save({version:1,colaborador_id:id(30),data:'2026-10-05',ids:r.allocations.map(x=>x.id),expected_revision:1,request_id:id(8400)},'remover');const s=await snap();assert.equal(s.allocations.filter(x=>x.colaborador_id===id(30)).length,0);assert.equal(s.alerts.length,2);assert.ok(s.alerts.every(x=>!s.allocations.some(y=>y.id===x.entidade_id)));
  });
  await t.test(phase+': duas ligações — lock comum entre API legada e v1; revisão invalida confirmação',async()=>{
   const d={...op(),colaborador_id:id(31),request_id:id(8500)},legacy={colaborador_id:id(31),data:'2026-10-05',periodo:'dia_inteiro',tipo_alocacao:'obra',obra_id:id(101)};
   await actor(a,13);await actor(b,13);const p=await call(a,'alocar',d);await a.query('BEGIN');let pending;try{
    await call(a,'alocar',d,true,p.versao);
    if(phase==='A')pending=result(b.query("SELECT fn_quadro_operar('minha_obra',$1::jsonb,false,NULL) v",[JSON.stringify(legacy)]));else pending=result(call(b,'alocar',{...d,obra_id:id(101),request_id:id(8501)}));
    let done=false;pending.then(()=>done=true);await delay(80);assert.equal(done,false);await a.query('COMMIT');const outcome=await pending;
    if(phase==='A'){assert.equal(outcome.error,undefined);assert.ok(outcome.value.rows[0].v.versao);}else assert.match(outcome.error.message,/STALE_REVISION/);
   }finally{await a.query('ROLLBACK');await a.query('RESET ROLE');await b.query('RESET ROLE');}
   await q('BEGIN');await q("SELECT set_config('test.actor',$1,true)",[id(10)]);await q('SET LOCAL ROLE authenticated');const remove={version:1,colaborador_id:id(31),data:d.data,expected_revision:1,request_id:id(8502),ids:(await q('SELECT id FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(31)])).rows.map(r=>r.id)};const preview=(await q("SELECT fn_quadro_operar_v1('remover',$1,false,NULL) v",[JSON.stringify(remove)])).rows[0].v;await q("SELECT fn_quadro_operar_v1('remover',$1,true,$2)",[JSON.stringify(remove),preview.versao]);await q('COMMIT'); await q('DELETE FROM alertas WHERE entidade_id=ANY($1::uuid[])',[remove.ids]);await q('DELETE FROM quadro_operacoes WHERE request_id=ANY($1::uuid[])',[[id(8500),id(8501),id(8502)]]);await q('DELETE FROM quadro_dias_revisoes WHERE colaborador_id=$1',[id(31)]);
  });
 }
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
