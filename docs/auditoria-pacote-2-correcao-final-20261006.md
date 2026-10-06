# Reauditoria independente focada do Pacote 2

Data: 06/10/2026. Auditoria defensiva, exclusivamente local e sintética.

## A–B. Identidade e limites

- Candidato auditado: `fix/pacote-2-auditoria-final-20261006`, `25303450f2d8afab97cb59ea521fd1d14f0a3c00`.
- Auditoria: `audit/pacote-2-correcao-final-20261006`, criada diretamente desse SHA. O SHA do commit deste relatório identifica a entrega; não há autorreferência de hash no ficheiro.
- Auditoria anterior preservada em `audit/pacote-2-folha-ponto-final-20261005`, `4ccdf1e2b44262019e06806b1f27540309ca8951`.
- A secção 1 do pedido contém um SHA abreviado incorretamente. Foi usado o SHA completo confirmado no Git e no início do pedido.
- Nenhum produto, SQL de rollout, fixture de produção ou definição backend foi alterado nesta auditoria. Não houve consulta à BD real, deploy, main, marker ou Fase B real.

## C–G. Achados anteriores, replay e projeções

**P1 anterior: PASS, fechado no candidato.** JSON bruto de Encarregado/Diretor/Adjunto contém exatamente `version`, `schedule`, `permissions`, `tasks`, `task_reports`, `overtime`, `history`. Não contém payroll, people, config, live_facts, vacations, vacation_revision ou entitlements. Sentinela salarial e ações salariais não passam. Administrativo/Gerência/Gestão conservam payroll e contexto administrativo legítimo.

**P2 anterior: PASS na correção específica.** `createSheetClient.history` conserva `events`, `legacy`, `legacy_interpretation='original'`. Os quatro estados V2/legado/ambos/nenhum são cobertos pela RPC/cliente e pela UI existente. A UI separa HISTÓRICO FOLHA V2 e REGISTO LEGADO, sem edição, conversão, revision inventada ou normalização do estado original. Há uma limitação de alcance adicional, descrita abaixo.

**Replay: PASS.** Payroll, HE e tarefa recusam o mesmo request após redução de papel para Financeiro. Restabelecer o papel devolve exatamente o resultado original, sem duplicar histórico. Retirar responsabilidade por obra recusa contexto e replay de tarefa/HE; restabelecê-la recupera o replay legítimo. As guardas atuais precedem o cache.

**Domínio: PASS.** Coluna gerada/armazenada, quatro categorias (`tarefas`, `he`, `horario`, `administrativo`), CHECK fechado de ações. Ação desconhecida e domínio escolhido pelo cliente são recusados. Evento salarial sintético com obra continua invisível ao operacional. Representantes dos quatro domínios foram verificados.

**Projeção legado: PASS.** Allowlist exata de 14 campos: id, data, obra_id, horas, quatro entradas/saídas, periodos_alocados, estado, registado_por, atualizado_por, criado_em, atualizado_em. Não passa observação, justificação, revision ou coluna privada futura adicionada à fixture. O precheck aborta quando falta coluna obrigatória; não modifica nem corrige o schema.

## H. Matriz dos quatro readers

| Perfil | Contexto diário | Pessoas/picker | Histórico | Contexto de gestão |
|---|---|---|---|---|
| Encarregado | Obras responsáveis, equipa/dia, permissões e revisões | Dentro do âmbito escritor, destino pontual | Pessoa/obra/data com evidência autorizada | Tarefas/reportes; HE vazio; sem administrativo |
| Diretor/Adjunto | Obras autorizadas e escritório próprio | Recusado sem gestão de alocação | Âmbito autorizado | Tarefas, HE e horário próprios da obra; sem salário |
| Preparador | Self-service próprio | Recusado | Próprio permitido; obra alheia recusada | Administrativo recusado |
| Administrativo/Gerência/Gestão | Empresa própria | Empresa própria | Empresa própria | Administrativo legítimo preservado |
| Financeiro | Obra recusada; sem obra envelope vazio | Recusado | Recusado | Recusado |
| Inativo/sem perfil/outra empresa/obra fora do âmbito | Recusado nos cenários preparados | Recusado | Recusado | Recusado |

Nuance: Financeiro com `p_obra_id=NULL` recebe envelope sem linhas/obras/externos e com permissões falsas, não erro 42501. Não recebe dados RH nem herda capacidades. Esta observação não foi apresentada como recusa universal.

Catálogos de fornecedores/externos para escrita não chegam a Diretor/Adjunto. Linhas externas efetivamente registadas permanecem consultáveis conforme âmbito. JSON não contém remuneração, contactos ou matriz global de alocações. Tenant e responsabilidade são verificados no backend, não apenas pela UI.

## I–M. Dois P2 restantes, sem correção do candidato

### P2-01 — histórico exclusivamente legado sem entrada na lista diária

Local: `supabase/folha_ponto_v2.sql:299`, `src/attendance-sheet.js:16` e `:24`.

Reprodução sintética: pessoa 45, obra 100, 24/09/2026, com ponto legado e sem alocação/folha V2. `fn_folha_historico_v2` devolve uma linha legado, mas `fn_folha_contexto_v2` não devolve a pessoa. O conjunto inicial usa apenas alocações e folhas V2. A UI só disponibiliza HISTÓRICO nas linhas desse conjunto; não consulta histórico para a pessoa ausente. O caso B passa na RPC e no cliente, mas não chega à interface diária neste estado realista.

Impacto: o utilizador autorizado não alcança pela lista diária um registo histórico existente. Não houve perda na BD nem quebra da allowlist. Os browsers anteriores injetam uma linha visível mesmo no cenário exclusivamente legado e não cobrem esta integração.

Recomendação para tarefa posterior: fornecer uma entrada de consulta histórica autorizada para estas pessoas, sem criar alocação, folha V2 ou revision fictícia. Este P2 bloqueia o fecho funcional do histórico pedido.

### P2-02 — justificação pendente deixa de ser visível na Folha diária

Local: `src/attendance-domain.js:31`, `:94`, `src/attendance-sheet.js:16`, `supabase/folha_ponto_v2.sql:322`.

Reprodução sintética existente: pessoa 20, obra 100, 03/01/2026, ausência `falta_injustificada / ausente_pendente`. O reader conserva `absence.estado`. A classificação cliente só consulta `absence.tipo`, e o cartão mostra apenas Ausência. Com essa única linha, a UI mostra `0 pendentes · DIA COMPLETO`, sem Justificação pendente. O resumo backend também não distingue os estados de justificação.

Impacto: um estado funcional importante recebido é silenciosamente omitido. A plataforma já chama este estado Justificação pendente no fluxo administrativo (`src/app.js:2189`). Não se afirma que uma ausência deva contar como ponto não registado, nem se propõe inventar regra salarial ou bloquear fecho remuneratório. A correção mínima posterior deve preservar um indicador explícito de justificação pendente e distinguir essa pendência da completude do registo diário. Este P2 bloqueia a confirmação solicitada de pending states preservados na UI.

Nenhum outro P0/P1 foi confirmado na classe focada. Os dois achados foram reproduzidos sem ampliar a auditoria ou executar técnicas novas contra produção.

## J. Regressões e rastreabilidade da execução

- 41 ficheiros existentes, sequenciais: **571 PASS / 0 FAIL / 3 SKIP**, 574 testes, 182,79 s. Inclui nove novas verificações independentes inicialmente adicionadas.
- Backend final, depois de acrescentar duas verificações de evidência: **61 PASS / 0 FAIL / 0 SKIP**, 21,54 s. Substitui os 59 casos backend da execução integrada. Conjunto de casos distintos executados: **573 PASS / 0 FAIL / 3 SKIP**; não é uma segunda execução integrada de 576 testes.
- As duas verificações P2 passam por afirmarem a presença do defeito. PASS de evidência não significa aceitação funcional do produto.
- Browser Folha: 57 grupos PASS; consolidação: 51 grupos PASS, seis perfis e três viewports.
- Browser sessão: 7 cenários PASS; Planeamento/custos: 33 PASS. Medicina, RH frontend, RNC/âmbito, Viaturas e Quadro: PASS nas suites existentes.
- Browser independente: seis observações dos dois P2 em 1440/820/390 px, zero pageErrors. Reproduz omissão do histórico e indicador pendente. É mock de apresentação; a evidência backend correspondente vem do PostgreSQL local.
- Matriz A–AN, escritório próprio, papéis, coletivo, externos, HE, férias, vencimentos, tarefas, concorrência/idempotência, alertas, Quadro, RH, Medicina, Financeiro, Planeamento, RNC, Viaturas e sessão foram reexecutados pelas suites preparadas.
- Três SKIP preservados em RH: PostgreSQL cadastro/lote; formulário; aviso contratual. Dependem de runtime RH não configurado. Não contam como PASS. Nenhuma nova falha de arranque PostgREST nesta execução.
- O primeiro arranque do browser de evidência falhou porque o mock novo omitia date/work_id obrigatórios; corrigiu-se apenas o mock. Reexecução final PASS. Nenhuma alteração ao produto para satisfazer testes.

Logs locais, fora do Git: `%TEMP%/primeline-reaudit-full.log`, `primeline-reaudit-final-backend.log`, `reaudit-*-browser.log`. Screenshots sintéticos das suites existentes permanecem em `%TEMP%/primeline-folha-v2-synthetic` e `primeline-folha-consolidation-synthetic`. Não contém dados reais.

## K. Scripts e compatibilidade

Delta revisto: precheck, core, gestão e postcheck. Precheck permanece read-only e exige as colunas da projeção legado; core projeta campos explicitamente; gestão gera domínio e aplica autorização antes de replay; postcheck verifica domínio gerado/CHECK, ACL/RLS/owners e preservação legada.

Backup e dois rollbacks não diferem da base auditada anterior. Instalação sintética vazia, postcheck, helpers privados e grants passaram. Rollback recusa factos persistentes; rollback vazio restaura núcleo V1 explicitamente. Fase B pós-hotfix local recusa gate ausente/drift; instalação e rollback locais passam, sem regenerar fingerprint real ou executar marker real.

Ordem técnica permanece PRECHECK → BACKUP → CORE → GESTÃO → POSTCHECK, com rollbacks gestão → core conforme precondições. Compatibilidade estrutural PASS não autoriza rollout: catálogo real não foi revalidado nesta tarefa, e os dois P2 impedem o GO funcional.

`git diff --check`: PASS. Delta desta auditoria limitado à chamada do módulo de testes, dois ficheiros novos de teste e este relatório. Nenhum SQL/frontend/backend de produto alterado.

## N. Decisão

**NO-GO LOCAL.** P1 anterior fechado; descarte do legado no cliente corrigido; segurança/regressões/scripts locais verdes. Permanecem dois P2 bloqueantes de backend → cliente → UI: alcance do histórico exclusivamente legado e visibilidade da justificação pendente.

Não foi feita qualquer correção do candidato. Não houve validação do catálogo real por método bloqueado nem alteração de produção. Fase B real e rollout permanecem parados. É necessária correção específica seguida de revalidação desses dois cenários; regras administrativas ainda desativadas e catálogo real continuam gates separados.
