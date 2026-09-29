import test from 'node:test';
import assert from 'node:assert/strict';
import { connect } from 'node:net';
import { readFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';

// Apenas cluster local descartável. Não aceita URL/host/credenciais Supabase.
const enabled = process.env.DOC_GUARD_LOCAL_TEST === '1';
const port = process.env.DOC_GUARD_PG_PORT || '55439';
const read = p => readFile(new URL(p,import.meta.url),'utf8');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const move = `UPDATE public.documentos_obra SET obra_id='${id(2)}' WHERE id='${id(4)}';`;
const validate = `UPDATE public.orcamento_versoes SET estado_validacao='validada',validado_por='${id(3)}',
  validado_em=now(),manifesto='{}',manifesto_hash=encode(sha256(convert_to('{}'::jsonb::text,'UTF8')),'hex');`;
// Protocolo simple-query mínimo, apenas TCP loopback/trust. Sem passwords,
// TLS, resolução de serviços ou variáveis PG* que possam apontar para produção.
function session(database='primeline_doc_guard_test') {
  const socket=connect({host:'127.0.0.1',port:Number(port)});
  let pending,buffer=Buffer.alloc(0),output=[],error;
  const ready=new Promise((resolve,reject)=>{pending={resolve,reject};});
  ready.catch(()=>{});
  socket.setTimeout(15000,()=>socket.destroy(new Error('Timeout local PostgreSQL')));
  socket.on('connect',()=>{
    const body=Buffer.from(`user\0postgres\0database\0${database}\0client_encoding\0UTF8\0\0`);
    const head=Buffer.alloc(8);head.writeInt32BE(8+body.length);head.writeInt32BE(196608,4);
    socket.write(Buffer.concat([head,body]));
  });
  socket.on('data',chunk=>{
    buffer=Buffer.concat([buffer,chunk]);
    while(buffer.length>=5) {
      const len=buffer.readInt32BE(1);
      if(buffer.length<len+1)break;
      const type=String.fromCharCode(buffer[0]),body=buffer.subarray(5,len+1);
      buffer=buffer.subarray(len+1);
      if(type==='R' && body.readInt32BE(0)!==0)socket.destroy(new Error('Cluster de teste deve usar trust local'));
      if(type==='D') {
        const fields=[];let offset=2;
        for(let i=0;i<body.readInt16BE(0);i++) {
          const size=body.readInt32BE(offset);offset+=4;
          fields.push(size<0?'':body.subarray(offset,offset+size).toString('utf8'));
          if(size>=0)offset+=size;
        }
        output.push(fields.join('|'));
      }
      if(type==='E') {
        const fields=body.toString('utf8').split('\0');
        error=new Error(fields.filter(f=>f.startsWith('C')||f.startsWith('M')).map(f=>f.slice(1)).join(' '));
      }
      if(type==='Z' && pending) {
        const p=pending;pending=null;
        if(error)p.reject(error);else p.resolve(output.join('\n'));
        output=[];error=undefined;
      }
    }
  });
  socket.on('error',e=>pending?.reject(e));
  socket.on('close',()=>pending?.reject(new Error('Ligação local fechada')));
  return {
    async query(sql) {
      await ready;
      assert.ok(!pending,'Não sobrepor comandos na mesma sessão');
      return new Promise((resolve,reject)=>{
        pending={resolve,reject};
        const body=Buffer.from(`${sql}\0`),head=Buffer.alloc(5);
        head[0]=81;head.writeInt32BE(body.length+4,1);socket.write(Buffer.concat([head,body]));
      });
    },
    async close() {
      if(socket.destroyed)return;
      const stopped=new Promise(resolve=>socket.once('close',resolve));
      socket.end(Buffer.from([88,0,0,0,4]));await stopped;
    }
  };
}
async function once(sql,database) {
  const c=session(database); try{return await c.query(sql);}finally{await c.close();}
}
async function blocked(pid,blocker) {
  for(let i=0;i<100;i++) {
    if(await once(`SELECT ${blocker}=ANY(pg_blocking_pids(${pid}));`)==='t')return;
    await delay(30);
  }
  assert.fail('A operação concorrente não esperou pelo lock esperado');
}
const invariant = async () => assert.equal(await once(`SELECT count(*) FROM public.orcamento_versoes v
  JOIN public.orcamento_versoes_fontes f ON f.versao_id=v.id JOIN public.documentos_obra d ON d.id=f.documento_obra_id
  WHERE v.estado_validacao='validada' AND v.obra_id IS DISTINCT FROM d.obra_id;`),'0');

test('PostgreSQL nativo: duas sessões concorrentes, sem Supabase', {
  skip:!enabled && 'Definir DOC_GUARD_LOCAL_TEST=1 para cluster local descartável; PGlite não simula duas sessões.', timeout:60000
},async t=>{
  assert.match(port,/^\d+$/);
  const audit=await read('../supabase/ativar_log_auditoria.sql');
  // O nome fixo da BD e host loopback são deliberados. O cluster deve ser novo.
  // Recusa uma BD já existente em vez de apagar ou reutilizar os seus dados.
  await once('CREATE DATABASE primeline_doc_guard_test;','postgres');
  await once(await read('./fixtures/orcamento-versoes-etapa1-base.sql'));
  await once(audit.slice(audit.indexOf('create or replace function'),audit.indexOf('\nrevoke all')));
  await once(await read('../supabase/orcamento_versoes_etapa1.sql'));
  await once(await read('../supabase/documentos_obra_fontes_validadas.sql'));
  await once(`INSERT INTO public.orcamento_versoes(id,obra_id,numero_versao,rotulo,natureza,estado_validacao,estado_reconciliacao)
    VALUES('${id(10)}','${id(1)}',1,'ORCA','original_documental','rascunho','pendente');
    INSERT INTO public.orcamento_versoes_fontes(versao_id,documento_obra_id,papel_fonte,nome_original,bucket,object_key,sha256)
    VALUES('${id(10)}','${id(4)}','original','orca.xlsx','documentos','orca.xlsx',repeat('a',64));`);

  // Cenários com rollback primeiro: preservam o rascunho para o seguinte.
  for(const [first,commit] of [['validate',false],['move',false],['move',true]]) {
    await t.test(`${first} obtém lock primeiro; ${commit?'COMMIT':'ROLLBACK'}`,async()=>{
      const a=session(),b=session();
      try {
        const pa=Number(await a.query('SELECT pg_backend_pid();'));
        const pb=Number(await b.query('SELECT pg_backend_pid();'));
        await a.query(`BEGIN; ${first==='validate'?validate:move}`);
        const waiting=b.query(`BEGIN; ${first==='validate'?move:validate}`).then(value=>({value}),error=>({error}));
        await blocked(pb,pa);
        await a.query(commit?'COMMIT;':'ROLLBACK;');
        const result=await waiting;
        if(commit) assert.match(result.error?.message || '',/23514.*Documento de outra obra/s);
        else { assert.equal(result.error,undefined); await b.query('ROLLBACK;'); }
        await invariant();
      } finally {await a.close();await b.close();}
    });
  }
  // O cenário anterior confirmou a reatribuição; repor apenas fixture sintética.
  await once(`UPDATE public.documentos_obra SET obra_id='${id(1)}' WHERE id='${id(4)}';`);
  await t.test('validação confirma enquanto UPDATE já espera: snapshot atualizado recusa reatribuição',async()=>{
    const a=session(),b=session();
    try {
      const pa=Number(await a.query('SELECT pg_backend_pid();'));
      const pb=Number(await b.query('SELECT pg_backend_pid();'));
      await a.query(`BEGIN; ${validate}`);
      const waiting=b.query(`BEGIN; ${move}`).then(value=>({value}),error=>({error}));
      await blocked(pb,pa); await a.query('COMMIT;');
      assert.match((await waiting).error?.message || '',/23514.*versão económica validada/s);
      await invariant();
    }finally{await a.close();await b.close();}
  });
  await t.test('snapshot fixo devolve 40001, incluindo documento sem fontes',async()=>{
    const c=session();
    try{
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM public.orcamento_versoes;');
      await assert.rejects(()=>c.query(`UPDATE public.documentos_obra SET obra_id='${id(1)}' WHERE id='${id(5)}';`),/40001/);
    }finally{await c.close();}
    await invariant();
  });
});
