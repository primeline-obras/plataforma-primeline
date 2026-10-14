import csv,json
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE');rows=[]
for file,kind in [('full-navigation/EVIDENCIAS-NAVEGACAO.json','NAVEGAÇÃO COMPLETA'),('full-navigation/EVIDENCIAS-CONTEXTO-OBRA.json','CONTEXTO SINTÉTICO DE OBRA'),('ui-modules/EVIDENCIAS-UI-MODULOS.json','COMPONENTE REAL ISOLADO')]:
 d=json.loads((Q/file).read_text(encoding='utf-8'))
 for i,p in enumerate(d['proofs']):
  view=p.get('view',p.get('id',''));state=p.get('stage',p.get('section',p.get('id','observado')));width=p.get('viewport',{}).get('width',p.get('measure',{}).get('viewport','NÃO REGISTADO'))
  if kind=='NAVEGAÇÃO COMPLETA':shot='full-navigation/'+view+'-'+state+'.png'
  elif kind=='CONTEXTO SINTÉTICO DE OBRA':shot='full-navigation/'+view+'-context-'+str(width)+'.png'if 'viewport'in p else''
  else:shot='ui-modules/'+view+'-'+str(width)+'.png'
  if shot and not(Q/shot).exists():shot=''
  rows.append(dict(id='UI-'+str(len(rows)+1).zfill(3),tipo=kind,interface=view,estado=state,largura=width,cobertura='OBSERVADO NO BROWSER LOCAL',resultado='Captura/DOM com API sintética; não certifica autorização ou sucesso integral',prova=file+'#proofs/'+str(i),screenshot=shot,limite='Fontes de substituição e dados sintéticos; ver LIMITE-TIPOGRAFIA.md'))
with(Q/'MATRIZ-INTERFACES-ESTADOS.csv').open('w',encoding='utf-8-sig',newline='')as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
print('UI states',len(rows),'with existing screenshot',sum(bool(r['screenshot'])for r in rows))
