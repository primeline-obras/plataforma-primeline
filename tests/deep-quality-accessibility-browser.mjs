// Full application, synthetic API only. No SQL or production requests.
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
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
      if(resource==='rpc/fn_folha_ferias_mapa_v2')return Response.json({version:2,people:[],vacations:[]});
      if(resource==='rpc/fn_folha_ausencias_contexto_v3')return Response.json({version:3,absences:[],can_classify:true});
      if(resource==='rpc/fn_pode_ver_visao_consolidada')return Response.json(true);
      if(resource==='rpc/fn_mapa_gestao_obras_excel')return Response.json([]);
      if(resource==='rpc/fn_listar_colegas_agenda'||resource==='rpc/fn_listar_participantes_reuniao')return Response.json([]);
      if(resource==='rpc/fn_folha_gestao_contexto_v2')return Response.json({version:2,permissions:{admin:true,adm:true,he_review:true,task_report:true,task_review:true},people:[],vacations:[],entitlements:[],payroll:[],tasks:[],task_reports:[],overtime:[],history:[],absences:[],vacation_revision:0,schedule:null,config:null,live_facts:null});
      if(resource==='rpc/fn_folha_contexto_v2')return Response.json({version:2,date:payload.p_data,work_id:payload.p_obra_id||null,works:[],rows:[],external_rows:[],permissions:{write:true,external_write:true,allocation_write:true},schedule:null,admin:true,management:true,providers:[]});
      if(resource==='rpc/fn_folha_horas_admin_contexto_v3')return Response.json({version:3,work_id:payload.p_obra_id||null,works:[],people:[],providers:[],can_monthly_read:true,can_monthly_write:true,can_view_hr_costs:true,can_approve_hr_cost:true,can_associate:true,can_read_external:false,can_view_operational_costs:false});
      if(resource==='rpc/fn_ausencias_equipa_encarregado')return Response.json([]);
      if(resource==='rpc/fn_e_admin')return Response.json(role==='gestao_plataforma');
      if(resource==='rpc/fn_listar_ponto_obra')return Response.json({obras:[{id:'w1'}],linhas:payload.p_obra_id?[{colaborador_id:'p1',nome:'Ana Ativa',funcao:'Administrativa'}]:[]});
      if(resource==='rpc/fn_colaborador_na_obra_atual_encarregado')return Response.json(payload.p_colaborador_id==='p1');
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
      if(method!=='GET'){window.unsupported=window.unsupported||[];unsupported.push({resource,method});return Response.json({code:'LOCAL_UNSUPPORTED_CONTRACT',message:'Contrato não preparado nesta fixture de navegação'},{status:501});}
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


 const proofs=[];await page.goto(origin+'/?view=team&role=gestao_plataforma');await page.locator('.sidebar nav [data-view]:visible').first().waitFor();
 const views=await page.locator('.sidebar nav [data-view]').evaluateAll(bs=>bs.filter(b=>!b.hidden&&getComputedStyle(b).display!=='none').map(b=>b.dataset.view));
 for(const width of [1440,768,390]){await page.setViewportSize({width,height:1024});for(const view of views){await page.locator('.sidebar nav [data-view="'+view+'"]').evaluate(b=>b.click());await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));const controls=await page.locator('main').evaluate(root=>[...root.querySelectorAll('button,input,select,textarea,a[href]')].filter(e=>e.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})&&!e.closest('[inert],[aria-hidden="true"]')).map(e=>({tag:e.tagName,type:e.type||'',id:e.id,name:e.name||'',text:(e.innerText||'').trim().slice(0,80),label:(e.getAttribute('aria-label')||(e.getAttribute('aria-labelledby')||'').split(/\s+/).map(id=>document.getElementById(id)?.textContent||'').join(' ') .trim()||e.getAttribute('title')||[...(e.labels||[])].map(l=>l.innerText).join(' ')||e.getAttribute('placeholder')||'').trim().slice(0,120),disabled:e.disabled,tabIndex:e.tabIndex,rect:{x:e.getBoundingClientRect().x,y:e.getBoundingClientRect().y,width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height}})));proofs.push({view,width,visible_controls:controls.length,unnamed_candidates:controls.filter(c=>!c.label&&!c.text&&c.type!=='hidden'),positive_tabindex:controls.filter(c=>c.tabIndex>0),controls});}}
 await page.locator('.sidebar nav [data-view="vehicles"]').evaluate(b=>b.click());await writeFile(path.join(screenshots,'VEHICLES-ARIA-SNAPSHOT.txt'),await page.locator('main').ariaSnapshot());await page.setViewportSize({width:768,height:1024});await page.locator('.sidebar nav [data-view="calendar"]').evaluate(b=>b.click());await page.locator('body').click({position:{x:500,y:20}});const sequence=[];for(let i=0;i<35;i++){await page.keyboard.press('Tab');sequence.push(await page.evaluate(()=>{const e=document.activeElement,s=getComputedStyle(e);return {tag:e.tagName,text:(e.innerText||e.getAttribute('aria-label')||e.getAttribute('placeholder')||'').slice(0,80),visible:!!(e.getBoundingClientRect().height&&e.getBoundingClientRect().width),outline:s.outline,boxShadow:s.boxShadow}}))}
 const writes=await page.evaluate(()=>calls.filter(c=>c.method!=='GET'&&!c.resource.startsWith('rpc/')));assert.equal(writes.length,0);assert.equal(errors.length,0);await writeFile(path.join(screenshots,'EVIDENCIAS-TECLADO-CONTROLOS.json'),JSON.stringify({environment:'Aplicação real; APIs sintéticas; inventário heurístico, não certificação WCAG',proofs,keyboard_sequence:sequence,errors},null,2)+'\n');console.log(JSON.stringify({views:views.length,states:proofs.length,unnamed_candidates:proofs.reduce((n,p)=>n+p.unnamed_candidates.length,0),positive_tabindex:proofs.reduce((n,p)=>n+p.positive_tabindex.length,0),keyboard_steps:sequence.length,errors}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
