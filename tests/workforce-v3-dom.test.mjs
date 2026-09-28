import test from 'node:test';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {createForemanTeam} from '../src/foreman-team.js';
const {JSDOM}=await import(process.env.QUADRO_JSDOM ? pathToFileURL(process.env.QUADRO_JSDOM).href : './quadro-runtime/node_modules/jsdom/lib/api.js');
const tick=async()=>{for(let i=0;i<5;i++) await new Promise(r=>setImmediate(r));};
async function screen({role='encarregado',failure=false,multiple=false,noOrigin=false}={}) {
 const dom=new JSDOM('<div id="root"></div>'),root=dom.window.document.querySelector('#root'),calls=[],messages=[];
 const person={colaborador_id:'person',nome:'João Afonso',funcao:'Pedreiro',ausente:false,alocacoes:noOrigin?[]:[{obra_id:'118',obra_numero:'118',periodo:'dia_inteiro'}]};
 const api=async(path,options)=>{
  const p=JSON.parse(options.body);calls.push({path,...p});
  if(path.endsWith('fn_equipa_obra_encarregado')) return new Response(JSON.stringify({data:p.p_data,obra_id:p.p_obra_id||'120',obras:[{id:'120',numero:'120',nome:'A minha obra'},...(multiple?[{id:'128',numero:'128',nome:'Outra autorizada'}]:[])],equipa:[person,{...person,periodo:'tarde'}],candidatos:[person,{...person,colaborador_id:'absent',nome:'Ausente',ausente:true}]}));
  if(failure) return new Response(JSON.stringify({message:'Várias origens / sobreposição parcial.'}),{status:400});
  return new Response(JSON.stringify({versao:'v1',acao:noOrigin?'adicionar':'mover',obra_origem_id:noOrigin?null:'118'}));
 };
 const module=createForemanTeam({root,supabase:api,getRole:()=>role,toast:m=>messages.push(m),onAttendance:c=>messages.push(c),onHistory:()=>{}});
 await module.show();
 const $=s=>root.querySelector(s);
 const click=async s=>{$(s).click();await tick();};
 const change=async(s,value)=>{$(s).value=value;$(s).dispatchEvent(new dom.window.Event('change',{bubbles:true}));await tick();};
 const select=async()=>{await click('[data-team-add]');await click('[data-candidate="person"]');};
 return {dom,root,$,calls,messages,module,click,change,select};
}
test('lista mobile, resumo único, data atual, sem retirar nem seletor para obra única',async()=>{
 const s=await screen();assert.match(s.root.textContent,/EQUIPA OBRA 120/);assert.match(s.root.textContent,/1 pessoas · 0 Encarregados · 1 Pedreiros/);
 assert(!s.$('[data-team-work]'));assert(!/RETIRAR|ÍMANES/.test(s.root.textContent));
 const d=new Date();assert.equal(s.$('[data-team-date]').value,`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`);
 await s.click('[data-team-attendance]');assert.equal(s.messages.at(-1).workId,'120');s.dom.window.close();
});
test('pesquisa por nome, ausente desativado, preview obrigatório e confirmação versionada',async()=>{
 const s=await screen();await s.click('[data-team-add]');assert(s.$('[data-candidate="absent"]').disabled);
 const input=s.$('[data-team-search]');input.value='joao';input.dispatchEvent(new s.dom.window.Event('input',{bubbles:true}));assert.equal(s.root.querySelectorAll('[data-candidate]').length,1);
 await s.click('[data-candidate="person"]');await s.click('[data-team-preview-button]');
 assert.equal(s.calls.at(-1).p_confirmar,false);assert.match(s.$('[data-team-preview]').textContent,/118.*120/);
 const before=s.calls.at(-1).p_dados;await s.click('[data-team-preview-button]');
 const writes=s.calls.filter(c=>c.p_confirmar);assert.equal(writes.length,1);assert.equal(writes[0].p_versao,'v1');assert.deepEqual(writes[0].p_dados,before);
 assert(!s.$('[data-team-cancel]'));assert.equal(s.messages.at(-1),'Movimentação concluída e registada.');assert(s.calls.at(-1).path.endsWith('fn_equipa_obra_encarregado'));s.dom.window.close();
});
test('sem origem pede confirmação de adição; alterar período invalida preview',async()=>{
 const s=await screen({noOrigin:true});await s.select();await s.click('[data-team-preview-button]');assert.match(s.$('[data-team-preview]').textContent,/não possui outra alocação/);
 await s.change('[data-team-period]','manha');assert.equal(s.$('[data-team-preview]').textContent,'');await s.click('[data-team-preview-button]');assert.equal(s.calls.at(-1).p_confirmar,false);assert.equal(s.calls.at(-1).p_dados.periodo,'manha');s.dom.window.close();
});
test('conflitos não confirmam nem removem; erro mantém ação em modo preview',async()=>{
 const s=await screen({failure:true});await s.select();await s.click('[data-team-preview-button]');assert.match(s.$('[data-team-error]').textContent,/ADM\/Gestão/);assert(!s.calls.some(c=>c.p_confirmar));assert.equal(s.$('[data-team-preview-button]').textContent,'PRÉ-VISUALIZAR');s.dom.window.close();
});
test('múltiplas obras autorizadas; abrir alerta escolhe obra; mudar data fecha preview',async()=>{
 const s=await screen({multiple:true});assert.equal(s.$('[data-team-work]').options.length,2);await s.module.show({workId:'128'});assert.match(s.root.textContent,/EQUIPA OBRA 128/);
 await s.select();await s.click('[data-team-preview-button]');await s.change('[data-team-date]','2026-10-01');assert(!s.$('[data-team-preview-button]'));assert.equal(s.calls.at(-1).p_data,'2026-10-01');s.dom.window.close();
});
test('outros perfis não abrem ação limitada nem consultam RPC',async()=>{
 for(const role of ['diretor_obra','adjunto','administrativo']) {const s=await screen({role});assert.equal(s.calls.length,0);assert.equal(s.root.textContent,'');s.dom.window.close();}
});
