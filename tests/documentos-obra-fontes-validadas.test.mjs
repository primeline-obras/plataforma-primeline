import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from './quadro-runtime/node_modules/@electric-sql/pglite/dist/index.js';

const read = p => readFile(new URL(p, import.meta.url), 'utf8');
const base = await read('./fixtures/orcamento-versoes-etapa1-base.sql');
const etapa1 = await read('../supabase/orcamento_versoes_etapa1.sql');
const migration = await read('../supabase/documentos_obra_fontes_validadas.sql');
const rollback = await read('../supabase/documentos_obra_fontes_validadas_rollback.sql');
const audit = await read('../supabase/ativar_log_auditoria.sql');
const auditFunction = audit.slice(audit.indexOf('create or replace function'), audit.indexOf('\nrevoke all'));
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const validate = `UPDATE public.orcamento_versoes SET estado_validacao='validada',
  validado_por='${id(3)}',validado_em=now(),manifesto='{}',
  manifesto_hash=encode(sha256(convert_to('{}'::jsonb::text,'UTF8')),'hex')`;

test('proteção documental — PGlite isolado, sem produção', async t => {
  const db = new PGlite();
  const rows = async sql => (await db.query(sql)).rows;
  const seed = async (state = 'rascunho') => db.exec(`
    INSERT INTO public.orcamento_versoes(id,obra_id,numero_versao,rotulo,natureza,estado_validacao,estado_reconciliacao)
      VALUES('${id(10)}','${id(1)}',1,'ORCA','original_documental','${state}','pendente');
    INSERT INTO public.orcamento_versoes_fontes(versao_id,documento_obra_id,papel_fonte,nome_original,bucket,object_key,sha256)
      VALUES('${id(10)}','${id(4)}','original','orca.xlsx','documentos','orca.xlsx',repeat('a',64));`);
  const move = `UPDATE public.documentos_obra SET obra_id='${id(2)}' WHERE id='${id(4)}'`;
  const reject = async (sql, code) => {
    await db.exec('SAVEPOINT expected');
    await assert.rejects(() => db.exec(sql), e => e.code === code);
    await db.exec('ROLLBACK TO SAVEPOINT expected; RELEASE SAVEPOINT expected');
  };
  const run = (name, fn) => t.test(name, async () => {
    await db.exec('BEGIN');
    try { await fn(); } finally { await db.exec('ROLLBACK; RESET ROLE'); }
  });
  const snapshot = async () => {
    const data = {};
    for (const {tablename} of await rows("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"))
      data[tablename] = await rows(`SELECT to_jsonb(t) AS row FROM public.${tablename} t ORDER BY to_jsonb(t)::text`);
    return {data, policies: await rows("SELECT * FROM pg_policies WHERE schemaname='public' ORDER BY tablename,policyname"),
      functions: await rows("SELECT oid::regprocedure::text AS name,pg_get_functiondef(oid) AS def FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname<>'fn_impedir_reatribuicao_documento_validado' ORDER BY 1"),
      constraints: await rows("SELECT conrelid::regclass::text AS tab,conname,pg_get_constraintdef(oid) AS def FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY 1,2"),
      indexes: await rows("SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1,2")};
  };
  try {
    await db.exec(base); await db.exec(auditFunction); await db.exec(etapa1);
    await db.exec(`INSERT INTO public.documentos_obra(id,obra_id) VALUES ('${id(6)}','${id(1)}'),('${id(7)}','${id(2)}');
      ALTER TABLE public.documentos_obra ENABLE ROW LEVEL SECURITY;
      CREATE POLICY test_doc_write ON public.documentos_obra TO authenticated USING(true) WITH CHECK(true);
      CREATE TRIGGER trg_auditoria_documentos_obra AFTER INSERT OR UPDATE OR DELETE ON public.documentos_obra
        FOR EACH ROW EXECUTE FUNCTION public.fn_registar_log_auditoria('id');
      SELECT set_config('test.utilizador','${id(3)}',false);`);
    const before = await snapshot();
    await db.exec(migration);
    await t.test('instalação não muda dados, policies, constraints, índices ou funções existentes', async () => {
      assert.deepEqual(await snapshot(),before);
      assert.equal(before.data.documentos_obra.length,4); // Quatro documentos sintéticos, nunca cópia da produção.
      const [fn] = await rows("SELECT prosecdef,provolatile,proconfig,pg_get_userbyid(proowner) AS owner FROM pg_proc WHERE oid='public.fn_impedir_reatribuicao_documento_validado()'::regprocedure");
      assert.equal(fn.prosecdef,true); assert.equal(fn.provolatile,'v'); assert.equal(fn.owner,'postgres');
      assert.ok(fn.proconfig.includes('search_path=pg_catalog, pg_temp')); assert.ok(fn.proconfig.includes('row_security=off'));
      for (const role of ['anon','authenticated','service_role'])
        assert.equal((await rows(`SELECT has_function_privilege('${role}','public.fn_impedir_reatribuicao_documento_validado()','EXECUTE') AS yes`))[0].yes,false);
    });
    await run('sem fonte: mudança permitida e auditoria existente executada', async () => {
      await db.exec(move);
      assert.equal((await rows(`SELECT obra_id FROM public.documentos_obra WHERE id='${id(4)}'`))[0].obra_id,id(2));
      assert.equal((await rows("SELECT count(*)::int AS n FROM public.log_auditoria WHERE tabela_afetada='public.documentos_obra' AND campo='obra_id'"))[0].n,1);
    });
    for (const state of ['rascunho','em_validacao','rejeitada']) await run(`${state}: mudança permitida, validação divergente recusada`, async () => {
      await seed(state); await db.exec(move); await reject(validate,'23514');
    });
    await run('validada: reatribuição recusada, mesmo com fontes invisíveis por RLS', async () => {
      await seed(); await db.exec(validate);
      await db.exec("SELECT set_config('test.obra','',true); SET LOCAL ROLE authenticated");
      assert.deepEqual(await rows('SELECT * FROM public.orcamento_versoes_fontes'),[]);
      await reject(move,'23514');
      assert.equal((await rows(`SELECT obra_id FROM public.documentos_obra WHERE id='${id(4)}'`))[0].obra_id,id(1));
    });
    await run('outros campos e atribuição da mesma obra permitidos; DELETE mantém FK RESTRICT', async () => {
      await seed(); await db.exec(validate);
      await db.exec(`UPDATE public.documentos_obra SET nome_arquivo='corrigido',arquivo_url='novo-caminho',obra_id=obra_id WHERE id='${id(4)}'`);
      await reject(`DELETE FROM public.documentos_obra WHERE id='${id(4)}'`,'23503');
      await db.exec(`DELETE FROM public.documentos_obra WHERE id='${id(6)}'`);
    });
    await run('service_role também não reatribui fonte validada', async () => {
      await seed(); await db.exec(validate); await db.exec('SET LOCAL ROLE service_role'); await reject(move,'23514');
    });
    await run('UPDATE de várias linhas é atómico quando uma fonte validada bloqueia', async () => {
      await seed(); await db.exec(validate);
      await reject(`UPDATE public.documentos_obra SET obra_id='${id(2)}' WHERE id IN ('${id(4)}','${id(6)}')`,'23514');
      assert.equal((await rows(`SELECT count(*)::int AS n FROM public.documentos_obra WHERE id IN ('${id(4)}','${id(6)}') AND obra_id='${id(1)}'`))[0].n,2);
    });
    for (const isolation of ['REPEATABLE READ','SERIALIZABLE']) await run(`${isolation}: 40001 apenas ao mudar obra; outros campos e no-op permitidos`, async () => {
      await db.exec(`SET TRANSACTION ISOLATION LEVEL ${isolation}`);
      await reject(move,'40001');
      await db.exec(`UPDATE public.documentos_obra SET obra_id=obra_id,nome_arquivo='permitido' WHERE id='${id(4)}'`);
    });
    await t.test('rollback recusa retirar proteção com evidência validada', async () => {
      await seed(); await db.exec(validate);
      await assert.rejects(()=>db.exec(rollback),/Rollback recusado/); await db.exec('ROLLBACK');
      await assert.rejects(()=>db.exec(move),e=>e.code==='23514');
      // Descartar a instância, nunca remover evidência validada para preparar rollback.
    });
  } finally { await db.close(); }
  const empty = new PGlite();
  try {
    await empty.exec(base); await empty.exec(auditFunction); await empty.exec(etapa1);
    const before = (await empty.query('SELECT * FROM public.documentos_obra ORDER BY id')).rows;
    await empty.exec(migration); await empty.exec(rollback);
    assert.deepEqual((await empty.query('SELECT * FROM public.documentos_obra ORDER BY id')).rows,before);
    assert.equal((await empty.query("SELECT to_regprocedure('public.fn_impedir_reatribuicao_documento_validado()') AS f")).rows[0].f,null);
    await empty.exec(migration);
  } finally { await empty.close(); }
});
