import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import path from 'node:path';
const require=createRequire(import.meta.url);const {PGlite}=require(process.env.FALTA_PGLITE||path.join(tmpdir(),'primeline-falta-test-deps/node_modules/@electric-sql/pglite'));
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
test('Falta V2 — SQL local sintético, sem produção',async t=>{
 const db=new PGlite();try{
 await db.exec(await readFile(new URL('./fixtures/quadro-base.sql',import.meta.url),'utf8'));
 const meta=JSON.parse(await readFile(new URL('./fixtures/quadro-funcoes-instaladas.json',import.meta.url),'utf8'));
 for(const c of meta.tables.find(x=>x.name==='ausencias').constraints.filter(x=>x.definition.startsWith('CHECK')))await db.exec(`ALTER TABLE ausencias ADD CONSTRAINT ${c.name} ${c.definition}`);
 await db.exec(`CREATE SCHEMA folha_privado;
 CREATE TABLE quadro_equipa_permanencias(empresa_id uuid,colaborador_id uuid,obra_id uuid,inicio date,fim date);
 CREATE TABLE folha_registos(colaborador_id uuid,data date);

 CREATE TABLE lancamentos_mao_obra(colaborador_id uuid,data date);
 CREATE TABLE horas_extraordinarias(colaborador_id uuid,data date);
 CREATE TABLE folha_privado.operacoes(empresa_id uuid,ator_id uuid,request_id uuid,payload jsonb,token text,resultado jsonb,criado_em timestamptz,PRIMARY KEY(empresa_id,ator_id,request_id));
 CREATE TABLE folha_historico(empresa_id uuid,obra_id uuid,tipo_local text,person_id uuid,kind text,data date,action text,antes jsonb,depois jsonb,revision integer,ator_id uuid,request_id uuid,reason text);
 CREATE FUNCTION folha_privado.ator() RETURNS public.utilizadores LANGUAGE sql AS $$ SELECT u FROM public.utilizadores u WHERE id=auth.uid() AND ativo $$;
 CREATE FUNCTION folha_privado.adm() RETURNS boolean LANGUAGE sql AS $$ SELECT funcao IN('administrativo','gestao_plataforma','gerencia') FROM public.utilizadores WHERE id=auth.uid() $$;
 CREATE FUNCTION folha_privado.lock_dia(uuid,date) RETURNS void LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_advisory_xact_lock(61001,1); END $$;
 CREATE FUNCTION folha_privado.linha(uuid,uuid,date,text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"conflict":null}'::jsonb $$;
 CREATE FUNCTION folha_privado.obra(uuid,boolean) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.obra_responsaveis WHERE obra_id=$1 AND utilizador_id=auth.uid() AND papel='encarregado') THEN RAISE EXCEPTION 'PERMISSION_DENIED'; END IF; END $$;
 CREATE FUNCTION folha_privado.legacy_closed() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'LEGACY_WRITER_CLOSED'; END $$;
 CREATE TRIGGER trg_01_folha_legacy_closed BEFORE INSERT OR UPDATE OR DELETE ON ponto_pessoal_obra FOR EACH STATEMENT EXECUTE FUNCTION folha_privado.legacy_closed();`);
 // Existing installed audit function, not a new audit implementation.
 const normal=meta.tables.find(x=>x.name==='ausencias').triggers.find(x=>x.name==='trg_normalizar_estado_ausencia');await db.exec(normal.function);await db.exec(normal.definition);
 const audit=meta.tables.find(x=>x.name==='ausencias').triggers.find(x=>x.name==='trg_auditoria_ausencias');await db.exec(audit.function);await db.exec(audit.definition);
 await db.exec(await readFile(new URL('../supabase/folha_falta_v2_backup.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/folha_falta_v2.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../supabase/folha_falta_v2_postcheck.sql',import.meta.url),'utf8'));
 const scalar=async sql=>(await db.query(sql)).rows[0];
 await db.exec(`INSERT INTO empresas VALUES('${id(1)}');INSERT INTO utilizadores(id,empresa_id,nome,email,funcao) VALUES('${id(2)}','${id(1)}','Encarregado','e@synthetic','encarregado'),('${id(9)}','${id(1)}','Admin','a@synthetic','administrativo');INSERT INTO obras(id,empresa_id,numero,nome,tipo) VALUES('${id(3)}','${id(1)}',1,'Sintética','obra');INSERT INTO colaboradores(id,empresa_id,nome,funcao) VALUES('${id(4)}','${id(1)}','Pessoa','pedreiro');INSERT INTO obra_responsaveis(obra_id,utilizador_id,papel) VALUES('${id(3)}','${id(2)}','encarregado');INSERT INTO quadro_equipa_permanencias VALUES('${id(1)}','${id(4)}','${id(3)}',current_date-10,NULL);`);
 await db.query("SELECT set_config('test.actor',$1,false)",[id(2)]);
 const today=(await scalar("SELECT (now() AT TIME ZONE 'Europe/Lisbon')::date::text AS d")).d;
 const yesterday=(await scalar("SELECT ((now() AT TIME ZONE 'Europe/Lisbon')::date-1)::text AS d")).d;
 let seq=50;const data=(extra={})=>({version:2,request_id:id(seq++),date:today,work_id:id(3),key:{kind:'primeline',person_id:id(4)},choice:'justificada',...extra});
 const call=async(action,b,confirm=false,token=null)=>(await db.query('SELECT public.fn_folha_falta_v2($1,$2,$3,$4) r',[action,b,confirm,token])).rows[0].r;
 const reject=async b=>assert.rejects(call('absence_report',b),/DATE_WINDOW|PERMISSION_DENIED|CONFLICT|VALIDATION/);
 await t.test('data antiga e futura recusadas',async()=>{await reject(data({date:'2020-01-01'}));await reject(data({date:'2099-01-01'}));});
 await t.test('externo e obra não autorizada recusados',async()=>{await reject(data({key:{kind:'external',person_id:id(4)}}));await reject(data({work_id:id(8)}));});
 await t.test('outra pessoa fora da equipa recusada',async()=>{await reject(data({key:{kind:'primeline',person_id:id(8)}}));});
 await t.test('perfil administrativo não reporta ocorrência de Encarregado',async()=>{await db.query("SELECT set_config('test.actor',$1,false)",[id(9)]);await reject(data());await db.query("SELECT set_config('test.actor',$1,false)",[id(2)]);});
 for(const table of ['folha_registos','lancamentos_mao_obra','horas_extraordinarias'])await t.test(table+' existente bloqueia sem apagar',async()=>{await db.query(`INSERT INTO ${table} VALUES($1,$2)`,[id(4),today]);await reject(data());assert.equal((await scalar(`SELECT count(*)::int n FROM ${table}`)).n,1);await db.exec(`DELETE FROM ${table}`);});
 await t.test('writer legado permanece CLOSED',async()=>{await assert.rejects(db.query('INSERT INTO ponto_pessoal_obra(colaborador_id,data) VALUES($1,$2)',[id(4),today]),/LEGACY_WRITER_CLOSED/);});
 let report;
 await t.test('hoje: preview não grava; justificada neutra, equipa intacta e auditoria',async()=>{report=data();const p=await call('absence_report',report);assert.equal((await scalar('SELECT count(*)::int n FROM ausencias')).n,0);const r=await call('absence_report',report,true,p.versao);assert.equal(r.absence.tipo,'falta_justificada_pendente');assert.equal(r.absence.estado,'ausente_pendente');assert.equal((await scalar('SELECT count(*)::int n FROM quadro_equipa_permanencias')).n,1);assert.equal((await scalar('SELECT count(*)::int n FROM folha_registos')).n,0);assert.ok((await scalar('SELECT count(*)::int n FROM log_auditoria')).n>0);const replay=await call('absence_report',report,true,p.versao);assert.deepEqual(replay,r);await assert.rejects(call('absence_report',{...report,choice:'injustificada'}),/IDEMPOTENCY_CONFLICT/);});
 await t.test('Encarregado não classifica; tipo neutro não pode ser confirmado sem classificação',async()=>{const a=(await scalar('SELECT id FROM ausencias')).id;await assert.rejects(call('absence_classify',{version:2,request_id:id(seq++),id:a,classification:'falta_justificada_com_remuneracao',reason:'Documento'}),/PERMISSION_DENIED/);await assert.rejects(db.exec("UPDATE ausencias SET estado='justificada'"),/CLASSIFICATION_REQUIRED/);});
 await t.test('Admin classifica explicitamente com remuneração',async()=>{await db.query("SELECT set_config('test.actor',$1,false)",[id(9)]);const a=(await scalar('SELECT id FROM ausencias')).id;const b={version:2,request_id:id(seq++),id:a,classification:'falta_justificada_com_remuneracao',reason:'Documento revisto'};const p=await call('absence_classify',b);const r=await call('absence_classify',b,true,p.versao);assert.equal(r.absence.tipo,b.classification);assert.equal(r.absence.estado,'confirmada');await db.query("SELECT set_config('test.actor',$1,false)",[id(2)]);});
 await t.test('ontem: injustificada pendente de validação, sem horas',async()=>{const b=data({date:yesterday,choice:'injustificada'});const p=await call('absence_report',b);const r=await call('absence_report',b,true,p.versao);assert.equal(r.absence.tipo,'falta_injustificada');assert.equal(r.absence.estado,'ausente_pendente');assert.equal((await scalar('SELECT count(*)::int n FROM folha_registos')).n,0);});
 await t.test('Admin classifica sem remuneração somente após escolha explícita',async()=>{await db.exec('DELETE FROM ausencias WHERE data=current_date-1');const b=data({date:yesterday});const p=await call('absence_report',b);const r=await call('absence_report',b,true,p.versao);await db.query("SELECT set_config('test.actor',$1,false)",[id(9)]);const c={version:2,request_id:id(seq++),id:r.absence.id,classification:'falta_justificada_sem_remuneracao',reason:'Classificação documental'};const cp=await call('absence_classify',c);const cr=await call('absence_classify',c,true,cp.versao);assert.equal(cr.absence.estado,'justificada');await db.query("SELECT set_config('test.actor',$1,false)",[id(2)]);});
 await t.test('rollback estrutural mantém auditoria e restaura constraints',async()=>{await db.exec(await readFile(new URL('../supabase/folha_falta_v2_rollback.sql',import.meta.url),'utf8'));assert.equal((await scalar("SELECT to_regprocedure('public.fn_folha_falta_v2(text,jsonb,boolean,text)') r")).r,null);assert.ok((await scalar('SELECT count(*)::int n FROM log_auditoria')).n>0);});
 }finally{await db.close();}
});