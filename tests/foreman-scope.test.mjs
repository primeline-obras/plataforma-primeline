import test from 'node:test';
import assert from 'node:assert/strict';
import {loadForemanDirectory,loadForemanAbsences} from '../src/foreman-scope.js';
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

test('absence RPC returns operational availability and filters vacation panel',async()=>{
 const calls=[];const api=async(path,options)=>{calls.push({path,body:JSON.parse(options.body)});return Response.json([{id:'a',tipo:'ferias'},{id:'b',tipo:'ausencia'}]);};
 assert.equal((await (await loadForemanAbsences(api,'2026-10-01','2026-10-31')).json()).length,2);
 assert.deepEqual(await (await loadForemanAbsences(api,'2026-10-01','2026-10-31',true)).json(),[{id:'a',tipo:'ferias'}]);
 assert.ok(calls.every(c=>c.path==='rpc/fn_ausencias_equipa_encarregado'));
 assert.deepEqual(calls[0].body,{p_inicio:'2026-10-01',p_fim:'2026-10-31'});
});

test('absence RPC missing/denied/malformed fails closed without raw table fallback',async()=>{
 for(const status of [403,404,500]){const calls=[];const r=await loadForemanAbsences(async path=>{calls.push(path);return new Response('{}',{status});},'2026-10-01','2026-10-31');assert.equal(r.status,status);assert.equal(calls.length,1);}
 assert.equal((await loadForemanAbsences(async()=>Response.json({}), '2026-10-01','2026-10-31')).status,502);
});
