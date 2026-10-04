import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLANNING_PLAYWRIGHT||'playwright');
const root=process.env.SESSION_TEST_ROOT||fileURLToPath(new URL('../',import.meta.url));
const hooks=`
window.sessionTest={
 seed(area){
  teamData.loadedWeek=selectedTeamWeek; selectedWorkId='private-A';workDetails.contract={private:'PRIVATE_A_SENTINEL'};
  const section=document.querySelector(area==='medicine'?'#team-medicine':area==='work'?'#work-detail-view':'#team-board')||document.querySelector('#root');
  section.insertAdjacentHTML('beforeend','<div data-private-test>PRIVATE_A_SENTINEL</div>');
  localStorage.setItem('primeline_planning_work_id','private-A');
 },
 state(){return {works:works.map(x=>x.id),people:collaborators.map(x=>x.id),selectedWorkId,loadedWeek:teamData.loadedWeek,role:effectiveRole()};},
 identity(id){sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:id,refresh_token:'refresh-'+id,user:{id}}));getSession();},
 expire(){window.dispatchEvent(new CustomEvent('primeline:session-expired'));}
};`;
const server=createServer(async(req,res)=>{
 try{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/config.js'){res.setHeader('Content-Type','text/javascript');return res.end('window.PRIMELINE_CONFIG={supabaseUrl:"https://synthetic.test",supabaseAnonKey:"synthetic"};');}
  const name=url.pathname==='/'?'index.html':url.pathname.slice(1);
  if(name.includes('..')||!(name==='index.html'||name.startsWith('src/')||name.startsWith('assets/'))){res.statusCode=404;return res.end();}
  let data=await readFile(path.join(root,name));if(name==='src/app.js')data=data.toString()+hooks;
  res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2'})[path.extname(name)]||'application/octet-stream');res.end(data);
 }catch{res.statusCode=404;res.end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
const browser=await chromium.launch({channel:'msedge',headless:true});
const roles={A:'gestao_plataforma',B:'encarregado',C:'diretor_obra'};
const work={id:'w1',numero:'120',nome:'Obra permitida',situacao:'em_curso'};
const person={id:'p1',nome:'Pessoa autorizada',funcao:'Pedreiro',data_saida:null};
let passes=0;
try{
 for(const scenario of [
  ['Gestão → Encarregado / Quadro','A','B','board','logout'],
  ['Encarregado → Gestão / Quadro','B','A','board','logout'],
  ['Diretor → Encarregado / Obra','C','B','work','logout'],
  ['Logout Medicina','A','B','medicine','logout'],
  ['Logout Obra','A','B','work','logout'],
  ['Sessão expirada','A','B','board','expire'],
  ['Mudança efetiva de identidade sem logout','A','B','board','identity']
 ]){
  const [label,from,to,area,mode]=scenario;const context=await browser.newContext();const page=await context.newPage();const errors=[],calls=[];
  let hold=false;let release;let blocked=new Promise(r=>release=r);let held=0;
  page.on('pageerror',e=>errors.push(e.message));
  await context.route('**/*',async route=>{
   const req=route.request(),url=new URL(req.url());if(url.origin===origin)return route.continue();
   if(url.hostname!=='synthetic.test')return route.fulfill({contentType:'text/javascript',body:''});
   const identity=(req.headers().authorization||'').replace('Bearer ','');const role=roles[identity]||'';
   const body=req.postData()?JSON.parse(req.postData()):{};const resource=url.pathname.replace('/rest/v1/','');
   calls.push({identity,resource,query:url.search,body});
   const reply=data=>route.fulfill({contentType:'application/json',body:JSON.stringify(data)});
   if(url.pathname==='/auth/v1/token'){
    const id=body.email?.split('@')[0];return reply({access_token:id,refresh_token:'refresh-'+id,user:{id}});
   }
   if(url.pathname==='/auth/v1/logout')return reply({});
   if(hold&&identity===to){held++;await blocked;}
   if(resource==='utilizadores')return reply([{id:'u-'+identity,auth_user_id:identity,ativo:true,funcao:role,nome:'Sessão '+identity}]);
   if(resource==='rpc/fn_e_admin')return reply(role==='gestao_plataforma');
   if(resource==='obras')return reply(identity==='B'?[work]:[work,{id:'private-A',numero:'999',nome:'Obra privada',situacao:'em_curso'}]);
   if(resource==='colaboradores')return reply([person,{id:'outside',nome:'OUTSIDE_TEAM_PERSON',funcao:'Pedreiro',data_saida:null}]);
   if(resource==='rpc/fn_listar_ponto_obra')return reply({obras:[work],linhas:body.p_obra_id?[{colaborador_id:person.id,nome:person.nome,funcao:person.funcao,periodos:['manha','tarde']}]:[],pode_validar:false});
   if(resource==='rpc/fn_colaborador_na_obra_atual_encarregado')return reply(body.p_colaborador_id==='p1');
   if(resource==='rpc/fn_quadro_contexto_v1')return reply({version:1,works:[work],people:[person,{id:'outside',nome:'OUTSIDE_TEAM_PERSON'}],allocations:[],revisions:[],read_work_ids:['w1'],edit_work_ids:role==='diretor_obra'?[]:['w1'],can_manage_global:role==='gestao_plataforma'});
   if(resource==='rpc/fn_medicina_consultar_colaborador')return reply({version:1,can_write:role!=='encarregado',atual:null,consultas:[],historico:[]});
   if(req.method()!=='GET'&&!resource.startsWith('rpc/'))throw Error('Unexpected write '+resource);
   return reply([]);
  });
  await context.addInitScript(({from})=>{
   if(!sessionStorage.getItem('seeded')){sessionStorage.setItem('seeded','yes');sessionStorage.setItem('primeline_supabase_session',JSON.stringify({access_token:from,refresh_token:'refresh-'+from,user:{id:from}}));}
  },{from});
  await page.goto(origin+'/?view=workforce');
  await page.waitForFunction(role=>window.sessionTest?.state().role===role,roles[from]);
  await page.waitForFunction(()=>document.querySelector('#team-board')?.textContent.includes('120'));
  await page.evaluate(area=>sessionTest.seed(area),area);
  assert.ok((await page.content()).includes('PRIVATE_A_SENTINEL'));
  if(mode==='identity'){
   hold=true;await page.evaluate(to=>sessionTest.identity(to),to);
  }else{
   if(mode==='expire')await page.evaluate(()=>sessionTest.expire());else await page.locator('#logout').click();
   await page.locator('#auth-screen:not([hidden])').waitFor();
   // Must already be gone on logout, before B has even submitted credentials.
   assert.ok(!(await page.content()).includes('PRIVATE_A_SENTINEL'),'old protected DOM remains after logout');
   await page.locator('#login-form [name=email]').fill(to+'@invalid.test');
   await page.locator('#login-form [name=password]').fill('synthetic');hold=true;
   await page.locator('#login-form button[type=submit]').click();
  }
  await page.waitForFunction(()=>!document.body.textContent.includes('PRIVATE_A_SENTINEL'));
  // Wait for the new account's API headers, but deliberately withhold all bodies.
  for(let n=0;n<100&&!held;n++)await new Promise(r=>setTimeout(r,20));assert.ok(held>0,'second identity request was withheld');
  assert.ok(!(await page.content()).includes('PRIVATE_A_SENTINEL'));
  assert.equal(await page.evaluate(()=>localStorage.getItem('primeline_planning_work_id')),null);
  hold=false;release();
  await page.waitForFunction(role=>window.sessionTest?.state().role===role,roles[to]);
  await page.waitForFunction(()=>window.sessionTest?.state().works.length>0);
  if(to==='B'){
   assert.deepEqual(await page.evaluate(()=>sessionTest.state().works),['w1']);
   await page.waitForFunction(()=>window.sessionTest?.state().people.length===1);
   await page.locator('.sidebar [data-view=team]').click();await page.locator('[data-team-tab=medicine]').click();
   await page.waitForFunction(()=>document.querySelector('#team-medicine')?.textContent.includes('Pessoa autorizada'));
   assert.ok(!(await page.locator('#team-medicine').textContent()).includes('OUTSIDE_TEAM_PERSON'));
   assert.ok(!calls.some(c=>c.identity==='B'&&c.resource==='colaboradores'));
   assert.ok(!calls.some(c=>c.identity==='B'&&c.resource==='subempreitadas'));
   assert.ok(!calls.some(c=>c.identity==='B'&&c.resource==='rpc/fn_medicina_consultar_colaborador'&&c.body.p_colaborador_id!=='p1'));
  }
  assert.deepEqual(errors,[],label+' console');console.log('PASS '+label);passes++;
  await context.close();
 }
 console.log(`${passes} scenarios PASS; synthetic identities only; all external traffic intercepted.`);
}finally{await browser.close();await new Promise(r=>server.close(r));}
