import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';
const dir='docs/auditorias/auditoria-global-noturna-20261014/FASE-2/';
const rows=[],sinks=[],files=[];
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
for(const file of fs.readdirSync('src').filter(x=>x.endsWith('.js')).sort()){
 const text=fs.readFileSync(path.join('src',file),'utf8'),lines=text.split('\n');let fn='module';let count=0,interpolations=0;
 lines.forEach((line,i)=>{
 const decl=line.match(/(?:async\s+)?function\s+(\w+)\s*\(/);if(decl)fn=decl[1];
 for(const m of line.matchAll(/(?:\.innerHTML\s*=|\.outerHTML\s*=|\.insertAdjacentHTML\s*\(|createContextualFragment\s*\()/g)){sinks.push({file:'src/'+file,line:i+1,function_context_heuristic:fn,sink:m[0],classification:'CANDIDATO; CONTEXTO E ORIGEM EXIGEM REVISÃO'});count++;}
 for(const m of line.matchAll(/\$\{([^{}\r\n]{1,240})\}/g)){
 const expr=m[1];interpolations++;
 if(/\b(?:work|supplier|invoice|billing|document|comment|message|alert|row|item|person|event|user)\b/.test(expr)) rows.push({file:'src/'+file,line:i+1,function_context_heuristic:fn,expression:expr,classification:/\b(?:escapeHtml|safeText|esc|Number|encodeURIComponent|format|euro|prettyDate)\b/.test(expr)?'ESCAPING/FORMATAÇÃO VISÍVEL; CONFIRMAR CONTEXTO':'REVISÃO MANUAL; NÃO EQUIVALE A VULNERABILIDADE'});
 }
 });files.push({file:'src/'+file,sink_count:count,interpolation_candidates:interpolations});
}
const csv=(name,items)=>{const fields=Object.keys(items[0]);fs.writeFileSync(dir+name,[fields.map(quote).join(','),...items.map(row=>fields.map(k=>quote(row[k])).join(','))].join('\n')+'\n')};
csv('HTML-SINKS.csv',sinks);csv('HTML-INTERPOLACOES.csv',rows);
fs.writeFileSync(dir+'HTML-INVENTARIO.json',JSON.stringify({method:'lexical scan, not AST/taint proof; nearest named function heuristic; nested interpolations may be omitted; no safety conclusion from counts',source_files:files.length,sinks:sinks.length,interpolations_review_queue:rows.length,files},null,2)+'\n');
assert.equal(files.length,56);
console.log(JSON.stringify({files:files.length,sinks:sinks.length,review_candidates:rows.length}));
const suspicious=rows.filter(x=>x.file==='src/app.js'&&x.classification.startsWith('REVISÃO')&&/\.(nome|cliente|morada|descricao|numero_doc|numero_fatura|observacao)|^(supplier|message)/.test(x.expression));
console.log(JSON.stringify(suspicious,null,2));
