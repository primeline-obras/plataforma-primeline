import {readFileSync,readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const folder=fileURLToPath(new URL('../supabase/',import.meta.url));
export const rolloutFiles=readdirSync(folder).filter(n=>/^(documentos_rh_tenant|folha_ponto_v2|folha_v2_legacy_cutover)(?:_|\.)/.test(n)&&n.endsWith('.sql')).sort();
export function ownershipInventory(){
 const result=[];
 for(const file of rolloutFiles){
  let storageRole=false;
  readFileSync(join(folder,file),'utf8').replaceAll('\r','').split('\n').forEach((text,index)=>{
   const line=text.trim();if(!line||line.startsWith('--'))return;
   if(/^SET LOCAL ROLE supabase_storage_admin;/i.test(line))storageRole=true;
   const category=/\b(?:ALTER\s+(?:TABLE|FUNCTION|SCHEMA|POLICY)|CREATE\s+(?:OR REPLACE\s+)?(?:POLICY|TRIGGER)|DROP\s+POLICY|GRANT|REVOKE|OWNER\s+TO|AUTHORIZATION|current_user|session_user|pg_has_role)\b|\b(?:storage|auth|extensions|realtime|vault)\./i;
   if(category.test(line)){
    const managedDDL=/\b(?:ALTER\s+(?:TABLE|FUNCTION|SCHEMA)\s+(?:ONLY\s+)?(?:storage|auth|extensions|realtime|vault)\.|(?:CREATE|DROP|ALTER)\s+POLICY\s+\S+\s+ON\s+(?:storage|auth|extensions|realtime|vault)\.|(?:GRANT|REVOKE)\s+.+?\s+ON\s+(?:TABLE|FUNCTION|SCHEMA)\s+(?:storage|auth|extensions|realtime|vault)(?:\.|\s))|\bGRANT\s+supabase_storage_admin\s+TO\b/i.test(line);
    const policy=/^(?:CREATE|DROP|ALTER) POLICY\s+\S+\s+ON storage\.(?:objects|buckets)\b/i.test(line);
    const ddl=/\b(?:ALTER\s+(?:TABLE|FUNCTION|SCHEMA|POLICY)|CREATE\s+(?:OR REPLACE\s+)?(?:POLICY|TRIGGER)|DROP\s+POLICY|GRANT|REVOKE|OWNER\s+TO|AUTHORIZATION)\b/i.test(line);
    const classification=managedDDL?(policy&&storageRole?'REQUIRES_STORAGE_OWNER':'UNSUPPORTED_REMOVE'):ddl?'POSTGRES_OWNED_OK':'READ_ONLY_OK';
    result.push({file:'supabase/'+file,line:index+1,classification,storage_owner_role_active:storageRole,excerpt:line.length>300?line.slice(0,300)+' …':line});
   }
   if(/^RESET ROLE;/i.test(line))storageRole=false;
  });
 }
 return result;
}
