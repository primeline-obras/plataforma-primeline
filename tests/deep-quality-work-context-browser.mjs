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
      if(resource==='rpc/fn_pode_editar_obra'||resource==='rpc/fn_pode_editar_documentos_obra')return Response.json(true);
      if(resource==='rpc/fn_resumo_custos_obra')return Response.json({real:{},por_concluir:{},componentes:[]});
      if(method!=='GET'){window.unsupported=window.unsupported||[];unsupported.push({resource,method});return Response.json({code:'LOCAL_UNSUPPORTED_CONTRACT',message:'Contrato não preparado nesta fixture de navegação'},{status:501});}
      if(resource==='utilizadores')return Response.json([{id:'u',auth_user_id:'auth',nome:'Utilizador de teste',funcao:role,ativo:true}]);
      if(resource==='obras')return Response.json([{id:'00000000-0000-4000-8000-000000000120',empresa_id:'00000000-0000-4000-8000-000000000001',numero:120,nome:'Obra sintética com nome extenso para verificação contextual',situacao:'em_curso',cliente:'Cliente sintético',modalidade:'empreitada_geral'}]);
      if(resource==='rpc/fn_pode_editar_documentos_obra')return Response.json(true);
      if(resource==='colaboradores')return Response.json(people.filter(p=>url.searchParams.get('data_saida')==='not.is.null'?p.data_saida!==null:p.data_saida===null));
      if(resource==='documentos')return Response.json([{id:'doc',entidade_tipo:'colaborador',entidade_id:'p1',tipo_documento:'ficha_aptidao',nome_arquivo:'Ficha de aptidão.pdf',url_arquivo:'private/test.pdf'}]);
      return Response.json([]);
    };
  });
  const medicine=()=>page.locator('[data-rh-medicine]');
  const reload=async()=>{await medicine().locator('[data-med-reload]').click();await medicine().locator('[data-med-new]').waitFor();};
  const close=async()=>{await page.locator('#workflow-dialog [data-close-workflow]').first().click();};
  const writeCount=()=>page.evaluate(()=>calls.filter(c=>c.resource.startsWith('rpc/fn_medicina_')&&!c.resource.endsWith('consultar_colaborador')).length);


 const proofs=[];await page.goto(origin+'/?view=works&role=gestao_plataforma');await page.locator('.sidebar nav [data-view="works"]:visible').waitFor();
 for(const view of ['works','documents','planning']){await page.setViewportSize({width:1440,height:1000});await page.locator('.sidebar nav [data-view="'+view+'"]').click();for(const viewport of [{width:1440,height:1000},{width:768,height:1024},{width:390,height:844}]){await page.setViewportSize(viewport);await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));const state=await page.locator('main').evaluate(e=>({text:e.innerText.slice(0,4500),buttons:[...e.querySelectorAll('button')].filter(b=>b.checkVisibility()).map(b=>({text:b.innerText,attributes:[...b.attributes].filter(a=>a.name.startsWith('data-')).map(a=>[a.name,a.value])})),controls:[...e.querySelectorAll('input,select,textarea')].filter(b=>b.checkVisibility()).map(b=>({name:b.name,type:b.type,id:b.id,attributes:[...b.attributes].filter(a=>a.name.startsWith('data-')).map(a=>[a.name,a.value]),rect:{left:b.getBoundingClientRect().left,right:b.getBoundingClientRect().right,width:b.getBoundingClientRect().width},outside_viewport:b.getBoundingClientRect().right>innerWidth})),overflow:document.documentElement.scrollWidth>innerWidth+1}));if(view!=='works'){state.selector_tap=await page.locator(view==='planning'?'#planning-work':'[data-documents-work]').click({timeout:800}).then(()=>({ok:true}),e=>({ok:false,error:e.message.split('\n')[0]}));await page.keyboard.press('Escape');}await page.screenshot({path:path.join(screenshots,view+'-context-'+viewport.width+'.png'),fullPage:true});proofs.push({view,viewport,state});}}
 await page.locator('.sidebar nav [data-view="documents"]').evaluate(b=>b.click());const uploader=page.locator('#documents-center-upload');const tabs=await page.locator('[data-document-section]').evaluateAll(bs=>bs.filter(b=>b.checkVisibility()).map(b=>b.dataset.documentSection));for(const tab of tabs){await page.locator('[data-document-section="'+tab+'"]').click();proofs.push({view:'documents',section:tab,text:(await page.locator('main').innerText()).slice(0,3000)})}
 await writeFile(path.join(screenshots,'EVIDENCIAS-CONTEXTO-OBRA.json'),JSON.stringify({scope:'UI real; uma obra sintética; respostas preparadas não provam permissão backend',proofs,errors,unsupported:await page.evaluate(()=>window.unsupported||[])},null,2)+'\n');assert.deepEqual(await page.evaluate(()=>window.unsupported||[]),[]);console.log(JSON.stringify({states:proofs.length,errors,unsupported:await page.evaluate(()=>window.unsupported||[])}));
}finally{await browser.close();await new Promise(r=>server.close(r));}
