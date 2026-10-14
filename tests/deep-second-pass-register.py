import csv,json,collections
from pathlib import Path
R=Path('docs/auditorias/validacao-profunda-20261014');files=['EVIDENCIAS-SEGUNDA-PASSAGEM-ECONOMICOS.json','EVIDENCIAS-SEGUNDA-PASSAGEM-RESTANTES.json','EVIDENCIAS-HORAS-INATIVOS.json','EVIDENCIAS-HORAS-OUTRA-EMPRESA.json','EVIDENCIAS-HORAS-RESPONSABILIDADE-REVOGADA.json','EVIDENCIAS-FINANCEIRO-INATIVOS-REVOGADOS.json','EVIDENCIAS-ESCOPO-RESTANTES.json','EVIDENCIAS-RESTANTES-OUTRA-EMPRESA.json','EVIDENCIAS-FINANCEIRO-OUTRA-EMPRESA.json','EVIDENCIAS-ALERTAS-OUTRA-EMPRESA-SEM-DESTINATARIO.json'];proofs=[]
for file in files:
 for i,p in enumerate(json.loads((R/file).read_text(encoding='utf-8'))['proofs']):proofs.append((p,file+'#proofs/'+str(i)))
rows=list(csv.DictReader((R/'MATRIZ-203-PARES.csv').open(encoding='utf-8-sig')));out=[]
for r in rows:
 key=(r['acao'],r['perfil']);x=dict(acao=key[0],perfil=key[1],primeira_passagem=r['resultado_observado'].split(' — ')[0])
 for field,variants in [('inativo',{'inactive'}),('outra_empresa',{'foreign'}),('responsabilidade_revogada',{'revoked','responsibility_revoked'})]:
  hit=[(p,f)for p,f in proofs if(p.get('action'),p.get('profile'))==key and p.get('variant')in variants]
  x[field]=';'.join(sorted({p['result']for p,f in hit}))if hit else'BLOQUEADO — SERVIÇO LOCAL'if r['cobertura']=='BLOQUEADO'else'SEM PROVA ESPECÍFICA';x[field+'_evidencia']=';'.join(f for p,f in hit)
 if x['responsabilidade_revogada']=='SEM PROVA ESPECÍFICA':
  if r['natureza']=='CONTRATO EM CONFLITO':x['responsabilidade_revogada']='PENDENTE CONTRATO';x['responsabilidade_revogada_evidencia']='DECISOES-PENDENTES.md'
  elif r['natureza']=='APLICÁVEL — PROIBIDA':x['responsabilidade_revogada']='NÃO APLICÁVEL — PAPEL JÁ SEM AÇÃO';x['responsabilidade_revogada_evidencia']=r['prova_nova']
  elif r['perfil']in ['gestao_plataforma','gerencia','administrativo','financeiro']:x['responsabilidade_revogada']='NÃO APLICÁVEL — AUTORIZAÇÃO POR PAPEL/EMPRESA';x['responsabilidade_revogada_evidencia']='MATRIZ-203-PARES.csv; contrato do helper/ação, sem dependência de responsabilidade individual'
 out.append(x)
assert len(out)==203;assert sum(x['inativo']=='PASS'for x in out)==179
with(R/'MATRIZ-SEGUNDA-PASSAGEM-203.csv').open('w',encoding='utf-8-sig',newline='')as f:w=csv.DictWriter(f,fieldnames=list(out[0]));w.writeheader();w.writerows(out)
counts={k:dict(collections.Counter(x[k]for x in out))for k in ['inativo','outra_empresa','responsabilidade_revogada']};(R/'CONTAGENS-SEGUNDA-PASSAGEM.json').write_text(json.dumps(counts,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(counts,ensure_ascii=True))
p=R/'COBERTURA-SEGUNDA-PASSAGEM.md';s=p.read_text(encoding='utf-8').split('## Reconciliação com203 chaves')[0].rstrip()+'\n\n'+'''\n## Reconciliação com203 chaves\n\nMATRIZ-SEGUNDA-PASSAGEM-203.csv mantém os mesmos203 pares e liga cada variante ao índice da prova. Todos os179 pares com backend executado têm agora variante de utilizador inativo aprovada;24 continuam bloqueados. Isto não cobre automaticamente todas as variantes de outra empresa/revogação, que permanecem explícitas na matriz. As6 chaves com falha de isolamento continuam FAIL (duas causas P1). A recusa de Gestão no FALTOU mantém contrato pendente apesar de o teste de inatividade passar.\n\nFinanceiro:27 variantes,24 inativos42501 e3 técnicos após revogação recusados com P0001 explícito de falta de permissão. Primeiro ensaio exigia42501 também nesses3; logs/JSON FIRST-STRICT-ERROR-CODE preservados como divergência da expectativa do harness, não autorização indevida. Não se aceita um erro P0001 genérico para certificar a recusa.\n''';p.write_text(s,encoding='utf-8')
