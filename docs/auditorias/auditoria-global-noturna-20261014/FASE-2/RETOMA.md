# Retoma — Auditoria noturna Fase 2

## Checkpoints

- Branch: `codex/auditoria-global-noturna-20261014`.
- Fase 1: `439b1e3b900a8d5b919062cf8efd1f05868e494a`.
- Checkpoint inicial Fase 2: `924b6fa` (RETOMA inicial, apenas documentação).
- Commit final: commit desta branch que contém a versão final deste ficheiro; obter `git rev-parse HEAD` após os commits de fecho. O SHA desse próprio commit não pode ser incluído no seu conteúdo sem criar novo commit; a entrega no chat fornece o SHA exato.
- Worktree: `C:/Users/conta/.codex/worktrees/auditoria-global-noturna-20261014/primeline-go-urgente`.
- Repositório principal permanece intocado; main local e base funcional não foram atualizados.

## Concluído

Leitura integral dos dez documentos, preservação das evidências antigas, aprofundamento dos três P1, renderers/origens/perfis, estados e consumidores financeiros, falhas por etapa, concorrência/replay, achados N2-FIN-01/02/03. Triagem de todos 34 IDs e revisão de todos Q01–Q20. Oito entregáveis obrigatórios mais evidências/índices locais.

Suites novas: 37 PASS /0 FAIL /0 SKIP. Fase 1:236 PASS preservados, não repetidos. Validações do pacote estão em VERIFICACAO-PACOTE.json; não somar provas de vulnerabilidade como indicadores de produto seguro.

## Pendentes intencionais

- **Nenhuma correção funcional implementada**. HTML, atomicidade, parciais e HR38 continuam abertos.
- Decisões Q01–05/07/08/10/14/16 conforme frentes; dados reais desconhecidos em Q06/13.
- Revisão semanticamente completa de todos candidatos lexicais, catálogo/ACL reais, CSP/hostedAuth e dados de reconciliação só em tarefas futuras autorizadas. Não alegar cobertura exaustiva.
- Correção do núcleo e consumidores dos receipts deve reutilizar a RPC parcial já existente; não recriar arquitetura.
- Não iniciar SQL, push, merge, deploy, Fase B, email, FP28/29 ou administração direta automaticamente.

## Como retomar

1. Ler RESUMO-PARA-CHATGPT.md, P1-ANALISE-TECNICA.md e PLANO-DE-CORRECOES.md.
2. Conferir `git branch --show-current`, `git rev-parse HEAD`, `git status --short`.
3. Consultar CSV 34 IDs e decisões 20 IDs; escolher frente e obter autorização de correção.
4. Não reexecutar os geradores night-global-* antigos: eles escrevem nos relatórios da Fase 1.
5. Novos scripts night-phase2-* só produzem FASE-2. Para reproduzir provas, usar P1-TESTES.md; o grupo PG pode declarar SKIP se runtime faltar.

## Dependências locais

Node24; Playwright empacotado e Edge; PostgreSQL17.6/pg já em TEMP; Python empacotado para CSV. Os clusters descartáveis foram parados, sem operação destrutiva. Não é necessário levar clusters: reproduzíveis por scripts com dados sintéticos. No outro computador instalar/configurar runtimes equivalentes antes de testes. Nenhum segredo/token é necessário ou foi versionado.

CSV validado por parser CSV e importação @oai/artifact-tool do runtime empacotado. Sem workbook extra solicitado. Todos campos originais preservados; ordem proposta única e critérios por ID.

## Gates

Produto e SQL inalterados. Sem produção nesta missão. DD-TENANT abc160d e FaseB b7bf4c1 permanecem separados, preparados e não instalados por esta auditoria. Precheck DD informado PASS continua evidência histórica, não autorização para etapas restantes. Publicação NO-GO; pacote de análise pronto para revisão.
