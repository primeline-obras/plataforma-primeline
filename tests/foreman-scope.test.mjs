import test from 'node:test';
import assert from 'node:assert/strict';
import {loadForemanDirectory} from '../src/foreman-scope.js';
test('scoped directory uses existing authorised works, deduplicates and separates Medicine permission',async()=>{
  const calls=[];
  const result=await loadForemanDirectory(async(path,options)=>{
    const b=JSON.parse(options.body);calls.push({path,b});
    if(path.endsWith('fn_colaborador_na_obra_atual_encarregado'))return Response.json(b.p_colaborador_id==='p1');
    if(!b.p_obra_id)return Response.json({obras:[{id:'w1'},{id:'w2'}]});
    return Response.json({linhas:[{colaborador_id:'p1',nome:'Equipa sintética',funcao:'Pedreiro'},{colaborador_id:'p2',nome:'Outra parcela autorizada',funcao:'Servente'}]});
  },'2026-10-04');
  assert.equal(result.people.length,2);assert.deepEqual([...result.medicineIds],['p1']);
  assert.ok(calls.every(c=>c.path.startsWith('rpc/')));assert.equal(calls.length,5);
  assert.ok(result.people.every(p=>Object.keys(p).join(',')==='id,nome,funcao,data_saida'));
});
test('unavailable scope fails closed, never falls back to company directory',async()=>{
  const calls=[];await assert.rejects(loadForemanDirectory(async path=>{calls.push(path);return new Response('{}',{status:403});},'2026-10-04'));
  assert.deepEqual(calls,['rpc/fn_listar_ponto_obra']);
});
