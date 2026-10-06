// Local synthetic DOM verification of the four real confirmation prefixes.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const read=p=>readFile(new URL('../src/'+p,import.meta.url),'utf8');
const [suppliers,costs,map,adapter,styles]=await Promise.all(['subcontractors.js','production-dashboard.js','management-map.js','platform-dialogs.js','styles.css'].map(read));
const prefixes=[...suppliers.matchAll(/const confirmed = await platformConfirm\([\s\S]*?if \(!confirmed\) return;/g)].map(m=>m[0]);
prefixes.push(costs.slice(costs.indexOf('async function confirmSubcontractCost(')).split('button.disabled = true;')[0].split('{').slice(1).join('{'));
prefixes.push(map.slice(map.indexOf('async function confirmImport() {')+'async function confirmImport() {'.length).split('state.importing = true;')[0]);
const server=createServer((req,res)=>{
  if(req.url==='/adapter.js'){res.setHeader('Content-Type','text/javascript');return res.end(adapter);}
  if(req.url==='/styles.css'){res.setHeader('Content-Type','text/css');return res.end(styles);}
  res.setHeader('Content-Type','text/html');res.end('<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/styles.css"><div id="root">TESTE SINTÉTICO</div>');
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({channel:'msedge',headless:true});
const errors=[];let groups=0;
try{
  for(const [label,width,height] of [['desktop',1440,900],['tablet',768,1024],['mobile',390,844]]){
    const page=await browser.newPage({viewport:{width,height}});
    page.on('pageerror',e=>errors.push(e.message));
    page.on('dialog',()=>errors.push('Diálogo nativo inesperado'));
    await page.goto(`http://127.0.0.1:${server.address().port}`);
    for(const body of prefixes){
      await page.evaluate(async body=>{
        const {platformConfirm}=await import('/adapter.js');
        // Import the real adapter; the appended callback is a synthetic counter.
        window.writes=0;
        const fn=new Function('platformConfirm','source','target','supplier','state','meetingState','canAdjustWorkCosts','write',`return (async()=>{${body};write();})()`);
        window.invoke=()=>fn(platformConfirm,{nome:'Sintético'},{nome:'Destino'},{nome:'Sintético'},{mergePreview:{total_referencias:0},preview:{criar:1,duplicados:0},importing:false},{},()=>true,()=>window.writes++);
        window.operation=window.invoke();
      },body);
      await page.locator('dialog[open]').waitFor();
      assert.equal(await page.evaluate(()=>window.writes),0,label+' pending');
      await page.locator('[data-dialog-cancel]').click();
      await page.evaluate(()=>window.operation);
      assert.equal(await page.evaluate(()=>window.writes),0,label+' cancelled');
      await page.evaluate(()=>{window.operation=window.invoke();});
      await page.locator('dialog[open]').waitFor();
      await page.locator('dialog button[type=submit]').click();
      await page.evaluate(()=>window.operation);
      assert.equal(await page.evaluate(()=>window.writes),1,label+' confirmed');
      groups++;
    }
    await page.close();
  }
  assert.deepEqual(errors,[]);
  console.log(JSON.stringify({groups,fail:0,viewports:3,pageErrors:0,source:'SYNTHETIC ONLY; real dialog adapter and real confirmation prefixes'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
