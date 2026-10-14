import fs from 'node:fs';import path from 'node:path';
const out='docs/auditorias/auditoria-global-noturna-20261014';
const files=fs.readdirSync('src').filter(x=>x.endsWith('.js')).sort();
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
const csv=(name,rows)=>fs.writeFileSync(path.join(out,name),rows.map(r=>r.map(quote).join(',')).join('\n')+'\n');
const moduleRows=[],endpoints=[],imports=[];
for(const file of files){const body=fs.readFileSync('src/'+file,'utf8'),lines=body.split(/\r?\n/),seen=new Set();
 for(let i=0;i<lines.length;i++){
  for(const m of lines[i].matchAll(/rpc\/(fn_[a-zA-Z0-9_]+)/g)){const key=m[1];if(!seen.has(key)){endpoints.push(['src/'+file,i+1,'RPC',key,'referência estática; autorização/instalação não inferida']);seen.add(key);}}
  for(const m of lines[i].matchAll(/(?:api|query|supabase|request|optionalClassification)\(\s*["'`]([a-z][a-z0-9_]+)\?/g)){if(!seen.has(m[1])){endpoints.push(['src/'+file,i+1,'REST',m[1],'referência estática; seleção/DML rever no consumidor']);seen.add(m[1]);}}
  for(const m of lines[i].matchAll(/(?:import.*?from\s*|import\(\s*)["'](\.\/[a-z0-9-]+\.js)(?:\?[^"']*)?["']/g))imports.push(['src/'+file,i+1,m[1]]);
 }
 const tests=fs.readdirSync('tests').filter(x=>x.endsWith('.test.mjs')&&fs.readFileSync('tests/'+x,'utf8').includes(file));
 moduleRows.push([file,lines.length,Buffer.byteLength(body),seen.size,tests.join(';'),'inspecção estática de referências; não prova funcional/produção']);
}
csv('11-REFERENCIAS-FRONTEND.csv',[['ficheiro','linha','tipo','objeto','limite'],...endpoints]);csv('12-FICHEIROS-TESTES.csv',[['ficheiro','linhas','bytes','referencias_endpoints','testes_que_referenciam_ficheiro','limite'],...moduleRows]);
const functions=[],definitions=new Map();
const excludedSeeds=fs.readdirSync('supabase').filter(x=>/(importar_dados_reais|nomes_reais|preencher_fornecedores_fontes|obra_118|atualizar_obra_120|import_obra_120|classificacao_especialidades_lote)/.test(x));
for(const file of fs.readdirSync('supabase').filter(x=>x.endsWith('.sql')&&!excludedSeeds.includes(x)).sort()){
 const body=fs.readFileSync('supabase/'+file,'utf8');for(const m of body.matchAll(/create\s+(?:or\s+replace\s+)?function\s+((?:public|folha_privado|[a-z_]+)\.)?([a-z_0-9]+)\s*\(/gi)){
 const name=(m[1]||'public.')+m[2],line=body.slice(0,m.index).split('\n').length;functions.push(['supabase/'+file,line,name,/_(?:backup|rollback|postcheck|precheck)\b/.test(file)?'script auxiliar/restauro':'script de definição; ordem de aplicação não determinada']);if(!definitions.has(name))definitions.set(name,[]);definitions.get(name).push(file+':'+line);
 }}
csv('13-DEFINICOES-SQL.csv',[['ficheiro','linha','funcao','natureza'],...functions]);
csv('14-SOBREPOSICOES-SQL.csv',[['funcao','definicoes','classificacao'],...[...definitions].filter(([k,v])=>v.length>1).map(([k,v])=>[k,v.join(';'),'CONFIRMADO existência múltipla; não implica duplicação instalada'])]);
fs.writeFileSync(path.join(out,'15-COBERTURA-ESTATICA.json'),JSON.stringify({src_js_files:files.length,supabase_sql_files:fs.readdirSync('supabase').filter(x=>x.endsWith('.sql')).length,test_mjs_files:fs.readdirSync('tests').filter(x=>x.endsWith('.mjs')).length,endpoint_references:endpoints.length,sql_definitions:functions.length,imports_count:imports.length,production_inspected:false,seed_files_excluded:excludedSeeds,supabase_sql_indexed:fs.readdirSync('supabase').filter(x=>x.endsWith('.sql')&&!excludedSeeds.includes(x)).length},null,2)+'\n');
console.log(JSON.stringify({files:files.length,endpoints:endpoints.length,functions:functions.length}));
