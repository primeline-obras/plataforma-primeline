# Reauditoria final — reconciliação de estado do Pacote 2

## A. SHA auditado e limites

Candidato `fix/pacote-2-reconciliacao-estado-final-20261006`, SHA exato `09b586bcf7e5905da46fdd67ca5efd46d96a6eac`. Auditoria de 06/10/2026, exclusivamente local e sintética. A auditoria anterior `f576726473691e11ac7d84f50a51ea357b2aa180` permanece preservada.

Não houve consulta ao catálogo real, SQL em produção, alteração de produto, merge, publicação ou Fase B real.

## B. Branch da auditoria

`audit/pacote-2-reconciliacao-estado-final-20261006`, criada diretamente do SHA auditado. O SHA da auditoria é o commit que contém este relatório e é apresentado na entrega. Alterações limitadas a este relatório, dois módulos de testes independentes e uma chamada desses casos na suite backend existente.

## C. P2 original — PASS

Uma pessoa/data sintética independente foi registada com oito horas, recebeu férias e passou a `regularization`. A remoção autorizada das férias restaurou `registered`, mantendo intervalos e minutos. Estado persistido, contexto diário, cliente, resumo, DIA COMPLETO, factos mensais vivos e fotografia mensal guardada coincidiram.

A UI real foi adicionalmente exercitada com 12 contextos capturados das RPCs no PostgreSQL local: 36 combinações de contexto/viewports aprovadas. Não se substituiu o estado esperado por uma fixture inventada nessa verificação.

## D. Fluxo inverso — PASS

Adicionar férias/ausência a uma folha registada produz regularização e pendência. Justificar uma ausência coexistente com trabalho mantém regularização, sem converter silenciosamente o tipo da ausência. Remover a ausência recalcula os factos restantes; uma folha curta regressa a `missing`.

## E. Matriz final e concorrência

| Caso | Resultado | Evidência |
|---|---|---|
| A: jornada completa | PASS: registered | Casos independentes e suite existente |
| B: jornada curta | PASS: missing | Casos independentes |
| C: intervalo aberto | PASS: open | Casos independentes |
| D: conflito remanescente | PASS: regularization | Suite de reconciliação existente reexecutada |
| E: replace multidata | PASS: todas as datas reconciliadas | Casos independentes e suite existente |
| F: erro intermédio | PASS: rollback integral | Falha sintética injetada na suite existente reexecutada |
| G: justificação pendente/confirmada | PASS: coexistência com trabalho preservada | Casos independentes e suite existente |
| H: adicionar ausência a folha existente | PASS: regularization | Casos independentes |
| I: remover única ausência | PASS: estado dos factos restantes | Casos independentes |

As duas ordens concorrentes Folha/ausência passaram com ligações PostgreSQL locais separadas. A revisão antiga é recusada sem duplicação. Revisão de código confirmou coordenação pelo lock transacional global e locks pessoa/data, seguida de FOR UPDATE nas folhas. Writers legados adquirem o lock antes da escrita; isolamentos com snapshot antigo são recusados com RETRY_READ_COMMITTED. Não foi criado caminho novo de exploração.

## F. História — PASS

Verificados antes/depois, revisão, ator, timestamp, request_id e origem. A remoção independente gerou uma única entrada de reconciliação da folha; preservou a história administrativa de férias e a reconciliação mensal. Mudança efetiva de estado incrementa revisão; ausência de mudança não inventa uma revisão de folha. Rollback intermédio também preserva atomicidade das histórias.

## G. HE e referências históricas — PASS

Reexecução dos testes de supersede, unicidade por folha/revisão, replay, regras desativadas, calendário incompleto, feriado/dia especial, HE manual, Escritório e externos. Nenhuma geração financeira automática foi introduzida. O reader devolve none quando não existe potencial aplicável; a UI não o inventa pelos minutos.

expected_minutes e special_day são referências persistidas por folha. Alterações de carga/calendário não reclassificam silenciosamente os registos existentes. Carga desconhecida continua em regularização. Não existe rebase retroativo exposto; uma nova entrada explícita usa a configuração corrente. Esta limitação está documentada, sem inventar vigência histórica.

## H. Fonte única e paridade — PASS

| Camada | Fonte/resultado verificado |
|---|---|
| Persistência | Estado canónico gravado na folha |
| Contexto diário | sheet.state preservado |
| Cliente e linha visual | Estado recebido prevalece sobre inferência por intervalos |
| Resumo e pendentes | Correspondem ao estado factual |
| DIA COMPLETO | Falso perante regularização, missing ou open |
| Vencimentos vivo | Usa estado persistido |
| Vencimentos guardado | Reconciliação transacional de factos e revisão |

Comparação independente na mesma pessoa/data para jornada completa, curta, aberta, férias set/remove/replace e ausência justificada/removida. Valores manuais mensais são preservados; fontes de mês fechado/exportado não mudam silenciosamente. As regras ADM permanecem neutras/desativadas, sem efeito económico fictício. A incorporação dessas regras pertence à etapa seguinte e não é bloqueador desta auditoria.

## I. Regressões e scripts — PASS local

Reexecutadas 15 suites focadas: attendance-backend-v2, attendance-domain, attendance-v2-static, workforce-controlled, workforce-vacations, absences-workflow, overtime-workflow, rh-cadastro, planning-operational, planning-cost-access, session-boundary, session-isolation, foreman-scope, phase-b-hotfix-compatibility e medicine-client.

Cobertura inclui histórias V2/legado, Folha, férias/ausências, Escritório, externos, HE, vencimentos, sessão, Quadro, RH, Medicina e Planeamento. Matriz e testes já preparados foram reutilizados; não foram criados cenários ofensivos.

Revisão da versão consolidada de precheck/backup/migrations/postchecks/rollbacks: precheck somente leitura; definição canónica, triggers e helpers presentes; postcheck exige catálogo/ACL e preservação do legado; helpers privados sem EXECUTE externo; rollback explícito sem CASCADE indiscriminado. Instalação e rollback vazios passaram no PostgreSQL efémero. Compatibilidade Fase B passou somente localmente. Scripts de instalação inicial continuam a recusar uma BD já instalada; não constituem atualização automática de produção.

## J. Testes e resultados

**Node: 325 PASS / 0 FAIL / 3 SKIP; 328 testes, 15 suites.** Inclui cinco grupos independentes acrescentados nesta auditoria. Os três SKIPs RH existentes permanecem SKIP, não aprovação; dependem do ambiente RH_TEST_DEPS não configurado.

| Browser local | Resultado |
|---|---|
| Contextos PostgreSQL independentes → UI | 36 PASS, zero erros JS; 1440/820/390 px |
| Reconciliação do candidato | 81 PASS, zero erros JS |
| Estados visíveis | 126 PASS |
| Folha | 57 PASS |
| Consolidação | 51 PASS |
| Sessão | 7 cenários PASS |
| Custos do Planeamento | 33 PASS |
| RH frontend | PASS; escape HTML e remoção do fluxo antigo |
| Quadro controlado | PASS; âmbito, ações e ausência de DML direto |

Todo tráfego externo do browser foi bloqueado. Escritas dos testes ocorreram apenas com dados sintéticos em base efémera ou mocks. Para repetir o browser independente, executar primeiro a suite backend, que produz contextos sintéticos no TEMP, e depois attendance-reconciliation-final-audit-browser.mjs.

Os 599 PASS / 0 FAIL / 3 SKIP do conjunto amplo do candidato são evidência anterior preservada; não são apresentados como nova execução integral nesta auditoria focada. git diff --check aprovado. Diff de produto/SQL/index.html contra o SHA auditado vazio.

## K. Achados e limites

Nenhum P0/P1/P2 restante confirmado nesta classe pelas evidências locais. Os dois sentidos de reconciliação, atomicidade, história, concorrência e paridade foram aprovados. Não houve correção do candidato.

O catálogo real não foi revalidado nem foi tentado método anteriormente bloqueado. Não há GO de produção nesta entrega. Os SKIPs e a política sem rebase retroativo permanecem explicitamente registados. Regras ADM desativadas requerem a tarefa própria antes da preparação do rollout.

## L. Decisão

**GO LOCAL.** P2 original fechado, zero FAIL, regressões verdes e nenhum novo P0/P1/P2 bloqueante identificado.

**PACOTE 2 APTO LOCALMENTE PARA INCORPORAÇÃO DAS REGRAS ADM JÁ VALIDADAS, ANTES DA PREPARAÇÃO DO ROLLOUT REAL.**
