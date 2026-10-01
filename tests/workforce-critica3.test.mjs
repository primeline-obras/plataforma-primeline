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
test('PostgreSQL 17.6: checks finais isolados do P1 de alertas',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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
 const collision=async(d,acao='alocar',profile=13)=>{
  const before=await snap();await actor(a,profile);const p=await call(a,acao,d);assert.equal(p.committed,false);
  await a.query('SAVEPOINT p1_failed');let error;await assert.rejects(()=>call(a,acao,d,true,p.versao),e=>{error=e;return e.code==='23505'&&e.constraint==='alertas_ocorrencia_unica_idx';});
  await a.query('ROLLBACK TO p1_failed; RELEASE p1_failed');assert.deepEqual(await snap(),before,'nenhum efeito parcial: alocação/revisão/histórico/alertas/request');
  assert.equal(before.operations.filter(o=>o.request_id===d.request_id).length,0);
  assert.ok(attempted.length>=2||before.alerts.length>0);return {p,error,rows:[...attempted]};
 };
 const evidence=[];
 for(const phase of ['A','B']){
  if(phase==='B'){
   await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));
   await q(await read('../supabase/quadro_controlado_fase_b_backup.sql'));
   await q(await read('../supabase/quadro_controlado_fase_b.sql'));
   await q(await read('../supabase/quadro_controlado_fase_b_postcheck.sql'));
  }
  await unit(phase+': Administrativo + Diretor colidem; atomicidade; request reutilizável',async()=>{
   const d=op();const c=await collision(d);const fields=['tipo','entidade_tipo','entidade_id','data_evento_referencia','antecedencia_dias','ocorrencia_chave','destinatario_role','destinatario_utilizador_id','destinatario_colaborador_id','obra_id'];
   const rows=c.rows.map(r=>Object.fromEntries(fields.map(k=>[k,r[k]??null])));assert.equal(rows.length,2);assert.equal(new Set(rows.map(r=>r.destinatario_utilizador_id)).size,2);
   const key=r=>JSON.stringify([r.tipo,r.entidade_tipo,r.entidade_id,r.data_evento_referencia,r.antecedencia_dias??-1,r.ocorrencia_chave??id(0).replace('4000','0000')]);assert.equal(key(rows[0]),key(rows[1]));
   evidence.push({phase,operation:'alocar',rows,code:c.error.code,constraint:c.error.constraint});
   // Reduzir elegibilidade só na fixture, sem corrigir emissor/índice, permite repetir request intacto.
   await single();await actor(a,13);const retry=await call(a,'alocar',d,true,c.p.versao);assert.equal(retry.committed,true);assert.equal(retry.idempotent,false);
   const saved=await snap();assert.equal(saved.operations.filter(o=>o.request_id===d.request_id).length,1);assert.equal(saved.alerts.length,1);assert.equal(saved.revisions.find(r=>r.colaborador_id===id(30)).revisao,1);
   await actor(a,13);const replay=await call(a,'alocar',d,true,c.p.versao);assert.equal(replay.idempotent,true);assert.deepEqual(await snap(),saved);
  });
  await unit(phase+': zero destinatários guarda sem alerta',async()=>{
   await single();await a.query('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(10)]);await actor(a,13);assert.equal((await save(op())).r.committed,true);assert.equal((await snap()).alerts.length,0);
  });
  await unit(phase+': um destinatário inicial guarda; replay sem duplicar; novo request não contorna',async()=>{
   await a.query("UPDATE utilizadores SET ativo=false WHERE id=$1",[id(10)]);await actor(a,13);const d=op();const {p,r}=await save(d);assert.equal(r.committed,true);let state=await snap();assert.equal(state.alerts.length,1);assert.equal(state.alerts[0].destinatario_utilizador_id,id(14));
   await actor(a,13);assert.equal((await call(a,'alocar',d,true,p.versao)).idempotent,true);assert.deepEqual(await snap(),state);
   await actor(a,13);const noop=await save(op(100,1,8001));assert.equal(noop.r.committed,true);const next=await snap();assert.equal(next.alerts.length,1);assert.deepEqual(next.revisions,state.revisions);assert.deepEqual(next.history,state.history);
  });
  await unit(phase+': dois Administrativos colidem sem Diretor',async()=>{
   await single();await a.query("INSERT INTO utilizadores(id,empresa_id,nome,email,funcao,ativo,auth_user_id) VALUES($1,$2,'Admin sintético 19','admin19@synthetic.test','administrativo',true,$1)",[id(19),id(1)]);
   const c=await collision(op());assert.deepEqual(new Set(c.rows.map(r=>r.destinatario_utilizador_id)),new Set([id(10),id(19)]));
  });
  await unit(phase+': Diretor origem + destino + Admin + Encarregado origem; falha na segunda linha',async()=>{
   await seed(op());await a.query("INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,'diretor_obra'),($3,$4,'encarregado'),($3,$5,'adjunto')",[id(101),id(15),id(100),id(18),id(16)]);
   const eligible=(await a.query("WITH d AS (SELECT utilizador_id,1 prioridade FROM obra_responsaveis WHERE obra_id=$1 AND papel='encarregado' UNION ALL SELECT utilizador_id,2 FROM obra_responsaveis WHERE obra_id=$1 AND papel='diretor_obra' UNION ALL SELECT utilizador_id,3 FROM obra_responsaveis WHERE obra_id=$2 AND papel='diretor_obra' UNION ALL SELECT id,4 FROM utilizadores WHERE empresa_id=$3 AND funcao='administrativo') SELECT DISTINCT u.id FROM d JOIN utilizadores u ON u.id=d.utilizador_id WHERE u.ativo AND u.auth_user_id IS NOT NULL AND u.empresa_id=$3 AND u.id<>$4",[id(100),id(101),id(1),id(13)])).rows;
   assert.equal(eligible.length,4);assert.ok(!eligible.some(r=>r.id===id(16)));const c=await collision(op(101,1,8002),'mover');assert.equal(c.rows.length,2);
  });
  for(const kind of ['mover','split','merge'])await unit(phase+': '+kind+' colide com dois destinatários',async()=>{
   if(kind==='merge'){await seed(op(100,0,8100,'manha'));await seed(op(101,1,8101,'tarde'));await collision(op(100,2,8102),'alocar');}
   else {await seed(op());await collision(op(101,1,8102,kind==='split'?'manha':'dia_inteiro'),'mover');}
  });
  await unit(phase+': merge pode colidir mesmo com um destinatário por par origem/destino',async()=>{
   await single();await seed(op(100,0,8100,'manha'));await seed(op(101,1,8101,'tarde'));
   // Destino 102 produz dois pares de origem e o mesmo ID agregado.
   await a.query("INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES($1,$2,'encarregado')",[id(102),id(13)]);const c=await collision(op(102,2,8102),'alocar');assert.ok(c.rows.every(r=>r.destinatario_utilizador_id===id(10)));
  });
  await unit(phase+': um destinatário também colide se reutilizar alocação/dia já alertados',async()=>{
   await single();await actor(a,13);await save(op());await collision(op(101,1,8102),'mover');
  });
  await unit(phase+': remover não cria alerta; conserva alerta anterior',async()=>{
   await single();await actor(a,13);await save(op());const state=await snap();await actor(a,13);await save({version:1,colaborador_id:id(30),data:'2026-10-05',ids:state.allocations.filter(x=>x.colaborador_id===id(30)&&x.data==='2026-10-05').map(x=>x.id),expected_revision:1,request_id:id(8200)},'remover');const end=await snap();assert.deepEqual(end.alerts,state.alerts);assert.equal(end.allocations.filter(x=>x.colaborador_id===id(30)&&x.data==='2026-10-05').length,0);
  });
  for(const profile of [10,12])await unit(phase+': actor '+profile+' aloca/move/split/merge sem notificar',async()=>{
   await actor(a,profile);await save(op());await save(op(101,1,8201),'mover');await save(op(100,2,8202,'manha'),'mover');await save(op(101,3,8203));assert.equal((await snap()).alerts.length,0);
  });
  await unit(phase+': renomear e Cadastro RH com alocação não notificam',async()=>{
   await actor(a,10);await save({...op(),tipo_alocacao:'pontual',obra_id:null,descricao_livre:'Linha sintética'});
   await save({version:1,tipo_alocacao:'pontual',descricao_anterior:'Linha sintética',descricao_nova:'Linha nova',request_id:id(8204)},'renomear_linha');
   await a.query('SELECT fn_rh_guardar($1::jsonb,false)',[JSON.stringify({campos:{nome:'Cadastro sintético P1',funcao:'Servente',data_admissao:'2026-10-05'},alocacao_tipo:'obra',obra_id:id(100)})]);assert.equal((await snap()).alerts.length,0);
  });
 }
 console.log('P1_FINAL_EVIDENCE',JSON.stringify(evidence));
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});
