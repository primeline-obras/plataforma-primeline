import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:net';
import {actualCashFlowByMonth} from '../src/production-dashboard.js';
const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8');
const sql=fs.readFileSync(new URL('../supabase/encarregado_escopo_migration.sql',import.meta.url),'utf8');
const out='docs/auditorias/auditoria-global-noturna-20261014/FASE-2/';
const evidence=[];
const take=(a,b)=>{const s=app.indexOf(a),e=app.indexOf(b,s);assert.ok(s>=0&&e>s);return app.slice(s,e)};
const billingCode=take('async function submitBilling(event)','\nfunction openPaymentDialog');
const uuid=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
const record=(name,result,classification='FALHA DE PRODUTO REPRODUZIDA')=>evidence.push({name,classification,...result});
function fixture(stage,shared={drafts:[],links:[],blobs:[],documents:[]},pdf=true){
 const button={disabled:false},error={textContent:''},form={querySelector:s=>s==='button[type="submit"]'?button:error};
 const ctx={FormData:class{getAll(){return['auto-a']}get(k){return{numero_fatura:'SYNTHETIC',data_emissao_fatura:'2026-10-14',pdf:pdf?{size:12,name:'synthetic.pdf'}:null}[k]}},workDetails:{measurements:[{id:'auto-a',tipo:'contratual',valor_a_faturar:100,data_medicao:'2026-10-14'}],contract:{id:'contract-a'},billings:[],billingLinks:[]},selectedWorkId:'work-a',billingAutoReference:()=> 'Auto sintético',crypto:{randomUUID:()=> 'client-temp'},isSupabaseConfigured:true,PRIMELINE_COMPANY_ID:'company-a',works:[{id:'work-a'}],closeWorkflowDialog(){},renderWorkDetail(){},toast(){},uploadWorkflowPdf:async()=>{if(stage==='upload')throw Error('synthetic upload failure');shared.blobs.push('blob-a');return'blob-a'},supabase:async(path,options)=>{
   const body=JSON.parse(options.body);
   if(path==='faturacao?select=*'){
    if(stage==='insert')return{ok:false,json:async()=>({message:'synthetic insert failure'})};
    const row={id:'draft-'+shared.drafts.length,...body};shared.drafts.push(row);
    if(stage==='insert-response-lost')throw Error('synthetic response lost after commit');
    return{ok:true,json:async()=>[row]};
   }
   if(path==='faturacao_autos_medicao'){
    if(stage==='links'||shared.links.some(l=>l.auto_medicao_id===body[0].auto_medicao_id))return{ok:false};
    shared.links.push(...body);if(stage==='link-response-lost')throw Error('synthetic link response lost');return{ok:true};
   }
   if(path==='documentos'){if(stage==='metadata')return{ok:false};shared.documents.push(body);return{ok:true}}
   throw Error('unexpected request '+path);
 },Error,Number,String,JSON};
 vm.createContext(ctx);vm.runInContext(billingCode,ctx);
 return{ctx,shared,error,button,run:()=>ctx.submitBilling({preventDefault(){},currentTarget:form})};
}
for(const [stage,expected] of [['insert',[0,0,0,0]],['links',[1,0,0,0]],['upload',[1,1,0,0]],['metadata',[1,1,1,0]],['none',[1,1,1,1]],['insert-response-lost',[1,0,0,0]],['link-response-lost',[1,1,0,0]]]){
 test('billing actual handler: '+stage,async()=>{const f=fixture(stage);await f.run();const counts=['drafts','links','blobs','documents'].map(k=>f.shared[k].length);assert.deepEqual(counts,expected);assert.equal(f.button.disabled,false);assert.equal(f.ctx.workDetails.billings.length,stage==='none'?1:0);record('billing:'+stage,{counts,ui_has_invoice:f.ctx.workDetails.billings.length,error:f.error.textContent},stage==='insert'||stage==='none'?'CONTROLO POSITIVO/NEGATIVO':'FALHA DE ATOMICIDADE REPRODUZIDA');});
}
test('billing concurrent attempts: unique auto model leaves losing draft',async()=>{const shared={drafts:[],links:[],blobs:[],documents:[]},a=fixture('none',shared,false),b=fixture('none',shared,false);await Promise.all([a.run(),b.run()]);assert.equal(shared.drafts.length,2);assert.equal(shared.links.length,1);record('billing:concurrency',{drafts:2,links:1,unlinked_drafts:1,limit:'HTTP fixture enforces repository UNIQUE(auto_medicao_id); hosted catalog not verified'});});
test('billing retry after ambiguous insert does not recover original',async()=>{const a=fixture('insert-response-lost',undefined,false);await a.run();const b=fixture('none',a.shared,false);await b.run();assert.equal(a.shared.drafts.length,2);assert.equal(a.shared.links.length,1);record('billing:ambiguous-retry',{drafts:2,links:1});});

test('supplier actual form: item failure still clears form and presents saved invoice',async()=>{
 const from=app.indexOf('form.addEventListener("submit", async event => {'),to=app.indexOf('\n$("#invoice-list").addEventListener("click"',from);assert.ok(from>=0&&to>from);
 const code=app.slice(from,to),saved=[],messages=[],submit={disabled:false,firstChild:{textContent:''}},nodes=new Map();let handler;
 const form={addEventListener:(name,fn)=>{handler=fn},querySelector:()=>submit,obra_id:{value:'work-a'}};
 const ctx={form,FormData:class{*[Symbol.iterator](){yield* Object.entries({obra_id:'work-a',tipo_origem:'material',fornecedor_id:'supplier-a',numero_doc:'SYNTHETIC',valor:'100',condicao_pagamento:'pronto',data_fatura:'2026-10-14'})}},canInsertInvoices:()=>true,editingInvoiceId:null,invoices:[],collectMaterialItems:()=>[{designacao:'SYNTHETIC',unidade:'un',quantidade:1,preco_unitario:100}],materialItemDatabasePayload:x=>x,findDuplicateInvoice:async()=>null,isSupabaseConfigured:true,selectedPdf:null,allowedViews:()=>new Set(),extractedMaterialItems:[],extractedMaterialItemsApplied:false,localPdfUrl:'',works:[{id:'work-a'}],toast:(msg)=>messages.push(msg),endExtractedInvoiceReview(){},stopInvoiceEditing(){},renderSubcontracts(){},renderInvoices(){},icon:()=>'', $:s=>{if(!nodes.has(s))nodes.set(s,{});return nodes.get(s)},supabase:async(path,opts)=>{if(path==='faturas'){const row={id:'invoice-a',...JSON.parse(opts.body)};saved.push(row);return{ok:true,json:async()=>[row]}}if(path==='faturas_itens')return{ok:false,text:async()=> 'synthetic item failure'};throw Error(path)},Number,JSON,Date};
 vm.createContext(ctx);vm.runInContext(code,ctx);await handler({preventDefault(){}});
 assert.equal(saved.length,1);assert.equal(ctx.invoices.length,1);assert.equal(ctx.extractedMaterialItems.length,0);assert.match(messages.join(' '),/artigos não foram guardados/);record('supplier:item-failure',{invoice_committed:1,items_committed:0,form_cleared:true});
});

const bin=process.env.QUADRO_PG_BIN,deps=process.env.QUADRO_TEST_DEPS;
test('financial semantics in disposable PostgreSQL',{skip:!bin||!deps?'Local PG runtime unavailable':false,timeout:90000},async t=>{
 const require=createRequire(import.meta.url),{Client}=require(join(deps,'pg')),folder=fs.mkdtempSync(join(tmpdir(),'night-phase2-finance-')),data=join(folder,'data'),srv=createServer();await new Promise(r=>srv.listen(0,'127.0.0.1',r));const port=srv.address().port;await new Promise(r=>srv.close(r));
 const run=(name,args)=>{const p=spawnSync(join(bin,name+'.exe'),args,{windowsHide:true,timeout:30000,encoding:'utf8',stdio:name==='pg_ctl'?'ignore':'pipe'});assert.equal(p.status,0,name+': '+(p.stderr||p.error?.message||''))};
 run('initdb',['-D',data,'-U','postgres','--auth-host=trust','--auth-local=trust','--encoding=UTF8','--no-locale']);run('pg_ctl',['-D',data,'-l',join(folder,'pg.log'),'-o','-h 127.0.0.1 -p '+port+' -F','-w','start']);
 const c=new Client({host:'127.0.0.1',port,user:'postgres',database:'postgres'}),c2=new Client({host:'127.0.0.1',port,user:'postgres',database:'postgres'});
 try{await c.connect();await c2.connect();const q=(s,p=[])=>c.query(s,p);
 await q("CREATE TABLE faturacao(id uuid PRIMARY KEY,obra_id uuid,valor numeric,estado text default 'emitida',estado_aprovacao text,estado_pagamento text,pago_por uuid,data_pagamento date,data_recebimento date,valor_recebido numeric); CREATE TABLE faturacao_recebimentos(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),faturacao_id uuid REFERENCES faturacao(id),request_id text UNIQUE,data_recebimento date,valor numeric,registado_por uuid); CREATE FUNCTION fn_autorizacao_sessao_ativa() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$; CREATE FUNCTION fn_e_financeiro() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;CREATE FUNCTION fn_utilizador_atual_id() RETURNS uuid LANGUAGE sql AS $$ SELECT '00000000-0000-4000-8000-000000000001'::uuid $$;CREATE FUNCTION fn_financeiro_autorizar_obra(uuid,boolean) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;");
 for(const name of ['fn_marcar_faturacao_auto_paga','fn_registar_recebimento_parcial']){const re=new RegExp('CREATE OR REPLACE FUNCTION public\\.'+name+'[\\s\\S]*?\\$function\\$;');const def=sql.match(re);assert.ok(def);await q(def[0]);}
 let n=100;const invoice=async()=>{const id=uuid(++n);await q("INSERT INTO faturacao(id,obra_id,valor,estado_aprovacao,estado_pagamento) VALUES($1,$2,1000,'aprovado','por_pagar')",[id,uuid(2)]);return id};
 const old=(id,value,date='2026-10-14')=>q('SELECT to_jsonb(fn_marcar_faturacao_auto_paga($1,$2,$3)) v',[id,date,value]);
 const partial=(id,value,key,expected,date='2026-10-14',client=c)=>client.query('SELECT fn_registar_recebimento_parcial(1,$1,$2,$3,$4,$5) v',[id,date,value,key,expected]);
 for(const value of [0,-1,null])await t.test('old RPC rejects '+value,async()=>{const id=await invoice();await assert.rejects(old(id,value),/superior a zero/);assert.equal((await q('SELECT estado_pagamento FROM faturacao WHERE id=$1',[id])).rows[0].estado_pagamento,'por_pagar');record('old:invalid:'+value,{unchanged:true},'CONTROLO NEGATIVO');});
 for(const value of [100,1000,1100])await t.test('old RPC amount '+value,async()=>{const id=await invoice(),r=(await old(id,value)).rows[0].v;assert.equal(r.estado_pagamento,'pago');assert.equal(Number(r.valor_recebido),value);assert.equal((await q('SELECT count(*)::int n FROM faturacao_recebimentos WHERE faturacao_id=$1',[id])).rows[0].n,0);record('old:amount:'+value,{invoice:1000,received:value,status:r.estado_pagamento,ledger:0},value===1000?'CONTROLO INTEGRAL':'INCOERÊNCIA MONETÁRIA REPRODUZIDA');});
 await t.test('existing partial RPC: partial, replay, conflict, completion',async()=>{const id=await invoice();const a=(await partial(id,100,'partial-a',0)).rows[0].v.billing;assert.equal(a.estado_pagamento,'por_pagar');await partial(id,100,'partial-a',0);assert.equal((await q('SELECT count(*)::int n FROM faturacao_recebimentos WHERE faturacao_id=$1',[id])).rows[0].n,1);await assert.rejects(partial(id,101,'partial-a',0),/IDEMPOTENCY_CONFLICT/);await assert.rejects(partial(id,901,'partial-b',100),/AMOUNT_EXCEEDS_BALANCE/);const b=(await partial(id,900,'partial-b',100)).rows[0].v.billing;assert.equal(b.estado_pagamento,'pago');assert.equal(Number(b.valor_recebido),1000);record('partial:contract',{partial_status:a.estado_pagamento,full_status:b.estado_pagamento,replay_count:1,excess_rejected:true},'CONTROLO POSITIVO DO MECANISMO EXISTENTE');});
 await t.test('existing partial RPC: optimistic concurrency rejects stale total',async()=>{const id=await invoice();const results=await Promise.allSettled([partial(id,100,'concurrent-a',0),partial(id,100,'concurrent-b',0,'2026-10-14',c2)]);assert.equal(results.filter(x=>x.status==='fulfilled').length,1);assert.match(results.find(x=>x.status==='rejected').reason.message,/STALE_REVISION/);assert.equal(Number((await q('SELECT valor_recebido FROM faturacao WHERE id=$1',[id])).rows[0].valor_recebido),100);record('partial:concurrency',{accepted:1,stale:1,received:100},'CONTROLO POSITIVO DE CONCORRÊNCIA');});
 await t.test('mixing APIs overwrites prior receipt and diverges from ledger',async()=>{const id=await invoice();await partial(id,100,'mixed-a',0);const r=(await old(id,900,'2026-11-14')).rows[0].v;const ledger=Number((await q('SELECT sum(valor) v FROM faturacao_recebimentos WHERE faturacao_id=$1',[id])).rows[0].v);assert.equal(Number(r.valor_recebido),900);assert.equal(ledger,100);assert.equal(r.estado_pagamento,'pago');record('mixed:apis',{document_received:900,ledger_received:100,actual_receipts_requested:1000,status:'pago'});});
 await t.test('monthly consumer moves cumulative receipts to final month',async()=>{const id=await invoice();await partial(id,100,'monthly-a',0,'2026-10-14');const final=(await partial(id,900,'monthly-b',100,'2026-11-14')).rows[0].v.billing;const r=actualCashFlowByMonth({billings:[final]});assert.equal(r.has('2026-10'),false);assert.equal(r.get('2026-11').incoming,1000);record('monthly:cumulative',{expected_october:100,expected_november:900,actual_october:0,actual_november:1000});});
 }finally{await Promise.allSettled([c.end(),c2.end()]);run('pg_ctl',['-D',data,'-m','fast','-w','stop'])}
});
test.after(()=>fs.writeFileSync(out+'EVIDENCIAS-FINANCEIRO.json',JSON.stringify({synthetic_only:true,production_access:false,authorization:'helpers allowed synthetically; monetary semantics only, not ACL proof',evidence},null,2)+'\n'));
