import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {parseManagementWorkbook} from '../src/management-map.js';
const [library,input,snapshot,output]=process.argv.slice(2);
const X=createRequire(import.meta.url)(library);globalThis.XLSX=X;
const book=X.read(fs.readFileSync(input),{cellDates:false});
const exported=X.read(fs.readFileSync(snapshot,'utf8'),{type:'string',raw:true});
const directory=JSON.parse(X.utils.sheet_to_json(exported.Sheets[exported.SheetNames[0]])[0].fornecedores);
const mappings=new Map([
 ['Galp','São Januário, Lda (GALP)'],
 ['BP Sintra','Combustop, Lda (BP)'],
 ['Moeve','P.A Moeve Cascais-Birre'],
 ['Farmacia da Beloura','Farmácia da Beloura'],
 ['Farmacia Silveira Alcoitao','Farmacia Silveira Alcoitão'],
 ['Grupo Vendap','Grupo Vendap, S.A'],
 ['Andaluga','Andaluga - Aluguer De Andaimes E Máquinas Para A Construção, Lda'],
 ['Duvibri Lda','Duvibri'],
 ['Mourelec, Lda','Mourelec, Unipessoal Lda']
]);
for(const name of mappings.values())assert.equal(directory.filter(f=>f.cadastro.nome===name).length,1,'Cadastro ambíguo/ausente: '+name);
const before=parseManagementWorkbook(book);assert.equal(before.rows.length,1294);assert.deepEqual(before.errors,[]);
let changed=0,reimbursements=0;
for(const sheetName of ['MATERIAIS','SUBCONTRATOS','DESPESAS - ESTALEIRO']){
 const sheet=book.Sheets[sheetName],range=X.utils.decode_range(sheet['!ref']);
 let header=-1,supplier=-1,employee=-1,description=-1;
 for(let r=0;r<10&&header<0;r++)for(let c=0;c<=range.e.c;c++){
   const v=String(sheet[X.utils.encode_cell({r,c})]?.v||'').trim().toLowerCase();
   if(v==='fornecedor'){header=r;supplier=c;break;}
 }
 assert.ok(header>=0);
 for(let c=0;c<=range.e.c;c++){
   const v=String(sheet[X.utils.encode_cell({r:header,c})]?.v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toLowerCase();
   if(v==='colaborador')employee=c;
   if(v==='designacao'||v==='descricao')description=c;
 }
 if(sheetName==='DESPESAS - ESTALEIRO'&&employee<0){
   employee=++range.e.c;sheet[X.utils.encode_cell({r:header,c:employee})]={t:'s',v:'Colaborador'};
   sheet['!ref']=X.utils.encode_range(range);
 }
 for(let r=header+1;r<=range.e.r;r++){
   const addr=X.utils.encode_cell({r,c:supplier}),cell=sheet[addr],name=String(cell?.v||'').trim();
   if(mappings.has(name)){sheet[addr]={...cell,t:'s',v:mappings.get(name)};delete sheet[addr].w;changed++;}
   const desc=String(sheet[X.utils.encode_cell({r,c:description})]?.v||'').trim();
   if(sheetName==='DESPESAS - ESTALEIRO'&&!name&&desc==='Compra de água Vitor Lopes'){
     sheet[X.utils.encode_cell({r,c:employee})]={t:'s',v:'Vitor Lopes'};reimbursements++;
   }
 }
}
const after=parseManagementWorkbook(book);assert.deepEqual(after.errors,[]);assert.equal(changed,32);assert.equal(reimbursements,1);
assert.equal(after.rows.length,before.rows.length);
for(let i=0;i<before.rows.length;i++){
 const a={...before.rows[i]},b={...after.rows[i]};delete a.fornecedor;delete b.fornecedor;delete a.colaborador;delete b.colaborador;
 assert.deepEqual(a,b,'Alteração inesperada em valores/datas/obra: '+i);
}
assert.ok(!fs.existsSync(output),'Não substituir ficheiro existente.');
fs.writeFileSync(output,X.write(book,{type:'buffer',bookType:'xlsx'}));
assert.deepEqual(parseManagementWorkbook(X.read(fs.readFileSync(output))).rows,after.rows);
console.log(JSON.stringify({linhas:after.rows.length,nomes_corrigidos:changed,reembolsos_identificados:reimbursements,valores_datas_obras_preservados:true,ficheiro:output}));
