# Grafo de dependências e fontes

MATRIZ-FONTES-DE-VERDADE contém30 relações críticas com chave, origem, risco e prova. Nomes abreviados de consumidor não são FK inventadas. GRAFO-SQL-LEXICAL.json contém575 declarações,1.713 chamadas qualificadas e2.020 candidatosDDL (table/view/trigger/policy/schema/index/alter/grant/revoke/constraint). Trata sintaxe textual, não pg_depend instalado; SQL dinâmico/sobrecargas e statements multiline exigem revisão.

```mermaid
flowchart LR
 F[fases / MQT] -->|fase_id| P[planeamento_itens]
 F -->|fase_id e obra_id| O[orcamento_fases]
 T[alteracoes_tee] -->|tee_id trigger| P
 T -->|obra e mês inicial| PREV[previsao_financeira_mensal]
 A[autos_medicao] -->|auto_medicao_id| L[faturacao_autos_medicao]
 FAT[faturacao] -->|faturacao_id| L
 FAT -->|faturacao_id| R[faturacao_recebimentos]
 R -. consumidor atual ainda usa agregado .-> MAP[caixa / mapas]
 C[colaboradores] -->|colaborador/data/obra| HR[folha_registos]
 HR --> EV[folha_avaliacoes_diarias]
 EV --> MON[folha_conferencias_mensais]
 P --> REP[folha_tarefas_reportes]
 REP --> AL[alertas]
 DOC[metadata documental] -. bytes em outro sistema .-> ST[Storage]
```

Nenhuma seta TEE-itens→auto granular foi comprovada; não incluída como FK. Não há nó implementado de custos-padrão independente: HR38 fonte/aprovador/vigência por fechar. Tarifas individuais confidenciais e valores padrão futuros são arquiteturas diferentes; não inferir salário do login/cargo.

## Migrations (propostas, não ordem operacional)
FolhaV2 → gestãoV2 → equipa persistente → fecho com baseline reconciliada → cutover fechado → avaliação AD15/14/13/03 → extensões HR27/FALTOU/readers/mensal/destinos/referências/plano/mapas. Checks de cada pacote determinam ordem/compatibilidade; rollback antes do uso difere após uso.

Financeiro/autos/hotfix e Storage têm dependências próprias. Um SQL antigo permissivo executado depois da restrição pode reabrir grant/policy. Branch DD-TENANT/FaseB não foi incorporada por existir localmente. Grafo não escolhe última definição por data/ordem alfabética. Sem baseline real reconstruída de documentação.
