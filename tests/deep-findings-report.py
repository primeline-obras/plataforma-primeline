import csv,json
from pathlib import Path
Q=Path('docs/auditorias/engenharia-qualidade-noturna-20261014/ENGENHARIA-QUALIDADE');R=Path('docs/auditorias/validacao-profunda-20261014')
fields=['id_temporario','modulo','gravidade','estado','esperado','observado','prova','limite','correspondencia','criterio_aceitacao']
raw=[
('DEEP-SEC-01','RNC','P1','CONFIRMADO LOCAL','Recusar empresa diferente','Gestão e Gerência criam RNC da empresa2 sendo atores empresa1','EVIDENCIAS-ESCOPO-RESTANTES.json','Montagem local de corpos reais; não confirmação do catálogo de produção','Novo contrato de isolamento tenant; código oficial pendente','Ator/obra/empresa validados antes de escrever; negar sem RNC/auditoria parcial'),
('DEEP-SEC-02','Alertas','P1','CONFIRMADO LOCAL','Recusar resolução noutra empresa','Gestão e Gerência resolvem alerta da empresa2 sendo atores empresa1','EVIDENCIAS-ESCOPO-RESTANTES.json','Sem acesso a alertas reais; triggers operacionais parciais na fixture','Novo contrato de isolamento tenant; código oficial pendente','Tenant do alvo validado e bloqueado; nenhuma resolução indevida'),
('DEEP-DOC-01','Documentos','P2','CONFIRMADO CLIENTE','Resposta A não altera contexto B','Consulta atrasada A preenche documentos sob contexto B','EVIDENCIAS-DOCUMENTOS-CONTEXTO.json#DEEP-DOC-RACE','Mesma identidade e obras sintéticas; não bypass tenant','TEMP-P3-C01: mesma classe, outro componente','Epoch/obra capturados; respostas antigas ignoradas'),
('DEEP-DOC-02','Documentos','P2','PEDIDO INCONSISTENTE COMPROVADO','Bytes e metadados na mesma obra','Upload começa em A; POST de metadados aponta B após troca','EVIDENCIAS-DOCUMENTOS-CONTEXTO.json#DEEP-DOC-UPLOAD-CONTEXT','Transporte sintético; persistência do pedido inconsistente não certificada','N-DOC-01: contexto adicional','Congelar contexto e autor; verificar coerência no servidor; não associar noutra obra'),
('DEEP-IMP-01','Importação financeira','P2','CONFIRMADO LOCAL','Texto monetário inválido recusado no preview','texto vira0; texto123 vira123 e writer real grava os números convertidos','EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json','SQL confirmado apenas na base descartável; confirmação explícita na fixture','N-FIN-03: nova causa de origem inválida','Parser estrito preserva NULL/zero e identifica linha/célula inválida'),
('DEEP-IMP-02','Importação financeira','P2','CONFIRMADO LOCAL','Duplicações contraditórias e linhas não resolvidas explícitas','XLSX3 linhas gera preview2; duas120 selecionadas sem aviso; writer diz2 importadas e mantém1 ajuste final200','EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json#FIN-BINARY-DUPLICATE-UNKNOWN','Obra999 é desconhecida sintética; não escrita cross-tenant','Novo: completude/deduplicação do lote','Reportar todas as linhas; bloquear conflito ou exigir escolha explícita antes de confirmar'),
('DEEP-OBS-01','Planeamento/importação','P3','LACUNA CLIENTE','Datas civis inválidas recusadas','Parser aceita31/02/2026 e2026-13-40','EVIDENCIAS-IMPORT-COMERCIAL.json','Não foi demonstrada persistência de data inválida; backend pode recusar','Validação de origem','Validar calendário antes de preview; manter recusa backend'),
('DEEP-OBS-02','Ficheiros','P3','OBSERVAÇÃO / DECISÃO','Contrato explícito sobre ficheiro vazio e MIME','Cliente envia PDF vazio e extensãoPDF/MIMEoctet-stream','EVIDENCIAS-DOCUMENTOS-CONTEXTO.json#DOC-FILE-CONTENT-VALIDATION','Storage local indisponível; não demonstra aceitação backend ou conteúdo malicioso','N-DOC-01','Documentar e testar contrato do serviço de bytes sem falsear permissões'),
('DEEP-OBS-03','Agenda','P3','USABILIDADE OBSERVADA','Ações confortáveis para toque','Botão REGISTAR medido com20px no componente local','compact-screenshots/METRICAS-VISUAIS.json;full-navigation/EVIDENCIAS-NAVEGACAO.json','20px confirmados também na aplicação completa em desktop/tablet; sem alteração CSS','UX tablet','Rever alvo de toque e contraste na tarefa de desenho, sem alterar nesta auditoria')]
raw.append(('DEEP-OBS-04','Acessibilidade','P3','CONFIRMADO CLIENTE','Controlos com nome acessível','Menu móvel e seletor de obra do Planeamento sem nome acessível programático','full-navigation/EVIDENCIAS-TECLADO-CONTROLOS.json;full-navigation/VEHICLES-ARIA-SNAPSHOT.txt','21 vistas/63 estados; não é certificação WCAG; controlos ocultos excluídos','Novo: semântica acessível','Nome acessível explícito para menu e select; preservar navegação por teclado'))
rows=[dict(zip(fields,r))for r in raw]
with(Q/'NOVAS-DESCOBERTAS.csv').open('w',encoding='utf-8-sig',newline='')as f:w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(rows)
old=list(csv.DictReader(Path('docs/auditorias/auditoria-global-noturna-20261014/CONSOLIDACAO-PARA-BACKLOG.csv').open(encoding='utf-8-sig',newline='')))
combined=[dict(codigo=r.get('codigo_existente')or r.get('id_temporario'),origem='AUDITORIA ANTERIOR PRESERVADA',modulo=r['modulo'],gravidade=r['prioridade'],estado=r['estado'],problema=r['problema'],evidencia=r['evidencia'],correspondencia=r.get('codigo_existente',''),criterio_aceitacao=r['criterio_aceitacao'])for r in old]
combined +=[dict(codigo=r['id_temporario'],origem='VALIDAÇÃO PROFUNDA',modulo=r['modulo'],gravidade=r['gravidade'],estado=r['estado'],problema=r['observado'],evidencia=r['prova'],correspondencia=r['correspondencia'],criterio_aceitacao=r['criterio_aceitacao'])for r in rows]
with(Q/'CONSOLIDACAO-BACKLOG.csv').open('w',encoding='utf-8-sig',newline='')as f:w=csv.DictWriter(f,fieldnames=list(combined[0]));w.writeheader();w.writerows(combined)
(R/'FALHAS-COMPROVADAS.md').write_text('''# Falhas comprovadas — checkpoint progressivo

## Isolamento

DEEP-SEC-01: fn_criar_rnc aceita alvo de outra empresa para Gestão/Gerência na montagem local. DEEP-SEC-02: fn_resolver_alerta resolve alerta de outra empresa para os mesmos perfis. Quatro pares FAIL, duas causas/contratos a corrigir. Provas: EVIDENCIAS-ESCOPO-RESTANTES.json e RESULTADO-ESCOPO-RESTANTES.txt. O teste de recusa falha efetivamente; a reprodução não é contabilizada como segurança aprovada.

A fixture usa funções reais capturadas, hotfix consolidado e guarda documental posterior de Viaturas. Não reconstrói todos os triggers/constraints do sistema nem confirma o catálogo hospedado. Os achados são locais e devem orientar correção/revisão, sem alegar exploração em produção. Viaturas recusou ambos os atores estrangeiros com o wrapper atual.

## Qualidade

Documentos: resposta obsoleta A em contexto B; pedido de metadados pode usar obraB com ficheiro de A. Importação: texto inválido transformado em número e gravado localmente; duplicações contraditórias sobrescrevem o ajuste sem aviso, enquanto linha desconhecida desaparece do preview. Ver NOVAS-DESCOBERTAS.csv na pasta ENGENHARIA-QUALIDADE.

## Preservado

P1 financeiros/HTML e riscos HR38 anteriores continuam sem correção. Não foram repetidas cargas HTML nem alteradas permissões. FP28/29 continuam em standby.
''',encoding='utf-8')
(R/'INTEGRACOES-EXECUTADAS.md').write_text('''# Integrações executadas

| Percurso | Prova | Limite |
|---|---|---|
| Preview numérico → RPC Mapa Financeiro → ajuste mensal | EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json | Base local; entradas inválidas convertidas persistem |
| XLSX binário → SheetJS → preview → writer → ajuste | Mesmo ficheiro, FIN-BINARY-DUPLICATE-UNKNOWN | Contradição de duas linhas120 resulta num ajuste200 |
| JWT sintético → PostgREST → recebimento → ledger/saldo | EVIDENCIAS-REST-SEGUNDA-PASSAGEM.json | Não é login GoTrue nem produção |
| Plano/FALTOU → factos → conferência/custos/alertas | EVIDENCIAS-HORAS-PERFIS.json;RESULTADO-RH-LOCAL.txt | Fixture cumulativa; cadastro inicialmente semeado |
| Documento → carregamento e contexto | EVIDENCIAS-DOCUMENTOS-CONTEXTO.json | Cliente real/transporte sintético; Storage não certificado |
| Recursos → TEE → preço final | FRONTE-07-TEE-ADMINISTRACAO.md | Proposta conceptual; ligação granular não implementada |

As integrações não ligadas permanecem por verificar. Um writer/backend validado não certifica automaticamente todos os consumidores, exports, anexos e estados.
''',encoding='utf-8')
dec='''# Decisões e dependências consolidadas

- Corrigir/rever guardas tenant de RNC/Alertas em tarefa autorizada; nesta missão o produto permanece inalterado.
- Reconciliar reporte FALTOU de Gestão com a regra global já aprovada de superutilizador funcional. A recusa foi observada, sem certificar a regra funcional nem conceder permissões.
- Preservar decisões HR38 e conceitos financeiros do backlog anterior; não escolher limiares de anonimização, tarifas ou fórmulas salariais.
- Confirmar contrato de ficheiros vazios/MIME no serviço de bytes local; nenhum acesso a Storage real.
- Pré-visualização de importação deve explicar células inválidas, linhas desconhecidas e duplicações; proposta de correção, sem implementação.
- Depende de ambiente: GoTrue/Storage locais para24 pares. PostgREST foi desbloqueado com DLLs existentes; não corresponde a login hospedado.
- A revisão automática rejeitou o encerramento do PID indicado; a ação não foi repetida. Retoma não deve tentar contornar essa rejeição. Limpeza desse processo requer identificação e autorização adequadas, sem bloquear outras frentes.
'''
(R/'DECISOES-PENDENTES.md').write_text(dec,encoding='utf-8');(Q/'DECISOES-PARA-UTILIZADORA.md').write_text(dec,encoding='utf-8')
print('Backlog anterior',len(old),'novos registos',len(rows),'— 2P1 +4P2 locais; 4 observações P3.')
