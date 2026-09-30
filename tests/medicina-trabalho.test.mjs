import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
const require=createRequire(import.meta.url),bin=process.env.MEDICINA_PG_BIN,deps=process.env.MEDICINA_TEST_DEPS;
const read=p=>readFile(new URL(p,import.meta.url),'utf8');
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const migration=await read('../supabase/medicina_trabalho_controlada.sql'),rollback=await read('../supabase/medicina_trabalho_controlada_rollback.sql');
const defs=JSON.parse(await read('./fixtures/medicina-funcoes-instaladas.json'));
const prior=defs.filter(d=>['fn_verificar_alertas_vencimento','fn_verificar_primeiras_consultas_medicina','fn_atualizar_colaborador_ciclo_vida'].includes(d.proname));
function run(name,args){const r=spawnSync(join(bin,name+(process.platform==='win32'?'.exe':'')),args,{encoding:'utf8',timeout:60000,windowsHide:true,stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(r.status,0,name+': '+(r.error?.message||r.stderr));return r.stdout;}
const outcome=p=>p.then(value=>({value}),error=>({error}));
test('isolamento SQL: ramos não médicos intactos e rollback completo',()=>{
 const text=migration.replaceAll('$function$;','$function$');
 const back=rollback.replaceAll('$function$;','$function$');
 const old=defs.find(d=>d.proname==='fn_verificar_alertas_vencimento').definition;
 assert.ok(text.includes(old.slice(0,old.indexOf('  -- Medicina do trabalho.'))));
 assert.ok(text.includes(old.slice(old.indexOf('  -- Inspeções das viaturas.'))));
 for(const d of prior)assert.ok(back.includes(d.definition));
 assert.doesNotMatch(migration,/ALTER TABLE public.(epis|colaboradores_contratos)/);
 assert.doesNotMatch(migration,/CREATE OR REPLACE FUNCTION public.fn_rh_guardar/);
 assert.doesNotMatch(migration,/CREATE OR REPLACE FUNCTION public.fn_executar_rotinas_diarias/);
});
test('PostgreSQL 17.6: testes locais e duas ligações independentes',{timeout:180000,skip:!bin||!deps?'Definir MEDICINA_PG_BIN e MEDICINA_TEST_DEPS':false},async t=>{
 assert.match(run('postgres',['--version']),/PostgreSQL\) 17\.6\b/);
 const {Client}=require(join(deps,'pg'));
 const folder=await mkdtemp(join(tmpdir(),'primeline-medicina-pg176-')),data=join(folder,'data');
 const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));const port=server.address().port;await new Promise(r=>server.close(r));
 run('initdb',['-D',data,'-U','postgres','--auth-local=trust','--auth-host=trust','--encoding=UTF8','--no-locale']);
 let started=false;const clients=[];
 async function connect(db='postgres'){const c=new Client({host:'127.0.0.1',port,user:'postgres',database:db,password:'',ssl:false});await c.connect();clients.push(c);return c;}
 try{
 run('pg_ctl',['-D',data,'-l',join(folder,'postgres.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);started=true;
 const admin=await connect(),a=await connect(),b=await connect(),q=(s,p=[])=>admin.query(s,p);
 await q(await read('./fixtures/medicina-base.sql'));for(const d of defs)await q(d.definition);
 for(const n of [1,2])await q('INSERT INTO empresas VALUES($1)',[id(n)]);
 for(const [n,r,c] of [[10,'administrativo',1],[11,'gerencia',1],[12,'gestao_plataforma',1],[13,'encarregado',1],[14,'financeiro',1],[15,'administrativo',2]])await q('INSERT INTO utilizadores VALUES($1,$2,$3,true)',[id(n),id(c),r]);
 for(let n=20;n<60;n++)await q('INSERT INTO colaboradores VALUES($1,$2,$3,current_date-90,NULL)',[id(n),id(n===59?2:1),n===20?'Visível ao Encarregado':'Pessoa sintética '+n]);
 for(let n=20;n<54;n++)await q('INSERT INTO medicina_trabalho(id,colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta) VALUES($1,$2,current_date+$3::integer,$4,current_date+365)',[id(100+n),id(n),n===53?10:-30,'Texto antigo livre']);
 await q("INSERT INTO parametros_operacionais VALUES('antecedencia_alerta_medicina','30')");
 const old=(await q('SELECT to_jsonb(m) row FROM medicina_trabalho m ORDER BY id')).rows;await q(await read('../supabase/medicina_trabalho_precheck.sql'));await q(await read('../supabase/medicina_trabalho_backup.sql'));await q(migration);await q(await read('../supabase/medicina_trabalho_postcheck.sql'));
 const actor=async(c,n=10)=>{await c.query('RESET ROLE');await c.query("SELECT set_config('test.actor',$1,false)",[id(n)]);await c.query('SET ROLE authenticated');};
 const reg=(c,p=54,r=1000,d=-1,result='Aptidão ocupacional')=>c.query('SELECT fn_medicina_registar_consulta(1,$1,current_date+$2::integer,$3,current_date+365,$4) result',[id(p),d,result,id(r)]);
 const person=(c,p=54)=>c.query('SELECT fn_medicina_consultar_colaborador(1,$1) result',[id(p)]);
 const corr=(c,consult,rev,req,motive='Correção explícita',result='Corrigido')=>c.query('SELECT fn_medicina_corrigir_consulta(1,$1,current_date-1,$2,current_date+365,$3,$4,$5) result',[consult,result,rev,id(req),motive]);
 const reject=async(c,fn,pattern)=>{await c.query('SAVEPOINT expected');try{await assert.rejects(fn,e=>pattern.test(e.message));}finally{await c.query('ROLLBACK TO expected; RELEASE expected');}};
 const unit=(name,fn)=>t.test(name,async()=>{await a.query('BEGIN');await actor(a);try{await fn();}finally{await a.query('ROLLBACK');await a.query('RESET ROLE');}});
 await unit('instalação preserva 34 linhas; autoria/request antigos NULL e revisão zero',async()=>{
 assert.deepEqual((await q("SELECT to_jsonb(m)-ARRAY['registado_por','request_id','revisao','anulado_em','anulado_por'] row FROM medicina_trabalho m ORDER BY id")).rows,old);
 assert.equal((await q('SELECT count(*)::int n FROM medicina_operacoes')).rows[0].n,0);
 assert.equal((await q('SELECT count(*)::int n FROM medicina_trabalho WHERE registado_por IS NOT NULL OR request_id IS NOT NULL OR revisao<>0')).rows[0].n,0);
 });
 await unit('nova consulta cria linha; replay e conflito de idempotência',async()=>{
 const first=(await reg(a)).rows[0].result;assert.equal(first.committed,true);assert.equal(first.consulta.registado_por,id(10));
 assert.deepEqual((await reg(a)).rows[0].result,{...first,idempotent:true});
 await reject(a,()=>reg(a,54,1000,-1,'Outro'),/IDEMPOTENCY_CONFLICT/);
 assert.equal((await a.query('SELECT count(*)::int n FROM medicina_operacoes')).rows[0].n,1);
 });
 await unit('correção exige motivo, before/after, autor, revisão e replay',async()=>{
 const c=(await reg(a)).rows[0].result.consulta.id;await reject(a,()=>corr(a,c,0,1001,''),/motivo obrigatório/);
 const changed=(await corr(a,c,0,1001)).rows[0].result;assert.equal(changed.consulta.revisao,1);
 assert.equal((await corr(a,c,0,1001)).rows[0].result.idempotent,true);await reject(a,()=>corr(a,c,0,1002),/STALE_REVISION/);
 const h=(await a.query("SELECT * FROM medicina_operacoes WHERE operacao='corrigir'")).rows[0];
 assert.equal(h.antes.resultado,'Aptidão ocupacional');assert.equal(h.depois.resultado,'Corrigido');assert.equal(h.autor_id,id(10));assert.ok(h.criado_em);assert.equal(h.motivo,'Correção explícita');
 });
 await unit('anulação preserva linha e histórico',async()=>{
 const c=(await reg(a)).rows[0].result.consulta.id;await a.query('SELECT fn_medicina_anular_consulta(1,$1,0,$2,$3)',[c,id(1001),'Lançamento incorreto']);
 const h=(await person(a)).rows[0].result;assert.equal(h.atual,null);assert.equal(h.consultas.length,1);assert.equal(h.historico.length,2);
 await reject(a,()=>corr(a,c,1,1002),/consulta anulada/);
 });
 await unit('escrita direta, GUC falso e helpers internos bloqueados',async()=>{
 await a.query("SELECT set_config('primeline.medicina_rpc','on',true)");
 for(const [sql,p] of [
 ['UPDATE medicina_trabalho SET resultado=$1 WHERE id=$2',['X',id(120)]],
 ['DELETE FROM medicina_trabalho WHERE id=$1',[id(120)]],
 ['INSERT INTO medicina_trabalho(colaborador_id,data_ultima_consulta) VALUES($1,current_date)',[id(54)]],
 ['SELECT fn_medicina_reconciliar_alertas($1)',[id(54)]]])await reject(a,()=>a.query(sql,p),/permission denied|PROTECTED/);
 });
 await unit('datas futuras/invertidas recusadas; resultado continua livre',async()=>{
 await reject(a,()=>reg(a,54,1000,1),/efetivamente realizada/);
 await reject(a,()=>a.query('SELECT fn_medicina_registar_consulta(1,$1,current_date,$2,current_date-1,$3)',[id(54),'Livre',id(1001)]),/medicina_datas_coerentes/);
 assert.equal((await reg(a,54,1002,-1,'Livre')).rows[0].result.consulta.resultado,'Livre');
 });
 await unit('consulta corrente determinística; antiga futura não conta',async()=>{
 assert.equal((await person(a,53)).rows[0].result.atual,null);
 await reg(a,54,1000,-20);await reg(a,54,1001,-1);await reg(a,54,1002,-10);await reg(a,54,1003,-1);
 const h=(await person(a)).rows[0].result;assert.equal(h.consultas.length,4);
 const expected=(await a.query('SELECT id FROM medicina_trabalho WHERE colaborador_id=$1 ORDER BY data_ultima_consulta DESC,criado_em DESC,id DESC LIMIT 1',[id(54)])).rows[0].id;
 assert.equal(h.atual.id,expected);
 });
 await unit('alerta pendente substituído; resolvido preservado byte/conteúdo',async()=>{
 await a.query('RESET ROLE');
 await a.query("INSERT INTO alertas(empresa_id,tipo,entidade_tipo,entidade_id,titulo,data_evento_referencia,antecedencia_dias,data_gatilho,estado,resolvido_em) VALUES($1,'consulta_medicina','medicina_trabalho',$2,'Antigo',current_date-7,30,current_date-37,'resolvido',now()),($1,'consulta_medicina','medicina_trabalho',$2,'Pendente',current_date-5,30,current_date-35,'pendente',NULL)",[id(1),id(120)]);
 const done=(await a.query("SELECT to_jsonb(a) row FROM alertas a WHERE estado='resolvido'")).rows[0];
 await actor(a);await reg(a,20,1000);await a.query('RESET ROLE');
 assert.equal((await a.query("SELECT count(*)::int n FROM alertas WHERE entidade_id=$1 AND estado='pendente'",[id(120)])).rows[0].n,0);
 assert.deepEqual((await a.query('SELECT to_jsonb(a) row FROM alertas a WHERE id=$1',[done.row.id])).rows[0],done);
 assert.equal((await a.query('SELECT count(*)::int n FROM medicina_alertas_historico WHERE colaborador_id=$1',[id(20)])).rows[0].n,1);
 });
 await unit('primeira consulta satisfeita apenas após realizada válida',async()=>{
 await a.query('RESET ROLE');await a.query('SELECT fn_verificar_primeiras_consultas_medicina()');
 assert.equal((await a.query("SELECT count(*)::int n FROM alertas WHERE tipo='primeira_consulta_medicina' AND entidade_id=$1 AND estado='pendente'",[id(53)])).rows[0].n,1);
 await actor(a);await reg(a,53,1000);await a.query('RESET ROLE');
 assert.equal((await a.query("SELECT count(*)::int n FROM alertas WHERE tipo='primeira_consulta_medicina' AND entidade_id=$1 AND estado='pendente'",[id(53)])).rows[0].n,0);
 });
 await unit('Administrativo/Gerência/Gestão escrevem; outra empresa e Financeiro recusados',async()=>{
 for(const n of [10,11,12]){await actor(a,n);assert.equal((await reg(a,54,1000+n)).rows[0].result.committed,true);}
 await actor(a,14);await reject(a,()=>reg(a),/PERMISSION_DENIED/);
 await actor(a,15);await reject(a,()=>person(a),/PERMISSION_DENIED/);await reject(a,()=>reg(a),/PERMISSION_DENIED/);
 assert.equal((await a.query('SELECT id FROM medicina_trabalho')).rows.length,0);
 });
 await unit('Encarregado apenas pessoa da obra e leitura limitada',async()=>{
 await actor(a,13);const r=(await person(a,20)).rows[0].result;assert.equal(r.can_write,false);assert.ok(r.atual);assert.equal(r.historico,undefined);assert.equal(r.atual.registado_por,undefined);
 await reject(a,()=>person(a,21),/PERMISSION_DENIED/);await reject(a,()=>reg(a,20),/PERMISSION_DENIED/);
 assert.equal((await a.query('SELECT id FROM medicina_trabalho')).rows.length,1);
 });
 await unit('admissão antiga funciona, com autoria e auditoria, sem sobrescrita',async()=>{
 await a.query('SELECT test_admissao($1,current_date)',[id(54)]);const h=(await person(a)).rows[0].result;
 assert.equal(h.consultas.length,1);assert.equal(h.atual.registado_por,id(10));assert.equal(h.historico.length,1);
 await reject(a,()=>a.query('SELECT test_admissao($1,current_date)',[id(54)]),/fora do fluxo/);
 });
 await unit('reconciliação diária só alerta consulta corrente e mantém resolvidos',async()=>{
 await a.query('SELECT fn_medicina_registar_consulta(1,$1,current_date-5,$2,current_date+10,$3)',[id(54),'A',id(1000)]);
 await a.query('SELECT fn_medicina_registar_consulta(1,$1,current_date-1,$2,current_date+20,$3)',[id(54),'B',id(1001)]);
 await a.query('RESET ROLE');await a.query('SELECT fn_executar_rotinas_diarias()');
 const r=(await a.query("SELECT a.* FROM alertas a JOIN medicina_trabalho m ON m.id=a.entidade_id WHERE m.colaborador_id=$1 AND a.estado='pendente' AND a.tipo='consulta_medicina'",[id(54)])).rows;
 assert.equal(r.length,1);await actor(a);assert.equal(r[0].entidade_id,(await person(a)).rows[0].result.atual.id);await a.query('RESET ROLE');
 await a.query('SELECT fn_executar_rotinas_diarias()');assert.equal((await a.query("SELECT count(*)::int n FROM alertas WHERE tipo='consulta_medicina' AND estado='pendente' AND entidade_id=$1",[r[0].entidade_id])).rows[0].n,1);
 });
 await unit('anulação gera primeira consulta pendente sem reabrir resolvido antigo',async()=>{
 await a.query('RESET ROLE');await a.query('SELECT fn_verificar_primeiras_consultas_medicina()');await actor(a);
 const c=(await reg(a)).rows[0].result.consulta.id;
 await a.query('SELECT fn_medicina_anular_consulta(1,$1,0,$2,$3)',[c,id(1001),'Anulação']);
 await a.query('RESET ROLE');const r=(await a.query("SELECT estado FROM alertas WHERE tipo='primeira_consulta_medicina' AND entidade_id=$1 ORDER BY estado",[id(54)])).rows;
 assert.deepEqual(r,[{estado:'pendente'},{estado:'resolvido'}]);
 });
 await unit('triggers rejeitam GUC falso mesmo com GRANT/policy temporários',async()=>{
 await q('GRANT UPDATE,DELETE ON medicina_trabalho TO authenticated');
 await q('CREATE POLICY test_write ON medicina_trabalho FOR ALL TO authenticated USING(true) WITH CHECK(true)');
 try{await a.query("SELECT set_config('primeline.medicina_rpc','on',true)");
 await reject(a,()=>a.query('UPDATE medicina_trabalho SET resultado=$1 WHERE id=$2',['X',id(120)]),/PROTECTED_MEDICINE/);
 await reject(a,()=>a.query('DELETE FROM medicina_trabalho WHERE id=$1',[id(120)]),/PROTECTED_HISTORY/);
 }finally{await q('DROP POLICY test_write ON medicina_trabalho');await q('REVOKE UPDATE,DELETE ON medicina_trabalho FROM authenticated');}
 });
 await unit('anulação de linha futura antiga permitida, sem escolher consulta futura',async()=>{
 await a.query('SELECT fn_medicina_anular_consulta(1,$1,0,$2,$3)',[id(153),id(1000),'Data futura antiga']);
 assert.equal((await person(a,53)).rows[0].result.atual,null);
 });
 await unit('histórico não editável/apagável, inclusive pelo proprietário',async()=>{
 const h=(await reg(a)).rows[0].result.historico_id;
 await reject(a,()=>a.query('UPDATE medicina_operacoes SET motivo=$1 WHERE id=$2',['X',h]),/permission denied/);
 await a.query('RESET ROLE');
 await reject(a,()=>a.query('UPDATE medicina_operacoes SET motivo=$1 WHERE id=$2',['X',h]),/PROTECTED_HISTORY/);
 await reject(a,()=>a.query('DELETE FROM medicina_operacoes WHERE id=$1',[h]),/PROTECTED_HISTORY/);
 });
 await unit('cadastro RH real mantém INSERT inicial após a nova proteção',async()=>{
 await a.query('RESET ROLE');
 await a.query("ALTER TABLE colaboradores ADD COLUMN funcao text,ADD COLUMN nivel text,ADD COLUMN valor_hora numeric,ADD COLUMN nif text,ADD COLUMN email text,ADD COLUMN contacto text,ADD COLUMN morada text,ADD COLUMN data_nascimento date,ADD COLUMN codigo_rh text,ADD COLUMN observacoes text,ADD COLUMN seguranca_social_ok boolean,ADD COLUMN seguro_ok boolean,ADD COLUMN registo_trabalhador_ok boolean");
 await a.query("ALTER TABLE colaboradores_contratos ADD COLUMN data_inicio date,ADD COLUMN criado_em timestamptz DEFAULT now()");
 await a.query("CREATE TABLE colaboradores_rh_privado(colaborador_id uuid PRIMARY KEY,niss text);CREATE TABLE rh_cadastro_auditoria(id uuid DEFAULT gen_random_uuid(),empresa_id uuid,colaborador_id uuid,utilizador_id uuid,origem text,antes jsonb,depois jsonb)");
 await a.query('CREATE TABLE obras(id uuid PRIMARY KEY,empresa_id uuid,situacao text)');
 const rh=await read('../supabase/rh_cadastro_importacao.sql');
 for(const name of ['fn_rh_empresa','fn_rh_consultar','fn_rh_guardar']){
 const from=rh.indexOf('create or replace function public.'+name+'(');
 const to=rh.indexOf('$$;',from)+3;await a.query(rh.slice(from,to));
 }
 // Apenas a criação/alocação auxiliar é sintética; o corpo RH instalado é integral.
 await a.query("CREATE FUNCTION fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE c colaboradores; BEGIN INSERT INTO colaboradores(id,empresa_id,nome,funcao,data_admissao) VALUES(gen_random_uuid(),(SELECT empresa_id FROM utilizadores WHERE id=fn_utilizador_atual_id()),$1,$2,$3) RETURNING * INTO c;RETURN jsonb_build_object('colaborador',to_jsonb(c));END $$");
 await actor(a);
 const result=(await a.query("SELECT fn_rh_guardar_interno($1,false,false) result",[JSON.stringify({campos:{nome:'Admissão sintética',funcao:'Pedreiro',data_admissao:'2026-09-01'},alocacao_tipo:'escritorio',medicina_data:'2026-09-02'})])).rows[0].result;
 assert.equal(result.alterado,true);const r=(await a.query('SELECT fn_medicina_consultar_colaborador(1,$1) result',[result.id])).rows[0].result;
 assert.equal(r.consultas.length,1);assert.equal(r.atual.registado_por,id(10));assert.equal(r.historico.length,1);
 assert.equal(r.atual.resultado,'Consulta inicial registada na admissão');
 await a.query('RESET ROLE');
 assert.equal((await a.query('SELECT count(*)::int n FROM epis')).rows[0].n,0);
 assert.equal((await a.query('SELECT count(*)::int n FROM colaboradores_contratos')).rows[0].n,0);
 });
 const pidA=(await a.query('SELECT pg_backend_pid() pid')).rows[0].pid,pidB=(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;assert.notEqual(pidA,pidB);
 async function waitLock(){for(let n=0;n<150;n++){if((await q('SELECT $2::int=ANY(pg_blocking_pids($1)) blocked',[pidB,pidA])).rows[0].blocked)return;await delay(20);}assert.fail('Sem lock real entre sessões');}
 await t.test('concorrência: mesmo request/payload cria uma consulta',async()=>{
 await a.query('BEGIN');await actor(a);const first=(await reg(a,55,2000)).rows[0].result;
 await b.query('BEGIN');await actor(b);const pending=outcome(reg(b,55,2000));await waitLock();await a.query('COMMIT');
 const r=await pending;assert.equal(r.error,undefined);assert.deepEqual(r.value.rows[0].result,{...first,idempotent:true});await b.query('COMMIT');
 assert.equal((await q('SELECT count(*)::int n FROM medicina_trabalho WHERE colaborador_id=$1',[id(55)])).rows[0].n,1);
 });
 await t.test('concorrência: mesmo request com payload diferente recusado',async()=>{
 await a.query('BEGIN');await actor(a);await reg(a,56,2100);await b.query('BEGIN');await actor(b);
 const pending=outcome(reg(b,56,2100,-1,'Diferente'));await waitLock();await a.query('COMMIT');
 const r=await pending;assert.match(r.error.message,/IDEMPOTENCY_CONFLICT/);await b.query('ROLLBACK');
 assert.equal((await q('SELECT count(*)::int n FROM medicina_trabalho WHERE colaborador_id=$1',[id(56)])).rows[0].n,1);
 });
 await t.test('concorrência: mesma revisão, segunda correção STALE_REVISION',async()=>{
 await actor(a);const c=(await reg(a,57,2200)).rows[0].result.consulta.id;
 await a.query('BEGIN');await corr(a,c,0,2201);await b.query('BEGIN');await actor(b);
 const pending=outcome(corr(b,c,0,2202));await waitLock();await a.query('COMMIT');
 const r=await pending;assert.match(r.error.message,/STALE_REVISION/);await b.query('ROLLBACK');
 assert.equal((await q('SELECT revisao FROM medicina_trabalho WHERE id=$1',[c])).rows[0].revisao,1);
 });
 await t.test('rollback recusa perder operações confirmadas',async()=>{await assert.rejects(()=>q(rollback),/ROLLBACK_REFUSED/);await q('ROLLBACK');});
 await q('CREATE DATABASE rollback_test');const clean=await connect('rollback_test');
 let fixture=await read('./fixtures/medicina-base.sql');fixture=fixture.replace('CREATE ROLE anon NOLOGIN;','').replace('CREATE ROLE authenticated NOLOGIN;','');
 await clean.query(fixture);for(const d of defs)await clean.query(d.definition);
 await clean.query('INSERT INTO empresas VALUES($1)',[id(1)]);await clean.query('INSERT INTO colaboradores VALUES($1,$2,$3,current_date-90,NULL)',[id(20),id(1),'Legado']);
 for(let n=0;n<34;n++)await clean.query('INSERT INTO medicina_trabalho(colaborador_id,data_ultima_consulta,resultado) VALUES($1,current_date-30,$2)',[id(20),'Legado '+n]);
 await t.test('rollback completo sem operações restaura linhas/funções/grants',async()=>{
 const before=(await clean.query('SELECT to_jsonb(m) row FROM medicina_trabalho m ORDER BY id')).rows;await clean.query(migration);await clean.query(rollback);
 assert.deepEqual((await clean.query('SELECT to_jsonb(m) row FROM medicina_trabalho m ORDER BY id')).rows,before);
 for(const d of prior){const r=(await clean.query('SELECT pg_get_functiondef(oid) def FROM pg_proc WHERE proname=$1',[d.proname])).rows;assert.ok(r.some(x=>x.def.replace(/\r\n/g,'\n')===d.definition));}
 assert.equal((await clean.query("SELECT has_table_privilege('authenticated','medicina_trabalho','UPDATE') ok")).rows[0].ok,true);
 });
 console.log('PostgreSQL 17.6 local; sessões independentes '+pidA+'/'+pidB+'; '+folder);
 }finally{for(const c of clients)await c.end().catch(()=>{});if(started)run('pg_ctl',['-D',data,'-m','immediate','-w','stop']);}
});