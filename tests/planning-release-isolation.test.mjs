import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

test('grafo do Planeamento isolado não depende de módulos financeiros ou outros módulos urgentes',async()=>{
 const seen=new Set();
 async function visit(file){
  if(seen.has(file.href))return;seen.add(file.href);
  const source=await readFile(file,'utf8');
  for(const match of source.matchAll(/(?:import|export)[^;]*?from\s+['"]([^'"]+)['"]/g)){
   const dependency=match[1].split('?')[0];
   assert.doesNotMatch(dependency,/monthly|financial|contract-composition|tee-index|workforce/);
   if(dependency.startsWith('.'))await visit(new URL(dependency,file));
  }
 }
 await visit(new URL('../src/planning.js',import.meta.url));
 assert(seen.has(new URL('../src/planning-batch.js',import.meta.url).href));
 assert(seen.has(new URL('../src/planning-operational.js',import.meta.url).href));
});
