import json,re,subprocess,csv
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE');d=json.loads((Q/'CONTRATOS-BRANCHES.json').read_text(encoding='utf-8'));branch=next(x for x in d['comparisons']if x['branch'].startswith('urgent/'));rows=[]
for f in branch['sql_function_overlap']:
 for side,ref in [('ours','2ae1f8a194f23d77bf0692d0a6d586566227298c'),('theirs',branch['sha'])]:
  for x in f[side]:
   if not x['file'].startswith('supabase/'):continue
   source=subprocess.check_output(['git','show',ref+':'+x['file']],encoding='utf-8',errors='replace');name=f['name'].split('.')[-1];pattern=r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?'+re.escape(name)+r'\s*\((.*?)\)\s*returns\s+([^\n\r]+)'
   for m in re.finditer(pattern,source,re.I|re.S):
    args=re.sub(r'--[^\n]*','',m.group(1));types=[a.group(1).lower()for a in re.finditer(r'(?:^|,)\s*(?:in\s+|inout\s+|out\s+)?\w+\s+([\w.]+(?:\[\])?)',args,re.I)]
    rows.append(dict(funcao=f['name'],lado=side,sha=ref,ficheiro=x['file'],linha=source[:m.start()].count('\n')+1,argumentos=' '.join(args.split()),tipos=','.join(types),retorno=m.group(2).strip(),limite='Extração lexical da assinatura; não instala nem escolhe versão canónica.'))
with(Q/'BRANCH-ASSINATURAS-QUADRO.csv').open('w',encoding='utf-8-sig',newline='')as h:w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
for name in sorted({r['funcao']for r in rows}):print(name,{side:sorted({r['tipos']for r in rows if r['funcao']==name and r['lado']==side})for side in ['ours','theirs']})
p=Q/'FRONTE-11-BRANCHES.md';s=p.read_text(encoding='utf-8').split('## Assinaturas das quatro funções')[0].rstrip()+'\n\n## Assinaturas das quatro funções\n\nBRANCH-ASSINATURAS-QUADRO.csv preserva cabeçalhos, tipos, retornos, ficheiros e SHAs. Nomes sobrepostos não bastam para afirmar colisão de overloads. Verificar assinaturas e sequência de instalação antes de qualquer proposta de integração. Os corpos históricos múltiplos continuam sem eleição automática por data/nome.\n';p.write_text(s,encoding='utf-8')
