import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
const require=createRequire(import.meta.url),{chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const repo=fileURLToPath(new URL('../',import.meta.url)),shots=path.join(os.tmpdir(),'primeline-folha-v2-synthetic');await mkdir(shots,{recursive:true});
const server=createServer(async(req,res)=>{try{if(req.url==='/'){res.setHeader('Content-Type','text/html; charset=utf-8');return res.end('<html data-theme="light"><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/src/styles.css"><link rel="stylesheet" href="/src/visual-phase2.css"><link rel="stylesheet" href="/src/visual-identity-final.css"><link rel="stylesheet" href="/src/workforce-calendar.css"><link rel="stylesheet" href="/src/medicine.css"><link rel="stylesheet" href="/src/attendance-sheet.css"><div id="root"></div></html>');}const p=new URL(req.url,'http://local').pathname;if(!p.startsWith('/src/')){res.writeHead(404);return res.end();}res.setHeader('Content-Type',p.endsWith('.css')?'text/css':'text/javascript');res.end(await readFile(path.join(repo,p)));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({channel:'msedge',headless:true});let pass=0;const errors=[];
async function setup(page,{role='encarregado',status=200,deny=false}={}) {
  await page.goto(url);
  await page.evaluate(async({role,status,deny})=>{
    const {createAttendanceModule}=await import('/src/attendance-sheet.js');
    window.calls=[];window.messages=[];window.mockStatus=status;window.deny=deny;window.records=new Map();
    window.createRow=(id,extra={})=>({person_id:id,name:id==='p'?'Pessoa <b>segura</b>':'Pessoa '+id,role:'Pedreiro',can_write:['encarregado','administrativo','gestao_plataforma'].includes(role),can_remove:['encarregado','administrativo','gestao_plataforma'].includes(role)&&!extra.sheet&&!extra.absence&&!extra.conflict,allocation_revision:1,allocation_ids:['alloc-'+id],revision:0,expected_minutes:480,sheet:null,...extra});
    window.rows=[createRow('p'),createRow('vacation',{absence:{tipo:'ferias'}}),createRow('absent',{absence:{tipo:'ausencia'}})];
    window.externalRows=[createRow('ext',{provider_name:'Fornecedor sintético'})];
    const context=(date,work)=>({version:2,date,work_id:work||null,works:[{id:'own',name:'Obra sintética',number:1}],rows:window.rows,external_rows:window.externalRows,permissions:{allocation_write:['encarregado','administrativo','gestao_plataforma'].includes(role),write:['encarregado','administrativo','gestao_plataforma'].includes(role),external_write:['encarregado','administrativo','gestao_plataforma'].includes(role)},providers:[{id:'provider',name:'Fornecedor'}],special_day:false,schedule:{intervals:[{period:'manha',start:'09:00',end:'13:00'},{period:'tarde',start:'14:00',end:'18:00'}]}});
    window.module=createAttendanceModule({root:document.querySelector('#root'),isConfigured:true,toast:(m,t)=>messages.push({m,t}),confirm:async()=>true,now:()=>new Date('2026-10-05T18:00:00Z'),supabase:async(name,o)=>{
      const b=JSON.parse(o.body);calls.push({name,b});
      if(window.mockStatus!==200)return Response.json({message:'Recusado'},{status:window.mockStatus});
      if(name.endsWith('fn_folha_contexto_v2'))return Response.json(context(b.p_data,b.p_obra_id));
      if(name.endsWith('fn_folha_pessoas_v2'))return Response.json({version:2,people:[{person_id:'available',name:'Disponível',can_allocate:true,allocation_revision:0},{person_id:'other',name:'Outra obra',current_work:{id:'source',label:'Obra 2',type:'obra'},can_transfer:true,allocation_revision:2},{person_id:'office',name:'Escritório',current_work:{id:null,label:'Escritório',type:'escritorio'},can_transfer:false,allocation_revision:0}]});
      if(name.endsWith('fn_folha_historico_v2'))return Response.json({version:2,events:[{at:'2026-10-05',action:'save',reason:'Histórico preservado'}]});
      if(name.endsWith('fn_folha_operar_v2')){
        if(deny)return Response.json({code:'42501',message:'Sem permissão'},{status:403});
        if(window.staleCommit&&b.p_confirmar)return Response.json({code:'STALE_REVISION',message:'Recarregue'},{status:409});
        if(!b.p_confirmar)return Response.json({version:2,committed:false,versao:'preview',summary:'Confirmar?'});
        const d=b.p_dados;
        if(b.p_acao==='save'){const all=d.key.kind==='external'?window.externalRows:window.rows;const row=all.find(r=>r.person_id===d.key.person_id);if(row){row.sheet={intervals:d.intervals,note:d.note};row.revision++;}}
        if(b.p_acao==='bulk')for(const i of d.items){const row=window.rows.find(r=>r.person_id===i.key.person_id);row.sheet={intervals:i.intervals};row.revision++;}
        if(b.p_acao==='allocate'||b.p_acao==='transfer')window.rows.push(createRow(d.person_id));
        if(b.p_acao==='external_register')window.externalRows.push(createRow('external-new',{name:d.name,provider_name:'Fornecedor sintético'}));
        if(b.p_acao==='remove_from_day')window.rows=window.rows.filter(r=>r.person_id!==d.person_id);
        const changed_keys=d.items?.map(i=>i.key)||[d.key||{kind:b.p_acao==='external_register'?'external':'primeline',person_id:d.person_id||'external-new',work_id:d.work_id,date:d.date}];
        return Response.json({version:2,committed:true,request_id:d.request_id,changed_keys});
      }
      throw new Error('Endpoint não permitido: '+name);
    }});await module.show();
  },{role,status,deny});
}
try {
  for(const size of [{width:1440,height:900},{width:820,height:1180},{width:390,height:844}]) {
    const page=await browser.newPage({viewport:size});page.on('pageerror',e=>errors.push(e.message));
    await page.route('**/*',route=>new URL(route.request().url()).hostname==='127.0.0.1'?route.continue():route.abort());
    for(const role of ['encarregado','diretor_obra','adjunto','administrativo','gestao_plataforma','financeiro']) {
      await setup(page,{role});assert.equal(await page.locator('.sheet-person').count(),4);assert.equal(await page.locator('.sheet-person b').first().textContent(),'Não registado');assert.equal(await page.locator('.sheet-person strong b').count(),0);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      assert.equal(await page.locator('[data-sheet-edit]').count(),['encarregado','administrativo','gestao_plataforma'].includes(role)?4:0);assert.equal(await page.locator('[data-sheet-add-external]').count(),['encarregado','administrativo','gestao_plataforma'].includes(role)?1:0);
      assert.ok(await page.evaluate(()=>[...document.querySelectorAll('button')].every(b=>b.getBoundingClientRect().height>=48)));
      if(role==='encarregado') {
        await page.locator('[data-sheet-edit="p"]').click();await page.locator('[name=start0]').fill('09:00');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>document.querySelector('.sheet-person b')?.textContent==='Em aberto');
        assert.equal(await page.evaluate(()=>rows[0].sheet.intervals[0].end),null);
        await page.locator('[data-sheet-bulk=finish]').click();await page.waitForFunction(()=>rows[0].revision===2);assert.equal(await page.evaluate(()=>rows[0].sheet.intervals[0].end),'19:00');
        const bulk=await page.evaluate(()=>calls.find(x=>x.name.endsWith('fn_folha_operar_v2')&&x.b.p_acao==='bulk').b.p_dados.items);assert.equal(bulk.length,1);assert.equal(bulk[0].key.person_id,'p');
        await page.locator('[data-sheet-add]').click();await page.locator('[data-sheet-candidate=available]').click();await page.waitForFunction(()=>rows.some(r=>r.person_id==='available'));
        await page.locator('[data-sheet-add]').click();await page.locator('[data-sheet-candidate=other]').click();await page.waitForFunction(()=>rows.some(r=>r.person_id==='other'));
        const transfer=await page.evaluate(()=>calls.find(x=>x.b.p_acao==='transfer').b.p_dados);assert.equal(transfer.source_work_id,'source');assert.equal(transfer.expected_allocation_revision,2);
        await page.locator('[data-sheet-add]').click();await page.locator('[data-sheet-candidate=office]').click();assert.equal(await page.evaluate(()=>calls.filter(x=>x.b.p_dados?.person_id==='office').length),0);
        await page.locator('[data-sheet-history="p"]').click();await page.waitForFunction(()=>document.querySelector('[data-sheet-detail]')?.textContent.includes('Histórico preservado'));
      }
      await page.screenshot({path:path.join(shots,`${role}-${size.width}.png`)});pass++;
    }
    await setup(page,{status:404});assert.match(await page.locator('#root').textContent(),/ainda não está disponível/);assert.equal(await page.locator('[data-sheet-edit]').count(),0);assert.equal(await page.evaluate(()=>calls.some(x=>/fn_guardar_ponto_obra|fn_listar_ponto_obra/.test(x.name))),false);pass++;
    await setup(page,{deny:true});await page.locator('[data-sheet-edit="p"]').click();await page.locator('[name=start0]').fill('09:00');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>messages.some(x=>x.m==='Sem permissão'));assert.equal(await page.evaluate(()=>rows[0].sheet),null);assert.equal(await page.evaluate(()=>messages.some(x=>x.m==='Registo confirmado.')),false);pass++;
    await setup(page);await page.locator('[data-sheet-bulk=start]').click();await page.waitForFunction(()=>rows[0].sheet!==null);assert.equal(await page.evaluate(()=>rows[0].sheet.intervals[0].end),null);assert.equal(await page.evaluate(()=>rows.filter(r=>r.sheet).length),1);pass++;
    await setup(page);await page.locator('[data-sheet-edit="p"]').click();await page.locator('[name=start0]').fill('14:00');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>rows[0].revision===1);await page.locator('[data-sheet-bulk=finish]').click();await page.waitForFunction(()=>rows[0].revision===2);assert.equal(await page.evaluate(()=>rows[0].sheet.intervals[0].end),'19:00');pass++;
    await setup(page,{role:'administrativo'});await page.locator('[data-sheet-add-external]').click();await page.locator('[name=provider_id]').selectOption('provider');await page.locator('[name=name]').fill('Externo sintético');await page.locator('[data-sheet-external-form] button[type=submit]').click();await page.waitForFunction(()=>externalRows.length===2);assert.equal(await page.evaluate(()=>rows.length),3);await page.locator('[data-sheet-edit="external-new"]').click();await page.locator('[name=start0]').fill('09:00');await page.locator('[name=end0]').fill('13:00');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>externalRows[1].revision===1);assert.equal(await page.evaluate(()=>calls.find(c=>c.b.p_acao==='save').b.p_dados.key.kind),'external');pass++;
    await setup(page);await page.evaluate(()=>window.staleCommit=true);await page.locator('[data-sheet-edit="p"]').click();await page.locator('[name=start0]').fill('09:00');await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>messages.some(x=>x.m==='Recarregue'));await page.waitForFunction(()=>document.querySelector('[data-sheet-edit]')!==null);assert.equal(await page.evaluate(()=>rows[0].sheet),null);assert.equal(await page.evaluate(()=>calls.filter(c=>c.b.p_confirmar).length),1);assert.equal(await page.evaluate(()=>messages.some(x=>x.m==='Registo confirmado.')),false);pass++;
    await setup(page);await page.locator('[data-sheet-remove="p"]').click();await page.waitForFunction(()=>!rows.some(r=>r.person_id==='p'));assert.equal(await page.evaluate(()=>calls.filter(x=>x.b.p_acao==='remove_from_day').length),2);pass++;
    await setup(page);assert.equal(await page.locator('[data-sheet-remove="vacation"]').count(),0);assert.equal(await page.evaluate(()=>calls.some(x=>x.b.p_acao==='remove_from_day')),false);pass++;
    await setup(page);await page.evaluate(()=>{rows[0].sheet={intervals:[{start:'09:00',end:'13:00'},{start:'14:00',end:'18:00'}]};rows[0].revision=1;externalRows[0].sheet={intervals:rows[0].sheet.intervals};});await page.locator('[data-sheet-refresh]').click();await page.waitForFunction(()=>document.querySelector('[data-sheet-summary]')?.textContent.includes('DIA COMPLETO'));await page.locator('[data-sheet-edit="p"]').click();assert.equal(await page.locator('[name=reason]').getAttribute('required'),null);await page.locator('[data-sheet-form] button[type=submit]').click();await page.waitForFunction(()=>rows[0].revision===2);assert.equal(await page.evaluate(()=>calls.find(x=>x.b.p_acao==='save').b.p_dados.reason),null);pass++;
    await page.close();
  }
  assert.deepEqual(errors,[]);console.log(JSON.stringify({pass,fail:0,pageErrors:errors.length,screenshots:shots,backend:'MOCK ONLY — does not prove installed authorization'}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
