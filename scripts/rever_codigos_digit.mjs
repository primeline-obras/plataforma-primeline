// Conferência offline. Não atualiza colaboradores nem decide identidades aproximadas.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const [library,payrollPath,rhPath,output]=process.argv.slice(2);
const X=createRequire(import.meta.url)(library);
const rows=path=>{const b=X.read(fs.readFileSync(path));return X.utils.sheet_to_json(b.Sheets[b.SheetNames[0]],{header:1,raw:false,defval:''});};
const payroll=rows(payrollPath).slice(3).filter(r=>r[0]&&r[1]);
const rh=rows(rhPath),headers=rh.shift();
const current=rh.map(row=>Object.fromEntries(headers.map((h,i)=>[h,row[i]])));
const norm=s=>String(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim();
assert.equal(payroll.length,37);
assert.equal(new Set(payroll.map(r=>r[0])).size,37);
assert.ok(payroll.every(r=>/^\d{3}$/.test(r[0])));
const review=payroll.map(row=>{
 const matches=current.filter(c=>norm(c.nome)===norm(row[1]));
 const match=matches.length===1?matches[0]:null;
 return {
   codigo_digit:row[0],nome_digit:row[1],
   id_snapshot:match?.id||'',nome_snapshot:match?.nome||'',codigo_rh_snapshot:match?.codigo_rh||'',
   verificacao:match?'Nome exato no ficheiro anterior; confirmar cadastro atual':'Confirmar identidade no cadastro atual',
   decisao_administrativo:'',observacoes:''
 };
});
const b=X.utils.book_new();
const info=[
 ['REVISÃO — NÃO IMPORTAR ESTE FICHEIRO'],
 ['Fonte dos códigos: mapa dos vencimentos.xlsx, folha Folha1, linhas 4–40.'],
 ['O cadastro de comparação é histórico e não prova o estado atual da plataforma.'],
 ['Códigos são texto: preservar zeros iniciais. Não reutilizar códigos antigos como correspondência.'],
 ['Não altera nomes, contratos, alocações, estado ativo ou vencimentos.'],
 ['Não criar colaboradores ausentes. Confirmar o ID e o código atualmente gravado antes da atualização.'],
 ['O mapa contém o mês setembro mas não especifica o ano.'],
 ['Não presume que ausência justificada seja não remunerada.'],
 ['Km e Ajudas de Custo continuam manuais. Unidades de ausências e tratamento de Prémio aguardam confirmação.']
];
X.utils.book_append_sheet(b,X.utils.aoa_to_sheet(info),'Ler primeiro');
const s=X.utils.json_to_sheet(review);
s['!cols']=[{wch:15},{wch:48},{wch:38},{wch:42},{wch:22},{wch:68},{wch:30},{wch:45}];
s['!autofilter']={ref:s['!ref']};
X.utils.book_append_sheet(b,s,'Codigos para conferir');
assert.ok(!fs.existsSync(output),'Não substituir revisão existente.');
fs.writeFileSync(output,X.write(b,{type:'buffer',bookType:'xlsx'}));
const check=X.read(fs.readFileSync(output));
assert.deepEqual(X.utils.sheet_to_json(check.Sheets['Codigos para conferir'],{defval:''}),review);
console.log(JSON.stringify({linhas:review.length,nomes_exatos_no_snapshot:review.filter(r=>r.id_snapshot).length,sem_correspondencia_exata:review.filter(r=>!r.id_snapshot).length,zeros_preservados:true,alteracoes_na_base:0}));
