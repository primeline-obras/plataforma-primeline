import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHmac} from 'node:crypto';
import {createServer} from 'node:net';
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
export async function restCases({t,port}) {
 assert.ok(process.env.QUADRO_POSTGREST,'Definir QUADRO_POSTGREST para os testes REST reais locais');
 const socket=createServer();await new Promise(r=>socket.listen(0,'127.0.0.1',r));const httpPort=socket.address().port;await new Promise(r=>socket.close(r));
 const secret='synthetic-local-only-not-a-production-secret-20261004';
 const token=n=>{const h=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url');const p=Buffer.from(JSON.stringify({role:'authenticated',sub:id(n),exp:Math.floor(Date.now()/1000)+1200})).toString('base64url');return h+'.'+p+'.'+createHmac('sha256',secret).update(h+'.'+p).digest('base64url');};
 const child=spawn(process.env.QUADRO_POSTGREST,[],{windowsHide:true,stdio:['ignore','pipe','pipe'],env:{...process.env,PGRST_DB_URI:`postgresql://postgres@127.0.0.1:${port}/postgres`,PGRST_DB_SCHEMAS:'public',PGRST_DB_ANON_ROLE:'anon',PGRST_JWT_SECRET:secret,PGRST_SERVER_HOST:'127.0.0.1',PGRST_SERVER_PORT:String(httpPort),PGRST_LOG_LEVEL:'crit'}});
 let output='';child.stderr.on('data',b=>{output+=b;});child.stdout.on('data',b=>{output+=b;});
 const url='http://127.0.0.1:'+httpPort;
 const request=(path,n=10,method='GET',body)=>fetch(url+'/'+path,{method,headers:{...(n===null?{}:{Authorization:'Bearer '+token(n)}),'Content-Type':'application/json',Prefer:'return=representation'},...(body?{body:JSON.stringify(body)}:{})});
 try {
  let ready=false;
  for(let i=0;i<100;i++){try{const r=await request('',null);if(r.ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}
  assert.ok(ready,'PostgREST local não iniciou (exit='+child.exitCode+'): '+output);
  await t.test('REST real: UUID/filtros/colunas não revelam RH, finanças ou alocações',async()=>{
   for(const path of ['colaboradores?select=nif,morada,valor_hora','subempreitadas?select=valor_adjudicado','quadro_pessoal_alocacao?select=*','ausencias?select=comentario','fornecedores?select=nif,condicoes','avaliacoes_subempreiteiro?select=*','faturas?select=*&id=eq.'+id(702),'pagamentos_subempreitada?select=*','contratos?select=*']){
    const r=await request(path);assert.equal(r.status,200,path);assert.deepEqual(await r.json(),[],path);
   }
  });
  await t.test('REST real: RPC mínima funciona e não há execução financeira direta',async()=>{
   const today=new Date().toISOString().slice(0,10);
   const r=await request('rpc/fn_ausencias_equipa_encarregado',10,'POST',{p_inicio:today,p_fim:today});assert.equal(r.status,200);const rows=await r.json();assert.equal(rows.length,1);assert.equal(rows[0].colaborador_id,id(30));assert.equal('comentario' in rows[0],false);
   for(const n of [null,10,18,19,20,999]){
    const denied=await request('rpc/fn_ajustar_saida_prevista_mensal',n,'POST',{p_obra_id:id(200),p_mes:today,p_variacao:900});assert.ok([401,403,404].includes(denied.status),'writer: '+denied.status);
   }
   const scope=await request('rpc/fn_subempreitadas_operacionais_obra',10,'POST',{p_obra_id:id(118)});assert.equal(scope.status,403);
  });
  await t.test('REST real: DELETE/PATCH ocultos e INSERT legado recusado',async()=>{
   for(const method of ['PATCH','DELETE']){const r=await request('quadro_pessoal_alocacao?id=eq.'+id(1030),10,method,method==='PATCH'?{periodo:'tarde'}:undefined);assert.equal(r.status,200);assert.deepEqual(await r.json(),[]);}
   const r=await request('quadro_pessoal_alocacao',10,'POST',{id:id(9999),colaborador_id:id(30),obra_id:id(120),data:new Date().toISOString().slice(0,10),periodo:'dia_inteiro',criado_por:id(10)});assert.equal(r.status,403);
  });
 } finally {child.kill();await new Promise(r=>{if(child.exitCode!==null)r();else child.once('exit',r);});}
}
