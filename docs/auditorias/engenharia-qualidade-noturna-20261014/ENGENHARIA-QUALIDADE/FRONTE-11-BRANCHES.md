# Frente 11 — comparação das branches locais

Base funcional auditada: `2ae1f8a194f23d77bf0692d0a6d586566227298c`. Todas as comparações foram feitas por leitura de objetos Git; nenhum merge/reset/fetch. Ver COMPARACAO-BRANCHES.csv.

As seis referências e SHAs constam de COMPARACAO-BRANCHES.csv. A sobreposição usa a base comum específica de cada branch; o resumo canónico de ficheiros/funções está abaixo.

## Proposta de integração, não executada

Preservar a sequência AD15 → AD14 → AD13 → AD03 e as dependências HR27/FALTOU/leitores/conferência/destinos/custos/plano/contextos. Fase B e Débitos Diretos são pacotes independentes: exigir catálogo/precheck próprio antes de qualquer proposta real. Comparar qualquer redefinição de helper/RPC com a versão cumulativa de Horas; coincidência de nome não prova equivalência. Repetir regressões em base combinada descartável apenas quando essa integração for autorizada. Não transportar a branch antiga de Planeamento por cópia cega de ficheiros partilhados.

Limitação: esta frente verifica divergência/ancestralidade e ficheiros; não certifica o comportamento de uma integração ainda inexistente.

## Aprofundamento de contratos

CONTRATOS-BRANCHES.json compara também funções SQL e tokensRPC. Sobreposições de ficheiros agora usam a base comum específica de cada branch, incluindo alterações anteriores a main que não pertencem apenas ao delta de Horas. Não há escolha automática de um corpo por nome/data. Definições históricas múltiplas são limites explícitos.

- main: 0 ficheiros partilhados; 0 nomes de função em ambos os deltas; RPCs sem referência SQL: [].
- feat/gestao-horas-integrada-20261013: 0 ficheiros partilhados; 0 nomes de função em ambos os deltas; RPCs sem referência SQL: [].
- urgent/planeamento-operacional-20260928: 22 ficheiros partilhados; 8 nomes de função em ambos os deltas; RPCs sem referência SQL: ['fn_definir_estado_mensal_v1', 'fn_guardar_planeamento_lote', 'fn_guardar_validade_viatura', 'fn_importar_tees_revisoes', 'fn_origens_financeiras_mensais_v1', 'fn_recalcular_previsao_mensal_v1', 'fn_registar_recebimento_parcial', 'fn_resumo_financeiro_mensal_v1'].
- chore/fase-b-readiness-20261011: 0 ficheiros partilhados; 0 nomes de função em ambos os deltas; RPCs sem referência SQL: [].
- fix/despesas-gerais-tenant-20261011: 0 ficheiros partilhados; 0 nomes de função em ambos os deltas; RPCs sem referência SQL: [].
- codex/auditoria-global-noturna-20261014: 0 ficheiros partilhados; 0 nomes de função em ambos os deltas; RPCs sem referência SQL: [].
