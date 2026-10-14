import subprocess,re,json,csv,hashlib
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE');product='2ae1f8a194f23d77bf0692d0a6d586566227298c'
def git(*args):return subprocess.check_output(['git',*args],encoding='utf-8',errors='replace').strip()
def text(ref,file):return git('show',ref+':'+file)
def sql_defs(ref,files):
 out={}
 pattern=re.compile(r'CREATE(?:\s+OR\s+REPLACE)?\s+FUNCTION\s+([\w.]+)\s*\(',re.I)
 for file in files:
  if not file.endswith('.sql'):continue
  src=text(ref,file)
  for m in pattern.finditer(src):
   rest=src[m.start():];tag=re.search(r'\bAS\s+(\$[\w]*\$)',rest,re.I)
   if not tag:continue
   end=rest.find(tag.group(1),tag.end())
   if end<0:continue
   normalized=re.sub(r'\s+',' ',rest[:end+len(tag.group(1))].replace('\r','')).strip();name=m.group(1).lower();name=name if'.'in name else'public.'+name
   out.setdefault(name,[]).append({'file':file,'hash':hashlib.sha256(normalized.encode()).hexdigest()})
 return out
rows=list(csv.DictReader((Q/'COMPARACAO-BRANCHES.csv').open(encoding='utf-8-sig',newline='')));detail=[]
for r in rows:
 ref=r['branch'];base=r['merge_base_com_horas'];theirs=git('diff','--name-only','--diff-filter=ACMRT',base+'..'+ref).splitlines();ours=git('diff','--name-only','--diff-filter=ACMRT',base+'..'+product).splitlines();r['sobreposicao_com_delta_horas']=';'.join(sorted(set(theirs)&set(ours)));a,b=sql_defs(product,ours),sql_defs(ref,theirs);shared=[]
 for name in sorted(a.keys()&b.keys()):
  ha={x['hash']for x in a[name]};hb={x['hash']for x in b[name]};shared.append({'name':name,'same_body_present':bool(ha&hb),'ours':a[name],'theirs':b[name],'classification':'COINCIDÊNCIA HISTÓRICA; NÃO ESCOLHER ÚLTIMA DEFINIÇÃO POR ORDEM DE FICHEIRO'})
 frontend=[f for f in theirs if f.startswith('src/')and f.endswith('.js')];calls=set()
 for file in frontend:calls.update(re.findall(r'\bfn_[a-z_0-9]+',text(ref,file)))
 known=set()
 if calls:
  matches=subprocess.run(['git','grep','-h','-o','-E','fn_[a-z_0-9]+',ref,'--','supabase'],capture_output=True,text=True,encoding='utf-8',errors='replace');known.update(matches.stdout.splitlines())
 detail.append({'branch':ref,'sha':r['sha_local'],'merge_base':base,'same_files':r['sobreposicao_com_delta_horas'].split(';')if r['sobreposicao_com_delta_horas']else[],'sql_function_overlap':shared,'frontend_rpc_tokens_without_sql_reference':sorted(calls-known),'limit':'Comparação lexical de contratos, não catálogo instalado; inclui definições históricas, não resolve ordem automaticamente'})
with(Q/'COMPARACAO-BRANCHES.csv').open('w',encoding='utf-8-sig',newline='')as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
(Q/'CONTRATOS-BRANCHES.json').write_text(json.dumps({'production_access':False,'merge_executed':False,'comparisons':detail},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=Q/'FRONTE-11-BRANCHES.md';s=p.read_text(encoding='utf-8');s+='\n## Aprofundamento de contratos\n\nCONTRATOS-BRANCHES.json compara também funções SQL e tokensRPC. Sobreposições de ficheiros agora usam a base comum específica de cada branch, incluindo alterações anteriores a main que não pertencem apenas ao delta de Horas. Não há escolha automática de um corpo por nome/data. Definições históricas múltiplas são limites explícitos.\n\n'+''.join(f'- {x["branch"]}: {len(x["same_files"])} ficheiros partilhados; {len(x["sql_function_overlap"])} nomes de função em ambos os deltas; RPCs sem referência SQL: {x["frontend_rpc_tokens_without_sql_reference"]}.\n'for x in detail);p.write_text(s,encoding='utf-8')
print([(x['branch'],len(x['same_files']),len(x['sql_function_overlap']))for x in detail])
