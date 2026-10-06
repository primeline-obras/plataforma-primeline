import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
export async function auditDocumentCases(t,{q,as,id}) {
 await t.test('independent audit: B CRUD has no access to known A collaborator/vehicle UUIDs',async()=>{
  for(const [tipo,n] of [['colaborador',20],['viatura',30]]){
   assert.equal((await as(11,'SELECT * FROM documentos WHERE entidade_id=$1',[id(n)])).rowCount,0);
   await assert.rejects(as(11,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3)',[id(2),tipo,id(n)]),e=>e.code==='42501');
   assert.equal((await as(11,"UPDATE documentos SET nome_arquivo='forbidden' WHERE entidade_id=$1",[id(n)])).rowCount,0);
   assert.equal((await as(11,'DELETE FROM documentos WHERE entidade_id=$1',[id(n)])).rowCount,0);
   const own=await as(11,'INSERT INTO documentos(empresa_id,entidade_tipo,entidade_id) VALUES($1,$2,$3) RETURNING id',[id(2),tipo,id(n+1)]);
   assert.equal((await as(11,"UPDATE documentos SET nome_arquivo='own' WHERE id=$1",[own.rows[0].id])).rowCount,1);assert.equal((await as(11,'DELETE FROM documentos WHERE id=$1',[own.rows[0].id])).rowCount,1);
  }
 });
 await t.test('independent audit: policy inventory, unsupported Storage UPDATE/DELETE and B-to-A ownership',async()=>{
  const policies=(await q("SELECT schemaname,tablename,policyname,permissive,cmd FROM pg_policies WHERE (schemaname='public' AND tablename IN('documentos','ausencias_anexos')) OR (schemaname='storage' AND tablename='objects') ORDER BY schemaname,tablename,policyname")).rows;
  assert.equal(policies.filter(p=>p.tablename==='documentos').length,9);assert.equal(policies.filter(p=>p.schemaname==='storage').length,5);assert.equal(policies.filter(p=>p.permissive==='RESTRICTIVE').length,3);
  for(const [tipo,n] of [['colaborador',20],['viatura',30]]){
   const a='rh/'+tipo+'/'+id(n)+'/synthetic.pdf',b='rh/'+tipo+'/'+id(n+1)+'/synthetic.pdf';
   assert.equal((await as(11,'SELECT * FROM storage.objects WHERE name=$1',[a])).rowCount,0);
   await assert.rejects(as(11,"INSERT INTO storage.objects(bucket_id,name) VALUES('documentos',$1)",[a+'-B']),e=>e.code==='42501');
   assert.equal((await as(11,'UPDATE storage.objects SET name=$1 WHERE name=$2',[a+'-moved',b])).rowCount,0);assert.equal((await as(11,'DELETE FROM storage.objects WHERE name=$1',[b])).rowCount,0);
  }
  console.log('AUDIT_DOCUMENT_POLICIES '+JSON.stringify(policies));
 });
 await t.test('independent audit browser: real local PostgreSQL RLS responses, both companies, three viewports',async()=>{
  const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT);let queue=Promise.resolve();
  const server=createServer((req,res)=>{if(req.method==='GET'){res.setHeader('Content-Type','text/html');return res.end('<meta name="viewport" content="width=device-width,initial-scale=1"><pre id="result"></pre>');}
   queue=queue.then(async()=>{try{let body='';for await(const chunk of req)body+=chunk;const d=JSON.parse(body);assert.ok([10,11].includes(d.actor));assert.ok(['colaborador','viatura'].includes(d.tipo));assert.ok([1,2].includes(d.company));
    const entity=id((d.tipo==='colaborador'?20:30)+(d.company===2?1:0)),metadata=(await as(d.actor,'SELECT id,entidade_id FROM documentos WHERE entidade_tipo=$1 AND entidade_id=$2',[d.tipo,entity])).rows;
    const objects=(await as(d.actor,"SELECT id,name FROM storage.objects WHERE bucket_id='documentos' AND name=$1",['rh/'+d.tipo+'/'+entity+'/synthetic.pdf'])).rows;
    res.setHeader('Content-Type','application/json');res.end(JSON.stringify({metadata,objects}));
   }catch(e){res.writeHead(500);res.end(JSON.stringify({error:e.message}));}});
  });await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;const browser=await chromium.launch({channel:'msedge',headless:true});const errors=[];let checks=0;
  try{for(const width of [1440,820,390]){const page=await browser.newPage({viewport:{width,height:900}});page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',r=>new URL(r.request().url()).origin===origin?r.continue():r.abort());await page.goto(origin);
   for(const actor of [10,11])for(const tipo of ['colaborador','viatura'])for(const company of [1,2]){
    const r=await page.evaluate(async d=>{const r=await fetch('/read',{method:'POST',body:JSON.stringify(d)});const x=await r.json();document.querySelector('#result').textContent=JSON.stringify(x);return x;},{actor,tipo,company});
    assert.equal(r.metadata.length,actor===10&&company===1||actor===11&&company===2?1:0);assert.equal(r.objects.length,r.metadata.length);checks++;
   }await page.close();}assert.deepEqual(errors,[]);console.log('AUDIT_DOCUMENT_BROWSER '+JSON.stringify({checks,viewports:3,errors,source:'live local PostgreSQL RLS, not response mocks'}));
  }finally{await browser.close();await new Promise(r=>server.close(r));}
 });
}
