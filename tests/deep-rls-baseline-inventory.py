import csv,json,re
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE')
f=json.loads(Path('tests/fixtures/encarregado-catalogo-real-20261004.json').read_text(encoding='utf-8-sig'));rows=[]
for t in f['catalog']['tables']:
 if t['kind']!='r':continue
 policies=t.get('policies')or[];admin=[p for p in policies if p.get('cmd')in ['*','r']and p.get('permissive')and re.search(r'\bfn_e_admin\s*\(',p.get('using')or'')]
 if not admin:continue
 cols={c['name']for c in t['columns']};restrict=[p['name']for p in policies if not p.get('permissive')]
 direct='empresa_id'in cols;linked=sorted(c for c in cols if c in ['obra_id','colaborador_id','subempreitada_id','fatura_id','fase_id','entidade_id','viatura_id','mapa_id'])
 acl=t.get('acl')or'';match=re.search(r'authenticated=([^/,}]*)',acl);read=bool(match and'r'in match.group(1))
 rows.append(dict(tabela=t['name'],rls=t.get('rls',t.get('row_security','NÃO REGISTADO')),admin_policies=';'.join(p['name']for p in admin),predicados=';'.join(p.get('using')or''for p in admin),restrictive_policies=';'.join(restrict),select_grant_tabela=read,empresa_coluna=direct,ligacoes_potenciais=';'.join(linked),classe='CANDIDATA A REVISÃO DE TENANT'if direct or linked else'CLASSIFICAR DICIONÁRIO GLOBAL/SEM TENANT COMPROVADO',estado='BASELINE20261004 — NÃO É CATALOGO ATUAL',limite='Não executado por tabela. Migrations posteriores podem restringir policies/grants. FK/nome de coluna não prova empresa histórica; não inferir pelo autor.'))
with(Q/'RLS-ADMIN-BASELINE-CANDIDATAS.csv').open('w',encoding='utf-8-sig',newline='')as h:w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
summary={'baseline':'tests/fixtures/encarregado-catalogo-real-20261004.json','candidates':len(rows),'table_select_grant':sum(r['select_grant_tabela']for r in rows),'tenant_or_link_column':sum(r['classe'].startswith('CANDIDATA')for r in rows),'restrictive_present':sum(bool(r['restrictive_policies'])for r in rows),'confirmed_by_this_inventory':0,'production_access':False}
(Q/'RLS-ADMIN-INVENTARIO-CONTAGENS.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
text='''# Policies administrativas — inventário de candidatos

RLS-ADMIN-BASELINE-CANDIDATAS.csv é uma triagem estática da captura20261004. Não classifica todas as linhas como vulnerabilidades atuais e não acrescenta um P1 por tabela.

A policy permissiva com fn_e_admin() pode dar acesso por papel sem relação com a empresa da linha. A composição efetiva depende também de grants de coluna/tabela, policies restritivas, definição dos helpers e alterações posteriores. Uma coluna obra_id/empresa_id é um ponto para análise; não prova sozinha o tenant legítimo de dados antigos.

Documentos_obra possui uma prova local concreta separada. As restantes candidatas necessitam comparação por pacote e, futuramente, catálogo autorizado. Não aplicar um fecho global que remova permissões legítimas de Gestão/Gerência/Administrativo.

Recomendação: para cada candidata, identificar fonte factual do tenant e policy efetiva; separar dicionários globais; distinguir concessão funcional de âmbito; testar utilizador ativo, empresa própria/estrangeira e relação revogada; manter fail-closed para linhas ambíguas. Não fazer backfill pelo utilizador criador.

Os dados da captura são metadados do schema. Não foram lidas linhas reais nem criado novo teste de acesso em produção.
'''
(Q/'RLS-ADMIN-BASELINE-REVISAO.md').write_text(text,encoding='utf-8')
print(summary)
