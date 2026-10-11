// All HTTP responses and financial writes are synthetic and intercepted locally.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const browser=await chromium.launch({channel:process.env.PLANNING_BROWSER||'msedge',headless:true});
const output=process.env.FINANCE_SCREENSHOT_DIR;
let groups=0;
try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(['/src/financial-expenses-import.js','/src/financial-map.js'].includes(u.pathname))return route.fulfill({contentType:'text/javascript',body:await readFile(new URL('..'+u.pathname,import.meta.url),'utf8')});
  if(u.pathname!=='/')return route.abort();
  return route.fulfill({contentType:'text/html',body:`<meta charset="utf-8"><style>body{font:16px system-ui;background:#f4f1eb;color:#26332d}button,input{font:inherit;padding:10px;border:1px solid #c9c5bc;border-radius:4px}button{cursor:pointer;background:#f3f0e9}h2,h3{font-size:20px}aside{width:230px;padding:25px;background:#263b31;color:white;height:90vh}</style><aside>PRIMELINE GO<br><br>Financeiro<br>Dados sintéticos</aside><script type="module">
   import {createFinancialExpensesImport} from '/src/financial-expenses-import.js';
   import {createFinancialMapModule} from '/src/financial-map.js';
   window.profile={id:'synthetic-actor',empresa_id:'synthetic-company',funcao:'gestao_plataforma'};window.calls=[];window.mode='valid';window.delay=false;window.release=null;
   const header=['Obra','JAN','FEV','MAR','ABR','MAI','JUN','JUL','AGO','SET','OUT','NOV','DEZ'];
   window.XLSX={read:()=>({SheetNames:['Mapa Financeiro'],Sheets:{'Mapa Financeiro':{}}}),utils:{sheet_to_json:()=>[header,['Despesas Sede',25],['Despesas Armazém',35]]}};
   const api=async(path,opts)=>{if(!opts?.body){calls.push({path,data:{}});return Response.json([]);}const d=JSON.parse(opts.body);calls.push({path,data:d});if(delay)await new Promise(r=>release=r);
    if(path.endsWith('reverter_v1'))return Response.json({committed:d.p_confirmar,preview_token:'reverse-token',objetos:4,reversed:d.p_confirmar});
    if(mode==='error')return Response.json({code:'40001',message:'STALE_PREVIEW'},{status:409});
    return Response.json({request_id:d.p_request_id,committed:d.p_confirmar,validas:mode==='invalid'?1:2,invalidas:mode==='invalid'?1:0,duplicadas:0,preview_token:'synthetic-token',linhas:d.p_linhas.map((r,i)=>({estado:mode==='invalid'&&i===1?'invalid':'valid',erros:mode==='invalid'&&i===1?['Mês 1: valor inválido.']:[]}))});
   };
   window.module=createFinancialExpensesImport({supabase:api,getProfile:()=>profile,isConfigured:true,onComplete:()=>{}});
   window.openImport=()=>module.open({year:2026,works:[]});openImport();
   window.integration=async()=>{module.close();const root=document.createElement('main');document.body.append(root);const map=createFinancialMapModule({root,supabase:api,isConfigured:true,getWorks:()=>[],getProfile:()=>profile,euro:{format:n=>Number(n).toFixed(2)},toast:m=>{throw Error(m)},onImportExcel:()=>{throw Error('Shared importer must not be used')}});await map.show();};
  </script>`});
 });
 const upload=async()=>{await page.locator('[data-file]').setInputFiles({name:'sintetico.xlsx',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',buffer:Buffer.from('mock')});await page.locator('[data-summary]').waitFor();};
 const shot=async name=>{if(output){await mkdir(output,{recursive:true});await page.screenshot({path:output+'/'+name+'.png',fullPage:true});}};
 await page.goto('http://localhost/');await upload();
 assert.equal(await page.locator('[data-summary]').innerText(),'VÁLIDAS\n2\nINVÁLIDAS\n0\nDUPLICADAS\n0');await shot('01-preview-desktop');
 assert.equal((await page.evaluate(()=>calls)).filter(c=>c.data.p_confirmar).length,0);groups++;
 await page.locator('[data-ask]').click();await page.locator('[data-confirm]').waitFor();await shot('02-confirmacao-desktop');
 await page.locator('[data-back]').click();assert.equal((await page.evaluate(()=>calls)).length,1);groups++;
 await page.locator('[data-ask]').click();await page.locator('[data-commit]').click();await page.locator('[data-result]').waitFor();await shot('03-resultado-desktop');
 const calls=await page.evaluate(()=>calls);assert.equal(calls[0].data.p_request_id,calls[1].data.p_request_id);assert.equal(calls[1].data.p_preview_token,'synthetic-token');groups++;
 await page.locator('[data-reason]').fill('Importação sintética para teste');await page.locator('[data-reverse-preview]').click();await page.locator('[data-reverse-commit]').waitFor();
 assert.equal((await page.evaluate(()=>calls)).at(-1).data.p_confirmar,false);await page.locator('[data-reverse-commit]').click();await page.locator('[data-reversed]').waitFor();groups++;
 await page.evaluate(()=>{module.close();mode='invalid';openImport();});await upload();assert.equal(await page.locator('[data-ask]').count(),0);await shot('04-erros-desktop');groups++;
 await page.locator('[data-close]').click();assert.equal(await page.locator('[data-financial-expenses]').count(),0);groups++;
 await page.evaluate(()=>{mode='valid';openImport();});await upload();await page.evaluate(()=>profile={id:'enc-synthetic',empresa_id:'synthetic-company',funcao:'encarregado'});await page.waitForFunction(()=>!document.querySelector('[data-financial-expenses]'));groups++;
 await page.evaluate(()=>{profile={id:'new-actor',empresa_id:'synthetic-company',funcao:'financeiro'};openImport();delay=true;});
 await page.locator('[data-file]').setInputFiles({name:'sintetico.xlsx',mimeType:'application/octet-stream',buffer:Buffer.from('mock')});
 await page.waitForFunction(()=>!!release);await page.evaluate(()=>{profile={id:'enc-synthetic',empresa_id:'synthetic-company',funcao:'encarregado'};release();});await page.waitForFunction(()=>!document.querySelector('[data-financial-expenses]'));groups++;
 await page.evaluate(()=>{profile={id:'finance-synthetic',empresa_id:'synthetic-company',funcao:'administrativo'};try{openImport();return false;}catch{return true;}}).then(result=>assert.equal(result,true));groups++;
 await page.goto('http://localhost/');await page.evaluate(()=>integration());await page.locator('[data-import-financial-map]').click();await upload();assert.equal((await page.evaluate(()=>calls)).filter(c=>c.path==='rpc/fn_despesas_gerais_importar_v1').length,1);groups++;
 assert.deepEqual(errors,[]);console.log('PASS '+groups+' grupos browser Financeiro; console limpo; HTTP exclusivamente sintético');
}finally{await browser.close();}
