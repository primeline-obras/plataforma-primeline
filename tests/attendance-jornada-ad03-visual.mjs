import fs from 'node:fs';import path from 'node:path';import http from 'node:http';import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLANNING_PLAYWRIGHT||'C:/Users/conta/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=process.cwd(),out=path.join(root,'docs/prototipos/ad03-capturas');fs.mkdirSync(out,{recursive:true});
const server=http.createServer((req,res)=>{const p=path.resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));if(!p.startsWith(root+path.sep)){res.writeHead(403);return res.end();}if(!fs.existsSync(p)){res.writeHead(404);return res.end();}res.setHeader('Content-Type',p.endsWith('.css')?'text/css':p.endsWith('.html')?'text/html':'application/octet-stream');res.end(fs.readFileSync(p));});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({channel:'msedge',headless:true}),errors=[],results=[];
try{
 for(const [name,width,height] of [['desktop',1440,1000],['tablet-paisagem',1024,768],['tablet-retrato',768,1024]]){
  const page=await browser.newPage({viewport:{width,height}});page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://fonts.googleapis.com/**',r=>r.fulfill({body:'',contentType:'text/css'}));
  await page.goto(base+'/docs/prototipos/folha-jornada-ad03.html',{waitUntil:'networkidle'});
  for(let i=0;i<8;i++){
   await page.locator('.tabs button').nth(i).click();await page.screenshot({path:path.join(out,name+'-'+(i+1)+'.png'),fullPage:true});
   const visible=page.locator('.state.active');if(!await visible.isVisible())throw Error('state hidden');
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);if(overflow)throw Error('horizontal overflow '+name+' '+i);
   results.push({viewport:name,state:i+1,pass:true});
  }
  await page.locator('.tabs button').nth(1).click();await page.getByRole('button',{name:'SELECIONAR',exact:true}).nth(1).click();
  if(!await page.getByRole('heading',{name:'Equipa Técnica · semana habitual'}).isVisible())throw Error('model switch');
  await page.screenshot({path:path.join(out,name+'-semana-tecnica.png'),fullPage:true});
  await page.locator('.tabs button').nth(3).click();await page.getByRole('button',{name:'REVER E CONFIRMAR 2 PESSOAS'}).click();if(!await page.locator('.state.active output').isVisible())throw Error('preview');
  await page.locator('.tabs button').nth(7).click();if(await page.locator('.state.active input,.state.active button').count())throw Error('own read only');
  await page.close();
 }
 if(errors.length)throw Error(errors.join('\n'));
 fs.writeFileSync(path.join(out,'resultado.json'),JSON.stringify({screens:results.length,additionalTechnicalScreens:3,viewports:3,errors,results},null,2));console.log('AD03 visual: 24 estados/viewport + 3 capturas técnicas PASS; seleção, preview e consulta PASS; sem overflow/erros JS.');
}finally{await browser.close();await new Promise(r=>server.close(r));}
