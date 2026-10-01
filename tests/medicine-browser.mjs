// Full application, synthetic API only. No SQL or production requests.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
const {chromium}=createRequire(import.meta.url)(process.env.PLANNING_PLAYWRIGHT||'playwright');
const root=fileURLToPath(new URL('../',import.meta.url));
const screenshots=process.env.RH_SCREENSHOTS||path.join(os.tmpdir(),'primeline-medicine-frontend');
await mkdir(screenshots,{recursive:true});
const server=createServer(async(req,res)=>{
  try {
    const url=new URL(req.url,'http://localhost');
    if(url.pathname==='/config.js'){res.setHeader('Content-Type','text/javascript');return res.end('window.PRIMELINE_CONFIG={supabaseUrl:"https://synthetic.test",supabaseAnonKey:"synthetic"};');}
    const name=url.pathname==='/'?'index.html':url.pathname.slice(1);
    if(name.includes('..')||!(name==='index.html'||name.startsWith('src/')||name.startsWith('assets/'))){res.statusCode=404;return res.end();}
    res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.png':'image/png'})[path.extname(name)]||'application/octet-stream');
    res.end(await readFile(path.join(root,name)));
  }catch{res.statusCode=404;res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const origin=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({channel:'msedge',headless:true});
try {
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',e=>{errors.push(e.message);console.error(e.message);});page.on('console',m=>{if(m.type()==='error'){errors.push(m.text());console.error(m.text());}});
  await page.route('**/*',r=>r.request().url().startsWith(origin)?r.continue():r.fulfill({body:'',contentType:'text/javascript'}));
  await page.clock.setFixedTime(new Date('2026-09-30T12:00:00Z'));
  await page.addInitScript(()=>{
    sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:'synthetic',user:{id:'auth'}}));
    window.role=new URL(location.href).searchParams.get('role')||'administrativo';
    window.calls=[];window.mode='ok';window.replays={};window.sequence=0;
    window.people=[{id:'p1',nome:'Ana Ativa',funcao:'Administrativa',data_admissao:'2026-01-01',data_saida:null},{id:'p2',nome:'Inês Inativa',funcao:'Técnica',data_admissao:'2026-01-01',data_saida:'2026-09-01'}];
    window.rows=[];window.medHistory=[];
    window.fetch=async(address,options={})=>{
      const url=new URL(address,location.href);if(url.hostname!=='synthetic.test')throw Error('Non-synthetic fetch refused');
      const resource=url.pathname.replace('/rest/v1/',''),payload=options.body?JSON.parse(options.body):null,method=options.method||'GET';calls.push({resource,payload,method});
      if(resource==='rpc/fn_quadro_contexto_v1')return Response.json({version:1,allocations:[],revisions:[],can_manage_global:role==='gestao_plataforma'||role==='administrativo',read_work_ids:[],edit_work_ids:[],people:[],works:[]});
      if(resource==='rpc/fn_e_admin')return Response.json(role==='gestao_plataforma');
      if(resource==='rpc/fn_listar_rastreio_faturas')return Response.json([]);
      if(resource==='rpc/fn_rh_consultar'){const person=people.find(p=>p.id===payload.p_id);return Response.json([{colaborador:person,contratos:[],niss:null,versao:'v1'}]);}
      if(resource==='rpc/fn_medicina_consultar_colaborador'){
        if(mode==='missing')return Response.json({code:'PGRST202'},{status:404});
        const consultations=rows.filter(r=>r.colaborador_id===payload.p_colaborador_id);
        const current=consultations.filter(r=>!r.anulado_em&&r.data_ultima_consulta<='2026-09-30').sort((a,b)=>b.data_ultima_consulta.localeCompare(a.data_ultima_consulta))[0]||null;
        return Response.json({version:1,can_write:role!=='encarregado',atual:current,...(role==='encarregado'?{}:{consultas:consultations,historico:medHistory})});
      }
      if(resource.startsWith('rpc/fn_medicina_')){
        if(role==='encarregado')return Response.json({code:'42501'},{status:403});
        if(replays[payload.p_request_id])return Response.json({...replays[payload.p_request_id],idempotent:true});
        if(mode==='stale'){mode='ok';rows[0].revisao++;rows[0].resultado='Atualizado por outra pessoa';return Response.json({code:'40001'},{status:400});}
        let c;
        if(resource.endsWith('registar_consulta')){c={id:'c'+(++sequence),colaborador_id:payload.p_colaborador_id,revisao:0};rows.push(c);}
        else c=rows.find(r=>r.id===payload.p_consulta_id);
        if(resource.endsWith('anular_consulta')){c.anulado_em='2026-09-30T12:00:00Z';c.revisao++;}
        else {Object.assign(c,{data_ultima_consulta:payload.p_data_consulta,data_proxima_consulta:payload.p_proxima_consulta,resultado:payload.p_resultado});if(payload.p_consulta_id)c.revisao++;}
        medHistory.push({operacao:resource,motivo:payload.p_motivo,criado_em:'2026-09-30T12:00:00Z'});
        const result={version:1,committed:true,consulta:structuredClone(c),historico_id:'h'+medHistory.length};replays[payload.p_request_id]=result;
        if(mode==='lost-response'){mode='ok';throw Error('Synthetic response lost after commit');}
        return Response.json(result);
      }
      if(method!=='GET')throw Error('Unexpected write: '+resource);
      if(resource==='utilizadores')return Response.json([{id:'u',auth_user_id:'auth',nome:'Utilizador de teste',funcao:role,ativo:true}]);
      if(resource==='colaboradores')return Response.json(people.filter(p=>url.searchParams.get('data_saida')==='not.is.null'?p.data_saida!==null:p.data_saida===null));
      if(resource==='documentos')return Response.json([{id:'doc',entidade_tipo:'colaborador',entidade_id:'p1',tipo_documento:'ficha_aptidao',nome_arquivo:'Ficha de aptidão.pdf',url_arquivo:'private/test.pdf'}]);
      return Response.json([]);
    };
  });
  const medicine=()=>page.locator('[data-rh-medicine]');
  const reload=async()=>{await medicine().locator('[data-med-reload]').click();await medicine().locator('[data-med-new]').waitFor();};
  const close=async()=>{await page.locator('#workflow-dialog [data-close-workflow]').first().click();};
  const writeCount=()=>page.evaluate(()=>calls.filter(c=>c.resource.startsWith('rpc/fn_medicina_')&&!c.resource.endsWith('consultar_colaborador')).length);
  await page.goto(origin+'/?view=team');
  await page.locator('#team-directory [data-edit-collaborator="p1"]').click();
  await medicine().getByText('Sem consulta realizada',{exact:true}).waitFor();
  assert.equal(await medicine().getByText('Ficha de aptidão.pdf',{exact:true}).count(),2);
  assert.equal(await page.locator('#rh-form [data-rh-medicine]').count(),0,'independent medicine form is not nested in RH form');
  await medicine().locator('[data-med-new]').click();
  await medicine().locator('[name=data_consulta]').fill('2026-10-01');
  await medicine().locator('[type=submit]').click();assert.equal(await writeCount(),0);
  await medicine().locator('[name=data_consulta]').fill('2026-09-01');
  await medicine().locator('[name=resultado]').fill('Apto');
  await page.evaluate(()=>mode='lost-response');await medicine().locator('[type=submit]').click();
  await medicine().locator('.form-error').filter({hasText:'confirmar'}).waitFor();
  assert.equal(await medicine().locator('[name=resultado]').isDisabled(),true);
  assert.equal(await medicine().locator('[data-med-new]').isDisabled(),true);
  await medicine().locator('[type=submit]').click();await medicine().getByText('Operação confirmada. Histórico atualizado.',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>rows.length),1);
  const replayCalls=await page.evaluate(()=>calls.filter(c=>c.resource.endsWith('registar_consulta')));assert.deepEqual(replayCalls[0].payload,replayCalls[1].payload);
  await medicine().getByText('Sem próxima consulta',{exact:true}).waitFor();
  await medicine().locator('[data-med-new]').click();await medicine().locator('[name=data_consulta]').fill('2026-09-20');await medicine().locator('[name=resultado]').fill('Apto condicionado');await medicine().locator('[name=proxima_consulta]').fill('2026-10-10');
  await medicine().locator('[type=submit]').click();await medicine().getByText('A vencer',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>rows.length),2);
  const ids=await page.evaluate(()=>rows.map(r=>r.id));
  await medicine().locator(`[data-med-correct="${ids[1]}"]`).click();
  const before=await writeCount();await medicine().locator('[type=submit]').click();assert.equal(await writeCount(),before,'reason required');
  await medicine().locator('[name=motivo]').fill('Correção de transcrição');await medicine().locator('[name=proxima_consulta]').fill('2026-09-25');await medicine().locator('[type=submit]').click();await medicine().getByText('Vencida',{exact:true}).waitFor();
  const correction=await page.evaluate(()=>calls.find(c=>c.resource.endsWith('corrigir_consulta')));assert.equal(correction.payload.p_revisao_esperada,0);assert.ok(correction.payload.p_request_id);
  await medicine().locator(`[data-med-correct="${ids[0]}"]`).click();await medicine().locator('[name=motivo]').fill('Conflito simulado');await page.evaluate(()=>mode='stale');await medicine().locator('[type=submit]').click();
  await medicine().locator('[data-med-message]').filter({hasText:'mudou entretanto'}).waitFor();assert.equal(await medicine().locator('.medicine-form').count(),0);await medicine().getByText('Atualizado por outra pessoa',{exact:true}).waitFor();
  await medicine().locator(`[data-med-cancel="${ids[1]}"]`).click();await medicine().locator('[name=motivo]').fill('Registo incorreto');await medicine().locator('[type=submit]').click();await medicine().locator('.medicine-cancelled').waitFor();assert.equal(await medicine().locator('.medicine-history article').count(),2);assert.equal(await medicine().locator('.medicine-cancelled button').count(),0);
  for(const [name,width,height] of [['desktop',1440,1000],['tablet',820,1180],['mobile',390,844]]){await page.setViewportSize({width,height});await medicine().scrollIntoViewIfNeeded();await page.screenshot({path:path.join(screenshots,`ficha-${name}.png`),animations:'disabled'});assert.equal(await medicine().isVisible(),true);}
  await page.setViewportSize({width:1440,height:1000});await close();
  await page.locator('[data-team-tab="medicine"]').click();
  assert.equal(await page.locator('#team-medicine .medicine-row').count(),1,'one current row per person, not one per consultation');
  await page.locator('[data-open-medicine="p1"]').click();await medicine().getByText('Sem próxima consulta',{exact:true}).waitFor();
  assert.equal(await page.locator('#rh-form').count(),1,'RH global panel opens central profile');await close();
  await page.locator('[data-team-tab="collaborators"]').click();
  await page.evaluate(()=>rows.push({id:'inactive-history',colaborador_id:'p2',data_ultima_consulta:'2026-01-10',data_proxima_consulta:null,resultado:'Histórico da pessoa inativa',revisao:0}));
  await page.locator('#toggle-inactive-collaborators').click();await page.locator('#inactive-collaborators [data-edit-collaborator="p2"]').click();await medicine().getByText('COLABORADOR INATIVO · histórico preservado',{exact:true}).waitFor();assert.equal(await medicine().locator('[data-med-consultation="inactive-history"]').count(),1);assert.equal(await page.evaluate(()=>calls.some(c=>c.resource.includes('ciclo_vida'))),false);
  await page.evaluate(()=>mode='missing');await medicine().locator('[data-med-reload]').click();await medicine().getByText('Medicina indisponível. A RPC necessária não está disponível.',{exact:true}).waitFor();assert.equal(await medicine().locator('[data-med-new]').count(),0);
  for(const role of ['gerencia','gestao_plataforma']){await page.goto(origin+'/?view=team&role='+role);await page.locator('#team-directory [data-edit-collaborator="p1"]').click();await medicine().locator('[data-med-new]').click();await medicine().locator('[name=data_consulta]').fill('2026-09-01');await medicine().locator('[type=submit]').click();await medicine().getByText('Operação confirmada. Histórico atualizado.',{exact:true}).waitFor();assert.equal(await writeCount(),1);}
  await page.goto(origin+'/?view=team&role=encarregado');await page.locator('[data-team-tab="medicine"]').click();await page.locator('[data-open-medicine="p1"]').click();await medicine().getByText('SOMENTE LEITURA',{exact:true}).waitFor();assert.equal(await medicine().locator('[data-med-new],[data-med-correct],[data-med-cancel]').count(),0);assert.equal(await writeCount(),0);
  assert.deepEqual(errors,[]);assert.equal(await page.evaluate(()=>calls.some(c=>c.resource==='medicina_trabalho')),false);
  console.log('PASS: central RH profile, documents, no consultation, NULL, current/history, overdue/due, new consultation, lost response/replay, correction, stale reload, cancellation/history, inactive, missing RPC, four roles, three viewports, no direct DML, clean console. Screenshots: '+screenshots);
}finally{await browser.close();await new Promise(r=>server.close(r));}
