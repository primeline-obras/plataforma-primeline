import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLANNING_PLAYWRIGHT);
const app=fs.readFileSync(new URL('../src/app.js',import.meta.url),'utf8'),dashboard=fs.readFileSync(new URL('../src/production-dashboard.js',import.meta.url),'utf8');
const out='docs/auditorias/auditoria-global-noturna-20261014/FASE-2/';
const extract=(source,start,end)=>{const a=source.indexOf(start),b=source.indexOf(end,a);assert.ok(a>=0&&b>a,start);return source.slice(a,b)};
const snippets={
 measurements:extract(app,'function renderMeasurementsTab(work)','\nconst WORK_DOCUMENT_TYPES'),
 detail:extract(app,'function renderWorkDetail(work)','\nasync function advanceInvoiceFlow'),
 paid:extract(app,'function paidFinanceRow(invoice)','\nfunction invoiceJourneyState'),
 pending:extract(app,'function renderInvoices()','\nasync function openInvoiceDetail'),
 toast:extract(app,'function toast(message','\n// Confirmação partilhada'),
 history:extract(app,'function invoiceTraceEvents(invoice)','\nfunction renderInvoiceTrace'),
 documents:extract(app,'function renderWorkDocumentsTab()','\nfunction safetyPersonName'),
 alerts:extract(dashboard,'  function renderNotificationDrawer()','\n  async function resolveAlert'),
};
const proofs=[];let browser;
test.before(async()=>{browser=await chromium.launch({headless:true,executablePath:process.env.PLANNING_CHROMIUM_EXE||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'})});
const cases=[['paid','supplier',true],['paid','number',true],['pending','supplier',true],['pending','number',true],['toast','message',true],['history','comment',false],['documents','filename',false],['alerts','description',false],['measurements','number',true],['measurements','auto-number',true],['measurements','error',true],['detail','work-name',true],['detail','client',true],['detail','address',true],['detail','error',true]];
for(const [name,field,vulnerable] of cases){
 test('actual browser renderer '+name+':'+field+(vulnerable?' — reproduces unsafe HTML':' — safe control'),async()=>{
 const page=await browser.newPage();let requests=0;page.on('request',()=>requests++);await page.route('**/*',route=>route.abort());await page.setContent('<div id="work-detail"></div><div id="card"></div><input id="search"><span id="count"></span><div id="invoice-list"></div><div id="toast"></div><div id="notification-drawer-list"></div>');
 const result=await page.evaluate(({code,name,field})=>{
 const probe='<img data-phase2-probe onerror="window.__phase2=true">';
 const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
 Object.assign(window,{$:s=>document.querySelector(s),escapeHtml:esc,safeText:esc,__phase2:false,
 suppliers:[{id:'supplier-a',nome:field==='supplier'?probe:'Fornecedor sintético'}],works:[{id:'work-a',nome:'Obra sintética',numero:999}],
 invoiceAttachments:[],invoiceGuides:[],currentFilter:'all',canPayInvoices:()=>false,canApproveInvoices:()=>false,canEditPendingInvoice:()=>false,canReturnInvoiceToAdministrative:()=>false,invoiceFlowState:()=> 'recebida',INVOICE_FLOW:['recebida'],INVOICE_FLOW_LABELS:{recebida:'Recebida'},invoiceSubcontractControl:()=>'',icon:()=>'',
 euro:new Intl.NumberFormat('pt-PT',{style:'currency',currency:'EUR'}),prettyDate:new Intl.DateTimeFormat('pt-PT'),traceMoment:()=> 'Data sintética',setTimeout:()=>0,
 });
 const invoice={id:'invoice-a',fornecedor_id:'supplier-a',obra_id:'work-a',numero_doc:field==='number'?probe:'DOC SYNTHETIC',valor:100,data_fatura:'2026-10-14',data_pagamento:'2026-10-14',tipo_origem:'material',eventos:[{tipo:'paga',observacao:probe,utilizador_nome:probe}]};window.invoices=[invoice];
 window.workDetails={workDocuments:[{id:'doc-a',tipo:'outro',nome_arquivo:probe,arquivo_url:'work-a/synthetic.pdf',numero_documento:probe,revisao:probe,destinatarios:probe}],documentUsers:{},canEditDocuments:false};window.WORK_DOCUMENT_TYPES=[['outro','Outro']];window.workDocumentExtension=()=> 'pdf';window.canPreviewWorkDocument=()=>false;
 window.workDetails.measurements=[{id:'auto-a',numero_auto:field==='auto-number'?probe:'AUTO SYNTHETIC',mes_referencia:'2026-10-01',estado:'aprovado_cliente',tipo:'contratual',valor_a_faturar:100}];window.workDetails.billings=[{id:'billing-a',numero_fatura:field==='number'?probe:'SYNTHETIC',estado_aprovacao:'aprovado',estado_pagamento:'por_pagar',valor:1000,valor_recebido:100}];window.workDetails.billingError=field==='error'?probe:'';window.workDetails.error=field==='error'?probe:'';
 window.totalClientBilling=()=>100;window.billingForMeasurement=()=>window.workDetails.billings[0];window.documentFor=()=>null;window.billingLines=()=>[];window.measurementStatusLabel=()=> 'Aprovado';window.canEditWork=()=>false;window.formatOptionalDate=x=>x||'—';window.isFinancial=()=>true;window.selectedWorkTab='summary';window.renderWorkTab=()=>'';window.workSituationLabel=()=> 'Em curso';window.works[0].nome=field==='work-name'?probe:'Obra sintética';window.works[0].cliente=field==='client'?probe:'Cliente sintético';window.works[0].morada=field==='address'?probe:'Morada sintética';
 window.overviewState={alerts:[{id:'alert-a',titulo:probe,descricao:probe,tipo:'outro'}]};window.groupAlertsByTopic=a=>[{topic:'other',label:'Grupo',alerts:a}];window.alertDestination=()=>({view:'team'});window.alertSeverity=()=> 'warning';window.isMeetingInformation=()=>false;window.safeDate=x=>new Date(x);
 const call={measurements:'document.querySelector("#card").innerHTML=renderMeasurementsTab(works[0]);',detail:'renderWorkDetail(works[0]);',paid:'document.querySelector("#card").innerHTML=paidFinanceRow(invoice);',pending:'renderInvoices();',toast:'toast(probe);',history:'document.querySelector("#card").innerHTML=invoiceTraceEvents(invoice);',documents:'document.querySelector("#card").innerHTML=renderWorkDocumentsTab();',alerts:'renderNotificationDrawer();'}[name];
 new Function('invoice','probe',code+';'+call)(invoice,probe);
 const element=document.querySelector('[data-phase2-probe]');element?.dispatchEvent(new Event('error'));
 return{element:!!element,executed:window.__phase2,text_preserved:document.body.textContent.includes(probe),origin:location.origin};
 },{code:snippets[name],name,field});
 assert.equal(result.element,vulnerable);assert.equal(result.executed,vulnerable);assert.equal(result.origin,'null');assert.equal(requests,0);if(!vulnerable)assert.equal(result.text_preserved,true);
 proofs.push({renderer:name,field,classification:vulnerable?'FALHA DE SEGURANÇA REPRODUZIDA':'CONTROLO PROTEGIDO; NÃO PROVA TODO O MÓDULO',network_requests:requests,...result});await page.close();
 });
}
test('legitimate characters remain literal in existing escape helper',async()=>{const page=await browser.newPage();await page.route('**/*',route=>route.abort());const code=extract(app,'function safeText(value)','\nfunction workDocumentLabel');const original='João & Filhos <revisão> "A" \'B\'';const value=await page.evaluate(({code,original})=>{const el=document.createElement('p');el.innerHTML=new Function('value',code+';return safeText(value);')(original);return el.textContent},{code,original});assert.equal(value,original);proofs.push({renderer:'safeText',classification:'APRESENTAÇÃO LEGÍTIMA PRESERVADA',roundtrip:true});await page.close()});
test.after(async()=>{await browser?.close();fs.writeFileSync(out+'EVIDENCIAS-HTML.json',JSON.stringify({synthetic_only:true,production_access:false,proofs},null,2)+'\n')});
