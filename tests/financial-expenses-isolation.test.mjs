import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url));
const base='1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0';
test('ENCARREGADO_IMPACT = NONE: diff protegido e importador compartilhado intacto',()=>{
 const names=execFileSync('git',['diff','--name-only',base,'--','src/','index.html','styles.css','workforce-calendar.css'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/).filter(Boolean);
 assert.ok(names.every(n=>['src/financial-map.js','src/financial-expenses-import.js'].includes(n)),names.join('\n'));
 const shared=execFileSync('git',['show',base+':src/xlsx-operational-import.js'],{cwd:root,encoding:'utf8',windowsHide:true}).replaceAll('\r','');
 assert.equal(readFileSync(new URL('../src/xlsx-operational-import.js',import.meta.url),'utf8').replaceAll('\r',''),shared);
 const importer=readFileSync(new URL('../src/financial-expenses-import.js',import.meta.url),'utf8');
 assert.doesNotMatch(importer,/rpc\/fn_(equipa|folha|quadro)|\/storage\//);
});
test('não substitui scripts antigos nem abre o ramo antigo de despesas',()=>{
 const names=execFileSync('git',['diff','--name-only',base,'--','supabase/'],{cwd:root,encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/).filter(Boolean);
 assert.ok(names.every(n=>/^supabase\/financeiro_debitos_tenant_20261011(?:_(precheck|backup|postcheck|rollback))?\.sql$/.test(n)),names.join('\n'));
 const sql=readFileSync(new URL('../supabase/financeiro_debitos_tenant_20261011.sql',import.meta.url),'utf8');
 assert.doesNotMatch(sql,/CREATE(?: OR REPLACE)? FUNCTION public\.fn_importar_mapa_financeiro_xlsx|\bSET ROLE\b|\bDROP\b[^;]+\bCASCADE\b/);
});
