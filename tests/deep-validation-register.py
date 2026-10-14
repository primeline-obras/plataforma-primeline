import csv,json,collections,subprocess
from pathlib import Path
R=Path('docs/auditorias/validacao-profunda-20261014');Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE')
old=Path('docs/auditorias/auditoria-global-noturna-20261014/FASE-5/MATRIZ-ACOES-PERFIS.csv')
rows=[r for r in csv.DictReader(old.open(encoding='utf-8-sig',newline=''))if r['verificacao']=='REVISÃO ESTÁTICA; PAR BACKEND NÃO EXECUTADO'];assert len(rows)==203
proofs={};extra=[]
for name in ['FINANCEIRO','HORAS','ECONOMICOS','RESTANTES']:
 p=R/f'EVIDENCIAS-{name}-PERFIS.json'
 if not p.exists():continue
 for i,x in enumerate(json.loads(p.read_text(encoding='utf-8'))['proofs']):
  k=(x['action'],x['profile']);assert k not in proofs;proofs[k]=(x,p.name,i)
keys={(r['acao'],r['perfil'])for r in rows};assert len(keys)==203
negative=[]
for negative_name in ['EVIDENCIAS-ESCOPO-RESTANTES.json','EVIDENCIAS-RESTANTES-OUTRA-EMPRESA.json','EVIDENCIAS-ALERTAS-OUTRA-EMPRESA-SEM-DESTINATARIO.json']:
 negative_path=R/negative_name
 if negative_path.exists():negative.extend(dict(n,_evidence=negative_name)for n in json.loads(negative_path.read_text(encoding='utf-8'))['proofs'])
for k,(x,p,i)in proofs.items():
 if k not in keys:extra.append(dict(x,evidence=p+'#proofs/'+str(i)))
partial_doc_path=Q/'EVIDENCIAS-DOCUMENTOS-DML-RLS.json'
partial_doc={p['profile']for p in json.loads(partial_doc_path.read_text(encoding='utf-8'))['proofs']if p['result']=='FAIL'and p['variant']=='foreign'}if partial_doc_path.exists()else set()
for r in rows:
 k=(r['acao'],r['perfil']);r.update(natureza='',cobertura='',resultado_observado='',prova_nova='',ambiente_teste='',resultado_parcial='',pre_condicoes='Ator sintético ativo; empresa e obra da fixture; recurso válido',risco_residual='',proximo_passo='')
 if k in proofs:
  x,p,i=proofs[k];r.update(natureza='APLICÁVEL — AUTORIZADA'if x['expected']=='PERMITIR'else'APLICÁVEL — PROIBIDA',cobertura='EXECUTADO'if x['result']!='BLOQUEADO'else'BLOQUEADO',resultado_observado=x['result']+' — '+json.dumps(x['observed'],ensure_ascii=False),prova_nova=p+'#proofs/'+str(i),ambiente_teste=x['environment'],risco_residual=x.get('limit',''),proximo_passo='Ligar consumidores finais e variantes adversas; não é certificação da produção')
  failures=[n for n in negative if (n['action'],n['profile'])==k and n['result']=='FAIL']
  if failures:
   r['resultado_observado']='FAIL — '+json.dumps({'baseline':x['result'],'second_pass':failures},ensure_ascii=False);r['prova_nova']+='; '+';'.join(sorted({n['_evidence']for n in failures}));r['risco_residual']+='; P1 LOCAL: outra empresa aceite na segunda passagem';r['proximo_passo']='Rever guarda de tenant do contrato; sem alterar produto nesta missão'
  if k==('ABSENCE_REPORT','gestao_plataforma'):
   r['natureza']='CONTRATO EM CONFLITO';r['resultado_observado']='PENDENTE CONTRATO — RPC recusa Gestão por exigir Encarregado; regra global de superutilizador funcional deve ser confrontada com o requisito específico';r['risco_residual']+='; teste de recusa não aprova a regra funcional';r['proximo_passo']='Reconciliar requisito específico de reporte FALTOU com regra global já aprovada, sem alterar permissões'
 else:
  assert r['acao']in ['LOGIN','DOCUMENT','DOWNLOAD'],r['acao'];dep='Serviço local GoTrue para login real'if r['acao']=='LOGIN'else'Serviço local Storage e Auth para o percurso completo de bytes/metadados'
  r.update(natureza='APLICÁVEL — AMBIENTE INCOMPLETO',cobertura='BLOQUEADO',resultado_observado='FLUXO COMPLETO NÃO EXECUTADO — sem substituição por mock',prova_nova='BLOQUEIOS-PARA-DECISAO.md#serviços-locais',ambiente_teste='PostgreSQL disponível; Docker/Podman/Supabase CLI não encontrados no PATH',risco_residual=dep,proximo_passo='DEPENDÊNCIA TÉCNICA — disponibilizar '+dep)
  if r['acao']=='DOCUMENT'and r['perfil']in partial_doc:
   r['resultado_parcial']='FAIL — leitura SQL de metadados noutra empresa na RLS capturada; catálogo real não validado'
   r['prova_nova']+='; ../engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE/EVIDENCIAS-DOCUMENTOS-DML-RLS.json'
   r['risco_residual']+='; P1 da baseline RLS: pl_admin_total não filtra empresa; não certificar bytes ou catálogo hospedado'
with(R/'MATRIZ-203-PARES.csv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
counts=collections.Counter(r['cobertura']for r in rows);results=collections.Counter(r['resultado_observado'].split(' — ')[0]for r in rows)
summary=dict(original=203,reconciliados=len(rows),chaves_unicas=len(keys),aplicaveis=203,nao_aplicaveis=0,cobertos_prova_anterior=0,cobertura=dict(counts),resultados_backend=dict(results),provas_suplementares=len(extra),falhas_parciais_metadados=sum(r['resultado_parcial'].startswith('FAIL')for r in rows),limitacao='Execução de variantes backend especificadas; não todos os fluxos frontend nem catálogo de produção atual')
(R/'CONTAGENS-203.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(R/'PROVAS-SUPLEMENTARES.json').write_text(json.dumps(extra,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
with(R/'TESTES-EM-FALTA.csv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.DictWriter(f,fieldnames=['acao','perfil','cobertura','resultado_parcial','risco_residual','proximo_passo']);w.writeheader();w.writerows({k:r[k]for k in w.fieldnames}for r in rows if r['cobertura']!='EXECUTADO' or r['natureza']=='CONTRATO EM CONFLITO')
(R/'COBERTURA-EXECUTADA.md').write_text('# Cobertura backend observada\n\n```json\n'+json.dumps(summary,ensure_ascii=False,indent=2)+'\n```\n\nAs chaves são exatamente as 203 originais. Zero exclusões por ausência de menu. As cinco provas adicionais fora desse conjunto ficam separadas. Não somar contagens Node de grupos/reexecuções como cenários únicos.\n\nA fixture económica reconstrói catálogo público/RLS/ACL e funções reais capturadas, mas não todos os defaults, constraints e triggers operacionais. Asserções financeiras verificam efeito intratransação antes da reversão. A fixture RH instala os scripts cumulativos e confirma preview, commit, consumidores e replay. As decisões de papel foram confrontadas com o código, sem mudar permissões.\n',encoding='utf-8')
text='# Testes por perfil\n\n|Perfil|Backend executado|PASS|FAIL|Contrato pendente|Fluxo bloqueado|FAIL parcial de metadados|\n|---|---:|---:|---:|---:|---:|---:|\n'
for role in sorted({r['perfil']for r in rows}):
 group=[r for r in rows if r['perfil']==role];c=collections.Counter(r['resultado_observado'].split(' — ')[0]for r in group)
 text+='|'+role+'|'+str(sum(r['cobertura']=='EXECUTADO'for r in group))+'|'+str(c['PASS'])+'|'+str(c['FAIL'])+'|'+str(c['PENDENTE CONTRATO'])+'|'+str(sum(r['cobertura']=='BLOQUEADO'for r in group))+'|'+str(sum(r['resultado_parcial'].startswith('FAIL')for r in group))+'|\n'
text+='\nFAIL parcial permanece dentro de um fluxo bloqueado: não somar como mais um par nem certificar Auth/Storage. Baseline RLS local não é catálogo hospedado.\n'
(R/'TESTES-POR-PERFIL.md').write_text(text,encoding='utf-8')
(R/'BLOQUEIOS-PARA-DECISAO.md').write_text('''# Bloqueios para decisão

## Serviços locais

DEPENDÊNCIA TÉCNICA: Login requer GoTrue real local; Documento/Download requerem Storage local, Auth e políticas correspondentes. Docker, Podman e Supabase CLI não foram encontrados no PATH. PostgreSQL e PostgREST locais não substituem o fluxo de login nem o serviço de bytes. 24 pares ficam BLOQUEADO, sem falso PASS. Não usar produção nem mocks de permissões para os certificar.

## Fidelidade tipográfica local

DEPENDÊNCIA TÉCNICA: fontes Google bloqueadas pelo isolamento. CDP confirmou fontes de substituição. Geometria das capturas não certifica produção; ver LIMITE-TIPOGRAFIA.md na Engenharia de Qualidade. Outros testes independentes continuam.

## Encerramento do harness REST

A primeira tentativa ficou presa no teardown após saída do processo PostgREST. A revisão automática rejeitou encerrar o PID 15136 porque a evidência apresentada não identificava o alvo com segurança. Não repetir nem contornar a ação rejeitada. O teardown do teste novo foi corrigido e uma execução independente pode seguir; o processo anterior não foi encerrado por esta tarefa. DEPENDÊNCIA TÉCNICA para limpeza desse processo, sem impacto demonstrado no produto.

## Decisões anteriores preservadas

AGUARDA DECISÃO: mitigação HR38, conceitos financeiros e TEE pendentes do backlog anterior; nenhuma mudança de contrato realizada. FALTOU recusa Gestão no código atual por exigir literalmente Encarregado; confrontar com regra global de superutilizador funcional antes de alterar. Esta verificação de contrato não se converte automaticamente em autorização para mudar a regra.
''',encoding='utf-8')
(R/'RETOMA.md').write_text('''# Retoma

Branch `codex/validacao-profunda-203-20261014`; base `63f98ddff6ca96e0c89dd0d4125d85a4d29f12b3`. Produto preservado.

Reexecutar `tests/deep-validation-register.py` depois de novas evidências. Continuar frentes independentes: segunda passagem REST; importadores/documentos/alertas/invariantes; screenshots e concorrência; comparação de branches; revisão final. Não encerrar por 24 pares de serviços locais bloqueados. Não chamar a missão concluída enquanto houver trabalho seguro pertinente pendente. Manter contagens do JSON em vez de somar resultados de todas as tentativas.

Runtimes locais: Node/Python no cache Codex; PG17.6 em TEMP/primeline-doc-guard-pg176/package/native/bin; pg em TEMP/primeline-medicina-test-deps/runtime/node_modules; PostgREST em TEMP/primeline-authorization-postgrest. Nenhuma credencial real necessária. Não instalar nem executar scripts contra produção.
''',encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False))
