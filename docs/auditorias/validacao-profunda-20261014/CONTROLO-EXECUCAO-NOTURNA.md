# Controlo da execução noturna

Estado geral: **EM EXECUÇÃO — COM BLOQUEIOS PARCIAIS**.

Base preservada63f98ddff6ca96e0c89dd0d4125d85a4d29f12b3; último checkpoint local9e28c96; branchcodex/validacao-profunda-203-20261014. Nenhum produto/SQL real/push/merge/deploy alterado.

## Pares

203 reconciliados;179 executados;174 aprovados,4 FAIL,1 contrato pendente;24 dependem de Auth/Storage local. Os4 FAIL representam2 achados P1 locais, sem afirmar ocorrência em produção.

## Fila

- Reconciliação203: **CONCLUÍDA** — Chaves exatas, sem duplicações.
- Primeira execução backend: **PARCIAL** — 179 executados;24 BLOQUEADO por serviços locais.
- Segunda passagem: **PARCIAL** — REST30 cenários; económica76; escopo12 incluindo4 FAIL.
- Consumidores: **PARCIAL** — Importação/ledger/RH e documentos; ligações restantes explicitadas.
- Interfaces: **PARCIAL** — 21 vistas/80 capturas, módulos detalhados e6 viewports; ampliar estados.
- Importadores: **PARCIAL** — CSV1000, XLSX reais, MQT/sub/TEE500linhas; regressões RH.
- Documentos: **PARCIAL** — Dois P2 cliente; ficheiros; Storage real local ausente.
- Alertas: **PARCIAL** — Produtor28contagens; filtros3; dois perfis falham tenant no resolver.
- Financeiro: **PARCIAL** — Invariantes, recibos reais e importação; cenários comerciais pendentes.
- Fornecedores: **PARCIAL** — Identidade/completude/comparabilidade; contratos comerciais por aprofundar.
- TEE128: **CONCLUÍDA COMO ESTUDO** — Mapa de13etapas e cenário sintético; implementação não autorizada.
- RH: **PARCIAL** — AD15/14/13/03 e72casos novos; matriz de integridade pendente.
- Visual: **PARCIAL** — Capturas inspecionadas; sem overflow com CSS completo em módulos próprios.
- Assincronia: **PARCIAL** — Novos P2 documentais e P2 anterior Compras; restantes contextos pendentes.
- Branches: **CONCLUÍDA** — Seis refs locais; sem merge/fetch.
- Autorrevisão: **EM EXECUÇÃO** — Links, contagens, segredos e arquivos por validar no fecho.

Subtarefas de qualidade inventariadas: 234; estados progressivos em ENGENHARIA-QUALIDADE/FILA-SUBTAREFAS.csv. Não foram marcadas completas apenas por existir relatório. Próxima execução segura: interfaces com obra sintética e matriz RH por precondição; depois contratos e autorrevisão.
