import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { existsSync } from 'node:fs';

const read = p => readFile(new URL(p, import.meta.url), 'utf8');
const precheck = await read('../supabase/quadro_controlado_fase_b_precheck.sql');
const migration = await read('../supabase/quadro_controlado_fase_b.sql');
const hotfix = await read('../supabase/encarregado_escopo_migration.sql');
const comparison = precheck.split(/\r?\n/).find(line => line.includes('jsonb_agg(to_jsonb(x)') && line.includes('quadro_policies_20261001'));

test('Fase B ainda exige policies anteriores ao hotfix; divergência não é ignorada', () => {
  assert.ok(comparison);
  assert.match(comparison, /IS DISTINCT FROM.*RAISE EXCEPTION/);
  assert.match(migration, /policy legado alterado na Fase A/);
  assert.match(hotfix, /CREATE POLICY encarregado_sem_dml_direto ON public\.quadro_pessoal_alocacao AS RESTRICTIVE/);
});

test('Fase B preserva Ponto, mantém v1 e fecha API/DML antigos', () => {
  assert.doesNotMatch(migration, /CREATE OR REPLACE FUNCTION public\.(fn_listar_ponto_obra|fn_guardar_ponto_obra)\(/);
  assert.match(migration, /CLIENT_UPGRADE_REQUIRED/);
  assert.match(migration, /REVOKE INSERT,UPDATE,DELETE/);
  assert.doesNotMatch(migration, /DROP FUNCTION public\.fn_quadro_operar_v1/);
  assert.match(precheck, /exigir_validacao/);
});

const bin = process.env.LOCAL_PG_BIN, deps = process.env.LOCAL_PG_DEPS;
test('PostgreSQL local: policy adicional do hotfix faz o comparador real abortar', { skip: !bin || !deps, timeout: 60000 }, async t => {
  if (!existsSync(join(bin, '..', 'share', 'postgres.bki'))) {
    t.skip('Cliente PostgreSQL disponível, mas sem postgres.bki para criar servidor efémero.');
    return;
  }
  const require = createRequire(import.meta.url);
  const { Client } = require(join(deps, 'pg'));
  const folder = await mkdtemp(join(tmpdir(), 'primeline-phase-b-compat-'));
  const data = join(folder, 'data');
  const socket = createServer();
  await new Promise(resolve => socket.listen(0, '127.0.0.1', resolve));
  const port = socket.address().port;
  await new Promise(resolve => socket.close(resolve));
  function run(name, args) {
    const result = spawnSync(join(bin, name + (process.platform === 'win32' ? '.exe' : '')), args, { encoding: 'utf8', timeout: 30000, windowsHide: true, stdio: name === 'pg_ctl' ? 'ignore' : 'pipe' });
    assert.equal(result.status, 0, `${name}: ${result.error?.message || result.stderr || 'failed'}`);
    return result.stdout;
  }
  run('initdb', ['-D', data, '-U', 'postgres', '--auth-local=trust', '--auth-host=trust', '--encoding=UTF8', '--no-locale']);
  let started = false, db;
  try {
    run('pg_ctl', ['-D', data, '-l', join(folder, 'postgres.log'), '-o', `-h 127.0.0.1 -p ${port} -F`, '-w', 'start']);
    started = true;
    db = new Client({ host: '127.0.0.1', port, user: 'postgres', database: 'postgres', password: '', ssl: false });
    await db.connect();
    await db.query(`CREATE ROLE authenticated;
      CREATE TABLE public.quadro_pessoal_alocacao(id uuid);
      CREATE TABLE public.quadro_pessoal_movimentos(id uuid);
      ALTER TABLE public.quadro_pessoal_alocacao ENABLE ROW LEVEL SECURITY;
      CREATE POLICY leitura ON public.quadro_pessoal_alocacao FOR SELECT TO authenticated USING(true);
      CREATE SCHEMA primeline_backup;
      CREATE TABLE primeline_backup.quadro_policies_20261001 AS
        SELECT * FROM pg_policies WHERE schemaname='public' AND tablename IN('quadro_pessoal_alocacao','quadro_pessoal_movimentos');`);
    await db.query(`DO $$ BEGIN ${comparison} END $$;`);
    await db.query('BEGIN');
    // Same relation/policy name/type as the installed hotfix. No production rows or credentials.
    await db.query('CREATE POLICY encarregado_sem_dml_direto ON public.quadro_pessoal_alocacao AS RESTRICTIVE FOR ALL TO authenticated USING(false) WITH CHECK(false)');
    await assert.rejects(db.query(`DO $$ BEGIN ${comparison} END $$;`), /POSTCHECK_FAILED: policy legado alterado na Fase A/);
    await db.query('ROLLBACK');
    await db.query(`DO $$ BEGIN ${comparison} END $$;`);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM public.quadro_pessoal_alocacao')).rows[0].n, 0);
    console.log('Comparator tested on local PostgreSQL; full post-hotfix Phase B remains unvalidated.');
  } finally {
    await db?.end();
    if (started) run('pg_ctl', ['-D', data, '-m', 'immediate', '-w', 'stop']);
  }
});
