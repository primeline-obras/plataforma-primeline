// Teste isolado do módulo com API simulada; não abre a produção.
// RH_TEST_DEPS: diretório com playwright e xlsx.full.min.js; RH_SCREENSHOTS: saída.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const deps=process.env.RH_TEST_DEPS;
if(!deps) throw new Error('Defina RH_TEST_DEPS com as dependências de teste.');
const {chromium}=createRequire(deps+'/package.json')('playwright');
const repo=path.resolve(new URL('..',import.meta.url).pathname);
const html=`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-identity-final.css">
<script src="/xlsx.js"></script>
<div id="workflow-dialog" class="dialog-backdrop" hidden><section class="work-dialog-card workflow-dialog-card">
<div class="panel-title"><span id="workflow-dialog-title"></span></div><div id="workflow-dialog-content"></div></section></div>`;
const server=http.createServer((req,res)=>{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/'){res.setHeader('Content-Type','text/html');res.end(html);return;}
  const target=url.pathname==='/xlsx.js'?deps+'/xlsx.full.min.js':path.join(repo,url.pathname);
  if(!target.startsWith(repo+'/')&&target!==deps+'/xlsx.full.min.js'){res.writeHead(403).end();return;}
  try{res.setHeader('Content-Type',target.endsWith('.css')?'text/css':'text/javascript');res.end(fs.readFileSync(target));}catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try {
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1366,height:900}});
  await page.route('**/*',route=>route.request().url().startsWith('http://127.0.0.1:')?route.continue():route.abort());
  await page.goto('http://127.0.0.1:'+server.address().port);
  await page.evaluate(async()=>{
    const {createRhCadastro}=await import('/src/rh-cadastro.js');
    window.fixture={versao:'v1',colaborador:{id:'30000000-0000-0000-0000-000000000001',nome:'Colaborador de teste',funcao:'Pedreiro',
      email:'teste@example.com',data_admissao:'2026-01-01',codigo_rh:'001',seguro_ok:true,observacoes:'Dados fictícios para validação do formulário.'},
      niss:'00123456789',contratos:[{tipo_contrato:'a_prazo',data_inicio:'2026-01-01',data_fim_prevista:'2026-12-31',estado:'ativo'}]};
    window.calls=[];
    window.rh=createRhCadastro({
      api:async(p,options)=>{
        const body=JSON.parse(options.body);calls.push([p,body]);let data;
        if(p.endsWith('fn_rh_consultar'))data=[fixture];
        else if(p.endsWith('fn_rh_importar')){data={erros:0,confirmado:body.p_confirmar,linhas:body.p_linhas.map(row=>({id:row.id,ok:true,alterado:row.campos.email!==fixture.colaborador.email}))};if(body.p_confirmar)fixture.colaborador.email=body.p_linhas[0].campos.email;}
        else data={alterado:true};
        return {ok:true,json:async()=>structuredClone(data)};
      },
      configured:()=>true,canManage:()=>true,isManagement:()=>true,works:()=>[],
      refresh:async()=>{},toast:(...args)=>{window.lastToast=args;}
    });
    await rh.open({id:fixture.colaborador.id,nome:fixture.colaborador.nome});
  });
  assert.equal(await page.locator('[name=email]').inputValue(),'teste@example.com');
  assert.equal(await page.locator('#rh-form button[type=submit]').count(),1);
  const overflow=()=>page.evaluate(()=>[...document.querySelectorAll('#rh-form input,#rh-form select,#rh-form textarea')].filter(e=>{const r=e.getBoundingClientRect();return r.left<0||r.right>innerWidth;}).length);
  assert.equal(await overflow(),0);
  if(process.env.RH_SCREENSHOTS)await page.screenshot({path:process.env.RH_SCREENSHOTS+'/rh-desktop.png'});
  await page.setViewportSize({width:390,height:844});
  assert.equal(await overflow(),0);
  if(process.env.RH_SCREENSHOTS)await page.screenshot({path:process.env.RH_SCREENSHOTS+'/rh-mobile.png'});
  await page.locator('[name=email]').fill('alterado@example.com');
  await page.locator('#rh-form button[type=submit]').click();
  await page.waitForFunction(()=>document.querySelector('#workflow-dialog').hidden);
  assert.equal(await page.evaluate(()=>calls.filter(([p])=>p.endsWith('fn_rh_guardar')).length),1);
  await page.setViewportSize({width:1366,height:900});
  await page.evaluate(()=>rh.openImport());
  const download=page.waitForEvent('download');
  await page.locator('[data-rh-template]').click();
  assert.equal((await download).suggestedFilename(),'cadastro-rh.xlsx');
  const bytes=await page.evaluate(async()=>{
    const {RH_FIELDS}=await import('/src/rh-cadastro.js');
    const book=XLSX.utils.book_new(),flat={...fixture.colaborador,niss:fixture.niss,...fixture.contratos[0]};
    flat.email='novo@example.com';
    XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet([['id','versao',...RH_FIELDS.map(([k])=>k)],
      [fixture.colaborador.id,fixture.versao,...RH_FIELDS.map(([k,,t])=>flat[k]==null?'':t==='boolean'?(flat[k]?'Sim':'Não'):flat[k])]]),'Colaboradores');
    return Array.from(new Uint8Array(XLSX.write(book,{type:'array',bookType:'xlsx'})));
  });
  const file={name:'rh-teste.xlsx',mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',buffer:Buffer.from(bytes)};
  await page.locator('[data-rh-file]').setInputFiles(file);
  await page.waitForFunction(()=>!document.querySelector('[data-rh-confirm]').disabled);
  assert.match(await page.locator('[data-rh-preview]').textContent(),/1 a atualizar/);
  if(process.env.RH_SCREENSHOTS)await page.screenshot({path:process.env.RH_SCREENSHOTS+'/rh-importacao.png'});
  await page.locator('[data-rh-confirm]').click();
  await page.waitForFunction(()=>document.querySelector('[data-rh-preview]').textContent.includes('Guardado: 1'));
  await page.locator('[data-rh-file]').setInputFiles(file);
  await page.waitForFunction(()=>document.querySelector('[data-rh-preview]').textContent.includes('0 a atualizar'));
  assert.equal(await page.locator('[data-rh-confirm]').isDisabled(),true);
  console.log('Browser OK: preenchimento, guardar único, 1366px/390px sem overflow, Excel real, preview, confirmação e reimportação sem alterações (API simulada).');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
