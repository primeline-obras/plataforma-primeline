// Base PostgreSQL isolada: nunca liga a Supabase/produção.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { normalizeManagementRows, validateManagementImportRows, prepareManagementImportRows } from '../src/management-map.js';
const require = createRequire(process.env.MGO_TEST_DEPS || import.meta.url);
const { PGlite } = require('@electric-sql/pglite');
const read = file => readFileSync(new URL('../' + file, import.meta.url), 'utf8').replace(/\r\n/g, '\n');
const db = new PGlite();
await db.exec([
 'create role anon; create role authenticated;',
 'create table utilizadores(id uuid,empresa_id uuid,ativo boolean,funcao text);',
 'create table obras(id uuid,empresa_id uuid,numero text,nome text);',
 'create table colaboradores(id uuid,empresa_id uuid,nome text);',
 'create table fornecedores(id uuid,empresa_id uuid,nome text);',
 'create table subempreitadas(id uuid,obra_id uuid,fornecedor_id uuid,criado_em timestamptz,especialidade text,valor_adjudicado numeric,estado text);',
 'create table ausencias(id uuid default gen_random_uuid(),colaborador_id uuid,data date,tipo text,estado text);',
 'create table lancamentos_mao_obra(id uuid primary key default gen_random_uuid(),obra_id uuid not null,colaborador_id uuid not null,data date not null,horas numeric not null,valor_hora numeric not null,valor_total numeric,percentual_afetacao numeric default 1.0,tee_id uuid,item_orcamento_id uuid);',
 "insert into utilizadores values('00000000-0000-0000-0000-000000000003','73fb13c8-d29f-4192-a506-4ca243343add',true,'gestao_plataforma');",
 "insert into obras values('00000000-0000-0000-0000-000000000002','73fb13c8-d29f-4192-a506-4ca243343add','122','Obra teste');",
 "insert into colaboradores values('00000000-0000-0000-0000-000000000001','73fb13c8-d29f-4192-a506-4ca243343add','Kamila Batista Gutterres');",
 'create function fn_e_admin() returns boolean language sql as $$ select true $$;',
 'create function fn_e_financeiro() returns boolean language sql as $$ select false $$;',
 "create function fn_utilizador_atual_id() returns uuid language sql as $$ select '00000000-0000-0000-0000-000000000003'::uuid $$;",
 "create function fn_mapa_gestao_obras() returns table(origem_id uuid,obra_id uuid,obra_numero text,obra_nome text,categoria text,data_lancamento date,entidade_nome text,descricao text,documento text,valor numeric) language sql as $$ select l.id,l.obra_id,o.numero,o.nome,'mao_obra',l.data,c.nome,'Horas',null::text,coalesce(l.valor_total,l.horas*l.valor_hora) from lancamentos_mao_obra l join obras o on o.id=l.obra_id join colaboradores c on c.id=l.colaborador_id $$;"
].join('\n'));
const base = read('supabase/mapa_gestao_obras.sql');
await db.exec(base.slice(base.indexOf('create or replace function public.fn_mgo_inserir_json_compativel'), base.lastIndexOf('\ncommit;')));
await db.exec(read('supabase/mgo_grelha_excel_leitura_tecnica.sql'));
const migration = read('supabase/mgo_mao_obra_periodicidade.sql');
await db.exec(migration);
await db.exec(migration);
console.log('OK: migração aditiva e repetível');
const monthly = {categoria:'mao_obra',linha:582,obra_numero:'122',colaborador:'Kamila Batista Gutterres',data:'2026-07-31',horas:110,valor_hora:17.85,tipo_registo:'mensal',mes_referencia:'2026-07-01'};
const rpc = async (rows, confirm = false) => (await db.query('select fn_importar_mapa_gestao($1::jsonb,$2) as r',[JSON.stringify(rows),confirm])).rows[0].r;
await db.exec("insert into ausencias(colaborador_id,data,tipo,estado) values('00000000-0000-0000-0000-000000000001','2026-07-31','ferias','confirmada')");
assert.equal((await rpc([monthly])).criar,1);
assert.equal((await rpc([monthly],true)).criados,1);
const second = await rpc([monthly],true);
assert.equal(second.criados,0);
assert.equal(second.duplicados,1);
assert.equal((await db.query('select count(*)::int as n from ausencias')).rows[0].n,1);
const stored = (await db.query('select *,horas*valor_hora as custo from lancamentos_mao_obra')).rows[0];
assert.equal(Number(stored.custo),1963.5);
assert.equal(stored.tipo_registo,'mensal');
const view = (await db.query('select * from fn_mapa_gestao_obras_excel()')).rows[0];
assert.match(view.descricao,/TOTAL MENSAL 07\/2026/);
assert.equal(Number(view.valor),1963.5);
console.log('OK: mensal em dia de férias aceite, custo preservado, reimportação cria 0, férias preservadas');
await db.exec('truncate lancamentos_mao_obra');
const daily = {...monthly,tipo_registo:'diario',mes_referencia:null,horas:8};
const conflict = await rpc([daily]);
assert.equal(conflict.criar,0);
assert.match(conflict.erros[0],/Kamila.*2026-07-31.*ausência/);
await assert.rejects(rpc([daily],true),/ausência/);
await assert.rejects(db.exec("insert into lancamentos_mao_obra(obra_id,colaborador_id,data,horas,valor_hora) values('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','2026-07-31',8,17.85)"),/ausência/);
console.log('OK: férias bloqueiam diário na pré-visualização, RPC e inserção direta');
assert.match((await rpc([{...monthly,tipo_registo:'diario',mes_referencia:null}])).erros[0],/24 horas/);
assert.match((await rpc([{...monthly,mes_referencia:'2026-08-01'}])).erros[0],/mês de referência/);
assert.match((await rpc([{...monthly,tipo_registo:'outro'}])).erros[0],/Tipo de registo/);
assert.match((await rpc([{...monthly,horas:800}])).erros[0],/duração do mês/);
const low = {...monthly,data:'2026-08-31',mes_referencia:'2026-08-01',horas:6.72};
assert.equal((await rpc([low],true)).criados,1);
assert.match((await rpc([{...low,horas:7}])).erros[0],/Já existem horas/);
assert.match((await rpc([{...low,tipo_registo:'diario',mes_referencia:null,data:'2026-08-10',horas:8}])).erros[0],/total mensal/);
await db.exec('truncate lancamentos_mao_obra');
const otherMonthly = {...monthly,horas:111};
assert.equal((await rpc([monthly,otherMonthly])).erros.length,2);
assert.equal((await rpc([monthly,{...daily,data:'2026-07-10'}])).erros.length,2);
assert.equal((await rpc([monthly,{...monthly,linha:999}],true)).criados,1);
console.log('OK: totais mensais pequenos, limite do mês, duplicados internos e proteção contra dupla contagem');
await db.exec('truncate lancamentos_mao_obra');
const normal = {...daily,data:'2026-07-10'};
assert.equal((await rpc([normal],true)).criados,1);
assert.match((await rpc([monthly])).erros[0],/Já existem horas/);
assert.equal((await rpc([{...normal,obra_numero:'79'}])).criar,0);
await db.exec('truncate lancamentos_mao_obra');
const smallFile=[monthly,low,{...normal,data:'2026-09-10'}];
assert.equal((await rpc(smallFile)).criar,3);
assert.equal((await rpc(smallFile,true)).criados,3);
const repeated=await rpc(smallFile,true);
assert.equal(repeated.criados,0);
assert.equal(repeated.duplicados,3);
console.log('OK: ficheiro de 3 linhas; primeira importação 3; segunda importação 0');
await db.exec('truncate lancamentos_mao_obra');
await assert.rejects(rpc([normal,daily],true),/ausência/);
assert.equal((await db.query('select count(*)::int as n from lancamentos_mao_obra')).rows[0].n,0);
console.log('OK: erro num lote anula as criações desse lote');
await db.exec('create or replace function fn_e_admin() returns boolean language sql as $$ select false $$');
await assert.rejects(rpc([monthly],true),/Sem permissão/);
console.log('OK: diário normal, obra reservada e permissões preservados');
const [parsed] = normalizeManagementRows('mao_obra',[{Obra:122,Colaborador:'Kamila Batista Gutterres',Data:'31/07/2026',Horas:'6,72','Valor/Hora':17.85,'Tipo Registo':'MENSAL','Mês Referência':'2026-07'}]);
assert.equal(parsed.tipo_registo,'mensal');
assert.equal(parsed.mes_referencia,'2026-07-01');
assert.deepEqual(validateManagementImportRows([parsed]),[]);
assert.ok(validateManagementImportRows([monthly,otherMonthly]).length);
assert.ok(validateManagementImportRows([monthly,{...daily,data:'2026-07-10'}]).length);
assert.equal(prepareManagementImportRows([monthly,monthly]).duplicates,1);
assert.ok(validateManagementImportRows([{...monthly,tipo_registo:'diario',mes_referencia:null}]).length);
console.log('OK: leitor Excel, classificação explícita e validação global antes dos lotes');
// Migração dos registos históricos: fixture com 33 das 35 linhas já gravadas.
await db.exec('truncate lancamentos_mao_obra; alter table lancamentos_mao_obra disable trigger trg_bloquear_mao_obra_ausencia');
const manifest = JSON.parse(read('docs/mgo_mensais_20260924.json'));
for (const [i,r] of manifest.entries()) {
  let c = (await db.query('select id from colaboradores where lower(nome)=lower($1)',[r.colaborador])).rows[0];
  if (!c) c = (await db.query("insert into colaboradores values(gen_random_uuid(),'73fb13c8-d29f-4192-a506-4ca243343add',$1) returning id",[r.colaborador])).rows[0];
  let o = (await db.query('select id from obras where numero=$1',[r.obra_numero])).rows[0];
  if (!o) o = (await db.query("insert into obras values(gen_random_uuid(),'73fb13c8-d29f-4192-a506-4ca243343add',$1,'Obra teste') returning id",[r.obra_numero])).rows[0];
  if (i<33) await db.query('insert into lancamentos_mao_obra(obra_id,colaborador_id,data,horas,valor_hora) values($1,$2,$3,$4,$5)',[o.id,c.id,r.data,r.horas,r.valor_hora]);
}
await db.exec('alter table lancamentos_mao_obra enable trigger trg_bloquear_mao_obra_ausencia');
const before = (await db.query("select id,(to_jsonb(l)-'tipo_registo'-'mes_referencia') as dados from lancamentos_mao_obra l order by id")).rows;
const correction = read('supabase/mgo_mensais_classificar_existentes_20260924.sql');
await db.exec(correction);
await db.exec(correction);
assert.equal((await db.query("select count(*)::int as n from lancamentos_mao_obra where tipo_registo='mensal'")).rows[0].n,33);
assert.equal((await db.query('select count(*)::int as n from mgo_mensais_20260924_backup')).rows[0].n,33);
assert.deepEqual((await db.query("select id,(to_jsonb(l)-'tipo_registo'-'mes_referencia') as dados from lancamentos_mao_obra l order by id")).rows,before);
assert.equal((await db.query('select count(*)::int as n from ausencias')).rows[0].n,1);
console.log('OK: 33 históricos classificados, 2 ausentes não criados, backup e repetição sem mudar valores/datas/férias');
await db.close();
