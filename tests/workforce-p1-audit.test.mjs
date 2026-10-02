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
test('Pré-varredura P1: PostgreSQL 17.6',{timeout:240000,skip:!bin||!deps?'Definir QUADRO_PG_BIN e QUADRO_TEST_DEPS':false},async t=>{
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

 const awaitSql={backupB:await read('../supabase/quadro_controlado_fase_b_backup.sql'),phaseB:await read('../supabase/quadro_controlado_fase_b.sql')};
 const denied=async(fn,re)=>{await a.query('SAVEPOINT expected');try{await assert.rejects(fn,e=>re.test(e.message));}finally{await a.query('ROLLBACK TO expected; RELEASE expected');}};
 const owner=async()=>a.query('RESET ROLE');
 const entityAlerts=async(ids)=>(await q('SELECT * FROM alertas WHERE entidade_id=ANY($1::uuid[]) ORDER BY destinatario_utilizador_id',[ids])).rows;
 for(const phase of ['A','B']){
  if(phase==='B'){await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await q(await read('../supabase/quadro_controlado_fase_b_backup.sql'));await q(await read('../supabase/quadro_controlado_fase_b.sql'));await q(postFinal);}
  await unit(phase+': índice global sem alteração e todos os constraints reais preservados',async()=>{
   const installed=(await a.query("SELECT pg_get_indexdef('alertas_ocorrencia_unica_idx'::regclass) v")).rows[0].v;assert.equal(installed,realIndex.index.definition);
   for(const table of meta.tables)for(const c of table.constraints||[]){assert.equal((await a.query('SELECT count(*)::int n FROM pg_constraint WHERE conrelid=$1::regclass AND conname=$2',['public.'+table.name,c.name])).rows[0].n,1);}
  });
  await unit(phase+': geração independente da chave; dois destinatários; não depende do UUID gerado',async()=>{
   await actor(a,13);const d=op(),p=await call(a,'alocar',d);assert.equal(attempted.length,0);await a.query('SAVEPOINT event');const first=await call(a,'alocar',d,true,p.versao);const keys=attempted.map(x=>x.ocorrencia_chave).sort();assert.equal(keys.length,2);await a.query('ROLLBACK TO event; RELEASE event');attempted.length=0;const second=await call(a,'alocar',d,true,p.versao);assert.notEqual(first.allocations[0].id,second.allocations[0].id);assert.deepEqual(attempted.map(x=>x.ocorrencia_chave).sort(),keys);
   const {createHash}=await import('node:crypto');for(const alert of attempted){const arr=['quadro_movimento_alerta_v1',id(1),d.request_id,id(30),'2026-10-05',null,id(100),alert.destinatario_utilizador_id];const canonical='['+arr.map(x=>JSON.stringify(x)).join(', ')+']';const hex=createHash('md5').update(canonical).digest('hex');const expected=[hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');assert.equal(alert.ocorrencia_chave,expected);}
   const before=await snap();await actor(a,13);await call(a,'alocar',d,true,p.versao);assert.deepEqual(await snap(),before);
  });
  for(const multiple of [false,true])for(const period of ['manha','tarde','dia_inteiro'])await unit(phase+': múltiplas='+multiple+', substituir '+period+' não cria sobreposição',async()=>{
   await a.query('UPDATE colaboradores SET permite_multiplas_obras=$1 WHERE id=$2',[multiple,id(30)]);await actor(a,10);await save(op(100,0,9000,period));const {r}=await save(op(101,1,9001,period));assert.equal(r.allocations.length,1);assert.equal(r.allocations[0].obra_id,id(101));assert.equal(r.revision,2);
   if(period!=='dia_inteiro'){const other=period==='manha'?'tarde':'manha';const half=await save(op(100,2,9002,other));assert.equal(half.r.allocations.length,2);assert.deepEqual(new Set(half.r.allocations.map(x=>x.periodo)),new Set(['manha','tarde']));}
  });
  for(const half of ['manha','tarde'])await unit(phase+': dia inteiro → '+half+' → inteiro, histórico/revisão atómicos',async()=>{
   await actor(a,10);await save(op());const split=(await save(op(101,1,9001,half))).r;assert.equal(split.allocations.length,2);assert.equal(split.revision,2);const merged=(await save(op(100,2,9002))).r;assert.equal(merged.allocations.length,1);assert.equal(merged.revision,3);assert.equal(merged.allocations[0].periodo,'dia_inteiro');
  });
  for(const kind of ['escritorio','garantia','pontual'])await unit(phase+': obra/linha '+kind+' em períodos distintos; nenhuma herança temporal',async()=>{
   await actor(a,10);await save(op(100,0,9000,'manha'));const d={...op(100,1,9001,'tarde'),obra_id:null,tipo_alocacao:kind,descricao_livre:'Linha '+kind};const r=(await save(d)).r;assert.equal(r.allocations.length,2);assert.equal(r.allocations.filter(x=>x.periodo==='tarde')[0].obra_id,null);const next=(await a.query("SELECT fn_quadro_contexto_v1('2026-10-06','2026-10-14') v")).rows[0].v;assert.equal(next.allocations.filter(x=>x.colaborador_id===id(30)).length,0);
  });
  await unit(phase+': erro após DELETE de merge reverte origem/destino/histórico/revisão/alerta',async()=>{
   await actor(a,10);await save(op(100,0,9000,'manha'));await save(op(101,1,9001,'tarde'));const before=await snap();await a.query("CREATE FUNCTION pg_temp.audit_fail_merge() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RAISE EXCEPTION ''AUDIT_FAIL_AFTER_DELETE''; END'");await a.query('CREATE TRIGGER audit_fail_merge AFTER UPDATE ON quadro_pessoal_alocacao FOR EACH ROW EXECUTE FUNCTION pg_temp.audit_fail_merge()');await actor(a,10);await denied(()=>save(op(100,2,9002)),/AUDIT_FAIL_AFTER_DELETE/);assert.deepEqual(await snap(),before);
  });
  for(const initial of [null,'obra','escritorio'])await unit(phase+': RH criação '+initial+' histórica/data explícita atómica',async()=>{
   await actor(a,11);const payload={campos:{nome:'RH audit '+initial,funcao:'Servente',data_admissao:'2020-02-03'},alocacao_tipo:initial,obra_id:initial==='obra'?id(100):null,contrato:{tipo_contrato:'tempo_indeterminado',data_inicio:'2020-02-03'}};const r=(await a.query('SELECT fn_rh_guardar($1::jsonb,false) v',[JSON.stringify(payload)])).rows[0].v;assert.ok(r.id);await owner();const al=(await a.query('SELECT * FROM quadro_pessoal_alocacao WHERE colaborador_id=$1',[r.id])).rows;assert.equal(al.length,initial?1:0);if(initial){assert.equal(al[0].data,'2020-02-03');const h=(await a.query('SELECT * FROM quadro_pessoal_movimentos WHERE colaborador_id=$1',[r.id])).rows;assert.equal(h.length,1);assert.equal(h[0].origem_operacao,'cadastro_rh');assert.equal(h[0].alterado_por,id(11));}assert.equal((await a.query('SELECT count(*)::int n FROM colaboradores_contratos WHERE colaborador_id=$1',[r.id])).rows[0].n,1);
  });
  await unit(phase+': RH falha após contrato reverte pessoa/contrato/alocação/ledger',async()=>{
   await a.query("CREATE FUNCTION pg_temp.audit_fail_contract() RETURNS trigger LANGUAGE plpgsql AS 'BEGIN RAISE EXCEPTION ''AUDIT_CONTRACT_LATE''; END'");await a.query('CREATE TRIGGER audit_fail_contract AFTER INSERT ON colaboradores_contratos FOR EACH ROW EXECUTE FUNCTION pg_temp.audit_fail_contract()');const before=await snap();const persons=(await a.query('SELECT count(*)::int n FROM colaboradores')).rows[0].n;await actor(a,10);await denied(()=>a.query('SELECT fn_rh_guardar($1::jsonb,false)',[JSON.stringify({campos:{nome:'RH late','funcao':'Servente',data_admissao:'2026-10-05'},alocacao_tipo:'obra',obra_id:id(100),contrato:{tipo_contrato:'tempo_indeterminado',data_inicio:'2026-10-05'}})]),/AUDIT_CONTRACT_LATE/);assert.deepEqual(await snap(),before);assert.equal((await a.query('SELECT count(*)::int n FROM colaboradores')).rows[0].n,persons);
  });
  await unit(phase+': cache/GUC privado não autorizam; profile inativo/UUID desconhecido recusados',async()=>{
   await a.query('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(13)]);await actor(a,13);await denied(()=>save(op()),/PERMISSION_DENIED/);await owner();await a.query('UPDATE utilizadores SET ativo=true WHERE id=$1',[id(13)]);await actor(a,13);await denied(()=>save({...op(),colaborador_id:id(99999)}),/PERMISSION_DENIED/);await denied(()=>save(op(103)),/PERMISSION_DENIED/);assert.equal((await snap()).operations.length,0);
  });
  if(phase==='A')await unit('A: Gerência recusada tanto na API nova como no DML legado',async()=>{
   await actor(a,11);await denied(()=>save(op()),/PERMISSION_DENIED/);await denied(()=>a.query("INSERT INTO quadro_pessoal_alocacao(colaborador_id,obra_id,data,semana_inicio,periodo) VALUES($1,$2,'2026-10-05','2026-10-05','manha')",[id(30),id(100)]),/autorização/);assert.equal((await snap()).allocations.filter(x=>x.colaborador_id===id(30)).length,0);
  });
  if(phase==='B'){
   await unit('P1 corrigido: postcheck B recusa histórico ausente',async()=>{
    await a.query('DROP TRIGGER trg_quadro_pessoal_movimentos ON quadro_pessoal_alocacao');await assert.rejects(()=>a.query(postFinal),/POSTCHECK_FAILED/);
   });
   await unit('P1 corrigido: postcheck B recusa notifier no-op',async()=>{
    await a.query("CREATE OR REPLACE FUNCTION public.fn_quadro_notificar_controlado_v1(p_colaborador uuid,p_data date,p_origem uuid,p_destino uuid,p_alocacao uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS 'BEGIN RETURN; END'");await assert.rejects(()=>a.query(postFinal),/POSTCHECK_FAILED/);
   });
  }
 }
 await t.test('transição: preview feito em A confirma em B com a mesma versão sem alteração de dados',async()=>{
  await q(await read('../supabase/quadro_controlado_fase_b_rollback.sql'));await actor(a,13);const d={...op(),colaborador_id:id(31),request_id:id(9500)},p=await call(a,'alocar',d);await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await q(await read('../supabase/quadro_controlado_fase_b_forward_fix.sql'));const r=await call(a,'alocar',d,true,p.versao);assert.equal(r.committed,true);assert.equal((await entityAlerts(r.allocations.map(x=>x.id))).length,2);
 });
 await t.test('backup 2x falha sem sobrescrever original; dados preservados',async()=>{
  await q(await read('../supabase/quadro_controlado_fase_b_rollback.sql'));await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));const old=(await q('SELECT jsonb_agg(to_jsonb(x)) v FROM primeline_backup.quadro_fase_b_controlo_20261001 x')).rows[0].v;await assert.rejects(()=>q(awaitSql.backupB),/already exists/);await q('ROLLBACK');assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(x)) v FROM primeline_backup.quadro_fase_b_controlo_20261001 x')).rows[0].v,old);
 });
 await t.test('FINDING recuperação: rollback A/forward-fix A exige rotação manual do backup B',async()=>{
  const prior=(await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v;await q(await read('../supabase/quadro_controlado_fase_a_rollback.sql'));await q(await read('../supabase/quadro_controlado_fase_a_forward_fix.sql'));await q(await read('../supabase/quadro_controlado_fase_a_postcheck.sql'));assert.deepEqual((await q('SELECT jsonb_agg(to_jsonb(x) ORDER BY id) v FROM quadro_pessoal_alocacao x')).rows[0].v,prior);await q(await read('../supabase/quadro_controlado_marcar_frontend_validado.sql'));await assert.rejects(()=>q(awaitSql.phaseB),/backup pertence a outra/);await q('ROLLBACK');await assert.rejects(()=>q(awaitSql.backupB),/already exists/);await q('ROLLBACK');
 });
 } finally {for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});