import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ownershipInventory,rolloutFiles} from './documentos-rh-storage-ownership-inventory.mjs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8').replaceAll('\r','');
test('rollout SQL has zero managed DDL, zero Storage locks and no role/owner workaround',()=>{
 const inventory=ownershipInventory();assert.equal(rolloutFiles.length,19);
 assert.deepEqual(inventory.filter(x=>['UNSUPPORTED_REMOVE','REQUIRES_STORAGE_OWNER'].includes(x.classification)),[]);
 for(const file of rolloutFiles){const sql=read('supabase/'+file);
 assert.doesNotMatch(sql,/SET\s+(?:LOCAL\s+)?ROLE\s+supabase_storage_admin|GRANT\s+supabase_storage_admin|LOCK\s+TABLE\s+storage\.|ALTER\s+(?:TABLE|SCHEMA)\s+storage\./i,file);}
 const committed=JSON.parse(read('docs/pacote-2-storage-owner-inventory-20261007.json'));assert.deepEqual(committed.occurrences,inventory);
});
test('exact 18 frozen Storage paths narrowed, no extra permissive policy or UPDATE permission',()=>{
 const manifest=JSON.parse(read('docs/storage-policy-rollout-20261007.json'));
 const baseline=JSON.parse(read('tests/fixtures/pacote2-real-baseline-20261007.json'));
 const policies=baseline.tables.find(t=>t.schema==='storage'&&t.name==='objects').policies;
 assert.equal(manifest.policies.length,18);assert.ok(!policies.some(p=>p.cmd==='UPDATE'));
 for(const p of policies){const e=manifest.policies.find(x=>x.policyname===p.policyname);for(const k of Object.keys(p))assert.deepEqual(e[k],p[k]);
 for(const [original,expected] of [['qual','expected_qual'],['with_check','expected_with_check']])assert.equal(e[expected],p[original]?'('+p[original]+') AND '+manifest.helper:null);}
});
test('read-only stages and unchanged frozen baseline; capability is external not SET-role',()=>{
 for(const n of ['documentos_rh_tenant_postcheck','documentos_rh_tenant_intermediate_postcheck','documentos_rh_tenant_rollback_postcheck']){const s=read('supabase/'+n+'.sql');assert.match(s,/BEGIN READ ONLY/);assert.match(s,/DOCUMENT_ORIGINAL_BACKUP_CHANGED/);assert.doesNotMatch(s,/CREATE TABLE|CREATE POLICY|ALTER POLICY|DROP POLICY|SET LOCAL ROLE/i);}
 const resume=read('supabase/documentos_rh_tenant_resume_precheck_20261007.sql');assert.match(resume,/STORAGE_DASHBOARD_POLICY_REQUIRED/);assert.match(resume,/supautils.policy_grants/);assert.ok(!resume.includes('STORAGE_OWNER_CAPABILITY_BLOCKED'));
 const baseline=s=>s.match(/WITH baseline AS \(SELECT '([\s\S]*?)'::jsonb data\),/)[1];assert.equal(baseline(resume),baseline(read('supabase/pacote2_precheck_real_final_20261007.sql')));
 assert.equal((resume.match(/AS resume_precheck;/g)||[]).length,1);
 const migration=read('supabase/documentos_rh_tenant.sql');assert.doesNotMatch(migration,/ALTER FUNCTION[^;]*OWNER TO/i);assert.match(migration,/CREATE TEMP TABLE documental_policy_parser/);assert.match(migration,/ON COMMIT DROP/);
});
