import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';

// Só binários locais explícitos; o teste cria o próprio cluster descartável.
// Não aceita host, URL, password ou configuração de Supabase.
const enabled = process.env.VIATURAS_PG_BIN != null;
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const read = p => readFile(new URL(p,import.meta.url),'utf8');
const require = createRequire(import.meta.url);
const exe = name => join(process.env.VIATURAS_PG_BIN,name+(process.platform==='win32'?'.exe':''));
function run(name,args) {
 const r=spawnSync(exe(name),args,{encoding:'utf8',timeout:60000,windowsHide:true,stdio:name==='pg_ctl'?'ignore':'pipe'});
 assert.equal(r.status,0,`${name}: ${r.error?.message||''}\n${r.stdout}\n${r.stderr}`);return r.stdout;
}
async function freePort() {
 const s=createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));
 const port=s.address().port;await new Promise(r=>s.close(r));return port;
}
const rpc=(v,c,request,rev=0)=>`SELECT public.fn_alterar_responsavel_viatura(1,'${id(v)}',${c===null?'NULL':`'${id(c)}'`},${rev},'${id(request)}') AS result`;
const outcome=p=>p.then(value=>({value}),error=>({error}));

test('PostgreSQL 17.6 — cluster local descartável, ligações independentes',{
 skip:!enabled && 'Definir VIATURAS_PG_BIN; não substitui concorrência por PGlite.',timeout:180000
},async t=>{
 const {Client}=require(process.env.VIATURAS_PG_MODULE||'pg');
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const root=await mkdtemp(join(tmpdir(),'primeline-viaturas-pg176-'));
 const data=join(root,'data'),log=join(root,'postgres.log'),port=await freePort();
 console.log(`PostgreSQL 17.6 local: 127.0.0.1:${port}; cluster ${root}`);
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false;const clients=[];
 async function connect(actor=false) {
  const c=new Client({host:'127.0.0.1',port,user:'postgres',database:'postgres',password:'',ssl:false,connectionTimeoutMillis:5000});
  await c.connect();clients.push(c);
  if(actor)await c.query(`SELECT set_config('test.utilizador','${id(10)}',false); SET ROLE authenticated`);
  return c;
 }
 try{
  run('pg_ctl',['-D',data,'-l',log,'-o',`-h 127.0.0.1 -p ${port} -F`,'-w','start']);started=true;
  const admin=await connect();assert.equal((await admin.query('SHOW server_version_num')).rows[0].server_version_num,'170006');
  await admin.query(await read('./fixtures/viaturas-atribuicao-base.sql'));
  const audit=await read('../supabase/ativar_log_auditoria.sql');
  await admin.query(audit.slice(audit.indexOf('create or replace function'),audit.indexOf('\nrevoke all')));
  await admin.query("CREATE TRIGGER trg_auditoria_viaturas AFTER INSERT OR UPDATE OR DELETE ON viaturas FOR EACH ROW EXECUTE FUNCTION fn_registar_log_auditoria('id')");
  await admin.query(await read('../supabase/viaturas_atribuicao_controlada.sql'));
  await admin.query(`INSERT INTO empresas VALUES('${id(1)}');INSERT INTO utilizadores(id,empresa_id,funcao) VALUES('${id(10)}','${id(1)}','administrativo')`);
  const a=await connect(true),b=await connect(true);
  const pidA=(await a.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  const pidB=(await b.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  assert.notEqual(pidA,pidB);console.log(`Sessões independentes: ${pidA} / ${pidB}`);
  async function blocked(waiter,holder) {
   for(let n=0;n<150;n++){
    if((await admin.query('SELECT $2::int = ANY(pg_blocking_pids($1)) AS blocked',[waiter,holder])).rows[0].blocked)return;
    await delay(20);
   }
   assert.fail(`A sessão ${waiter} não esperou pelo lock da sessão ${holder}`);
  }
  async function fixture(n) {
   // Identidades diferentes em cada caso; não se apaga histórico para repor fixtures.
   await admin.query(`INSERT INTO colaboradores(id,empresa_id,nome) VALUES('${id(n+1)}','${id(1)}','A'),('${id(n+2)}','${id(1)}','B');
    INSERT INTO viaturas(id,empresa_id,marca_modelo,matricula) VALUES('${id(n)}','${id(1)}','Teste','TEST-${n}')`);
  }
  async function invariant() {
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM viaturas v JOIN colaboradores c ON c.id=v.colaborador_atribuido_id WHERE c.data_saida IS NOT NULL')).rows[0].n,0);
  }
  async function history(v) {return (await admin.query('SELECT * FROM viaturas_atribuicoes_historico WHERE viatura_id=$1',[id(v)])).rows;}
  await t.test('A: mesma revisão, apenas uma troca confirma; segunda recebe STALE_REVISION',async()=>{
   await fixture(100);await a.query('BEGIN');await a.query(rpc(100,101,1000));
   await b.query('BEGIN');const pending=outcome(b.query(rpc(100,102,1001)));
   await blocked(pidB,pidA);await a.query('COMMIT');const r=await pending;
   assert.equal(r.error?.code,'40001');assert.match(r.error.message,/STALE_REVISION/);await b.query('ROLLBACK');assert.equal((await history(100)).length,1);
  });
  await t.test('B: mesmo request/payload concorrente devolve replay; um histórico',async()=>{
   await fixture(200);await a.query('BEGIN');const first=(await a.query(rpc(200,201,2000))).rows[0].result;
   await b.query('BEGIN');const pending=outcome(b.query(rpc(200,201,2000)));
   await blocked(pidB,pidA);await a.query('COMMIT');const r=await pending;assert.equal(r.error,undefined);
   assert.deepEqual(r.value.rows[0].result,{...first,idempotent:true});await b.query('COMMIT');assert.equal((await history(200)).length,1);
  });
  await t.test('C: mesmo request/payload diferente recebe IDEMPOTENCY_CONFLICT',async()=>{
   await fixture(300);await a.query('BEGIN');await a.query(rpc(300,301,3000));
   await b.query('BEGIN');const pending=outcome(b.query(rpc(300,302,3000)));
   await blocked(pidB,pidA);await a.query('COMMIT');const r=await pending;
   assert.equal(r.error?.code,'22023');assert.match(r.error.message,/IDEMPOTENCY_CONFLICT/);await b.query('ROLLBACK');assert.equal((await history(300)).length,1);
  });
  await t.test('D1: atribuição confirma primeiro; saída espera e é recusada',async()=>{
   await fixture(400);await a.query('BEGIN');await a.query(rpc(400,401,4000));
   await b.query('BEGIN');const pending=outcome(b.query(`UPDATE colaboradores SET data_saida='2026-09-30' WHERE id='${id(401)}'`));
   await blocked(pidB,pidA);await a.query('COMMIT');const r=await pending;
   assert.equal(r.error?.code,'23514');assert.match(r.error.message,/possui 1 viatura/);await b.query('ROLLBACK');await invariant();
  });
  await t.test('D2: saída confirma primeiro; atribuição espera e é recusada',async()=>{
   await fixture(500);await b.query(`BEGIN; UPDATE colaboradores SET data_saida='2026-09-30' WHERE id='${id(501)}'`);
   await a.query('BEGIN');const pending=outcome(a.query(rpc(500,501,5000)));
   await blocked(pidA,pidB);await b.query('COMMIT');const r=await pending;
   assert.equal(r.error?.code,'22023');assert.match(r.error.message,/ativo/);await a.query('ROLLBACK');assert.equal((await history(500)).length,0);await invariant();
  });
  await t.test('segurança: UPDATE direto e GUC falsificado recusados; RPC e outro campo permitidos',async()=>{
   await fixture(600);
   for(const spoof of [false,true]){
    await a.query('BEGIN');if(spoof)await a.query("SELECT set_config('primeline.atribuicao_viatura_rpc','on',true)");
    await assert.rejects(()=>a.query(`UPDATE viaturas SET colaborador_atribuido_id='${id(601)}' WHERE id='${id(600)}'`),e=>e.code==='42501'&&/PROTECTED_ASSIGNMENT/.test(e.message));
    await a.query('ROLLBACK');
   }
   assert.equal((await a.query(rpc(600,601,6000))).rows[0].result.committed,true);
   await a.query(`UPDATE viaturas SET chaves_estado='OK' WHERE id='${id(600)}'`);
   assert.equal((await a.query(`SELECT chaves_estado FROM viaturas WHERE id='${id(600)}'`)).rows[0].chaves_estado,'OK');
  });
  await t.test('saída: conta todas as viaturas; outros campos livres; desatribuição permite saída',async()=>{
   await fixture(700);await a.query(rpc(700,701,7000));
   await admin.query(`INSERT INTO viaturas(id,empresa_id,marca_modelo,matricula) VALUES('${id(703)}','${id(1)}','Teste','TEST-703')`);
   await a.query(rpc(703,701,7001));
   await assert.rejects(()=>a.query(`UPDATE colaboradores SET data_saida='2026-09-30' WHERE id='${id(701)}'`),/possui 2 viatura/);
   await a.query(`UPDATE colaboradores SET nome='Nome corrigido' WHERE id='${id(701)}'`);
   await a.query(rpc(700,null,7002,1));await a.query(rpc(703,null,7003,1));
   await a.query(`UPDATE colaboradores SET data_saida='2026-09-30' WHERE id='${id(701)}'`);
   // Preenchida -> outra data não é a transição protegida.
   await a.query(`UPDATE colaboradores SET data_saida='2026-09-29' WHERE id='${id(701)}'`);await invariant();
  });
  await t.test('snapshot fixo recusado: REPEATABLE READ/SERIALIZABLE não contornam a invariável',async()=>{
   await fixture(800);
   for(const isolation of ['REPEATABLE READ','SERIALIZABLE']){
    await b.query(`BEGIN ISOLATION LEVEL ${isolation}; SELECT count(*) FROM viaturas`);
    await assert.rejects(()=>b.query(`UPDATE colaboradores SET data_saida='2026-09-30' WHERE id='${id(801)}'`),e=>e.code==='40001');await b.query('ROLLBACK');
    await b.query(`BEGIN ISOLATION LEVEL ${isolation}`);await assert.rejects(()=>b.query(rpc(800,801,8000)),e=>e.code==='40001');await b.query('ROLLBACK');
   }
   await invariant();
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));
  if(started)run('pg_ctl',['-D',data,'-m','fast','-w','stop']);
 }
});
