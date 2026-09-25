// Comparação conservadora do Excel histórico com um snapshot integral do diretório.
// Não usa nomes aproximados para fazer fusões; sem correspondência certa => revisão.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export const clean = v => String(v ?? '').replace(/\u00a0/g,' ').replace(/\s+/g,' ').trim();
export const norm = v => clean(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const words=v=>clean(v).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().match(/[a-z0-9]+/g)||[];
export const emails=v=>[...new Set((clean(v).match(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/gi)||[]).map(x=>x.toLowerCase()))];
export function phones(v) {
  // Grupos de nove dígitos portugueses; mantém todos os números na nota de origem.
  const candidates=clean(v).match(/(?:\+351[ .-]*)?(?:\d[ .-]*){9}(?!\d)/g)||[];
  return [...new Set(candidates.map(x=>x.replace(/\D/g,'')).map(x=>x.length===12&&x.startsWith('351')?x.slice(3):x).filter(x=>/^[239]\d{8}$/.test(x)))];
}
const uniq=xs=>[...new Set(xs.filter(Boolean))];
const legal=v=>words(v).filter(w=>!['lda','sa','unipessoal','sociedade','ltd'].includes(w)).join('');
const common=new Set(['a','o','de','da','do','das','dos','e','and','lda','sa','unipessoal','sociedade','construcoes','construcao','civil','comercio','comercial','portugal','grupo','servicos','sistemas','materiais']);
function editDistance(a,b){let prev=Array.from({length:b.length+1},(_,i)=>i);for(let i=1;i<=a.length;i++){const next=[i];for(let j=1;j<=b.length;j++)next[j]=Math.min(next[j-1]+1,prev[j]+1,prev[j-1]+(a[i-1]===b[j-1]?0:1));prev=next;}return prev[b.length];}
export function similar(a,b){const x=legal(a),y=legal(b);if(!x||!y)return false;if(x===y)return true;if(Math.min(x.length,y.length)>=5&&(x.includes(y)||y.includes(x)))return true;if(Math.max(x.length,y.length)>=6&&Math.abs(x.length-y.length)<=2&&editDistance(x,y)<=2)return true;const aw=words(a).filter(w=>w.length>=4&&!common.has(w)),bw=words(b).filter(w=>w.length>=4&&!common.has(w));return aw.some(w=>bw.includes(w));}

export function extractWorkbook(X,book){
  const rows=[],orphans=[],skippedSheets=[];let sheets=0;
  for(const sheet of book.SheetNames){const grid=X.utils.sheet_to_json(book.Sheets[sheet],{header:1,raw:true,defval:''});
    const h=grid.slice(0,10).findIndex(r=>norm(r[0])==='nome'&&norm(r[1]).startsWith('ativ'));
    if(h<0){skippedSheets.push(sheet);continue;}sheets++;
    for(let i=h+1;i<grid.length;i++){
      const v=Array.from({length:6},(_,j)=>clean(grid[i][j]));
      if(!v.slice(1).some(Boolean))continue;
      const row={nome:v[0],atividade:v[1],localidade:v[2],telefone_original:v[3],email_original:v[4],observacoes:v[5],folha:sheet,linha:i+1};
      if(!v[0]){orphans.push(row);continue;}if(norm(v[0])==='nome')continue;
      rows.push(row);
    }
  }return {rows,orphans,sheets,skippedSheets};
}
function contactSet(row){return new Set([...emails(row.email_original),...phones(row.telefone_original)]);}
const intersects=(a,b)=>a.some(v=>b.includes(v));
function notes(group,hash){return `[Fonte Excel ${hash.slice(0,16)} — dados históricos a confirmar]\n`+group.rows.map(r=>[
  `Folha: ${r.folha}; linha: ${r.linha}; nome na fonte: ${r.nome}`,
  r.atividade&&`Atividade: ${r.atividade}`,r.localidade&&`Localidade/morada: ${r.localidade}`,
  r.telefone_original&&`Contactos na fonte: ${r.telefone_original}`,r.email_original&&`Emails na fonte: ${r.email_original}`,
  r.observacoes&&`Observações da fonte: ${r.observacoes}`
].filter(Boolean).join('\n')).join('\n\n');}

export function compare(extracted,current,hash){
  const grouped=new Map();for(const r of extracted.rows){const k=norm(r.nome);if(!grouped.has(k))grouped.set(k,[]);grouped.get(k).push(r);}
  const groups=[...grouped].map(([key,rows])=>({key,nome:rows[0].nome,rows,emails:uniq(rows.flatMap(r=>emails(r.email_original))),phones:uniq(rows.flatMap(r=>phones(r.telefone_original)))}));
  const existing=current.map(r=>({...r.cadastro,aliases:r.nomes_alternativos||[]}));
  const candidates=existing.map(f=>({id:f.id,names:[f.nome,...f.aliases.map(a=>a.nome)],emails:uniq([...emails(f.email),...f.aliases.flatMap(a=>emails(a.email))]),phones:phones(f.telefone+' '+(f.contacto||''))}));
  const shortPersonal=new Set(['alexandre','antonio','carlos','fernando','joao','jose','luis','manuel','miguel','paulo','pedro','rui','sergio','silvia','semedo','radu']);
  const manualReview=new Set([
    'Class+', 'Barramentos', 'Painéis Sandwich em Lã de Rocha', 'IMPIC',
    'Cristiano', 'Maximino', 'Catita', 'Gilberto ARG', 'Celso (grupo Wiston)',
    'Tozé Carpinteiro lote 77'
  ].map(norm));
  const report=[];
  for(const group of groups){
    const contacts=candidates.filter(c=>intersects(group.emails,c.emails)||intersects(group.phones,c.phones));
    const exact=candidates.filter(c=>c.names.some(n=>norm(n)===group.key));
    const reinforced=contacts.filter(c=>c.names.some(n=>legal(n)===legal(group.nome)));
    const related=candidates.filter(c=>c.names.some(n=>similar(group.nome,n)));
    const siblings=groups.filter(g=>g!==group&&(intersects(group.emails,g.emails)||intersects(group.phones,g.phones)||similar(group.nome,g.nome)));
    let target=null,reason='',status='revisao';
    const identityWeak=manualReview.has(group.key)||shortPersonal.has(group.key)||group.key.length<4||/[?\uFFFD]/.test(group.nome);
    if(exact.length===1&&!identityWeak&&!contacts.some(c=>c.id!==exact[0].id)){target=existing.find(f=>f.id===exact[0].id);status='existente';reason='Nome exato normalizado ou alias já aprovado';}
    else if(exact.length>1)reason='Vários cadastros com este nome/alias';
    else if(identityWeak)reason='Nome insuficiente para identificar com segurança';
    else if(exact.length===1)reason='Nome aponta para um cadastro e contacto para outro';
    else if(reinforced.length===1&&contacts.every(c=>c.id===reinforced[0].id)){target=existing.find(f=>f.id===reinforced[0].id);status='existente';reason='Nome sem sufixo societário e contacto coincidentes, sem outro candidato';}
    else if(contacts.length||related.length)reason='Nome/contacto semelhante a cadastro existente; confirmar identidade';
    else if(siblings.length)reason='Possível duplicação entre nomes no próprio Excel';
    else if(!group.emails.length&&!group.phones.length)reason='Sem email/telefone válido para distinguir um novo contacto';
    else {status='novo';reason='Sem correspondência de nome, alias ou contacto; sem semelhanças detetadas';}
    // Um mesmo nome genérico repetido com contactos disjuntos não é uma identidade segura.
    if(group.rows.length>1&&words(group.nome).length===1&&group.rows.some((r,i)=>i&&contactSet(r).size&&contactSet(group.rows[0]).size&&!intersects([...contactSet(r)],[...contactSet(group.rows[0])]))){status='revisao';target=null;reason='Nome único repetido com contactos diferentes no Excel';}
    const proposal={email:group.emails.length===1?group.emails[0]:null,telefone:group.phones.length?group.phones.join(' / '):null,notas:notes(group,hash)};
    const conflicts=[];const fields=[];
    if(target){for(const k of ['email','telefone']){if(proposal[k]&&!clean(target[k]))fields.push(k);else if(proposal[k]&&clean(target[k])&&norm(proposal[k])!==norm(target[k]))conflicts.push(k);}if(!clean(target.notas))fields.push('notas');}
    report.push({...group,status,reason,target,proposal,fields,conflicts,candidates:uniq([...exact,...contacts,...related].map(c=>existing.find(f=>f.id===c.id).nome)),siblings:siblings.map(g=>g.nome)});
  }
  // Múltiplos nomes de origem a apontar ao mesmo ID não são aplicados silenciosamente.
  const counts=new Map();for(const r of report)if(r.target)counts.set(r.target.id,(counts.get(r.target.id)||0)+1);
  for(const r of report)if(r.target&&counts.get(r.target.id)>1){r.status='revisao';r.reason='Vários nomes do Excel correspondem ao mesmo cadastro; consolidar manualmente';r.target=null;r.fields=[];}
  return report;
}

export function loadSources(X,xlsx,csv){
  const source=fs.readFileSync(xlsx),snapshot=fs.readFileSync(csv,'utf8');
  const cb=X.read(snapshot,{type:'string',raw:true});const cs=X.utils.sheet_to_json(cb.Sheets[cb.SheetNames[0]]);
  if(cs.length!==1)throw Error('Esperada exportação integral numa única linha.');
  const current=JSON.parse(cs[0].fornecedores);
  if(Number(cs[0].total_fornecedores)!==current.length)throw Error('Snapshot incompleto.');
  if(new Set(current.map(r=>r.cadastro.id)).size!==current.length)throw Error('IDs repetidos no snapshot.');
  if(current.some(r=>r.cadastro.empresa_id!=='73fb13c8-d29f-4192-a506-4ca243343add'))throw Error('Empresa inesperada no snapshot.');
  const hash=crypto.createHash('sha256').update(source).digest('hex');
  return {hash,current,extracted:extractWorkbook(X,X.read(source,{type:'buffer'}))};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  const [lib,xlsx,csv]=process.argv.slice(2);const X=createRequire(import.meta.url)(path.resolve(lib));
  const data=loadSources(X,xlsx,csv);const report=compare(data.extracted,data.current,data.hash);
  console.log(JSON.stringify({snapshot:data.current.length,sourceRows:data.extracted.rows.length,uniqueNames:report.length,orphans:data.extracted.orphans.length,
    counts:report.reduce((o,r)=>(o[r.status]=(o[r.status]||0)+1,o),{}),updates:report.filter(r=>r.status==='existente'&&r.fields.length).length,
    matched:report.filter(r=>r.status==='existente').map(r=>({name:r.nome,target:r.target.nome,fields:r.fields,conflicts:r.conflicts})),
    reviewReasons:report.filter(r=>r.status==='revisao').reduce((o,r)=>(o[r.reason]=(o[r.reason]||0)+1,o),{})},null,2));
}
