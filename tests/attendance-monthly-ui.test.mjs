import test from 'node:test';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {createAttendanceModule} from '../src/attendance.js';
const {JSDOM}=await import(process.env.QUADRO_JSDOM ? pathToFileURL(process.env.QUADRO_JSDOM).href : './quadro-runtime/node_modules/jsdom/lib/api.js');
const tick=async()=>{for(let i=0;i<5;i++)await new Promise(r=>setImmediate(r));};
const work={id:'120',numero:'120',nome:'Casa R'};
test('ADM exige obra e mês; RPC usa ambos e exporta Excel e PDF',async()=>{
 const dom=new JSDOM('<div id="root"></div>'),root=dom.window.document.querySelector('#root'),calls=[],files=[],messages=[];
 const savedWindow=globalThis.window;
 globalThis.window={XLSX:{utils:{book_new:()=>({}),aoa_to_sheet:()=>({}),book_append_sheet:()=>{}},writeFile:(b,f)=>files.push(f)},jspdf:{jsPDF:class{setFontSize(){}text(){}splitTextToSize(s){return [s];}addPage(){}save(f){files.push(f);}}}};
 try {
 const api=async(path,opt)=>{const body=JSON.parse(opt.body);calls.push({path,body});return new Response(JSON.stringify(path.endsWith('fn_folha_ponto_mensal')?[{obra_id:'120',data:'2026-09-01',colaborador_id:'p',colaborador:'Pessoa',horas:8,estado:'presente'}]:{obras:[work],linhas:[],pode_validar:true}));};
 await createAttendanceModule({root,supabase:api,isConfigured:true,toast:m=>messages.push(m),getRole:()=> 'administrativo'}).show();
 const change=(selector,value)=>{root.querySelector(selector).value=value;root.querySelector(selector).dispatchEvent(new dom.window.Event('change',{bubbles:true}));};
 root.querySelector('[data-attendance-download="excel"]').click();await tick();assert(!calls.some(c=>c.path.endsWith('fn_folha_ponto_mensal')));assert.match(messages.at(-1),/Selecione/);
 change('[data-attendance-report-work]','120');change('[data-attendance-report-month]','2026-09');
 for(const format of ['excel','pdf']) {root.querySelector(`[data-attendance-download="${format}"]`).click();await tick();assert.deepEqual(calls.at(-1).body,{p_mes:'2026-09-01',p_obra_id:'120'});}
 assert.deepEqual(files,['folha-ponto-obra-120-2026-09.xlsx','folha-ponto-obra-120-2026-09.pdf']);
 } finally {globalThis.window=savedWindow;dom.window.close();}
});
test('relatório não aparece para Diretor, Adjunto ou Encarregado mesmo com pode_validar',async()=>{
 for(const role of ['diretor_obra','adjunto','encarregado']) {
 const dom=new JSDOM('<div id="root"></div>'),root=dom.window.document.querySelector('#root');
 await createAttendanceModule({root,supabase:async()=>new Response(JSON.stringify({obra_id:'120',obras:[work],equipa:[],linhas:[],pode_validar:true})),isConfigured:true,toast:()=>{},getRole:()=>role}).show();
 assert(!root.querySelector('[data-attendance-download]'));dom.window.close();
 }
});
test('Folha de Ponto não apresenta pessoas fora da equipa e preserva tempos vazios guardados',async()=>{
 const dom=new JSDOM('<div id="root"></div>'),root=dom.window.document.querySelector('#root');
 const api=async path=>new Response(JSON.stringify(path.endsWith('fn_equipa_obra_encarregado')?{obra_id:'120',obras:[work],equipa:[{colaborador_id:'p'}]}:{obras:[work],linhas:[{colaborador_id:'other',nome:'Outra equipa',periodos:['dia_inteiro']},{colaborador_id:'p',nome:'Pessoa',periodos:['dia_inteiro'],ponto:{estado:'presente',horas:4,entrada_manha:null,saida_manha:null,entrada_tarde:'13:00:00',saida_tarde:'17:00:00'}}]}));
 await createAttendanceModule({root,supabase:api,isConfigured:true,toast:()=>{},getRole:()=> 'encarregado'}).show();
 assert(!root.textContent.includes('Outra equipa'));assert.equal(root.querySelector('[name=entrada_manha]').value,'');assert.equal(root.querySelector('[name=entrada_tarde]').value,'13:00');dom.window.close();
});
test('guardar falta com nota usa apenas RPC de ponto e mantém justificação pendente',async()=>{
 const dom=new JSDOM('<div id="root"></div>'),root=dom.window.document.querySelector('#root'),calls=[];
 const api=async(path,opt)=>{calls.push({path,body:JSON.parse(opt.body)});return new Response(JSON.stringify(path.endsWith('fn_equipa_obra_encarregado')?{obra_id:'120',obras:[work],equipa:[{colaborador_id:'p'}]}:{obras:[work],linhas:[{colaborador_id:'p',nome:'Pessoa',periodos:['dia_inteiro']}]}));};
 await createAttendanceModule({root,supabase:api,isConfigured:true,toast:()=>{},getRole:()=> 'encarregado'}).show({date:'2026-09-28'});
 const form=root.querySelector('form');form.elements.estado.value='falta_com_justificacao';form.elements.estado.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
 assert(form.elements.observacao.required);assert(form.querySelector('fieldset').disabled);form.elements.observacao.value='Documento entregue';
 form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await tick();
 const save=calls.find(c=>c.path.endsWith('fn_guardar_ponto_obra'));assert.equal(save.body.p_obra_id,'120');assert.equal(save.body.p_data,'2026-09-28');assert.equal(save.body.p_estado,'falta_com_justificacao');assert.equal(save.body.p_observacao,'Documento entregue');assert(!calls.some(c=>c.path.endsWith('fn_validar_justificacao_ponto')));dom.window.close();
});
