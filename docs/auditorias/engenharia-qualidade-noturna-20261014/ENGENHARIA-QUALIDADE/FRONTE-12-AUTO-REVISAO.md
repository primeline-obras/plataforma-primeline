# Frente 12 — AUTO-REVISAO

Estado: **EM EXECUÇÃO**.

## Verificações

Chaves originais203 preservadas; contagens Node separadas de resultados funcionais e de reproduções de falha.

## Evidências

../../validacao-profunda-20261014/CONTAGENS-203.json

## Limites e próximo passo

Autorrevisão final, validação dos links e CSVs ainda pendentes.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Separação de defeitos e erros de teste

INCIDENTES-DO-HARNESS.csv preserva10 incidentes/limites da instrumentação. Não pertencem ao total de P1/P2 do produto. Provas iniciais inconclusivas ou testes com expectativa antiga não foram somados como falhas reais nem usados para ocultar os6 FAIL tenant confirmados.

Asserções de artefactos validam203 chaves,172PASS/6FAIL/1contrato/24bloqueados; negativas179inativos,173PASS/6FAIL estrangeiros e38revogados;4 falhas Alertas corroboradas com campos obrigatórios efetivamenteNOT NULL. Esses testes de integridade de relatório não são aprovação de segurança do produto.

## Portabilidade da fila

O gerador da fila passa a reutilizar os rótulos da própria FILA-SUBTAREFAS.csv versionada se o anexo original não existir. Os testes continuam a exigir runtimes locais declarados, sem carregar credenciais de produção. RLS-ADMIN-BASELINE-CANDIDATAS.csv contém59 candidatas históricas,41 com coluna empresa/ligação potencial e10 com policy restritiva na captura. O inventário declara0 novas confirmações: não é59 vulnerabilidades nem catálogo atual.

## Portabilidade do checkpoint

O gerador da fila usa o CSV versionado quando o anexo original não existe. O ramo de fallback foi executado sem remover o anexo: comparação byte a byte da fila antes/depois PASS. Isto evita depender exclusivamente dos anexos desta máquina; os runtimes PostgreSQL/PostgREST/Node continuam dependências explícitas.
