import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {focusedInventory,focusedResidual} from './writers-economicos-final-scan.mjs';
const read=async p=>(await readFile(new URL(p,import.meta.url),'utf8')).replaceAll('\r','');
const inventory=JSON.parse(await read('./fixtures/writers-economicos-final-inventario-20261004.json'));
const scripts=Object.fromEntries(await Promise.all(['precheck','backup','migration','postcheck','rollback'].map(async kind=>[kind,await read('../supabase/encarregado_escopo_'+kind+'.sql')])));
const definition=f=>scripts.migration.slice(scripts.migration.indexOf('CREATE OR REPLACE FUNCTION public.'+f.name+'(')).split('ALTER FUNCTION public.')[0];

test('final focused residual search is zero; 14 requested plus two additional writers covered',()=>{
 assert.equal(inventory.functions.length,16);
 assert.deepEqual(focusedResidual,[]);
 for(const f of inventory.functions){
  const found=focusedInventory.find(x=>x.signature===f.signature);
  assert.ok(found,f.signature);
  assert.equal(found.status,f.external?'SCOPED':'INTERNAL_ONLY',f.signature);
 }
});
test('final consolidated scripts cover exact contracts, bodies, privileges and rollback',()=>{
 for(const f of inventory.functions){
  for(const kind of ['precheck','backup','postcheck','rollback'])assert.ok(scripts[kind].includes("'"+f.signature+"'"),kind+' '+f.signature);
  const def=definition(f);
  assert.ok(def.startsWith(f.original_definition.split(' LANGUAGE ')[0]));
  const body=def.split('$function$')[1];
  assert.equal(createHash('md5').update(body).digest('hex'),f.expected_body_md5);
  assert.ok(scripts.postcheck.includes(f.expected_body_md5));
  assert.ok(body.includes('fn_financeiro_autorizar_obra('));
 }
});
test('financial importer rejects all general expenses before import writes or logging',()=>{
 const f=inventory.functions.find(f=>f.name==='fn_importar_mapa_financeiro_xlsx');
 const body=definition(f).split('$function$')[1];
 const block=body.indexOf('DESPESAS_GERAIS_BLOQUEADAS');
 const write=body.search(/insert\s+into/i);
 assert.ok(block>=0 && block<write);
 assert.ok(body.indexOf('fn_financeiro_autorizar_obra(')<write);
 assert.ok(body.indexOf('fn_log_importacao_xlsx(')>write);
 assert.doesNotMatch(body,/\b(?:insert\s+into|update|delete\s+from)\s+public\.debitos_diretos/i);
 assert.doesNotMatch(scripts.migration,/ALTER TABLE\s+(?:public\.)?debitos_diretos\s+ADD/i);
 assert.match(body,/errcode = '0A000'/);
});
