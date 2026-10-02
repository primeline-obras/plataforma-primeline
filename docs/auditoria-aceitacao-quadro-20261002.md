# Auditoria independente de aceitação — Pacote 1 Quadro

02/10/2026. Ensaios exclusivamente locais. **NO-GO para fechar o Pacote 1/Fase B: um novo P1 confirmado.** Nenhum P0 confirmado. Não foi corrigido o candidato.

## A. Branch e identidade

- Candidato auditado: `feat/quadro-controlado-20261001`, `507fb1390c793b62e9d804e7cbf61445916e0480`.
- Base remota indicada e confirmada por `ls-remote`: `origin/main`, `9e0e6c40b439160201289823db8cfee0b9adad02`. O checkout main local está mais antigo; não o atualizei.
- Auditoria anterior: `audit/quadro-controlado-pacote1-final-20261002`, `47fcda710e5a6d48d8853be924632f84c9797114`, preservada.
- Nova branch criada exatamente do candidato: `audit/quadro-controlado-aceitacao-20261002`.
- Worktree: `C:\Users\Cristiana\Documents\plataforma-primeline-quadro-aceitacao`.
- Entrega desta branch: apenas este relatório e três testes independentes. O SHA da entrega consta do commit e da resposta final.

Não usei Supabase, produção, Chrome autenticado ou dados pessoais. PostgreSQL 17.6 real **local**, PGlite e browsers offline com API sintética. Não houve migration real, merge ou deploy. As fixtures reconstituem funções/constraints/triggers capturados; não provam o catálogo real atual.

## B. P0

Nenhum confirmado nos ensaios realizados. Isto não substitui os prechecks reais nem é prova de todos os schedules de concorrência.

## C. P1 — novo falso positivo na privacidade da referência B

**P1-AC01: pós-check B e alias aceitam grants de coluna na referência privada. Bloqueia a aceitação completa da Fase B.**

Objeto: `primeline_backup.quadro_fase_b_estrutura_20261001.estrutura`.

Em `supabase/quadro_controlado_fase_b_postcheck.sql:83–88`, a proteção da referência verifica owner/schema ACL e `pg_class.relacl`. Não examina `pg_attribute.attacl` dessa tabela. O snapshot de colunas seguinte cobre as oito tabelas operacionais/rollout, mas não a tabela de referência. Um grant de coluna não altera `relacl`.

Reprodução **somente na BD sintética**, instalação B íntegra:

```sql
BEGIN;
GRANT UPDATE (estrutura)
ON primeline_backup.quadro_fase_b_estrutura_20261001 TO authenticated;
-- Executar integralmente quadro_controlado_fase_b_postcheck.sql:
-- devolve POSTCHECK_B_OK, quando deveria recusar esta ACL.
ROLLBACK;
```

Repeti separadamente SELECT, INSERT, UPDATE e REFERENCES, executando **os dois scripts** em cada cenário e revertendo cada transação. Resultado em todos:

| Evidência | Resultado |
| --- | --- |
| `has_column_privilege(authenticated, ..., estrutura, privilégio)` | true |
| `has_schema_privilege(authenticated, primeline_backup, USAGE)` | false |
| Pós-check B rejeita | false |
| Alias rejeita | false |
| Instalação limpa após ROLLBACK | ambos passam |

Prova: `tests/audit-quadro-aceitacao.test.mjs:111`, saída `ACCEPTANCE_COLUMN_ACL`. Quatro assertions de aceitação falham deliberadamente; não foram convertidas em testes verdes de caracterização.

**Alcance:** a falta de USAGE no schema continua a impedir acesso normal pela aplicação. Não demonstrei leitura/adulteração por authenticated nem um bypass de atribuição/alocação; não é P0. Mesmo assim, o gate declara privada uma referência com grants inesperados, contrariando o critério explícito de rejeição de drift ACL. É um falso positivo de integridade do pós-check, classificado P1.

Correção mínima recomendada para tarefa futura: verificar também ACL de todas as colunas da referência, incluindo privilégios/grantees inesperados, e manter B/alias equivalentes. Repetir estes quatro negativos. **Não implementei a correção.**

## D. P2/P3 documentados

| Classe | Questão | Estado/limite |
| --- | --- | --- |
| P2 | Replay próprio após perda de papel/âmbito | Receipt original para autor ativo/mesma empresa/pedido original; nenhuma nova escrita. Política de receipts a decidir. |
| P2 | Alertas preservados depois de remover alocação | Referência histórica pode já não abrir uma alocação existente; resolução/navegação por definir. |
| P2 | Ausência posterior à alocação | Ordem ausência→alocação recusa; ordem alocação→ausência pode deixar ambos. Invariável inversa não implementada neste pacote. |
| P2 | RH multi-op na mesma transação x Quadro | Deadlock 40P01 reproduzido; vítima revertida. Uma chamada normal por transação funcionou. Não generalizar batches sem padronizar locks. |
| P2 | Rotação de backups após rollback A/forward-fix A | Dados recuperam; backup B pertence à instalação anterior e nomes fixos impedem nova cópia. Recuperação sem intervenção manual continua FAIL. |
| P2 | Cadastro novo RH sem idempotência geral | Contrato preservado; não repetir automaticamente após resposta perdida. |
| P2 | Obras encerradas | Diferença entre opções UI e permissibilidade backend exige decisão de negócio. |
| P2 | Rollback A restaura notifier baseline | Pode restaurar risco 23505 antigo; forward-fix volta a instalar o corrigido. |
| P2 | Lock global | Serializa pessoas/empresas; carga/fairness/starvation não certificadas. |
| P2 | Toast cobre temporariamente uma célula mobile | Confirmado abaixo; teste original de P1 falha. Sem envio errado; clique volta a funcionar depois de desaparecer. |
| P2 | Coluna da obra sai de vista ao fazer scroll horizontal | Coluna não congelada; utilizador precisa consultar antes/deslizar de volta. |
| P2 | Agenda preexistente e Excel externo RH | Falha Agenda não corrigida; um skip RH_XLSX não aprovado. |
| P3 | Cabeçalho geral mobile compacto e duplicação de SQL de referência | Melhorias futuras de UX/manutenção; não alteradas. |

Os P2 anteriores mantêm as limitações já conhecidas; não foram tratados como testes de produto aprovado. O toast é uma observação adicional de UX/teste.

## E. Resultado dos três P1 corrigidos

| Achado original | Resultado desta auditoria |
| --- | --- |
| Histórico ausente/disabled/rebound/definição divergente | PASS: B e alias recusam, incluindo trigger com WHEN adicional. |
| Notifier no-op mantendo assinatura | PASS: recusado. |
| Corpo crítico/ACL operacional/policy/objeto crítico alterados | PASS nos ataques operacionais; **FAIL para ACL de coluna da referência**, novo P1-AC01. |
| Célula fica saving após erro | PASS pelo handler físico real: finalmente remove classe/restaura pointer e permite nova tentativa. |
| Tablet/mobile enviam dia diferente | PASS: 27 alvos de nove datas, mouse/tap/hit-test/labels; nenhum dia errado. |

Novo teste PG também recusa referência ausente/vazia/duplicada, índice global removido/redefinido, policy ausente/extra, RLS desligada, coluna/revisão/default/tipo alterados, tabela/helper removidos, trigger extra, ACL schema e marker eliminado/invalidado/desconsumido. Drift de corpos antes do backup B é recusado por ROLLOUT_DRIFT; o backup não legitima esse drift.

B e alias são byte-equivalentes após normalizar CRLF. Instalação limpa passa e fotografia baseline permanece igual. Os negativos do candidato foram repetidos, não apenas lidos.

## F. Regressão histórica

| Item | Resultado |
| --- | --- |
| Novo fluxo evita DELETE→POST separado | PASS; somente preview+confirmação v1, rollback após falha tardia preserva tudo. |
| Temporalidade explícita novo Quadro | PASS; apenas data/período pedido, zero continuidade futura. |
| Ponto legado preservado | PASS de preservação; dívida temporal permanece. |
| Gerência não escreve Quadro | PASS; nova API e legado A recusam. |
| Revisão quando estado vazio | PASS; remove/recria e concorrentes detectados. |
| Notificações/chave/23505 | PASS com índice real capturado, A/B e múltiplos destinatários. |
| Gate privado B | PASS nos ataques de marker/roles/GUC; novo P1 no pós-check da referência. |
| Rollout A/B | PASS funcional/recusa segura, tabela seguinte. |
| Tenant/autoria/helpers | PASS nas combinações ensaiadas. |
| Cadastro/Importação RH | PASS dos contratos existentes; Excel externo é skip. |
| Writers legítimos | PASS da adaptação/inventário capturado; catálogo real atual pendente. |
| Backup não sobrescreve | PASS; segunda execução recusa. |
| Rollback/forward-fix preservam dados | PASS; recuperação B sem rotação manual FAIL/P2. |

### Writers revistos

- Frontend novo usa `fn_quadro_operar_v1`/`fn_quadro_contexto_v1`; sem INSERT/PATCH/DELETE de alocação.
- Núcleo `fn_quadro_aplicar_interno`: único writer nominal B de alocação, com permit privado/transação/lock; helpers de criação/renomear o reutilizam.
- `fn_quadro_operar` legado: compatibilidade A; stub e EXECUTE fechados B. DML direto A mantém triggers/locks/revisões; B fechado.
- `fn_rh_guardar`/`fn_rh_importar` → `fn_rh_guardar_interno` → overloads de criação → núcleo. Nenhum segundo algoritmo de alocação no RH.
- Trigger `fn_registar_movimento_quadro` escreve histórico/revisão; v1/núcleo escrevem ledger/permit/revisão.
- Scripts A/forward-fix criam/reconstituem controlo/revisões explicitamente; não inventam alocações. Marcador/rollback consomem/invalidam provas privadas.
- Backup B escreve fotografia/metadados privados, não operação de alocação.
- SQL histórico de criação e `quadro_pessoal_alocacao_diaria.sql` contém writers/backfill anteriores: não reaplicar.
- Helper dinâmico `fn_mgo_inserir_json_compativel(regclass,jsonb)` tem chamadas constantes de MGO e ACL privada na captura; não o publiquei/modifiquei. Novo pós-check deteta adição de helper dinâmico depois da referência. Varredura real de callers/ACL continua obrigatória.

## G. Rollout A/B/cache

| Frontend | Backend | Resultado |
| --- | --- | --- |
| Antigo | Antigo | PASS: escrita antiga funcional. |
| Antigo | A | PASS: compatibilidade antiga funcional. |
| Novo | A | PASS: preview e confirmação v1. |
| Novo | B | PASS: preview e confirmação v1. |
| Antigo | B | PASS de segurança: recusa sem persistência. |

Matriz provada pelo contrato PG e pelo browser independente. Assets antigos index/app/CSS/permissões vêm exatamente de 9e0e6c..., servidos só pelo HTTP local. Browser usa API simulada; não é PostgREST real.

Aba antiga permanece antiga depois de mudar assets do servidor e B recusa escrita; reload carrega cliente novo e grava no mock. RPC de contexto ausente simula deploy parcial: edição escondida, zero confirmações. Resposta perdida após commit mock: UI não presume sucesso/não repete; reload recupera contexto. Preview A pode confirmar em B quando a revisão ainda é válida. Escrita antiga já bloqueada durante hardening B é recusada depois do DDL.

Não foi certificado CDN real, todos os tipos arbitrários de mistura de assets/cache, nem reload persistente de todos os dados por um motor SQL no browser.

## H. Segurança/tenant

PASS local A/B: empresa/obra/pessoa alheias, utilizador inativo, Encarregado sem responsabilidade, request de outro autor, GUC falsificado e helpers privados. anon/authenticated/service_role não obtêm marcadores/permits/helpers pelo canal público. B fecha DML tabela/coluna e RPC antiga; SECURITY DEFINER legítima mantém caminho controlado. Autor/tenant derivam do contexto do utilizador, não de matching por nome/email.

A referência B protege schema/tabela mas omite coluna, P1-AC01. Não confundir esse falso positivo owner-local com um exploit de utilizador público demonstrado.

## I. Permissões

| Perfil | Escrita nova de alocação |
| --- | --- |
| Administrativo | Global na empresa. |
| Gestão da Plataforma | Global na empresa. |
| Gerência | Sem escrita de Quadro; Cadastro RH continua autorizado pelo seu contrato. |
| Diretor/Adjunto/Preparador | Consulta no âmbito permitido; sem escrita. |
| Encarregado autorizado | Apenas obras/origens/destinos do seu âmbito. |
| Encarregado não autorizado | Recusa. |

Backend PG e UI/browser concordam nas combinações testadas. A alteração de acesso do Adjunto é consulta à view workforce; não confere capacidade de gerir. Não troquei contas reais.

## J. Alertas

PASS: geração independente da chave via MD5 da representação canónica, evento/destinatário determinísticos, destinatários/eventos distintos, múltiplos ADM/Diretores, autor excluído, replay sem duplicar, preview zero, rollback sem persistência. Split/merge e legado concorrente repetidos. `alertas_ocorrencia_unica_idx` preserva exatamente a definição capturada; nenhum default UUID novo contorna unicidade.

Medicina original, Viaturas e regressões de alertas passaram, exceto Agenda preexistente. Alertas históricos após remoção são P2 já explícito.

## K. Locks/concorrência PostgreSQL 17.6

Duas ligações independentes de aplicação e uma de inspeção. Funções, constraints/FKs e triggers de ausência capturados reinstalados.

| Schedule | Resultado fresco |
| --- | --- |
| Pessoas diferentes A/B | Serializam globalmente; 118/72ms com pausa deliberada. |
| Mesma pessoa/dia/revisão | Uma confirma, segunda STALE; 71/66ms. |
| API antiga x nova A | Espera e versão antiga recusada, 74ms. |
| Cadastro RH x movimento | Atómico após espera; 94/95ms. |
| Renomear x mover | Segunda STALE; 66/63ms. |
| Ausência primeiro | Alocação recusa depois de libertar FK lock. |
| Alocação primeiro | Ausência posterior coexistente, P2. |
| lock_timeout 100ms | 55P03 em 113/116ms; rollback liberta, operação seguinte funciona. |
| RH multi-op explícito x Quadro | 40P01 confirmado, vítima revertida; P2. |
| B bloqueada por operação aberta | 57014 em 263ms; rollback conserva A/marker não consumido; retry autorizado local instala. |

Nenhum lock ficou preso nos ensaios que recuperaram; clusters parados em finally. Não se provou fairness/starvation sob carga, nem ausência universal de deadlock. O deadlock conhecido não foi ocultado por testes de caracterização verdes.

## L. Cadastro/Importação RH

A/B locais: com/sem alocação inicial, escritório/obra, data histórica explícita, contrato, tenant divergente, ausência/conflito e falha tardia preservam atomicidade. Falha após pessoa/contrato/DELETE/alerta reverte pessoa/contrato/alocação/ledger/histórico/revisão/auditoria. Cadastro x Quadro concorrente completou sem cadastro parcial.

Importação atual trata IDs existentes; com/sem alocação mantém alocações e não cria pessoas novas. Erro na segunda linha reverte a primeira. Não reinterpretei esse contrato como uma nova importação criadora de colaboradores. Excel real sintético no browser passou; fixture externa opcional de 47 linhas não foi fornecida e permanece skip.

## M. Ponto legado

PASS: funções de Ponto capturadas permanecem iguais e não são redefinidas pelo pacote. Nenhuma cobertura futura/backfill criado para corrigir herança. Responsabilidade por obra não cria presença.

**DÍVIDA TRANSITÓRIA INTENCIONAL — REMOVER NO PACOTE 2.**

## N. Prechecks/backups/postchecks

Fluxos completos locais A/B executados pelas suites: precheck, backup, migration, pós-check, marker, precheck B e backup B. Backups privados cobrem objetos inventariados/ACL/grants/colunas/triggers e fotografias de alocações/movimentos/revisões/ledger; referência estrutural B antecede B e exige A validada. Repetição não sobrescreve cópias.

Fotografia sintética de 227 alocações/98 movimentos e conflitos deliberados preservada na instalação. Nenhum destes números representa a BD real.

Pós-check íntegro passa. Negativos de instalação operacionais passam como recusas. **Pós-check B não rejeita todos os grants da referência**, P1-AC01. Não considero o gate completo aprovado.

## O. Rollback/forward-fix

PASS de preservação nos ciclos locais A→rollback A, A+operações→rollback A, A→B→rollback B, nova prova→forward-fix B e rollback A→forward-fix A. Dados operacionais/histórico/revisões/alertas não são apagados por restauro da fotografia.

Arollback fecha v1/restaura baseline. FFA invalida previews antigos. Brollback invalida validação/aumenta tentativa; FFB exige nova prova. Marker consumido/inválido/reutilizado é recusado. **FAIL/P2** para recuperação totalmente automática B depois de reconstruir A: exige rotação autorizada de backups, não apagar backups para contornar.

## P. Browser desktop/tablet/mobile

Browser independente usa handler físico, sem hooks de save, sem force-click, sem alterar app.js. Hooks servidos em memória dão leitura de estado e perfil sintético; rede não-local intercetada.

| Viewport | Board visível | ScrollWidth | Menor célula | Resultado |
| --- | ---: | ---: | ---: | --- |
| 1440×1000 | 1071px | 1600px | 48,42px | PASS independente |
| 820×1180 | 451px | 1600px | 48,42px | PASS independente |
| 390×844 | 329px | 1600px | 48,42px | PASS independente após esperar toast |

Nove datas em três semanas por viewport: 21/24/27 setembro, 05/08/11 outubro, 12/15/18 outubro. boundingBox, elementFromPoint, label do dia/semana, sete colunas, wheel horizontal, mouse e touchscreen Playwright. Payload coincide com data/célula. Conteúdo de íman cabe na célula/overflow hidden. Mover/retirar/cancelar/reload e split→merge visuais passaram nos três tamanhos; regras SQL de split também testadas em PG. Mock de split fornece respostas coerentes de duas metades; não se apresenta como motor SQL.

Onze falhas preview/confirmação por viewport: ABSENCE_CONFLICT, LEGACY_CONFLICT, permissão, STALE, rede, resposta inválida e exceção. Saving/pointer recuperam; clique manual posterior funciona; sem retry automático. Duplo clique e outro alvo durante pedido pendente: uma confirmação, nenhuma célula presa.

### P2 adicional — original P1 browser não passou integralmente

`tests/workforce-p1-browser.mjs` falhou no mobile ao testar a célula 09/10 depois de TERMINAR. Repetição isolada falhou novamente. Reprodutor independente `audit-quadro-aceitacao-hit-test.mjs` identificou em elementFromPoint **div.toast.success**, não outra data/célula.

Centro do alvo: retângulo x=106,70/y=750,31/w=48,44/h=94, viewport 390×844. Toast ocupa a parte inferior durante até 4200ms. Original exige hit-test imediato sem aguardar toast e falha. Não houve gravação errada nem saving preso. Teste independente aguarda desaparecimento natural, mede/hit-testa novamente e só então faz mouse/tap. Não remove toast, não força clique e não relaxa a comparação de data.

Screenshots locais inspecionados em `%TEMP%\primeline-quadro-aceitacao-browser` e `%TEMP%\primeline-quadro-aceitacao-hit`. Não versionados. O ecrã capturado pode já não conter o toast por ele desaparecer entre hit-test e screenshot; a evidência do elemento interceptador foi registada no log. Header mobile compacto e primeira coluna não congelada continuam limitações.

## Q. Testes e contagens

| Execução final | Total Node | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| Quadro/RH/Ponto-Férias/Medicina/Viaturas/Planeamento/wrapper/acesso | 439 | 438 | 0 | 1 |
| Alertas/Agenda/documentos/reuniões/Horas Extra legado | 24 | 23 | 1 | 0 |
| Novo PG independente de aceitação | 37 | 32 | 5 | 0 |
| **Total sem somar reruns** | **500** | **493** | **6** | **1** |

Os grupos-pai Node entram nas contagens: cinco FAIL do novo PG são quatro cenários de ACL e o grupo-pai. Falhas distintas: quatro ACL + Agenda. **Skip não é aprovado.** Agenda já exige styles v98/app v145 na base anterior, enquanto versões publicadas são mais novas; não corrigi nem relaxei a assertion.

Browsers, contados por script e sem somar reruns: **11 scripts, 9 passaram, 2 falharam**. Nove originais: oito passam, workforce-p1-browser falha pelo toast; novo browser completo passa; novo reprodutor do hit-test falha pela mesma obstrução. Não digo que todos os browsers passaram.

Oito originais verdes: workforce-controlled, rh-frontend, **medicine ORIGINAL**, planning, planning-selection, vehicle-assignment, vehicle-validity, rh-cadastro. Medicina executada sem editar; o candidato já contém uma linha de stub Quadro relativamente à base, não remoção de assertions de Medicina. RH original Windows usou bootstrap temporário/dependências existentes.

Separação: PostgreSQL local real para gate/RLS/RH/alertas/concurrency e suites próprias; PGlite para suites que o usam; testes estáticos/clientes não são BD real; browser usa mocks HTTP. `git diff --check` executado no final.

Logs locais: `%TEMP%\quadro-aceitacao-global.log`, `quadro-aceitacao-alertas.log`, `quadro-aceitacao-independente.log`, `quadro-aceitacao-browser.log`, `quadro-aceitacao-hit-test.log`, `quadro-aceitacao-p1-rerun.log` e logs dos nove browsers. Sem dados reais. Tentativas intermédias de desenvolvimento dos testes não foram somadas ao total.

## R. GO/NO-GO LOCAL — Fase A

**GO LOCAL condicionado** aos P2 documentados e prechecks reais/autorização futura. Não encontrei P0/P1 novo que afete a instalação/transação A. Não é autorização para aplicar.

## S. GO/NO-GO LOCAL — frontend

**GO LOCAL condicionado** à limitação do toast/scroll e validação autenticada futura. Saving e correspondência data/payload corrigidos; teste original mobile permanece FAIL/P2, independente passa sem force-click depois da espera natural. Nenhum deploy autorizado/executado.

## T. GO/NO-GO LOCAL — Fase B

**NO-GO para aceitação/fecho B**, por P1-AC01. Corrigir em outra tarefa o check de ACL de coluna da referência e reexecutar os negativos, alias e recuperação. Não declarar o pacote apto antes disso.

## U. Validações reais ainda necessárias

1. Novo candidato corrigindo P1-AC01 e nova verificação independente do SHA exato; candidato atual não modificado aqui.
2. Confirmar main/candidato/catalogo atuais, todas as definições/FKs/triggers/ACL/RLS/roles/writers dinâmicos/callers e índice/default real de alertas. Capturas não são prova atual.
3. Precheck/fotografia reais de alocações/movimentos/conflitos/ausências/responsáveis/RH/Ponto; sem dados pessoais no Git.
4. Backup privado + exportação verificável; inventário/rotação de backups existentes e plano de recuperação B. Não fabricar referência de um B com drift.
5. Autorização separada para A, pre/postcheck real e preservação de dados legados sem backfill.
6. Frontend autenticado por perfil, desktop/tablet/mobile/dispositivo real, histórico/autor/data, ausências, Ponto e alertas/visibilidade por destinatário; verificar toast/scroll operacional.
7. Propagação real de assets/CDN/cache/abas antigas/deploy parcial/resposta perdida; sem retry cego.
8. Owner regista prova privada B somente após validação operacional verdadeira; autorização separada para B, pós-check corrigido, RH/importação e recusa antiga.
9. Carga/locks com writers reais e plano para deadlock multi-op; não prometer fairness. Decidir P2 receipts, ausência inversa, recuperação e alertas antigos.
10. Fixture externa RH_XLSX caso necessária; ensaios offline não substituem dados reais. Pacote 2 remove dívida temporal do Ponto.

Nenhuma correção de produto foi feita. Entrega/push apenas da auditoria; candidato, auditoria anterior, main e urgent permanecem intactos.