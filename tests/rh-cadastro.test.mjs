import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { RH_FIELDS, parseRhValue, prepareRhRows, createRhCadastro } from '../src/rh-cadastro.js';

test('normalização estrita: datas, booleanos, moeda e zeros',()=>{
  assert.equal(parseRhValue('1.234,56','number'),1234.56);
  assert.equal(parseRhValue('0','number'),0);
  assert.equal(parseRhValue('Não','boolean'),false);
  assert.equal(parseRhValue('Sim','boolean'),true);
  assert.equal(parseRhValue('00123456789'), '00123456789');
  assert.equal(parseRhValue('23/09/2026','date'),'2026-09-23');
  for(const date of ['31/02/2026','2026-02-29','23/09/26'])assert.throws(()=>parseRhValue(date,'date'));
  assert.throws(()=>parseRhValue('€ abc','number'));
  assert.throws(()=>parseRhValue('talvez','boolean'));
  assert.equal(parseRhValue('  '),undefined);
});

test('Excel não apaga vazios; bloqueia IDs repetidos ou desconhecidos',()=>{
  const records=[{colaborador:{id:'a',nome:'Pessoa',email:'original@exemplo.pt'},versao:'v',niss:null,contratos:[]}];
  const [row]=prepareRhRows([{id:'a',versao:'v',email:'',seguro_ok:'Não',valor_hora:0}],records);
  assert.equal(row.errors.length,0);
  assert.ok(!('email' in row.payload.campos));
  assert.equal(row.payload.campos.seguro_ok,false);
  assert.equal(row.payload.campos.valor_hora,0);
  assert.equal(prepareRhRows([{id:'a',versao:'v'},{id:'a',versao:'v'}],records)[1].errors.length,1);
  assert.ok(prepareRhRows([{id:'z',versao:'v'}],records)[0].errors.length);
});

// Dependências de teste isoladas (não são dependências de produção).
const deps=process.env.RH_TEST_DEPS;
test('PostgreSQL: migração, cadastro, permissões e lote atómico',{skip:!deps},async t=>{
  const require=createRequire(deps+'/package.json');
  const {PGlite}=require('@electric-sql/pglite');
  const db=new PGlite();
  const company='10000000-0000-0000-0000-000000000001',other='10000000-0000-0000-0000-000000000002';
  const user='20000000-0000-0000-0000-000000000001';
  const person='30000000-0000-0000-0000-000000000001',person2='30000000-0000-0000-0000-000000000002';
  await db.exec(`
    create role anon; create role authenticated;
    create table empresas(id uuid primary key);
    create table utilizadores(id uuid primary key,empresa_id uuid references empresas,funcao text,ativo boolean);
    create table colaboradores(id uuid primary key default gen_random_uuid(),empresa_id uuid not null references empresas,
      nome text not null,funcao text,nivel text,valor_hora numeric,data_saida date,data_nascimento date,
      permite_multiplas_obras boolean not null default false,data_admissao date,nif text,email text,contacto text,
      morada text,codigo_rh text,observacoes text,registo_trabalhador_ok boolean,seguro_ok boolean,seguranca_social_ok boolean);
    create table colaboradores_contratos(id uuid primary key default gen_random_uuid(),colaborador_id uuid not null references colaboradores,
      tipo_contrato text not null check(tipo_contrato in ('a_prazo','tempo_indeterminado')),data_inicio date not null,
      data_fim_prevista date,estado text not null default 'ativo' check(estado in ('ativo','renovado','encerrado')),criado_em timestamptz not null default now());
    create table obras(id uuid primary key,empresa_id uuid,situacao text);
    create table quadro_pessoal_alocacao(id uuid primary key default gen_random_uuid(),colaborador_id uuid,obra_id uuid,
      tipo_alocacao text,descricao_livre text,semana_inicio date,data date,periodo text,criado_por uuid);
    create table epis(id uuid default gen_random_uuid(),colaborador_id uuid,tipo_epi text,data_entrega date,data_validade date);
    create table medicina_trabalho(id uuid default gen_random_uuid(),colaborador_id uuid,data_ultima_consulta date,resultado text,data_proxima_consulta date);
    create table alertas(id uuid default gen_random_uuid(),entidade_tipo text,entidade_id uuid,estado text,tipo text);
    create function fn_utilizador_atual_id() returns uuid language sql as $$select '${user}'::uuid$$;
    create function fn_e_admin() returns boolean language sql as $$select true$$;
    create function fn_e_administrativo() returns boolean language sql as $$select false$$;
    create function fn_verificar_alertas_vencimento() returns void language plpgsql as $$begin end$$;
    insert into empresas values('${company}'),('${other}');
    insert into utilizadores values('${user}','${company}','gestao_plataforma',true);
    insert into colaboradores(id,empresa_id,nome,funcao,data_admissao,email) values
      ('${person}','${company}','Pessoa A','Pedreiro','2026-01-01','original@exemplo.pt'),
      ('${person2}','${company}','Pessoa B','Pedreiro','2026-01-01','b@exemplo.pt');
  `);
  await db.exec(fs.readFileSync(new URL('../supabase/colaboradores_campos_completos.sql',import.meta.url),'utf8'));
  const migration=fs.readFileSync(new URL('../supabase/rh_cadastro_importacao.sql',import.meta.url),'utf8');
  await db.exec(migration);
  await db.exec(migration);
  const rpc=async(name,args=[])=> (await db.query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) value`,args)).rows[0].value;
  const read=async id=>(await rpc('fn_rh_consultar',[id]))[0];
  const patch=async(id,campos,extra={})=>({id,versao:(await read(id)).versao,campos,...extra});
  await t.test('pré-visualização não escreve; contrato e RH guardam juntos',async()=>{
    const data=await patch(person,{codigo_rh:'001',seguro_ok:true,observacoes:'Nota'},{
      niss:'00123456789',contrato:{tipo_contrato:'a_prazo',data_inicio:'2026-01-01',data_fim_prevista:'2026-12-31'}});
    assert.equal((await rpc('fn_rh_guardar',[data,true])).alterado,true);
    assert.equal((await read(person)).contratos.length,0);
    await rpc('fn_rh_guardar',[data,false]);
    const after=await read(person);
    assert.equal(after.colaborador.seguro_ok,true);
    assert.equal(after.niss,'00123456789');
    assert.equal(after.contratos.length,1);
    assert.equal((await rpc('fn_rh_guardar',[data,false])).alterado,false);
    assert.equal((await read(person)).contratos.length,1);
  });
  await t.test('Excel: vazios preservados, reimportação sem alterações',async()=>{
    const data=await patch(person,{email:'',observacoes:'Atualizado'});
    const preview=await rpc('fn_rh_importar',[[data],false]);
    assert.equal(preview.erros,0);
    assert.equal((await read(person)).colaborador.observacoes,'Nota');
    assert.equal((await rpc('fn_rh_importar',[[data],true])).linhas[0].alterado,true);
    assert.equal((await read(person)).colaborador.email,'original@exemplo.pt');
    assert.equal((await rpc('fn_rh_importar',[[data],true])).linhas[0].alterado,false);
  });
  await t.test('erro na segunda linha reverte a primeira',async()=>{
    const a=await patch(person,{observacoes:'Não guardar'});
    const b=await patch(person2,{valor_hora:-1});
    await assert.rejects(rpc('fn_rh_importar',[[a,b],true]),/nenhuma alteração/);
    assert.equal((await read(person)).colaborador.observacoes,'Atualizado');
  });
  await t.test('conflito concorrente, saída via Excel e ID duplicado bloqueados',async()=>{
    const stale=await patch(person,{observacoes:'Antigo'});
    await rpc('fn_rh_guardar',[await patch(person,{observacoes:'Mais recente'}),false]);
    await assert.rejects(rpc('fn_rh_guardar',[stale,false]),/entretanto/);
    const row=await patch(person,{data_saida:'2026-09-23'});
    assert.equal((await rpc('fn_rh_importar',[[row],false])).erros,1);
    const valid=await patch(person,{observacoes:'Mais recente'});
    assert.equal((await rpc('fn_rh_importar',[[valid,valid],false])).erros,1);
  });
  await t.test('A: início sem tipo, com e sem contrato existente; reimportação idempotente',async()=>{
    await db.exec('begin');
    try {
      for(const id of [person,person2]){
        const before=await read(id),tipo=before.contratos[0]?.tipo_contrato??null;
        const data=await patch(id,{contacto:'912345678'},{contrato:{data_inicio:'2026-07-20',tipo_contrato:''}});
        const preview=await rpc('fn_rh_importar',[[data],false]);assert.equal(preview.erros,0);
        assert.deepEqual(await read(id),before);
        assert.equal((await rpc('fn_rh_importar',[[data],true])).erros,0);
        const after=await read(id);assert.equal(after.contratos[0].data_inicio,'2026-07-20');
        assert.equal(after.contratos[0].tipo_contrato,tipo);assert.equal(after.colaborador.contacto,'912345678');
        assert.equal((await rpc('fn_rh_importar',[[data],true])).linhas[0].alterado,false);
      }
    }finally{await db.exec('rollback');}
  });
  await t.test('B/E: contrato e campos comuns vazios preservam valores, false e zero são importados',async()=>{
    await db.exec('begin');
    try {
      const before=await read(person);
      const data=await patch(person,{email:' ',nome:null,nif:'',contacto:'923456789',seguro_ok:false,valor_hora:0},{
        contrato:{tipo_contrato:'',data_inicio:null,data_fim_prevista:' '}});
      assert.equal((await rpc('fn_rh_importar',[[data],true])).erros,0);
      const after=await read(person);assert.deepEqual(after.contratos,before.contratos);
      for(const key of ['email','nome','nif','data_saida'])assert.equal(after.colaborador[key],before.colaborador[key]);
      assert.equal(after.colaborador.seguro_ok,false);assert.equal(after.colaborador.valor_hora,0);
      assert.equal(after.colaborador.contacto,'923456789');
    }finally{await db.exec('rollback');}
  });
  await t.test('C: tempo indeterminado aceite; fim vazio preserva data existente',async()=>{
    await db.exec('begin');
    try {
      for(const id of [person,person2]){
        const before=await read(id),end=before.contratos[0]?.data_fim_prevista??null;
        const data=await patch(id,{},{contrato:{tipo_contrato:'tempo_indeterminado',data_inicio:'2026-07-20',data_fim_prevista:''}});
        const result=await rpc('fn_rh_importar',[[data],true]);assert.equal(result.erros,0);
        const after=await read(id);assert.equal(after.contratos[0].tipo_contrato,'tempo_indeterminado');
        assert.equal(after.contratos[0].data_fim_prevista,end);
        assert.equal(after.contratos[0].data_inicio,'2026-07-20');
        if(end)assert.ok(result.linhas[0].avisos.length);
      }
    }finally{await db.exec('rollback');}
  });
  await t.test('D: a prazo completo aceite; incompleto guarda restantes campos e avisa sem criar contrato',async()=>{
    await db.exec('begin');
    try {
      const incomplete=await patch(person2,{contacto:'934567890'},{contrato:{tipo_contrato:'a_prazo',data_inicio:'2026-07-20'}});
      const p=await rpc('fn_rh_importar',[[incomplete],false]);assert.equal(p.erros,0);assert.match(p.linhas[0].avisos[0],/Contrato não alterado/);
      const result=await rpc('fn_rh_importar',[[incomplete],true]);assert.equal(result.erros,0);
      assert.equal((await read(person2)).contratos.length,0);assert.equal((await read(person2)).colaborador.contacto,'934567890');
      const complete=await patch(person2,{},{contrato:{tipo_contrato:'a_prazo',data_inicio:'2026-07-20',data_fim_prevista:'2027-07-19'}});
      assert.equal((await rpc('fn_rh_importar',[[complete],true])).erros,0);
      assert.equal((await read(person2)).contratos[0].data_fim_prevista,'2027-07-19');
    }finally{await db.exec('rollback');}
  });
  await t.test('contrato incoerente preservado; importação não cria pessoas nem altera alocações',async()=>{
    await db.exec('begin');
    try {
      const before=await read(person);
      const data=await patch(person,{contacto:'945678901'},{contrato:{data_fim_prevista:'2025-01-01'},alocacao_tipo:'escritorio'});
      const result=await rpc('fn_rh_importar',[[data],true]);assert.equal(result.erros,0);assert.ok(result.linhas[0].avisos.length);
      assert.deepEqual((await read(person)).contratos,before.contratos);
      assert.equal((await db.query('select count(*)::int n from quadro_pessoal_alocacao')).rows[0].n,0);
      for(const id of [null,'39999999-0000-0000-0000-000000000099']){
        assert.equal((await rpc('fn_rh_importar',[[{id,campos:{nome:'Nunca criar'}}],false])).erros,1);
      }
      assert.equal((await db.query('select count(*)::int n from colaboradores')).rows[0].n,2);
      const stale={...data,campos:{contacto:'956789012'}};assert.equal((await rpc('fn_rh_importar',[[stale],false])).erros,1);
    }finally{await db.exec('rollback');}
  });
  await t.test('modo interno parcial não é RPC acessível diretamente',async()=>{
    await db.exec('set role authenticated');
    try{await assert.rejects(rpc('fn_rh_guardar_interno',[{id:person,campos:{}},true,true]),/permission denied/);}
    finally{await db.exec('reset role');}
  });
  await t.test('ficheiro real: 47 linhas, tipo vazio, pré-visualização e reimportação',{skip:!process.env.RH_XLSX},async()=>{
    await db.exec('begin');
    try {
      const X=require(deps+'/xlsx.full.min.js'),book=X.read(fs.readFileSync(process.env.RH_XLSX));
      const rows=X.utils.sheet_to_json(book.Sheets.Colaboradores,{defval:''});
      assert.equal(rows.length,47);assert.ok(rows.every(r=>!r.tipo_contrato&&r.data_inicio));
      const testCompany='10000000-0000-0000-0000-000000000047';
      await db.query('insert into empresas values($1)',[testCompany]);
      await db.query('update utilizadores set empresa_id=$1',[testCompany]);
      for(const row of rows)await db.query('insert into colaboradores(id,empresa_id,nome,funcao,data_admissao) values($1,$2,$3,$4,$5)',
        [row.id,testCompany,row.nome,row.funcao,parseRhValue(row.data_admissao,'date')]);
      const before=await rpc('fn_rh_consultar',[]);
      // Versões só da base sintética; nunca modificar o Excel nem versões em produção.
      const versions=new Map(before.map(r=>[r.colaborador.id,r.versao]));
      const prepared=prepareRhRows(rows.map(r=>({...r,versao:versions.get(r.id)})),before);
      assert.ok(prepared.every(r=>!r.errors.length));
      const payload=prepared.map(r=>r.payload),preview=await rpc('fn_rh_importar',[payload,false]);
      assert.equal(preview.erros,0,JSON.stringify(preview.linhas.filter(r=>!r.ok)));
      assert.deepEqual(await rpc('fn_rh_consultar',[]),before);
      const applied=await rpc('fn_rh_importar',[payload,true]);assert.equal(applied.erros,0);
      assert.equal(applied.linhas.filter(r=>r.alterado).length,47);
      const after=await rpc('fn_rh_consultar',[]);assert.equal(after.length,47);
      assert.ok(after.every(r=>r.contratos.length===1&&r.contratos[0].tipo_contrato===null));
      assert.equal((await rpc('fn_rh_importar',[payload,true])).linhas.filter(r=>r.alterado).length,0);
      assert.equal((await db.query('select count(*)::int n from quadro_pessoal_alocacao')).rows[0].n,0);
      console.log('RH Excel (base sintética): 47 aceites; 0 erros; repetição 0 alterações; 0 pessoas criadas pela importação.');
    }finally{await db.exec('rollback');}
  });
  await t.test('administrativo edita mas não importa; técnico não consulta',async()=>{
    await db.exec("update utilizadores set funcao='administrativo'");
    assert.equal((await read(person)).colaborador.nome,'Pessoa A');
    await assert.rejects(rpc('fn_rh_importar',[[],false]),/permissão/);
    await db.exec("update utilizadores set funcao='diretor_obra'");
    await assert.rejects(rpc('fn_rh_consultar',[person]),/permissão/);
    await db.exec("update utilizadores set funcao='gestao_plataforma'");
    await db.exec(`update colaboradores set empresa_id='${other}' where id='${person2}'`);
    await assert.rejects(rpc('fn_rh_guardar',[{id:person2,campos:{}},false]),/nesta empresa/);
  });
  await t.test('criação com alocação, EPI, consulta e contrato',async()=>{
    const created=await rpc('fn_rh_guardar',[{campos:{nome:'Nova Pessoa',funcao:'Servente',data_admissao:'2026-09-23'},
      alocacao_tipo:'escritorio',epi_data:'2026-09-23',medicina_data:'2026-09-23',
      contrato:{tipo_contrato:'tempo_indeterminado',data_inicio:'2026-09-23'}},false]);
    assert.equal((await read(created.id)).contratos.length,1);
    assert.equal((await db.query('select count(*)::int n from quadro_pessoal_alocacao')).rows[0].n,1);
    assert.equal((await db.query('select count(*)::int n from epis')).rows[0].n,1);
    assert.equal((await db.query('select count(*)::int n from medicina_trabalho')).rows[0].n,1);
  });
  await t.test('contrato inválido não guarda edição parcial; histórico preservado',async()=>{
    const before=await read(person);
    const invalid=await patch(person,{nome:'Não gravar'},{contrato:{data_fim_prevista:'2025-01-01'}});
    await assert.rejects(rpc('fn_rh_guardar',[invalid,false]),/anterior/);
    assert.equal((await read(person)).colaborador.nome,before.colaborador.nome);
    await db.exec(`insert into colaboradores_contratos(colaborador_id,tipo_contrato,data_inicio,estado)
      values('${person}','tempo_indeterminado','2025-01-01','encerrado')`);
    await rpc('fn_rh_guardar',[await patch(person,{},{
      contrato:{tipo_contrato:'tempo_indeterminado',data_fim_prevista:null}}),false]);
    assert.equal((await read(person)).contratos.length,2);
    assert.equal((await read(person)).contratos.filter(c=>c.estado==='encerrado').length,1);
  });
  await t.test('saída preserva histórico e auditoria identifica autor',async()=>{
    await rpc('fn_rh_guardar',[await patch(person,{data_saida:'2026-09-23'}),false]);
    assert.equal((await read(person)).colaborador.data_saida,'2026-09-23');
    assert.equal((await read(person)).contratos.length,2);
    assert.equal((await db.query('select utilizador_id from rh_cadastro_auditoria limit 1')).rows[0].utilizador_id,user);
  });
  await t.test('permissões PostgreSQL: RPC autorizada, acesso direto a NISS negado',async()=>{
    await db.exec('set role authenticated');
    assert.equal((await read(person)).niss,'00123456789');
    await assert.rejects(db.query('select * from colaboradores_rh_privado'),/permission denied/);
    await assert.rejects(db.query('select * from rh_cadastro_auditoria'),/permission denied/);
    await db.exec('reset role; set role anon');
    await assert.rejects(rpc('fn_rh_consultar',[person]),/permission denied/);
    await db.exec('reset role');
  });
  await db.close();
});

test('formulário preserva dados ao abrir e guarda uma única vez',{skip:!deps},async()=>{
  const require=createRequire(deps+'/package.json');const {JSDOM}=require('jsdom');
  const dom=new JSDOM('<div id="workflow-dialog" hidden><h2 id="workflow-dialog-title"></h2><div id="workflow-dialog-content"></div></div>');
  const previous={document:globalThis.document,FormData:globalThis.FormData};
  globalThis.document=dom.window.document;globalThis.FormData=dom.window.FormData;
  const record={versao:'v',colaborador:{id:'a',nome:'Pessoa A',funcao:'Pedreiro',email:'a@exemplo.pt',data_admissao:'2026-01-01',seguro_ok:false},niss:'00123456789',
    contratos:[{id:'c',tipo_contrato:'a_prazo',data_inicio:'2026-01-01',data_fim_prevista:'2026-12-31',estado:'ativo'}]};
  const calls=[];
  const module=createRhCadastro({api:async(path,options)=>{calls.push([path,JSON.parse(options.body)]);return {ok:true,json:async()=>path.includes('consultar')?[record]:{alterado:true}};},
    canManage:()=>true,isManagement:()=>true,configured:()=>true,works:()=>[],refresh:async()=>{},toast:()=>{}});
  try {
    await module.open({id:'a',nome:'Pessoa A'});
    const form=document.querySelector('#rh-form');
    assert.equal(form.elements.email.value,'a@exemplo.pt');
    assert.equal(form.elements.niss.value,'00123456789');
    assert.equal(form.elements.seguro_ok.value,'false');
    assert.equal(form.elements.tipo_contrato.value,'a_prazo');
    assert.equal(form.querySelectorAll('[type=submit]').length,1);
    await form.onsubmit({preventDefault(){}});
    const saves=calls.filter(([p])=>p.includes('guardar'));
    assert.equal(saves.length,1);assert.equal(saves[0][1].p_dados.campos.email,'a@exemplo.pt');
    assert.equal(document.querySelector('#workflow-dialog').hidden,true);
    record.contratos[0].tipo_contrato=null;record.contratos[0].data_fim_prevista=null;
    await module.open({id:'a',nome:'Pessoa A'});
    assert.match(document.querySelector('#workflow-dialog-content').textContent,/Tipo por confirmar/);
    const pendingForm=document.querySelector('#rh-form');
    pendingForm.elements.contacto.value='912345678';
    await pendingForm.onsubmit({preventDefault(){}});
    const pendingSave=calls.filter(([p])=>p.includes('guardar')).at(-1)[1].p_dados;
    assert.equal(pendingSave.campos.contacto,'912345678');assert.equal(pendingSave.contrato,undefined);
    assert.equal(document.querySelector('#workflow-dialog').hidden,true);
  }finally{globalThis.document=previous.document;globalThis.FormData=previous.FormData;dom.window.close();}
});

test('interface: aviso contratual visível, permite confirmar e não limpa células vazias',{skip:!deps},async()=>{
  const require=createRequire(deps+'/package.json'),{JSDOM}=require('jsdom'),X=require(deps+'/xlsx.full.min.js');
  const dom=new JSDOM('<div id="workflow-dialog" hidden><h2 id="workflow-dialog-title"></h2><div id="workflow-dialog-content"></div></div>');
  const previous={document:globalThis.document,XLSX:globalThis.XLSX};
  globalThis.document=dom.window.document;globalThis.XLSX=X;
  const record={versao:'versao-preservada',colaborador:{id:'a',nome:'Pessoa',funcao:'Pedreiro'},contratos:[],niss:null};
  const calls=[],warning='Contrato não alterado: Indique o fim previsto. Os restantes campos podem ser atualizados.';
  const module=createRhCadastro({api:async(path,options)=>{
    const data=JSON.parse(options.body);calls.push([path,data]);
    return {ok:true,json:async()=>path.includes('consultar')?[record]:{erros:0,linhas:[{ok:true,alterado:true,avisos:[warning]}]}};
  },canManage:()=>true,isManagement:()=>true,configured:()=>true,works:()=>[],refresh:async()=>{},toast:()=>{}});
  try{
    await module.openImport();
    const headers=['id','versao',...RH_FIELDS.map(([k])=>k)],row={id:'a',versao:record.versao,contacto:'912345678',tipo_contrato:'a_prazo',data_inicio:'2026-07-20'};
    const book=X.utils.book_new();X.utils.book_append_sheet(book,X.utils.aoa_to_sheet([headers,headers.map(k=>row[k]??'')]),'Colaboradores');
    const bytes=X.write(book,{type:'buffer',bookType:'xlsx'}),input=document.querySelector('[data-rh-file]');
    Object.defineProperty(input,'files',{value:[{size:bytes.length,arrayBuffer:async()=>bytes}]});
    await input.onchange();
    assert.match(document.querySelector('[data-rh-preview]').textContent,/AVISO/);
    assert.ok(document.querySelector('[data-rh-preview]').textContent.includes(warning));
    const confirm=document.querySelector('[data-rh-confirm]');assert.equal(confirm.disabled,false);
    await confirm.onclick();
    assert.match(document.querySelector('[data-rh-preview]').textContent,/1 cadastros atualizados/);
    assert.ok(document.querySelector('[data-rh-preview]').textContent.includes(warning));
    const payload=calls.filter(([p])=>p.includes('importar')).at(-1)[1].p_linhas[0];
    assert.equal(payload.versao,record.versao);assert.equal(payload.id,'a');
    assert.equal(payload.contrato.data_fim_prevista,undefined);assert.equal(payload.campos.nome,undefined);
  }finally{globalThis.document=previous.document;globalThis.XLSX=previous.XLSX;dom.window.close();}
});
