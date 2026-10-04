import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const read=async p=>(await readFile(new URL(p,import.meta.url),'utf8')).replaceAll('\r','');
const inventory=JSON.parse(await read('./fixtures/writers-economicos-inventario-20261004.json'));
const scripts=Object.fromEntries(await Promise.all(['precheck','backup','migration','postcheck','rollback'].map(async kind=>[kind,await read('../supabase/encarregado_escopo_'+kind+'.sql')])));
test('12 writers: tenant precedes the unchanged functional role, contracts preserved',()=>{
 for(const f of inventory.functions){
  const definition=scripts.migration.slice(scripts.migration.indexOf('CREATE OR REPLACE FUNCTION public.'+f.name+'(')).split('ALTER FUNCTION public.')[0];
  assert.ok(definition.startsWith(f.original_definition.split(' LANGUAGE ')[0]));
  const body=definition.split('AS $function$')[1].split('$function$')[0];
  assert.equal(createHash('md5').update(body).digest('hex'),f.expected_body_md5);
  const role=body.search(/if not (?:\(public\.fn_e_gestao_plataforma|public\.fn_(?:e_diretor_obra|pode_editar_obra|pode_editar_mapa_gestao_obras))/);
  assert.ok(role>body.indexOf('perform public.fn_financeiro_autorizar_obra('),f.name);
  assert.ok(body.includes('for update')||body.includes('for share'),f.name+' locks resource');
 }
});
test('consolidated scripts inventory all 12 and postcheck pins bodies/ACL/headers',()=>{
 for(const f of inventory.functions){
  for(const kind of ['precheck','backup','postcheck','rollback'])assert.ok(scripts[kind].includes("'"+f.signature+"'"),kind+' '+f.signature);
  assert.ok(scripts.postcheck.includes(f.expected_body_md5));
 }
 assert.ok(scripts.postcheck.includes('original_definition'));
 assert.ok(scripts.postcheck.includes('PRIVATE_TENANT_HELPER_INVALID'));
 assert.ok(scripts.rollback.includes('LOOP EXECUTE def; END LOOP;'));
 assert.ok(scripts.precheck.includes('BEGIN READ ONLY;'));assert.ok(scripts.postcheck.includes('BEGIN READ ONLY;'));
 assert.doesNotMatch(scripts.migration,/CREATE(?: OR REPLACE)? FUNCTION public\.fn_financeiro_autorizar_obra[\s\S]*?GRANT EXECUTE ON FUNCTION public\.fn_financeiro_autorizar_obra/);
});
