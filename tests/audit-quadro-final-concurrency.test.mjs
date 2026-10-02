// Independent local audit. FINDING assertions intentionally reproduce defects; a passing runner is not product acceptance.
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
test('Auditoria independente: concorrência e transição PG 17.6',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client,types}=require(join(deps,'pg'));types.setTypeParser(1082,value=>value);const folder=await mkdtemp(join(tmpdir(),'primeline-quadro-pg176-')),data=join(folder,'data');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const port=socket.address().port;await new Promise(r=>socket.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false;const clients=[];
 async function connect(database='postgres'){const c=new Client({host:'127.0.0.1',port,user:'postgres',database,password:'',ssl:false});await c.connect();clients.push(c);return c;}
 try {
 run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
 const admin=await connect(),a=await connect(),b=await connect(),q=(s,p=[])=>admin.query(s,p);await a.query("SET deadlock_timeout='100ms'");await b.query("SET deadlock_timeout='100ms'");
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

 const awaitScripts={B:await read('../supabase/quadro_controlado_fase_b.sql')};
 const metrics=[];let seq=10000;
 const dataFor=(person,rev=0,work=100,extras={})=>({...op(work,rev,++seq),colaborador_id:id(person),data:'2026-10-19',...extras});
 const execute=async(c,d,action='alocar')=>{const p=await call(c,action,d);return call(c,action,d,true,p.versao);};
 const pair=async(name,fn)=>t.test(name,async()=>{await actor(a,10);await actor(b,13);try{await fn();}finally{await a.query('ROLLBACK');await b.query('ROLLBACK');await a.query('RESET ROLE');await b.query('RESET ROLE');}});
 const waitForLock=async(c)=>{for(let i=0;i<50;i++){const r=(await q('SELECT wait_event_type,wait_event FROM pg_stat_activity WHERE pid=$1',[c.processID])).rows[0];if(r?.wait_event_type==='Lock')return r;await delay(10);}throw Error('Não ficou à espera de lock: '+c.processID);};
 const timing=async(label,promise,releasing)=>{const begin=performance.now();await waitForLock(b);await delay(60);await releasing();const r=await promise;metrics.push({label,ms:Math.round(performance.now()-begin)});return r;};
 for(const phase of ['A','B']){
  if(phase==='B'){
   await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await q(await read('../supabase/quadro_controlado_fase_b_backup.sql'));
   await t.test('transição A→B: escrita legada já enviada, mas bloqueada, é recusada após hardening',async()=>{
    await actor(a,10);await q('BEGIN; LOCK TABLE quadro_pessoal_alocacao IN ACCESS EXCLUSIVE MODE');const pending=result(a.query("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo) VALUES($1,$2,'2026-10-20','2026-10-19','manha')",[id(31),id(100)]));await waitForLock(a);await q(await read('../supabase/quadro_controlado_fase_b.sql'));const r=await pending;assert.ok(r.error);assert.match(r.error.message,/permission denied|CONTROLLED_WRITE/);assert.equal((await q("SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1 AND data='2026-10-20'",[id(31)])).rows[0].n,0);await a.query('RESET ROLE');await q(postFinal);
   });
  }
  await pair(phase+': pessoas diferentes também serializam no lock global, sem deadlock',async()=>{
   const d=dataFor(30),other=dataFor(31);await a.query('BEGIN');await execute(a,d);const pending=result(call(b,'alocar',other));const r=await timing(phase+' different-people',pending,()=>a.query('ROLLBACK'));assert.equal(r.error,undefined);assert.equal(r.value.committed,false);
  });
  await pair(phase+': mesma pessoa/dia, uma confirmação e segunda STALE',async()=>{
   const d=dataFor(phase==='A'?32:45),other=dataFor(phase==='A'?32:45,0,101),pa=await call(a,'alocar',d),pb=await call(b,'alocar',other);await a.query('BEGIN');await call(a,'alocar',d,true,pa.versao);const pending=result(call(b,'alocar',other,true,pb.versao));const r=await timing(phase+' same-person',pending,()=>a.query('COMMIT'));assert.equal(r.error.code,'P0001');assert.match(r.error.message,/STALE_REVISION/);
  });
  if(phase==='A')await pair('A: RPC antiga x nova com previews simultâneos',async()=>{
   const d=dataFor(33),old={colaborador_id:id(33),obra_id:id(101),data:d.data,periodo:'dia_inteiro',tipo_alocacao:'obra'};const p=await call(a,'alocar',d),legacy=(await b.query("SELECT fn_quadro_operar('minha_obra',$1,false,NULL) v",[JSON.stringify(old)])).rows[0].v;await a.query('BEGIN');await call(a,'alocar',d,true,p.versao);const pending=result(b.query("SELECT fn_quadro_operar('minha_obra',$1,true,$2) v",[JSON.stringify(old),legacy.versao]));const r=await timing('legacy/new',pending,()=>a.query('COMMIT'));assert.ok(r.error);assert.match(r.error.message,/alter|mud|recarreg|STALE|desatualizada/i);
  });
  await pair(phase+': Cadastro RH com alocação x movimento de outra pessoa, espera e completa atomicamente',async()=>{
   await actor(b,11);await a.query('BEGIN');await execute(a,dataFor(34));const payload={campos:{nome:'RH concorrente '+phase,funcao:'Pedreiro',data_admissao:'2026-10-19'},alocacao_tipo:'obra',obra_id:id(100),contrato:{tipo_contrato:'tempo_indeterminado',data_inicio:'2026-10-19'}};const pending=result(b.query('SELECT fn_rh_guardar($1,false) v',[JSON.stringify(payload)]));const r=await timing(phase+' RH-create/move',pending,()=>a.query('ROLLBACK'));assert.equal(r.error,undefined);const person=r.value.rows[0].v.id;assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[person])).rows[0].n,1);assert.equal((await q('SELECT count(*)::int n FROM colaboradores_contratos WHERE colaborador_id=$1',[person])).rows[0].n,1);
  });
  await pair(phase+': renomear x mover: segunda operação deteta revisão, sem deadlock',async()=>{
   await actor(b,10);const person=phase==='A'?35:36;const initial=dataFor(person,0,100,{periodo:'manha',obra_id:null,tipo_alocacao:'pontual',descricao_livre:'Linha '+phase});await execute(a,initial);const d=dataFor(person,1,101),p=await call(b,'alocar',d);await a.query('BEGIN');await execute(a,{version:1,request_id:id(++seq),tipo_alocacao:'pontual',descricao_anterior:'Linha '+phase,descricao_nova:'Nova '+phase},'renomear_linha');const pending=result(call(b,'alocar',d,true,p.versao));const r=await timing(phase+' rename/move',pending,()=>a.query('COMMIT'));assert.match(r.error.message,/STALE_REVISION/);
  });
  await pair(phase+': ausência confirma primeiro; atribuição recusa após libertar FK lock',async()=>{
   const person=phase==='A'?37:38;await b.query('RESET ROLE');await b.query('BEGIN');await b.query("INSERT INTO ausencias(colaborador_id,data,tipo) VALUES($1,'2026-10-19','ferias')",[id(person)]);const pending=result(execute(a,dataFor(person)));await waitForLock(a);await b.query('COMMIT');const r=await pending;assert.match(r.error.message,/ABSENCE_CONFLICT/);assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(person)])).rows[0].n,0);
  });
  await pair(phase+': caracterização P2 — atribuição confirma primeiro; ausência posterior coexistente',async()=>{
   const person=phase==='A'?39:40;await a.query('BEGIN');await execute(a,dataFor(person));await b.query('RESET ROLE');const pending=result(b.query("INSERT INTO ausencias(colaborador_id,data,tipo) VALUES($1,'2026-10-19','ferias')",[id(person)]));await waitForLock(b);await a.query('COMMIT');assert.equal((await pending).error,undefined);assert.equal((await q('SELECT count(*)::int n FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[id(person)])).rows[0].n,1);assert.equal((await q('SELECT count(*)::int n FROM ausencias WHERE colaborador_id=$1',[id(person)])).rows[0].n,1);
  });
  await pair(phase+': timeout recusa integralmente; rollback liberta locks para próxima operação',async()=>{
   const person=phase==='A'?41:42;await a.query('BEGIN');await execute(a,dataFor(person));await b.query('BEGIN');await b.query("SET LOCAL lock_timeout='100ms'");const d=dataFor(43);const start=performance.now(),r=await result(call(b,'alocar',d));const ms=Math.round(performance.now()-start);metrics.push({label:phase+' timeout',ms});assert.equal(r.error.code,'55P03');assert.ok(ms>=80&&ms<1500);await a.query('ROLLBACK');await b.query('ROLLBACK');const p=await call(b,'alocar',d);assert.equal(p.committed,false);
  });
 }
 await pair('caracterização P2: duas operações RH numa transação x Quadro permitem ciclo de locks',async()=>{
  await actor(a,10);await actor(b,13);await a.query('BEGIN');const person=id(44),rh=(await a.query('SELECT fn_rh_consultar($1) v',[person])).rows[0].v[0];await a.query('SELECT fn_rh_guardar($1,false)',[JSON.stringify({id:person,versao:rh.versao,campos:{observacoes:'Primeira operação na mesma transação'}})]);await b.query('BEGIN');const pendingB=result(execute(b,dataFor(44)));await waitForLock(b);const pendingA=result(a.query('SELECT fn_rh_guardar($1,false)',[JSON.stringify({campos:{nome:'Segunda operação RH mesma transação',funcao:'Pedreiro',data_admissao:'2026-10-19'},alocacao_tipo:'obra',obra_id:id(100)})]));const outcomes=await Promise.all([pendingA,pendingB]);assert.ok(outcomes.some(x=>x.error?.code==='40P01'));metrics.push({label:'RH batched / Quadro deadlock',victims:outcomes.filter(x=>x.error).map(x=>x.error.code)});
 });

 await pair('rollout B sob operação aberta: timeout deixa A/gate intactos; retry após rollback funciona',async()=>{
  await q(await read('../supabase/quadro_controlado_fase_b_rollback.sql'));await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await a.query('BEGIN');await execute(a,dataFor(46));await q("SET statement_timeout='250ms'");const started=performance.now();await assert.rejects(()=>q(awaitScripts.B),e=>e.code==='57014');await q('ROLLBACK');metrics.push({label:'rollout B timeout',ms:Math.round(performance.now()-started)});await q('SET statement_timeout=0');assert.equal((await q('SELECT estado FROM primeline_quadro_rollout.controlo')).rows[0].estado,'a');assert.equal((await q('SELECT count(*)::int n FROM primeline_quadro_rollout.validacoes WHERE consumida_em IS NULL AND invalidada_em IS NULL')).rows[0].n,1);await a.query('ROLLBACK');await q(awaitScripts.B);await q(postFinal);
 });
 console.log('AUDIT_LOCK_METRICS '+JSON.stringify(metrics));
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});