import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
// Exclusivamente PostgreSQL em memória. Nenhuma URL/ligação remota é aceite.
const { PGlite } = await import(process.env.QUADRO_PGLITE
  ? pathToFileURL(process.env.QUADRO_PGLITE).href
  : './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js');
const read = p => readFile(new URL(p, import.meta.url), 'utf8');
const migration = await read('../supabase/viaturas_atribuicao_controlada.sql');
const rollback = await read('../supabase/viaturas_atribuicao_controlada_rollback.sql');
const base = await read('./fixtures/viaturas-atribuicao-base.sql');
const audit = await read('../supabase/ativar_log_auditoria.sql');
const auditFunction = audit.slice(audit.indexOf('create or replace function'),audit.indexOf('\nrevoke all'));
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
let db;
const q = (s,a=[]) => db.query(s,a);
const rows = async(s,a) => (await q(s,a)).rows;
const actor = async(n=10) => {await db.exec('RESET ROLE');await q("SELECT set_config('test.utilizador',$1,false)",[n===null?'':id(n)]);await db.exec('SET ROLE authenticated');};
const rpc = async(n=21,rev=0,request=100,motivo=null,vehicle=30,version=1) =>
 (await rows('SELECT public.fn_alterar_responsavel_viatura($1,$2,$3,$4,$5,$6) AS result',
 [version,vehicle===null?null:id(vehicle),n===null?null:id(n),rev,request===null?null:id(request),motivo]))[0].result;
async function rejected(fn, pattern) {
 await db.exec('SAVEPOINT expected_error');
 try {await assert.rejects(fn,e=>pattern.test(e.message));}
 finally {await db.exec('ROLLBACK TO SAVEPOINT expected_error; RELEASE SAVEPOINT expected_error');}
}
async function snapshot() {
 await db.exec('RESET ROLE');
 const out={};for(const t of ['viaturas','alertas','viaturas_eventos','viaturas_sinistros','multas','viaturas_atribuicoes_historico','log_auditoria'])
  out[t]=await rows(`SELECT to_jsonb(t) AS row FROM public.${t} t ORDER BY id`);
 return out;
}
async function setup() {
 db=new PGlite();await db.exec(base);await db.exec(auditFunction);
 await db.exec("CREATE TRIGGER trg_auditoria_viaturas AFTER INSERT OR UPDATE OR DELETE ON public.viaturas FOR EACH ROW EXECUTE FUNCTION public.fn_registar_log_auditoria('id')");
 for(const n of [1,2])await q('INSERT INTO empresas VALUES($1)',[id(n)]);
 for(const [n,role] of [[10,'administrativo'],[11,'gerencia'],[12,'financeiro'],[13,'encarregado'],[14,'gestao_plataforma']])
  await q('INSERT INTO utilizadores(id,empresa_id,funcao,auth_user_id) VALUES($1,$2,$3,$1)',[id(n),id(1),role]);
 for(const [n,company,user,exit] of [[20,1,13,null],[21,1,11,null],[22,1,null,null],[23,2,null,null],[24,1,null,'2026-09-01']])
  await q('INSERT INTO colaboradores VALUES($1,$2,$3,$4,$5)',[id(n),id(company),'Pessoa '+n,exit,user&&id(user)]);
 for(const n of [30,31])await q(`INSERT INTO viaturas(id,empresa_id,marca_modelo,matricula,colaborador_atribuido_id,seguro_data,data_inspecao_proxima,data_proxima_revisao)
 VALUES($1,$2,'Teste',$3,$4,'2027-01-01','2027-02-01','2027-03-01')`,[id(n),id(1),'TEST-'+n,id(20)]);
 for(const [n,type,status,v] of [[40,'seguro_viatura','pendente',30],[41,'inspecao_viatura','pendente',30],[42,'seguro_viatura','resolvido',30],[43,'inspecao_viatura','resolvido',30],[44,'outro','pendente',30],[45,'seguro_viatura','pendente',31]])
  await q(`INSERT INTO alertas(id,entidade_tipo,entidade_id,tipo,estado,destinatario_role,destinatario_colaborador_id,destinatario_utilizador_id,resolvido_em)
 VALUES($1,'viaturas',$2,$3,$4,'administrativo',$5,$6,CASE WHEN $4='resolvido' THEN '2026-09-01'::timestamptz END)`,[id(n),id(v),type,status,id(20),id(13)]);
 for(const t of ['viaturas_eventos','viaturas_sinistros','multas'])await q(`INSERT INTO ${t} VALUES($1,$2,'Legado preservado')`,[id(50),id(30)]);
}
test('Atribuição controlada — PostgreSQL local isolado',async t=>{
 await setup();
 try {
  const original=await rows('SELECT to_jsonb(v) AS row FROM viaturas v ORDER BY id');
  await db.exec(migration);
  const run=(name,fn)=>t.test(name,async()=>{await db.exec('BEGIN');try{await actor();await fn();}finally{await db.exec('ROLLBACK; RESET ROLE');}});
  await run('instalação preserva atribuições/dados; revisão zero; histórico vazio',async()=>{
   assert.deepEqual(await rows("SELECT to_jsonb(v)-'atribuicao_revisao' AS row FROM viaturas v ORDER BY id"),original);
   assert.deepEqual(await rows('SELECT DISTINCT atribuicao_revisao FROM viaturas'),[{atribuicao_revisao:0}]);
   assert.equal((await rows('SELECT * FROM viaturas_atribuicoes_historico')).length,0);
  });
  await run('ativo da mesma empresa: resposta, histórico, revisão e auditoria',async()=>{
   const r=await rpc();assert.equal(r.committed,true);assert.equal(r.idempotent,false);assert.equal(r.version,1);
   assert.equal(r.viatura_id,id(30));assert.equal(r.colaborador_anterior_id,id(20));assert.equal(r.colaborador_novo_id,id(21));assert.equal(r.atribuicao_revisao,1);
   const [h]=await rows('SELECT * FROM viaturas_atribuicoes_historico');assert.equal(h.id,r.historico_id);assert.equal(h.alterado_por,id(10));assert.ok(h.alterado_em);assert.equal(h.request_id,id(100));assert.equal(h.revisao_anterior,0);assert.equal(h.revisao_nova,1);
   await db.exec('RESET ROLE');assert.equal((await rows("SELECT * FROM log_auditoria WHERE tabela_afetada='public.viaturas_atribuicoes_historico' AND campo='__INSERT__'")).length,1);
  });
  for(const [name,n] of [['outra empresa',23],['inativo',24],['inexistente',999]])await run(name+' recusado sem efeitos',async()=>{
   const before=await snapshot();await actor();await rejected(()=>rpc(n),/VALIDATION_FAILED/);assert.deepEqual(await snapshot(),before);
  });
  await run('ativo sem login permitido; alerta mantém colaborador e utilizador NULL',async()=>{
   await rpc(22);await db.exec('RESET ROLE');const a=await rows("SELECT * FROM alertas WHERE id=$1",[id(40)]);
   assert.equal(a[0].destinatario_colaborador_id,id(22));assert.equal(a[0].destinatario_utilizador_id,null);
  });
  await run('NULL permitido; limpa vínculos individuais e mantém Administrativo',async()=>{
   const r=await rpc(null);assert.equal(r.colaborador_novo_id,null);
   await db.exec('RESET ROLE');for(const a of await rows("SELECT * FROM alertas WHERE id IN ($1,$2)",[id(40),id(41)])){
    assert.equal(a.destinatario_colaborador_id,null);assert.equal(a.destinatario_utilizador_id,null);assert.equal(a.destinatario_role,'administrativo');assert.equal(a.estado,'pendente');
   }
  });
  await run('revisão antiga e sequência A → B → A detetadas',async()=>{
   await rpc(21,0,100);await rejected(()=>rpc(22,0,101),/STALE_REVISION/);
   await rpc(20,1,102);await rejected(()=>rpc(22,0,103),/STALE_REVISION/);
   assert.equal((await rows('SELECT atribuicao_revisao FROM viaturas WHERE id=$1',[id(30)]))[0].atribuicao_revisao,2);
  });
  await run('replay idempotente devolve resultado original mesmo após outra alteração',async()=>{
   const first=await rpc(21,0,100,' Entrega ');await rpc(22,1,101);
   const before=await snapshot();await actor();assert.deepEqual(await rpc(21,0,100,'Entrega'),{...first,idempotent:true});assert.deepEqual(await snapshot(),before);
  });
  await run('request_id diferente conteúdo/autor recusado',async()=>{
   await rpc(21,0,100,'Entrega');
   for(const args of [[22,0,100,'Entrega'],[21,1,100,'Entrega'],[21,0,100,'Outro'],[21,0,100,'Entrega',31]])
    await rejected(()=>rpc(...args),/IDEMPOTENCY_CONFLICT/);
   await actor(11);await rejected(()=>rpc(21,0,100,'Entrega'),/IDEMPOTENCY_CONFLICT/);
  });
  await run('PATCH direto e revisão direta bloqueados, mesmo com GUC falsificado',async()=>{
   for(const setting of ['', 'on']){
    await q("SELECT set_config('primeline.atribuicao_viatura_rpc',$1,true)",[setting]);
    await rejected(()=>q('UPDATE viaturas SET colaborador_atribuido_id=$1 WHERE id=$2',[id(21),id(30)]),/PROTECTED_ASSIGNMENT/);
    await rejected(()=>q('UPDATE viaturas SET atribuicao_revisao=1 WHERE id=$1',[id(30)]),/PROTECTED_ASSIGNMENT/);
   }
  });
  await run('outro campo continua editável; contexto RPC não fica aberto',async()=>{
   await rpc();await q("UPDATE viaturas SET chaves_estado='OK' WHERE id=$1",[id(30)]);
   assert.equal((await rows('SELECT chaves_estado FROM viaturas WHERE id=$1',[id(30)]))[0].chaves_estado,'OK');
   await rejected(()=>q('UPDATE viaturas SET colaborador_atribuido_id=NULL WHERE id=$1',[id(30)]),/PROTECTED_ASSIGNMENT/);
  });
  await run('retarget apenas pendentes; resolvidos, outras viaturas/tipos e restante legado intactos',async()=>{
   const before=await snapshot();await actor();await rpc();const after=await snapshot();
   for(const n of [40,41]){const a=after.alertas.find(x=>x.row.id===id(n)).row;assert.equal(a.destinatario_colaborador_id,id(21));assert.equal(a.destinatario_utilizador_id,id(11));assert.equal(a.estado,'pendente');}
   assert.deepEqual(after.alertas.filter(x=>![id(40),id(41)].includes(x.row.id)),before.alertas.filter(x=>![id(40),id(41)].includes(x.row.id)));
   for(const table of ['viaturas_eventos','viaturas_sinistros','multas'])assert.deepEqual(after[table],before[table]);
   const strip=v=>{const {colaborador_atribuido_id,atribuicao_revisao,...rest}=v.row;return rest};assert.deepEqual(after.viaturas.map(strip),before.viaturas.map(strip));
  });
  await run('histórico protegido; RLS; grants e autorizações',async()=>{
   await rpc();
   await rejected(()=>q("UPDATE viaturas_atribuicoes_historico SET motivo='X'"),/permission denied/);
   await rejected(()=>q('DELETE FROM viaturas_atribuicoes_historico'),/permission denied/);
   await rejected(()=>q('INSERT INTO viaturas_atribuicoes_historico DEFAULT VALUES'),/permission denied/);
   await actor(12);assert.deepEqual(await rows('SELECT * FROM viaturas_atribuicoes_historico'),[]);await rejected(()=>rpc(22,1,101),/FORBIDDEN/);
   await actor(11);assert.equal((await rows('SELECT * FROM viaturas_atribuicoes_historico')).length,1);await rpc(22,1,101);
   await actor(14);await rpc(null,2,102);
   await actor(null);await rejected(()=>rpc(20,3,103),/FORBIDDEN/);
   await db.exec('RESET ROLE; SET ROLE anon');await rejected(()=>rpc(20,3,103),/permission denied/);
  });
  await run('proteção do histórico também recusa UPDATE/DELETE pelo proprietário',async()=>{
   await rpc();await db.exec('RESET ROLE');
   await rejected(()=>q("UPDATE viaturas_atribuicoes_historico SET motivo='X'"),/PROTECTED_HISTORY/);
   await rejected(()=>q('DELETE FROM viaturas_atribuicoes_historico'),/PROTECTED_HISTORY/);
   await rejected(()=>q(`INSERT INTO viaturas_atribuicoes_historico(viatura_id,revisao_anterior,revisao_nova,alterado_por,request_id,colaborador_novo_id) VALUES($1,1,2,$2,$3,$4)`,[id(30),id(10),id(105),id(21)]),/PROTECTED_HISTORY/);
  });
  await run('constraints e FKs do histórico são efetivas',async()=>{
   await rpc();await db.exec('RESET ROLE');await q("SELECT set_config('primeline.atribuicao_viatura_rpc','on',true)");
   const insert=(args)=>q(`INSERT INTO viaturas_atribuicoes_historico(viatura_id,colaborador_anterior_id,colaborador_novo_id,revisao_anterior,revisao_nova,alterado_por,request_id) VALUES($1,$2,$3,$4,$5,$6,$7)`,args);
   await rejected(()=>insert([id(30),id(21),id(22),1,2,id(10),id(100)]),/unique constraint/);
   await rejected(()=>insert([id(30),id(21),id(22),0,1,id(10),id(101)]),/unique constraint/);
   await rejected(()=>insert([id(30),id(21),id(22),1,4,id(10),id(101)]),/check constraint/);
   for(const index of [0,1,2,5]){
    const args=[id(30),id(21),id(22),1,2,id(10),id(101)];args[index]=id(999);
    await rejected(()=>insert(args),/foreign key constraint/);
   }
  });
  await run('falha ao inserir histórico reverte viatura, alertas e auditoria',async()=>{
   await db.exec("RESET ROLE; CREATE FUNCTION public.test_history_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'TEST_FAILURE'; END $$; CREATE TRIGGER zz_test_failure BEFORE INSERT ON viaturas_atribuicoes_historico FOR EACH ROW EXECUTE FUNCTION test_history_fail()");
   const before=await snapshot();await actor();await rejected(()=>rpc(),/TEST_FAILURE/);assert.deepEqual(await snapshot(),before);
  });
  await run('saída recusada com viaturas; outros campos livres; NULL inalterado permitido',async()=>{
   await rejected(()=>q("UPDATE colaboradores SET data_saida='2026-09-30' WHERE id=$1",[id(20)]),/possui 2 viatura/);
   await q("UPDATE colaboradores SET nome='Outro nome',data_saida=NULL WHERE id=$1",[id(20)]);
   await q("UPDATE colaboradores SET data_saida='2026-09-30' WHERE id=$1",[id(22)]);
   await q("UPDATE colaboradores SET data_saida='2026-09-29' WHERE id=$1",[id(22)]);
  });
  await run('desatribuir todas as viaturas permite saída sem transferência silenciosa',async()=>{
   await rpc(null,0,100,null,30);await rpc(null,0,101,null,31);
   await q("UPDATE colaboradores SET data_saida='2026-09-30' WHERE id=$1",[id(20)]);
   assert.equal((await rows('SELECT * FROM viaturas_atribuicoes_historico')).length,2);
  });
  await run('validação de versão, parâmetros e alteração sem efeito',async()=>{
   for(const args of [[21,0,100,null,30,2],[21,null,100],[21,-1,100],[21,0,null],[21,0,100,null,null],[21,0,100,null,999],[20,0,100]])
    await rejected(()=>rpc(...args),/VALIDATION_FAILED/);
  });
  await run('utilizador desativado não autorizado',async()=>{
   await db.exec('RESET ROLE');await q('UPDATE utilizadores SET ativo=false WHERE id=$1',[id(10)]);await actor();await rejected(()=>rpc(),/FORBIDDEN/);
  });
  // Rollback após uso deve recusar, sem apagar qualquer histórico.
  await actor();await rpc();await db.exec('RESET ROLE');
  await t.test('rollback recusa histórico utilizado',async()=>{
   await assert.rejects(()=>db.exec(rollback),/ROLLBACK_BLOCKED/);await db.exec('ROLLBACK');
   assert.equal((await rows('SELECT * FROM viaturas_atribuicoes_historico')).length,1);
  });
  await db.close();await setup();await db.exec(migration);
  await t.test('rollback sem uso restaura schema, dados e trigger legado',async()=>{
   await db.exec(rollback);
   assert.equal((await rows("SELECT count(*)::int AS n FROM information_schema.columns WHERE table_name='viaturas' AND column_name='atribuicao_revisao'"))[0].n,0);
   assert.equal((await rows("SELECT to_regclass('public.viaturas_atribuicoes_historico') AS t"))[0].t,null);
   assert.equal((await rows("SELECT count(*)::int AS n FROM pg_trigger WHERE tgname='trg_atualizar_destinatario_alerta_viatura'"))[0].n,1);
   assert.equal((await rows("SELECT count(*)::int AS n FROM pg_trigger WHERE tgname='trg_impedir_saida_colaborador_com_viaturas'"))[0].n,0);
   await actor();await q('UPDATE viaturas SET colaborador_atribuido_id=$1 WHERE id=$2',[id(21),id(30)]);
  });
 }finally{await db.close();}
});
