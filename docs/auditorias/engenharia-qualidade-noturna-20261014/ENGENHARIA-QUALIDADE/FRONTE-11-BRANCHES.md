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

## Triagem de origem e expectativas

BRANCH-CONTRATOS-TRIAGEM.csv separa os8 nomes:4 são exclusivamente fixtures (auth.uid, fn_e_admin, fn_pode_ver_obra, fn_utilizador_atual_id). Não são4 conflitos adicionais de migrations de produção. Os4 restantes são fn_quadro_notificar_movimentacao_encarregado, fn_quadro_operar, fn_quadro_proteger_escrita e fn_registar_movimento_quadro: comparar semântica/ACL/marcadores e ordem aprovada antes de qualquer integração. Hash diferente não prova sozinho incompatibilidade.

Expectativa desatualizada concreta: tests/planning-browser.mjs:55 e69 exige resumo de pesos resolvidos/100% visível. O contrato visual aprovado oculta pesos resolvidos; deep-quality-expanded-browser-run.mjs aplica adaptação apenas à cópia de teste e a regressão expandida passou. Não modificar produto para satisfazer a expectativa antiga.

Segunda divergência de fixture: medicine-browser.mjs não preparava fn_folha_ferias_mapa_v2, hoje lida no percurso RH; o adapter sintético adiciona DTO vazio version2. A falha inicial não demonstra regressão de Medicina. Logs iniciais e finais preservados.

Refs são locais, sem fetch. As8 RPCs sem referência SQL no delta antigo são um sinal de rastreabilidade, não prova de função ausente no ambiente hospedado. Backend independente pode ter sido instalado por outro pacote; confirmar catálogo/precheck num futuro escopo autorizado. Fase B e Financeiro continuam preparados e não integrados.

## Assinaturas das quatro funções

BRANCH-ASSINATURAS-QUADRO.csv preserva cabeçalhos, tipos, retornos, ficheiros e SHAs. Nomes sobrepostos não bastam para afirmar colisão de overloads. Verificar assinaturas e sequência de instalação antes de qualquer proposta de integração. Os corpos históricos múltiplos continuam sem eleição automática por data/nome.

BRANCH-GUARDAS-QUADRO.csv compara helpers, marcadores de contexto, alvos DML e presença lexical da guarda de sessão/42501 por definição. As quatro funções têm assinaturas coincidentes nas duas linhas históricas (fn_quadro_operar text,jsonb,boolean,text; três triggers sem argumentos). São candidatas reais a sobreposição de corpo, distintas das quatro fixtures. Não basta a presença de42501 para certificar autorização; revisão do fluxo e manifest de instalação continuam necessários antes de integração autorizada.
