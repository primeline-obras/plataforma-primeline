# Fecho local final do Pacote 2 — 07/10/2026

## A. Branch e versão

Branch: `fix/pacote-2-fecho-local-final-20261007`.
Base exata: `6517aad4409b988b9fd6eda7c8f1eda1ec2296e1`, preservando a auditoria e os seus testes negativos.
Candidato anterior: `32e9493e6083f042ee29dbf2f09dab66e7a55e04`.
Código final: `23058444d402224354bb6765db66b5b8daa44971`.
O HEAD entregue inclui este relatório e o ajuste do runner para dependências isoladas; a segunda execução completa também verifica esses commits. O SHA completo de entrega é obtido por `git rev-parse HEAD` e confirmado no remoto.

## B. Commits

- `979fe78ae9faf1e345f023a7e21785c5696e4734`: correções FC-01–FC-08, regressões, runtime e descoberta automática.
- `23058444d402224354bb6765db66b5b8daa44971`: guarda adicional de evidência no rollback parcial, encontrada na segunda revisão.
- `a9c058663ba0f2c90fcc68feccc854b388bbe8b8`: relatório consolidado.
- `bc26002588ef57dc193103826ada497cc71060b1`: override PGlite para as suites antigas na worktree limpa.
- Commit documental de entrega: este relatório. Nenhum commit em main.

## C. FC-01 — PASS

A baseline documental passa a certificar também `storage.buckets`: schema/nome, owner, RLS/force RLS, ACL efetiva de tabela e colunas, policies completas, conteúdo do bucket e helpers usados diretamente pelas policies. Os helpers incluem definição, owner, SECURITY DEFINER, search_path e ACL efetiva. ACLs são normalizadas por privilégio, em vez de depender da ordem textual dos grants.

A configuração é capturada da instalação autorizada; não se inventa uma política de Storage. A mesma expressão é usada na instalação, postchecks, Folha precheck, cutover e gates B. A baseline não é regenerada durante os testes de drift.

`audit-pacote2-final-bucket-drift.test.mjs` cobre separadamente 15 mutações: owner, RLS, force RLS, ACL tabela/coluna, policy adicionada/removida, USING, WITH CHECK, public, MIME, limite, SECURITY DEFINER, search_path e ACL do helper. Todas são recusadas; instalação correta passa.

## D. FC-02 — PASS

Precheck, backup, migration e postcheck B exigem cutover completo: trigger exato e ativo, helper com corpo/owner/privilégios/search_path corretos, snapshot privado, legado integralmente igual ao snapshot e writer V2 instalado. Aprovação pré-cutover não permite B. Catálogo pós-cutover diferente da aprovação aborta.

Testes: pré-cutover recusado, cutover parcial recusado, trigger reaberto/desativado recusado, helper alterado recusado, snapshot exposto recusado, aprovação antiga recusada e sequência pós-cutover aprovada permitida. Aprovações usadas nos testes são exclusivamente sintéticas.

## E. FC-03 — PASS

O coletor read-only devolve `ABSENT`, `MATCH`, `STALE` ou `INCOMPATIBLE`, hashes SHA-256 de expected/live, match, cutover presente, privacidade do gate e correspondência da instalação. Compara a mesma expressão de catálogo usada pelo gate B.

Regressões executam o coletor com aprovação correta, `{}`, catálogo alterado, linha ausente, tabela ausente, trigger desativado, installation_id errado, aprovação consumida e grant indevido no gate. Os estados são distinguíveis. Não há atualização de expected_catalog pelo coletor.

## F. FC-04 — PASS / concorrência

Gestão, core e cutover adquirem locks antes dos checks destrutivos. A ordem respeita o Quadro: lock da tabela de alocações, advisory canónico `(61001,1)`, depois tabelas da camada. Writers Folha usam a mesma coordenação. READ COMMITTED é exigido; lock_timeout recusa fechado a contenção prolongada.

Dois clientes PostgreSQL reais locais provaram: writer anterior bloqueia rollback, commit legítimo faz rollback recusar e preservar a linha; writer posterior aos locks não consegue commitar um facto que seja apagado. Rollback vazio funciona. Não se usa um atraso fixo como prova: os testes observam `pg_blocking_pids`.

Sweep: documental bloqueia a tabela antes de restaurar policy e preserva as guardas restritivas; B bloqueia alocações/movimentos antes da alteração e não apaga factos; core/cutover recusam factos e ordem inválida. Não foi introduzido CASCADE destrutivo.

## G. FC-05 — PASS / dependências

`calendar_validated_years` pertence agora ao core, que já o utilizava. Gestão adiciona-o apenas se necessário e não o remove no rollback parcial. Foi revista a lista de DROP de Gestão contra as referências do core: helpers, colunas, triggers e tabelas exclusivos são removidos; dependência partilhada permanece.

Gestão rollback → RPC core legítima passa, sem 42703. Ordem Gestão → core vazia passa; core antes de Gestão ou com cutover ativo recusa explicitamente. Revisões de férias e operações administrativas também impedem rollback parcial que perderia evidência.

## H. FC-06 — PASS / replay

O core chama `folha_privado.autorizar_replay` antes de devolver token/resultado antigo. Revalida ator ativo, empresa, papel/capability atual, obra/responsabilidade, pessoa/fornecedor e janela de correção aplicável. Gestão revalida papel, âmbito e entidades de HE, ausência, Folha, tarefas e pessoa antes do replay.

Não se repetem revisões/precondições factuais que o commit original alterou. Resultado original continua idempotente, sem segunda escrita. Gestão → Gerência, perda de responsabilidade, inativação e correção histórica fora da janela são recusadas. Payload diferente continua `IDEMPOTENCY_CONFLICT`. Tenant e permissões negativas permanecem cobertos pela matriz.

Gestão Plataforma conserva a capacidade funcional prevista; Gerência não recebe por esta correção as capacidades reservadas. Tenant, auditoria e concorrência continuam obrigatórios.

## I. FC-07 — PASS / reentrância

O lock de importação é adquirido antes do primeiro await e libertado no finally. Sweep encontrou o mesmo padrão em confirmações próximas de custos e subempreitadas: os handlers agora bloqueiam segunda ativação enquanto a confirmação está pendente e libertam no cancelamento/erro/sucesso.

Testes usam handlers completos do produto, sem cortar o prefixo de confirmação. Cobrem duas chamadas simultâneas, cancelamento sem escrita, adapter com erro, retry e uma única operação confirmada. Browser usa o adapter `platformConfirm` real em desktop/tablet/mobile.

## J. FC-08 — PASS / testes e runtime

Expectativas obsoletas foram alinhadas com platformConfirm e CSS v9; não se restaurou confirm nativo nem asset antigo. `tests/runtime/package.json` e lockfile fixam jsdom, PGlite, pg, Playwright e xlsx como dependências apenas de teste. `login-password.test.mjs` executa.

Foram corrigidos caminhos Windows do browser RH e mocks de âmbito que não incluíam as RPCs já existentes. As regressões funcionais não foram relaxadas. Node_modules, logs e dados gerados ficam fora de Git.

## K. Achados correlatos resolvidos

- Helpers referenciados pelas policies e ACLs semânticas entram na evidência documental.
- Todos os gates B verificam cutover, incluindo backup/migration/postcheck.
- Coletor identifica instalação errada, aprovação consumida e gate exposto.
- Core rollback protege dependências/ordem e factos concorrentes.
- Gestão rollback protege também revisões de férias e evidência administrativa isolada.
- Confirmações de custos, fusão e eliminação têm guardas antes de await.
- Browser RH e Quadro usam os contratos atuais e executam no Windows.
- O runner aponta `QUADRO_PGLITE` para o runtime declarado do checkout; dois testes antigos já aceitavam esse override, mas recorriam a uma pasta ignorada ausente numa worktree nova.

## L. Descoberta integral

`tests/run-pacote2-local.ps1` descobre, ordena e deduplica os ficheiros no checkout em execução: **143 ficheiros `*.test.mjs` e 20 scripts browser**. Nenhuma lista fixa histórica é usada. A busca adicional por ficheiros test/spec não encontrou outro executor omitido. O runner termina toda a matriz e recolhe resultados antes de devolver falha.

## M. Node

Execução final: **1067 PASS / 0 FAIL / 1 SKIP** (1068 testes reportados pelo Node). O total é o resumo nativo, incluindo os containers de teste; não se somam repetições diagnósticas. Os 143 ficheiros foram executados uma vez nessa matriz.

O único SKIP exige `RH_XLSX`, um ficheiro RH real externo não fornecido a esta execução. Os antigos SKIPs de runtime RH executaram com xlsx; jsdom também executou. Não há FAIL convertido em SKIP.

## N. Browser

**20 suites PASS / 0 FAIL**. Contextos novos e dados sintéticos, desktop/tablet/mobile nas suites responsivas. Folha, Escritório, estados/legado, ações coletivas, sessão, Quadro, RH, Medicina, Planeamento, Financeiro, RNC, Viaturas, dialogs e assets cobertos pelos executores descobertos. Não houve page errors relevantes nas verificações das suites.

## O. PostgreSQL

PostgreSQL **17.6 local/efémero**, com clusters e clientes novos; PGlite nos testes que o utilizam. Suites de backend/tenant, idempotência, concorrência, calendário, HE, dias especiais, férias/ausências, vencimentos, externos, tarefas e histórico executadas. Nenhuma ligação à produção foi utilizada.

## P. Rollout/cutover

Sequência local comprovada: documental precheck → backup → migration → postcheck; core/gestão; cutover precheck → migration → postcheck; aprovação sintética pós-cutover; B precheck → backup → migration → postcheck. Gate real permanece separado e não foi fabricado. O cutover não fecha writer legado antes das suas próprias precondições.

## Q. Rollbacks

Rollbacks documental, Gestão, core, cutover e B revistos e exercitados localmente. Segurança documental e tenant não são removidos pelo rollback de compatibilidade. Rollback B preserva dados/revisões e writer legado fechado; aprovação consumida não é reativada. Rollback com factos exige plano específico e recusa esta operação vazia.

## R. SQL real read-only

`supabase/pacote2_validacao_real_final_readonly.sql` usa transação REPEATABLE READ READ ONLY e termina em ROLLBACK. Apenas catálogo, contagens e evidência agregada; sem DDL/DML, GRANT/REVOKE ou chamada de RPC mutante. Não imprime pessoas, ficheiros ou valores económicos. Calendário informa anos e completude sem inferir validação a partir de linhas existentes.

## S. Segunda verificação em worktree limpa

Passagem separada pelo mesmo agente, a partir do commit, sem alterar produto nessa worktree. Instalação `npm ci` pelo lockfile, sem reutilizar node_modules do desenvolvimento; nova descoberta integral, clusters PostgreSQL efémeros, contextos browser e diretório de logs separado.

A primeira revisão limpa encontrou a guarda de evidência descrita em K e duas dependências de teste em pasta ignorada; foram corrigidas na branch e testadas. A verificação limpa foi então repetida sobre o HEAD final, com negativos FC, matriz completa, scripts/rollbacks e `git diff --check`. Resultado final verde, com os totais M/N. Não se afirma auditoria por outra pessoa/agente.

## T. Restantes locais

**P0 = 0; P1 = 0; P2 = 0; P3 = 0 nas classes desta tarefa.** Os oito FC e os correlatos identificados ficaram fechados. Isso não é uma certificação universal de código fora do âmbito revisto.

## U. Gate externo

**REAL_VALIDATION_REQUIRED**: confirmar catálogo/calendário/baselines atuais com uma execução do coletor real autorizado. O teste RH com ficheiro real permanece dependente desse artefacto externo e não bloqueia as regressões sintéticas.

Não se alterou produção, main, perfis/dados reais, deploy, marcador ou Fase B. Scripts SQL foram executados exclusivamente em bases locais sintéticas.

## V. Decisão

**GO LOCAL para validação READ-ONLY real.** Rollout real depende da análise do resultado e de autorização própria.

FECHO LOCAL CONCLUÍDO — TODOS OS ACHADOS FC-01–FC-08 E CORRELATOS RESOLVIDOS, SEGUNDA VERIFICAÇÃO INDEPENDENTE VERDE, 0 FAIL, P0/P1/P2 LOCAIS = 0.

PRÓXIMO E ÚNICO GATE: VALIDAÇÃO READ-ONLY REAL.
