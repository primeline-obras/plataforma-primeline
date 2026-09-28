import test from 'node:test';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {readFile} from 'node:fs/promises';
import {createAttendanceModule} from '../src/attendance.js';
const {JSDOM}=await import(process.env.QUADRO_JSDOM ? pathToFileURL(process.env.QUADRO_JSDOM).href : './quadro-runtime/node_modules/jsdom/lib/api.js');
test('Encarregado vê apenas obra autorizada, horários completos e linguagem nova',async()=>{
 const dom=new JSDOM('<div id="attendance"></div>');const root=dom.window.document.querySelector('#attendance');
 const calls=[];
 const supabase=async(path,options)=>{
  calls.push({path,body:JSON.parse(options.body)});
  if(path.endsWith('fn_equipa_obra_encarregado')) return new Response(JSON.stringify({obra_id:'120',obras:[{id:'120',numero:'120',nome:'A minha obra'}],equipa:[{colaborador_id:'c1'}]}));
  return new Response(JSON.stringify({obras:[{id:'120',numero:'120',nome:'A minha obra'},{id:'118',numero:'118',nome:'Outra obra'}],pode_validar:false,
    linhas:[{colaborador_id:'c1',nome:'Pessoa',funcao:'Pedreiro',periodos:['dia_inteiro']}]}));
 };
 const module=createAttendanceModule({root,supabase,isConfigured:true,toast:()=>{},getRole:()=> 'encarregado'});
 await module.show();
 assert(root.classList.contains('attendance-touch'));
 assert.equal(root.querySelector('[data-attendance-work]').value,'120');
 assert(!root.querySelector('[data-attendance-work]').textContent.includes('Outra obra'));
 for(const [field,time] of [['entrada_manha','08:00'],['saida_manha','12:00'],['entrada_tarde','13:00'],['saida_tarde','17:00']]) assert.equal(root.querySelector(`[name=${field}]`).value,time);
 assert(root.textContent.includes('FOLHA DE PONTO'));assert(root.textContent.includes('GUARDAR REGISTO'));
 assert(!root.querySelector('[data-attendance-download]'));
 assert.equal(calls.at(-1).body.p_obra_id,'120');dom.window.close();
});
test('nomenclatura antiga retirada dos componentes visíveis',async()=>{
 for(const file of ['../src/app.js','../src/attendance.js']) {
 const text=await readFile(new URL(file,import.meta.url),'utf8');
 assert(!/ponto de obra|ponto diário|guardar ponto|relatório mensal de horas/i.test(text));
 }
});
