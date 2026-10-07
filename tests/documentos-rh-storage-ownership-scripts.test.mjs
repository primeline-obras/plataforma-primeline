import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ownershipInventory,rolloutFiles} from './documentos-rh-storage-ownership-inventory.mjs';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8').replaceAll('\r','');
test('complete rollout inventory: managed DDL is confined to the owner-scoped restrictive policy',()=>{
 const inventory=ownershipInventory();assert.equal(rolloutFiles.length,18);
 assert.deepEqual(inventory.filter(x=>x.classification==='UNSUPPORTED_REMOVE'),[]);
 const managed=inventory.filter(x=>x.classification==='REQUIRES_STORAGE_OWNER');
 assert.equal(managed.length,1);assert.match(managed[0].excerpt,/CREATE POLICY rh_storage_empresa_guard/);
 assert.equal(managed[0].storage_owner_role_active,true);
 for(const file of rolloutFiles){const sql=read('supabase/'+file);
  assert.doesNotMatch(sql,/GRANT\s+supabase_storage_admin\s+TO\s+postgres|ALTER\s+(?:TABLE|SCHEMA)\s+storage\.[^;]+OWNER\s+TO\s+postgres/i,file);
 }
 const committed=JSON.parse(read('docs/pacote-2-storage-owner-inventory-20261007.json'));
 assert.deepEqual(committed.occurrences,inventory,'Inventory must match the final committed SQL');
});
test('pre/post/rollback preserve Storage ownership and remain read-only where required',()=>{
 const migration=read('supabase/documentos_rh_tenant.sql');
 assert.doesNotMatch(migration,/ALTER TABLE storage\.(objects|buckets) ENABLE ROW LEVEL SECURITY/);
 assert.match(migration,/pg_has_role\(session_user,'supabase_storage_admin','SET'\)/);
 assert.match(migration,/SET LOCAL ROLE supabase_storage_admin;\nCREATE POLICY rh_storage_empresa_guard[\s\S]*?RESET ROLE;\nREVOKE USAGE ON SCHEMA primeline_documentos_rh_privado FROM supabase_storage_admin;/);
 for(const name of ['documentos_rh_tenant_postcheck','documentos_rh_tenant_rollback_postcheck']){
  const s=read('supabase/'+name+'.sql');assert.match(s,/BEGIN READ ONLY;/);assert.match(s,/STORAGE_OWNER_OR_RLS_DRIFT/);assert.doesNotMatch(s,/SET LOCAL ROLE|ALTER TABLE|CREATE POLICY|DROP POLICY/i);
 }
 const rollback=read('supabase/documentos_rh_tenant_rollback.sql');assert.doesNotMatch(rollback,/(?:CREATE|DROP|ALTER) POLICY[^;]*ON storage\./i);
 const resume=read('supabase/documentos_rh_tenant_resume_precheck_20261007.sql');
 assert.match(resume,/BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;/);assert.match(resume,/ROLLBACK;\s*$/);
 assert.doesNotMatch(resume,/RAISE NOTICE|CREATE\s+(?:TABLE|FUNCTION|SCHEMA)|GRANT\s|REVOKE\s/i);
 for(const state of ['CLEAN_START','VALID_EXISTING_BACKUP_RESUME','PARTIAL_OR_UNKNOWN_STATE','READY_TO_RESUME_DOCUMENTAL_MIGRATION','BLOCKED'])assert.ok(resume.includes(state),state);
 // The real expected catalog is copied unchanged, never recalibrated to the new implementation.
 const original=read('supabase/pacote2_precheck_real_final_20261007.sql');
 const baseline=s=>s.match(/WITH baseline AS \(SELECT '([\s\S]*?)'::jsonb data\),/)[1];assert.equal(baseline(resume),baseline(original));
 assert.equal((resume.match(/AS resume_precheck;/g)||[]).length,1);
});
