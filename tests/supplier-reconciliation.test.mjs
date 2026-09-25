import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import {norm,phones,emails,extractWorkbook,compare,loadSources} from '../scripts/reconcile_supplier_directory.mjs';
import {makeSql} from '../scripts/supplier_import_sql.mjs';
const company='73fb13c8-d29f-4192-a506-4ca243343add';
const hash='abcdef0123456789'.repeat(4);
const row=(nome,extra={})=>({nome,atividade:'Atividade confirmada',localidade:'',telefone_original:'',email_original:'',observacoes:'',folha:'Teste',linha:2,...extra});
const current=(nome,extra={},aliases=[])=>({cadastro:{id:'10000000-0000-0000-0000-000000000001',empresa_id:company,nome,email:null,telefone:null,notas:null,...extra},nomes_alternativos:aliases});

test('normalização não perde acentos/zeros; contactos separados',()=>{
  assert.equal(norm('António & Filhos, Lda.'),'antoniofilhoslda');
  assert.deepEqual(phones('+351 214 489 300 / 919 874 466'),['214489300','919874466']);
  assert.deepEqual(emails('geral@EXEMPLO.pt; compras@exemplo.pt'),['geral@exemplo.pt','compras@exemplo.pt']);
});
test('alias aprovado encontra cadastro; informação já preenchida não é proposta para substituir',()=>{
  const result=compare({rows:[row('Nome Antigo',{email_original:'novo@example.pt'})]},[current('Empresa Atual',{email:'manual@example.pt'},[{nome:'Nome Antigo'}])],hash)[0];
  assert.equal(result.status,'existente');assert.ok(!result.fields.includes('email'));assert.ok(result.conflicts.includes('email'));
});
test('contactos iguais em nomes diferentes ficam para revisão, não fusão',()=>{
  const result=compare({rows:[row('Nova Designação',{email_original:'partilhado@example.pt'})]},[current('Empresa Distinta',{email:'partilhado@example.pt'})],hash)[0];
  assert.equal(result.status,'revisao');assert.equal(result.target,null);
});
test('repetições no Excel e nomes curtos não geram novos cadastros',()=>{
  const result=compare({rows:[row('Alpha Zeta',{telefone_original:'912345678'}),row('Marca Alternativa',{telefone_original:'912345678'}),row('Paulo',{telefone_original:'923456789'})]},[],hash);
  assert.ok(result.every(r=>r.status==='revisao'));
});
test('tipo, NIF, zona, avaliação e representante não são inventados',()=>{
  const result=compare({rows:[row('Marca Distinta',{telefone_original:'912345678',localidade:'Lisboa',observacoes:'Sr. Manuel'})]},[],hash)[0];
  assert.equal(result.status,'novo');assert.equal(result.proposal.tipo_entidade,undefined);assert.equal(result.proposal.representante,undefined);assert.match(result.proposal.notas,/Lisboa/);
});

const deps=process.env.RH_TEST_DEPS;
test('SQL integral numa base isolada: preview, aplicação, repetição, preservação e guardas',{skip:!deps},async t=>{
  const require=createRequire(deps+'/package.json'),{PGlite}=require('@electric-sql/pglite');
  const db=new PGlite();
  await db.exec(`create role anon;create role authenticated;create schema auth;
    create function auth.uid() returns uuid language sql as $$select null::uuid$$;
    create function public.fn_utilizador_atual_id() returns uuid language sql as $$select null::uuid$$;
    create table empresas(id uuid primary key);insert into empresas values('${company}');
    create table utilizadores(id uuid,empresa_id uuid,funcao text,ativo boolean);
    create table fornecedores(id uuid primary key default gen_random_uuid(),empresa_id uuid not null,nome text not null,nif text,email text,telefone text,
      contacto text,categoria text,condicoes text,notas text,representante text,criado_em timestamptz default now(),
      tipo_entidade text check(tipo_entidade is null or tipo_entidade in ('fornecedor','subempreiteiro','ambos')),
      estado_confianca text,unique(empresa_id,nome));
    create table fornecedores_aliases(id uuid default gen_random_uuid(),empresa_id uuid,fornecedor_id uuid,nome text,nif text,email text,
      nome_normalizado text,fornecedor_origem_id uuid,criado_por uuid,criado_em timestamptz);`);
  let data,report;
  if(process.env.SUPPLIER_SNAPSHOT&&process.env.SUPPLIER_XLSX){
    const X=require(deps+'/xlsx.full.min.js');data=loadSources(X,process.env.SUPPLIER_XLSX,process.env.SUPPLIER_SNAPSHOT);report=compare(data.extracted,data.current,data.hash);
  }else{
    data={current:[current('Fornecedor Confirmado',{notas:'NOTA MANUAL',tipo_entidade:'fornecedor',estado_confianca:'recomendado'})],hash};
    report=compare({rows:[row('Fornecedor Confirmado',{email_original:'geral@confirmado.pt'}),row('Marca Distinta',{telefone_original:'912345678'})]},data.current,hash);
  }
  for(const entry of data.current){
    await db.query('insert into fornecedores select * from jsonb_populate_record(null::fornecedores,$1::jsonb)',[entry.cadastro]);
    for(const a of entry.nomes_alternativos)await db.query('insert into fornecedores_aliases select * from jsonb_populate_record(null::fornecedores_aliases,$1::jsonb)',[a]);
  }
  const before=(await db.query('select * from fornecedores order by id')).rows;
  const preview=makeSql(report,data.current,data.hash,false),apply=makeSql(report,data.current,data.hash,true);
  const summary=results=>results.find(r=>r.rows?.[0]?.novos_previstos!==undefined)?.rows[0];
  const anticipated=report.filter(r=>r.status==='novo').length;
  const updated=report.filter(r=>r.status==='existente'&&r.fields.length).length;
  await t.test('pré-visualização não grava nem cria auditoria persistente',async()=>{
    const result=summary(await db.exec(preview));
    assert.equal(Number(result.novos_previstos),anticipated);assert.equal(Number(result.cadastros_a_completar),updated);
    assert.deepEqual((await db.query('select * from fornecedores order by id')).rows,before);
    assert.equal((await db.query("select to_regclass('public.fornecedores_excel_historico') t")).rows[0].t,null);
  });
  await t.test('gravação preenche só vazios; novos sem tipo ou avaliação inventada',async()=>{
    const result=summary(await db.exec(apply));assert.equal(Number(result.novos_inseridos),anticipated);assert.equal(Number(result.cadastros_completados),updated);
    const after=(await db.query('select * from fornecedores')).rows,byId=new Map(after.map(r=>[r.id,r]));
    for(const old of before)for(const [k,v] of Object.entries(old))if(v!==null&&String(v).trim()!=='')assert.deepEqual(byId.get(old.id)[k],v,`${old.nome}: ${k} preservado`);
    for(const r of after.filter(r=>!before.some(b=>b.id===r.id))){assert.equal(r.tipo_entidade,null);assert.equal(r.estado_confianca,'nao_avaliado');assert.equal(r.nif,null);}
    assert.equal(after.length,before.length+anticipated);
  });
  await t.test('segunda execução: zero criações e zero preenchimentos',async()=>{
    const audit=(await db.query('select count(*)::int n from fornecedores_excel_historico')).rows[0].n;
    const result=summary(await db.exec(apply));assert.equal(Number(result.novos_inseridos),0);assert.equal(Number(result.cadastros_completados),0);assert.equal(Number(result.ja_importados),anticipated);
    assert.equal((await db.query('select count(*)::int n from fornecedores_excel_historico')).rows[0].n,audit);
  });
  await t.test('nome alterado desde exportação impede execução sem perder a correção',async()=>{
    await db.query("update fornecedores set nome=nome||' CORRIGIDO' where id=$1",[before[0].id]);
    await assert.rejects(db.exec(apply),/renomeado\/mesclado/);await db.exec('rollback');
    assert.match((await db.query('select nome from fornecedores where id=$1',[before[0].id])).rows[0].nome,/CORRIGIDO$/);
  });
  console.log(JSON.stringify({snapshot:before.length,novos:anticipated,completados:updated,repeticao_criados:0,repeticao_completados:0}));
  await db.close();
});
