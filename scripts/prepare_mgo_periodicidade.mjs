// Apenas prepara ficheiro/manifesto; nunca liga à base de dados.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {parseManagementWorkbook} from '../src/management-map.js';
const [library,input,output,manifestPath]=process.argv.slice(2);
const X=createRequire(import.meta.url)(library);globalThis.XLSX=X;
const book=X.read(fs.readFileSync(input),{cellDates:false});
const before=parseManagementWorkbook(book);
assert.equal(before.rows.length,1294);
const monthlyNames=new Set([
 'HENRIQUE BOGÉA','YNAÊ DE OLIVEIRA BOMFIM','JORDANE SILVESTRE',
 'ANA CAROLINA SARAIVA','JOSÉ TRAVI','RAFAEL PIRES','KAMILA BATISTA GUTTERRES'
]);
const labor=before.rows.filter(r=>r.categoria==='mao_obra');
const monthly=labor.filter(r=>monthlyNames.has(r.colaborador.toUpperCase()));
assert.equal(monthly.length,35);
assert.equal(new Set(monthly.map(r=>r.colaborador.toUpperCase())).size,7);
assert.equal(labor.length,669);
const sheetName=book.SheetNames.find(n=>/funcion|mão|mao/i.test(n));
assert.ok(sheetName);
const sheet=book.Sheets[sheetName],range=X.utils.decode_range(sheet['!ref']);
const grid=X.utils.sheet_to_json(sheet,{header:1,defval:''});
const header=grid.findIndex(r=>r.some(v=>String(v).trim().toLowerCase().startsWith('obra')));
assert.ok(header>=0);
const typeCol=range.e.c+1,monthCol=range.e.c+2;
sheet[X.utils.encode_cell({r:header,c:typeCol})]={t:'s',v:'Tipo Registo'};
sheet[X.utils.encode_cell({r:header,c:monthCol})]={t:'s',v:'Mês Referência'};
const manifest=[];
for(const row of labor){
 const isMonthly=monthlyNames.has(row.colaborador.toUpperCase());
 const cellRow=row.linha-1;
 sheet[X.utils.encode_cell({r:cellRow,c:typeCol})]={t:'s',v:isMonthly?'mensal':'diario'};
 if(isMonthly){
   const month=row.data.slice(0,7)+'-01';
   sheet[X.utils.encode_cell({r:cellRow,c:monthCol})]={t:'s',v:month};
   manifest.push({...row,tipo_registo:'mensal',mes_referencia:month});
 }
}
range.e.c=monthCol;sheet['!ref']=X.utils.encode_range(range);
const after=parseManagementWorkbook(book);
assert.deepEqual(after.errors,[]);
assert.equal(after.rows.length,before.rows.length);
for(let i=0;i<before.rows.length;i++){
 const a={...before.rows[i]},b={...after.rows[i]};
 for(const key of ['tipo_registo','mes_referencia']){delete a[key];delete b[key];}
 assert.deepEqual(a,b,'Alteração financeira inesperada na linha '+i);
}
assert.ok(!fs.existsSync(output),'Não substituir Excel existente.');
assert.ok(!fs.existsSync(manifestPath),'Não substituir manifesto existente.');
fs.writeFileSync(output,X.write(book,{type:'buffer',bookType:'xlsx'}));
fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
assert.deepEqual(parseManagementWorkbook(X.read(fs.readFileSync(output))).rows,after.rows);
console.log(JSON.stringify({linhas:after.rows.length,mensais:manifest.length,diarias:labor.length-manifest.length,campos_financeiros_preservados:true,erros:after.errors}));
