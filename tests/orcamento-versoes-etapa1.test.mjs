import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

// PostgreSQL em memória; não aceita URL, credenciais nem ligação externa.
const { PGlite } = await import(process.env.QUADRO_PGLITE
  ? pathToFileURL(process.env.QUADRO_PGLITE).href
  : './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js');
const read = p => readFile(new URL(p, import.meta.url), 'utf8');
const migration = await read('../supabase/orcamento_versoes_etapa1.sql');
const rollback = await read('../supabase/orcamento_versoes_etapa1_rollback.sql');
const base = await read('./fixtures/orcamento-versoes-etapa1-base.sql');
// Usar a implementação existente da auditoria, sem executar o instalador legado.
const auditInstaller = await read('../supabase/ativar_log_auditoria.sql');
const auditFunction = auditInstaller.slice(auditInstaller.indexOf('create or replace function'), auditInstaller.indexOf('\nrevoke all'));
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const tables = ['orcamento_versoes', 'orcamento_versoes_fontes'];
let db;
const q = (sql, args = []) => db.query(sql, args);
const rows = async (sql, args) => (await q(sql, args)).rows;
const fails = (sql, args, code) => assert.rejects(() => q(sql, args), e => e.code === code);
const version = (n = 10, obra = 1, numero = 1, anterior = null) => q(`
  INSERT INTO public.orcamento_versoes(id,obra_id,numero_versao,rotulo,natureza,estado_validacao,estado_reconciliacao,versao_anterior_id)
  VALUES($1,$2,$3,'REV03','original_documental','rascunho','pendente',$4)`, [id(n),id(obra),numero,anterior && id(anterior)]);
const source = (n = 20, versao = 10, documento = 4) => q(`
  INSERT INTO public.orcamento_versoes_fontes(id,versao_id,documento_obra_id,papel_fonte,nome_original,bucket,object_key,sha256)
  VALUES($1,$2,$3,'original','ORCA.xlsx','documentos','orca.xlsx',repeat('a',64))`, [id(n),id(versao),documento && id(documento)]);
const validate = (n = 10) => q(`UPDATE public.orcamento_versoes SET estado_validacao='validada',
  validado_por=$2,validado_em=now(),manifesto='{"formato":1}',
  manifesto_hash=encode(sha256(convert_to('{"formato":1}'::jsonb::text,'UTF8')),'hex') WHERE id=$1`, [id(n),id(3)]);

// Falhas esperadas não podem abortar a transação que isola cada caso.
async function rejected(sql, args, code) {
  await db.exec('SAVEPOINT expected_error');
  try { await fails(sql, args, code); }
  finally { await db.exec('ROLLBACK TO SAVEPOINT expected_error; RELEASE SAVEPOINT expected_error'); }
}
async function isolated(fn) {
  await db.exec('BEGIN');
  try { await fn(); } finally { await db.exec('ROLLBACK; RESET ROLE'); }
}
async function legacySnapshot() {
  const names = (await rows(`SELECT relname FROM pg_class WHERE relnamespace='public'::regnamespace
    AND relkind IN ('r','v') AND relname NOT IN ('orcamento_versoes','orcamento_versoes_fontes') ORDER BY relname`)).map(r=>r.relname);
  const data = {};
  for (const name of names.filter(n=>n!=='log_auditoria')) data[name] = await rows(`SELECT to_jsonb(t) AS row FROM public.${name} t ORDER BY to_jsonb(t)::text`);
  const schema = await rows(`SELECT c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, c.relacl,
    (SELECT jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,
      pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum) FROM pg_attribute a
      LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0) AS columns,
    (SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid=c.oid) AS constraints,
    (SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY i.indexrelid::regclass::text) FROM pg_index i WHERE i.indrelid=c.oid) AS indexes,
    (SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal) AS triggers,
    (SELECT jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polroles,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname)
      FROM pg_policy p WHERE p.polrelid=c.oid) AS policies,
    CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid) END AS view
    FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relname=ANY($1::text[]) ORDER BY c.relname`, [names]);
  const functions = await rows(`SELECT proname, pg_get_functiondef(oid) AS definition FROM pg_proc
    WHERE pronamespace='public'::regnamespace AND proname NOT LIKE 'fn_guardar_integridade_orcamento_%' ORDER BY proname`);
  return { data, schema, functions };
}

test('Etapa 1 — PostgreSQL isolado, sem ligação ao Supabase', async t => {
  db = new PGlite();
  try {
    await db.exec(base); await db.exec(auditFunction);
    await q("SELECT set_config('test.utilizador',$1,false)",[id(3)]);
    const before = await legacySnapshot();
    await db.exec(migration);
    const run = (name, fn) => t.test(name, () => isolated(fn));

    await run('duas tabelas vazias, sem backfill, PKs, FKs RESTRICT, índices e RLS', async () => {
      for (const table of tables) {
        assert.deepEqual(await rows(`SELECT * FROM public.${table}`), []);
        assert.equal((await rows('SELECT relrowsecurity FROM pg_class WHERE oid=$1::regclass',[`public.${table}`]))[0].relrowsecurity,true);
        const fk = await rows('SELECT confdeltype FROM pg_constraint WHERE conrelid=$1::regclass AND contype=\'f\'',[`public.${table}`]);
        assert.equal(fk.length, table === tables[0] ? 4 : 3);
        assert.ok(fk.every(r=>r.confdeltype==='r'));
        assert.equal((await rows('SELECT count(*)::int AS n FROM pg_constraint WHERE conrelid=$1::regclass AND contype=\'p\'',[`public.${table}`]))[0].n,1);
      }
      assert.equal((await rows("SELECT count(*)::int AS n FROM pg_indexes WHERE tablename=ANY($1::text[])",[tables]))[0].n,6);
    });
    await run('rascunho editável; defaults UUID/data; fontes editáveis e removíveis', async () => {
      await version(); await source();
      await q("UPDATE public.orcamento_versoes SET rotulo='Corrigido',pendencias='[\"279,78 por reconciliar\"]' WHERE id=$1",[id(10)]);
      await q("UPDATE public.orcamento_versoes_fontes SET folha='Folha3',intervalo_origem='J23:K29' WHERE id=$1",[id(20)]);
      await q('DELETE FROM public.orcamento_versoes_fontes WHERE id=$1',[id(20)]);
      await q('DELETE FROM public.orcamento_versoes WHERE id=$1',[id(10)]);
      const [r] = await rows(`INSERT INTO public.orcamento_versoes(obra_id,numero_versao,rotulo,natureza,estado_validacao,estado_reconciliacao)
        VALUES($1,1,'Original','original_documental','rascunho','nao_avaliada') RETURNING id,criado_em`,[id(1)]);
      assert.match(r.id,/^[a-f0-9-]{36}$/); assert.ok(r.criado_em);
      const [f] = await rows(`INSERT INTO public.orcamento_versoes_fontes(versao_id,papel_fonte,nome_original,bucket,object_key,sha256)
        VALUES($1,'original','orca.xlsx','documentos','orca.xlsx',repeat('a',64)) RETURNING id,associado_em`,[r.id]);
      assert.match(f.id,/^[a-f0-9-]{36}$/); assert.ok(f.associado_em);
    });
    await run('CHECKs de natureza, estados, metadados de validação e hashes', async () => {
      await version(); await source();
      for (const field of ['natureza','estado_validacao','estado_reconciliacao'])
        await rejected(`UPDATE public.orcamento_versoes SET ${field}='invalido' WHERE id=$1`,[id(10)],'23514');
      await rejected("UPDATE public.orcamento_versoes SET estado_validacao='validada' WHERE id=$1",[id(10)],'23514');
      for (const assignment of ['validado_por=NULL','validado_em=NULL','manifesto=NULL',"manifesto='null'",'manifesto_hash=NULL',"manifesto_hash='inválido'"]) {
        const assignments = { validado_por:'$2', validado_em:'now()', manifesto:"'{}'::jsonb", manifesto_hash:"encode(sha256(convert_to('{}'::jsonb::text,'UTF8')),'hex')" };
        const key = assignment.split('=')[0]; assignments[key] = assignment.slice(key.length+1);
        // Usar o UUID literal quando o parâmetro $2 é removido pelo caso de teste.
        assignments.validado_por = assignments.validado_por.replace('$2',`'${id(3)}'::uuid`);
        await rejected(`UPDATE public.orcamento_versoes SET estado_validacao='validada',${Object.entries(assignments).map(([k,v])=>`${k}=${v}`).join(',')} WHERE id=$1`,[id(10)],'23514');
      }
      for (const set of ["sha256='abc'", "sha256=repeat('g',64)", 'tamanho_bytes=-1', "bucket=''", "object_key=' '", "papel_fonte=''", "nome_original=''" ])
        await rejected(`UPDATE public.orcamento_versoes_fontes SET ${set} WHERE id=$1`,[id(20)],'23514');
      await q('UPDATE public.orcamento_versoes_fontes SET tamanho_bytes=0 WHERE id=$1',[id(20)]);
    });
    await run('fluxo documental: sem fontes recusa, rascunho aceita, valida e congela', async () => {
      await version();
      await db.exec('SAVEPOINT no_sources');
      await assert.rejects(()=>validate(),e=>e.code==='23514' && /pelo menos uma fonte/.test(e.message));
      await db.exec('ROLLBACK TO SAVEPOINT no_sources');
      assert.equal((await rows('SELECT estado_validacao FROM public.orcamento_versoes WHERE id=$1',[id(10)]))[0].estado_validacao,'rascunho');
      await source(); await validate();
      assert.equal((await rows('SELECT estado_validacao FROM public.orcamento_versoes WHERE id=$1',[id(10)]))[0].estado_validacao,'validada');
      await db.exec('SAVEPOINT frozen_source');
      await assert.rejects(()=>source(21),e=>e.code==='23514' && /imutáveis/.test(e.message));
      await db.exec('ROLLBACK TO SAVEPOINT frozen_source');
    });
    await run('INSERT diretamente validada sem fontes também é recusado', async () => {
      await rejected(`INSERT INTO public.orcamento_versoes(obra_id,numero_versao,rotulo,natureza,estado_validacao,
        estado_reconciliacao,validado_por,validado_em,manifesto,manifesto_hash)
        VALUES($1,1,'Original','original_documental','validada','pendente',$2,now(),'{}',
        encode(sha256(convert_to('{}'::jsonb::text,'UTF8')),'hex'))`,[id(1),id(3)],'23514');
    });
    await run('revalidação recusa qualquer fonte inválida, mesmo com outra fonte válida', async () => {
      await version(); await source();
      await q(`INSERT INTO public.orcamento_versoes_fontes(id,versao_id,papel_fonte,nome_original,bucket,object_key,sha256)
        VALUES($1,$2,'detalhe','d.xlsx','documentos','d.xlsx',repeat('a',64))`,[id(21),id(10)]);
      // Simular corrupção administrativa apenas nesta transação local; rollback restaura DDL e dados.
      for (const {conname} of await rows("SELECT conname FROM pg_constraint WHERE conrelid='public.orcamento_versoes_fontes'::regclass AND contype='c'"))
        await db.exec(`ALTER TABLE public.orcamento_versoes_fontes DROP CONSTRAINT "${conname}"`);
      await db.exec('ALTER TABLE public.orcamento_versoes_fontes ALTER COLUMN sha256 DROP NOT NULL');
      for (const bad of ["sha256='abc'",'sha256=NULL',"papel_fonte=''","nome_original=' '","bucket=''","object_key=''",'tamanho_bytes=-1']) {
        await db.exec('SAVEPOINT bad_structure');
        await q(`UPDATE public.orcamento_versoes_fontes SET ${bad} WHERE id=$1`,[id(21)]);
        await assert.rejects(()=>validate(),e=>e.code==='23514' && /estruturalmente inválida/.test(e.message));
        await db.exec('ROLLBACK TO SAVEPOINT bad_structure');
      }
    });
    await run('SHA-256 confere bytes UTF-8 reais; espaços/ordem de chaves normalizados pelo jsonb', async () => {
      const samples = ['{"b":2,"a":1}', ' { "a" : 1, "b" : 2 } ',
        '{"ação":"João 🏗","itens":[{"z":null,"a":true},2.00]}', '{"n":1}', '{"n":1.0}'];
      const results = [];
      for (const json of samples) {
        const [r] = await rows("SELECT $1::jsonb::text AS serialized, encode(sha256(convert_to($1::jsonb::text,'UTF8')),'hex') AS hash",[json]);
        assert.equal(r.hash,createHash('sha256').update(r.serialized,'utf8').digest('hex'));
        results.push(r);
      }
      assert.equal(results[0].hash,results[1].hash);
      assert.notEqual(results[3].hash,results[4].hash); // Igualdade JSONB não é igualdade dos bytes serializados.
      await version(); await source();
      await rejected(`UPDATE public.orcamento_versoes SET estado_validacao='validada',validado_por=$2,
        validado_em=now(),manifesto='{"formato":1}',manifesto_hash=repeat('b',64) WHERE id=$1`,[id(10),id(3)],'23514');
      const hash = createHash('sha256').update('{"formato": 1}','utf8').digest('hex');
      await rejected(`UPDATE public.orcamento_versoes SET estado_validacao='validada',validado_por=$2,
        validado_em=now(),manifesto='{"formato":2}',manifesto_hash=$3 WHERE id=$1`,[id(10),id(3),hash],'23514');
      await q(`UPDATE public.orcamento_versoes SET estado_validacao='validada',validado_por=$2,
        validado_em=now(),manifesto='{"formato":1}',manifesto_hash=$3 WHERE id=$1`,[id(10),id(3),hash]);
    });
    await run('unicidade por obra/número e por fonte/papel/localização, incluindo NULL', async () => {
      await version(); await source();
      await db.exec('SAVEPOINT duplicate_version');
      await assert.rejects(()=>version(11),e=>e.code==='23505');
      await db.exec('ROLLBACK TO SAVEPOINT duplicate_version');
      await rejected(`INSERT INTO public.orcamento_versoes_fontes(versao_id,papel_fonte,nome_original,bucket,object_key,sha256,folha)
        VALUES($1,'original','outro_nome.xlsx','documentos','orca.xlsx',repeat('c',64),'')`,[id(10)],'23505');
      await q(`INSERT INTO public.orcamento_versoes_fontes(versao_id,papel_fonte,nome_original,bucket,object_key,sha256,folha)
        VALUES($1,'original','ORCA.xlsx','documentos','orca.xlsx',repeat('a',64),'Folha3')`,[id(10)]);
    });
    await run('versão validada rejeita UPDATE, DELETE, retrocesso e todas as mutações de fontes', async () => {
      await version(); await source(); await validate();
      for (const sql of ["UPDATE public.orcamento_versoes SET rotulo=rotulo WHERE id=$1",
        "UPDATE public.orcamento_versoes SET estado_validacao='rascunho' WHERE id=$1",'DELETE FROM public.orcamento_versoes WHERE id=$1'])
        await rejected(sql,[id(10)],'23514');
      await rejected("UPDATE public.orcamento_versoes_fontes SET nome_original='mudou' WHERE id=$1",[id(20)],'23514');
      await rejected('DELETE FROM public.orcamento_versoes_fontes WHERE id=$1',[id(20)],'23514');
      await rejected(`INSERT INTO public.orcamento_versoes_fontes(versao_id,papel_fonte,nome_original,bucket,object_key,sha256)
        VALUES($1,'detalhe','d.xlsx','documentos','d.xlsx',repeat('a',64))`,[id(10)],'23514');
      await version(11,1,2,10); // revisão nova permitida; original fica intacto.
      assert.equal((await rows('SELECT estado_validacao FROM public.orcamento_versoes WHERE id=$1',[id(10)]))[0].estado_validacao,'validada');
    });
    await run('linhagem fixa, sem autorreferência/ciclos ou mistura de obras', async () => {
      await version();
      for (const [n,obra,num,prev,code] of [[11,2,2,10,'23514'],[11,1,1,10,'23514'],[11,1,2,11,'23503'],[11,1,2,999,'23503']]) {
        await db.exec('SAVEPOINT bad_previous'); await assert.rejects(()=>version(n,obra,num,prev),e=>e.code===code);
        await db.exec('ROLLBACK TO SAVEPOINT bad_previous');
      }
      for (const set of [`id='${id(12)}'`,`obra_id='${id(2)}'`,'numero_versao=2',`versao_anterior_id='${id(10)}'`])
        await rejected(`UPDATE public.orcamento_versoes SET ${set} WHERE id=$1`,[id(10)],'23514');
      await source(); await version(11,2);
      await rejected('UPDATE public.orcamento_versoes_fontes SET versao_id=$2 WHERE id=$1',[id(20),id(11)],'23514');
    });
    await run('documento de outra obra recusado em INSERT/UPDATE e na validação', async () => {
      await version();
      await db.exec('SAVEPOINT bad_document'); await assert.rejects(()=>source(20,10,5),e=>e.code==='23514');
      await db.exec('ROLLBACK TO SAVEPOINT bad_document'); await source();
      await rejected('UPDATE public.orcamento_versoes_fontes SET documento_obra_id=$2 WHERE id=$1',[id(20),id(5)],'23514');
      await q('UPDATE public.documentos_obra SET obra_id=$2 WHERE id=$1',[id(4),id(2)]);
      await db.exec('SAVEPOINT moved_document'); await assert.rejects(()=>validate(),e=>e.code==='23514');
      await db.exec('ROLLBACK TO SAVEPOINT moved_document');
    });
    await run('FKs existentes e não destrutivas, sem apagar obra/documento/utilizador referenciado', async () => {
      await version(); await source();
      await q('UPDATE public.orcamento_versoes SET criado_por=$1 WHERE id=$2',[id(3),id(10)]);
      await rejected('DELETE FROM public.documentos_obra WHERE id=$1',[id(4)],'23503');
      await rejected('DELETE FROM public.utilizadores WHERE id=$1',[id(3)],'23503');
      await rejected('DELETE FROM public.orcamento_versoes WHERE id=$1',[id(10)],'23503');
      await rejected('UPDATE public.orcamento_versoes SET validado_por=$1 WHERE id=$2',[id(999),id(10)],'23503');
      await rejected('UPDATE public.orcamento_versoes_fontes SET associado_por=$1 WHERE id=$2',[id(999),id(20)],'23503');
    });
    await run('limite documental: FK bloqueia DELETE, mas não reatribuição posterior da obra', async () => {
      await version(); await source(); await validate();
      await rejected('DELETE FROM public.documentos_obra WHERE id=$1',[id(4)],'23503');
      await q('UPDATE public.documentos_obra SET obra_id=$2 WHERE id=$1',[id(4),id(2)]);
      const [r] = await rows(`SELECT v.estado_validacao,v.obra_id AS versao_obra,d.obra_id AS documento_obra
        FROM public.orcamento_versoes v JOIN public.orcamento_versoes_fontes f ON f.versao_id=v.id
        JOIN public.documentos_obra d ON d.id=f.documento_obra_id WHERE v.id=$1`,[id(10)]);
      assert.equal(r.estado_validacao,'validada'); assert.notEqual(r.versao_obra,r.documento_obra);
    });
    await run('authenticated lê apenas a sua obra; admin lê ambas; anon sem acesso', async () => {
      await version(); await source(); await version(11,2); await source(21,11,5);
      await q("SELECT set_config('test.obra',$1,true)",[id(1)]); await db.exec('SET LOCAL ROLE authenticated');
      assert.deepEqual((await rows('SELECT id FROM public.orcamento_versoes')).map(r=>r.id),[id(10)]);
      assert.deepEqual((await rows('SELECT id FROM public.orcamento_versoes_fontes')).map(r=>r.id),[id(20)]);
      await q("SELECT set_config('test.obra','',true)");
      for (const table of tables) assert.equal((await rows(`SELECT * FROM public.${table}`)).length,0);
      await q("SELECT set_config('test.admin','true',true)");
      for (const table of tables) assert.equal((await rows(`SELECT * FROM public.${table}`)).length,2);
      await db.exec('SET LOCAL ROLE anon');
      for (const table of tables) await rejected(`SELECT * FROM public.${table}`,[],'42501');
    });
    await run('authenticated nem admin escrevem diretamente; TRUNCATE sem privilégio', async () => {
      await version(); await source();
      await q("SELECT set_config('test.admin','true',true)"); await db.exec('SET LOCAL ROLE authenticated');
      for (const table of tables) for (const sql of [`INSERT INTO public.${table} DEFAULT VALUES`,`UPDATE public.${table} SET id=id`,`DELETE FROM public.${table}`,`TRUNCATE public.${table}`])
        await rejected(sql,[],'42501');
      await db.exec('RESET ROLE');
      for (const table of tables) assert.equal((await rows("SELECT has_table_privilege('service_role',$1,'TRUNCATE') AS yes",[`public.${table}`]))[0].yes,false);
    });
    await run('RLS bloqueia escrita mesmo com concessão DML acidental futura', async () => {
      await version(); await source();
      await db.exec('GRANT INSERT,UPDATE,DELETE ON public.orcamento_versoes,public.orcamento_versoes_fontes TO authenticated');
      await q("SELECT set_config('test.admin','true',true)"); await db.exec('SET LOCAL ROLE authenticated');
      for (const table of tables) {
        assert.equal((await rows(`UPDATE public.${table} SET id=id RETURNING id`)).length,0);
        assert.equal((await rows(`DELETE FROM public.${table} RETURNING id`)).length,0);
      }
      await db.exec('SAVEPOINT rls_insert'); await assert.rejects(()=>version(11,1,2),e=>e.code==='42501');
      await db.exec('ROLLBACK TO SAVEPOINT rls_insert');
    });
    await run('service_role pode gerir rascunhos mas não contornar imutabilidade', async () => {
      await db.exec('SET LOCAL ROLE service_role'); await version(); await source(); await validate();
      await rejected('DELETE FROM public.orcamento_versoes WHERE id=$1',[id(10)],'23514');
      await rejected('DELETE FROM public.orcamento_versoes_fontes WHERE id=$1',[id(20)],'23514');
    });
    await run('auditoria existente regista INSERT/UPDATE/DELETE e utilizador nas duas tabelas', async () => {
      await version(); await source();
      await q("UPDATE public.orcamento_versoes SET rotulo='novo' WHERE id=$1",[id(10)]);
      await q("UPDATE public.orcamento_versoes_fontes SET nome_original='novo.xlsx' WHERE id=$1",[id(20)]);
      await q('DELETE FROM public.orcamento_versoes_fontes WHERE id=$1',[id(20)]);
      await q('DELETE FROM public.orcamento_versoes WHERE id=$1',[id(10)]);
      for (const [table,n,field] of [[tables[0],10,'rotulo'],[tables[1],20,'nome_original']]) {
        const logs = await rows('SELECT campo,utilizador_id FROM public.log_auditoria WHERE tabela_afetada=$1 AND registo_id=$2 ORDER BY campo',[`public.${table}`,id(n)]);
        assert.deepEqual(logs.map(r=>r.campo),['__DELETE__','__INSERT__',field]);
        assert.ok(logs.every(r=>r.utilizador_id===id(3)));
      }
    });
    await run('falha de auditoria anula a escrita', async () => {
      await db.exec("CREATE FUNCTION public.test_audit_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'falha auditoria'; END $$; CREATE TRIGGER test_audit_fail BEFORE INSERT ON public.log_auditoria FOR EACH ROW EXECUTE FUNCTION public.test_audit_fail()");
      await db.exec('SAVEPOINT audit_fail'); await assert.rejects(()=>version(),e=>e.code==='P0001');
      await db.exec('ROLLBACK TO SAVEPOINT audit_fail');
      assert.equal((await rows('SELECT * FROM public.orcamento_versoes')).length,0);
    });
    await t.test('dados, IDs, constraints, RLS, índices, triggers, funções e view legados intactos', async () => {
      assert.deepEqual(await legacySnapshot(),before);
      assert.equal((await rows('SELECT count(*)::int AS n FROM public.itens_orcamento'))[0].n,18);
      assert.equal((await rows('SELECT count(*)::int AS n FROM public.orcamento_fases'))[0].n,9);
    });
    await t.test('rollback recusa tabelas com registos sem perda de dados', async () => {
      await version();
      await assert.rejects(()=>db.exec(rollback),/Rollback recusado/); await db.exec('ROLLBACK');
      assert.equal((await rows('SELECT count(*)::int AS n FROM public.orcamento_versoes'))[0].n,1);
      await q('DELETE FROM public.orcamento_versoes WHERE id=$1',[id(10)]);
    });
    await t.test('rollback sem CASCADE recusa dependências novas e mantém atomicidade', async () => {
      await db.exec('CREATE VIEW public.test_version_dependency AS SELECT id FROM public.orcamento_versoes');
      await assert.rejects(()=>db.exec(rollback),e=>e.code==='2BP01'); await db.exec('ROLLBACK');
      for (const table of tables) assert.ok((await rows('SELECT to_regclass($1) AS name',[`public.${table}`]))[0].name);
      await db.exec('DROP VIEW public.test_version_dependency');
    });
    await t.test('rollback vazio remove apenas Etapa 1, mantém auditoria/legado e permite reaplicação', async () => {
      const auditBefore = await rows('SELECT * FROM public.log_auditoria ORDER BY id');
      await db.exec(rollback);
      for (const table of tables) assert.equal((await rows('SELECT to_regclass($1) AS name',[`public.${table}`]))[0].name,null);
      assert.deepEqual(await rows('SELECT * FROM public.log_auditoria ORDER BY id'),auditBefore);
      assert.deepEqual(await legacySnapshot(),before);
      await db.exec(migration);
      for (const table of tables) assert.equal((await rows(`SELECT * FROM public.${table}`)).length,0);
    });
  } finally { await db.close(); }
});
