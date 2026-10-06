# Pacote 2 — correção consolidada da varredura final

Data: 06/10/2026. Desenvolvimento e testes exclusivamente locais, com dados sintéticos.

## A. Branch e base

- Branch de implementação: `fix/pacote-2-correcao-consolidada-final-20261006`.
- Base exata: `5e0feb3454243bdf11fe09292bd9e3db2d40e9b3`.
- Main permanece separado desta tarefa: `3df019a2f2813c0cbf7f36a8d13000431d33dd50` na referência local.
- SHA de implementação testado: `5312afa6932c4685674bbd992401e986ba86322b`. O commit seguinte contém apenas este relatório; o HEAD final é identificado na entrega e no histórico Git.

## B. Preservação e commits

O relatório de readiness foi primeiro corrigido para respeitar a decisão definitiva sobre Gestão. A preservação foi feita apenas na branch `audit/pacote-2-readiness-total-final-20261006`, commit `7a010b8bcb04cb89ea24d0f507b493d135519464`, enviado ao remoto. Produto inalterado nessa preservação.

- `5312afa6932c4685674bbd992401e986ba86322b` — `fix(attendance): close consolidated readiness findings`: 41 ficheiros de código/scripts/testes, 871 inserções e 98 remoções.
- Commit seguinte — `docs(attendance): record consolidated readiness verification`: somente este relatório único.

Não foram incorporados em main. A matriz final valida o conteúdo do primeiro commit; o segundo não altera código ou testes.

## C. R01 — antes e depois

Antes, `folha_privado.adm()` aceitava exclusivamente Administrativo; `task_report`, `task_confirm`, aprovação e rejeição de HE rejeitavam Gestão. O helper amplo `admin()` agrupava também Gerência e permitia-lhe correção fora da janela normal. O trigger de conclusão de tarefas permitia confirmação indireta por esse mesmo agrupamento.

Depois:

- `superuser()` identifica somente `gestao_plataforma`, através do ator ativo e da empresa.
- `adm_operacional()` identifica Administrativo/Gestão; `adm()` delega nele.
- Gestão pode executar as ações administrativas e operacionais reservadas: reportar/confirmar tarefas, aprovar/rejeitar/validar/processar HE, corrigir, gerir ausências, rever dias especiais e gerir Vencimentos.
- Correções fora de +1 dia e confirmação administrativa de ausência/dia especial usam o helper exato.
- Gerência mantém os direitos anteriormente aprovados de consulta, configuração, férias e rascunho de Vencimentos. Não herda validação/fecho/reabertura, processamento HE ou confirmação administrativa.
- O trigger de confirmação de tarefa exige Gestão/Diretor/Adjunto. Uma edição de Planeamento por Gerência não confirma o reporte administrativo por acidente.
- Os flags devolvidos ao cliente distinguem `admin`, `adm`, `he_review`, `task_report`, `task_review`. A UI já os consome; não foi necessário duplicar autorização na Folha.

## D. Regra de Gestão da Plataforma

Gestão é superutilizador funcional dentro da sua empresa. Continua obrigada a ator ativo, âmbito da empresa, direitos sobre os factos, estado válido, calendário/configuração, motivo, revisão, locks, preview/confirmação, idempotência, auditoria e atomicidade.

O replay volta a verificar o papel atual. Reduzir o papel depois de uma operação não permite repetir essa operação com direitos antigos. Os testes comprovam também recusa de Gestão sobre outra empresa.

Um bloqueio por factos pendentes ou por ausência do exportador oficial não é uma restrição de papel. `payroll_export` continua `OFFICIAL_EXPORTER_REQUIRED` para todos: não foi inventado um exportador nesta correção.

## E. Matriz de permissões do Pacote 2

**P** = papel permitido, sujeito aos gates factuais; **N** = papel recusado; **Próprio** = somente a própria Folha de Escritório; **Âmbito** = obra atribuída/equipa autorizada; **Existente** = depende de alocação válida, sem poder de alocação global. Todas as permissões são limitadas à empresa.

| Ação | Gestão Plataforma | Administrativo | Gerência | Diretor | Adjunto | Preparador | Encarregado |
|---|---|---|---|---|---|---|---|
| Consulta administrativa Folha/Vencimentos | P | P | P | N | N | N | N |
| Consulta operacional Folha de obra | P | P | P | Âmbito | Âmbito | N | Âmbito |
| Consulta/registo Folha de Escritório | P | P | P | Próprio | Próprio | Próprio | N |
| Registar/corrigir Folha de obra, dia/+1 | P | P | Existente | N | N | N | Âmbito |
| Ação coletiva de registo, dia/+1 | P | P | Existente | N | N | N | Âmbito |
| Correção além de +1 com motivo | P | P | N | N | N | N | N |
| Adicionar pessoa/alocar/transferir/retirar no dia | P | P | N | N | N | N | Âmbito |
| Gerir registo de externo no âmbito permitido | P | P | Existente | N | N | N | Âmbito |
| Configurar empresa/horário | P | P | P | N | N | N | N |
| Marcar/remover/substituir férias | P | P | P | N | N | N | N |
| Gerir direito de férias | P | P | P | N | N | N | N |
| Confirmar ausência não-férias | P | P | N | N | N | N | N |
| Rever/confirmar dia especial | P | P | N | N | N | N | N |
| Configurar elegibilidade HE | P | P | N | N | N | N | N |
| Aprovar HE operacional | P | N | N | Âmbito | Âmbito | N | N |
| Rejeitar HE operacional | P | N | N | Âmbito | Âmbito | N | N |
| Validar HE administrativa | P | P | N | N | N | N | N |
| Processar HE | P | P | N | N | N | N | N |
| Guardar rascunho Vencimentos | P | P | P | N | N | N | N |
| Validar Vencimentos | P | P | N | N | N | N | N |
| Fechar Vencimentos | P | P | N | N | N | N | N |
| Reabrir Vencimentos com motivo | P | P | N | N | N | N | N |
| Exportar oficialmente Vencimentos: autorização | P | P | P | N | N | N | N |
| Reportar conclusão de tarefa | P | N | N | N | N | N | Âmbito |
| Confirmar reporte após conclusão no Planeamento | P | N | N | Âmbito | Âmbito | N | N |
| Confirmar reporte pelo trigger do Planeamento | P | N | N | Âmbito | Âmbito | N | N |
| Consultar histórico V2/legado | P | P | P | Âmbito/Próprio | Âmbito/Próprio | Próprio | Âmbito |
| Alterar legado após cutover | N | N | N | N | N | N | N |

A última linha é imutabilidade da origem histórica, obrigatória também para Gestão. O exportador oficial ainda não existe; a autorização indicada não significa que essa funcionalidade esteja ativa. Configurar regras não dispensa validação documental/calendário ou permite fabricar factos. Direitos dos restantes módulos não foram redesenhados por esta tabela.

## F. R02 — evidência documental

A migration documental captura, uma única vez, a instalação aprovada em `primeline_documentos_rh_backup.instalacao`. O namespace e a tabela de evidência são privados. O precheck/migration exigem bucket `documentos` privado; não alteram o bucket.

O snapshot inclui **todas** as policies de `documentos`, `ausencias_anexos` e `storage.objects`: tabela, nome, modo permissivo/restritivo, comando, roles, USING e WITH CHECK. Inclui RLS/force RLS, owner, ACL de tabela/coluna, definições/configuração/ACL/owner dos helpers, ator canónico, helper administrativo, schema privado e metadados do bucket.

Não basta uma policy com o nome correto. Uma policy adicional OR, expressão `true`, check alargado, tabela diferente, RLS desligado, helper invoker ou bucket público invalidam o postcheck.

## G. Postcheck documental e rollback seguro

O postcheck compara o catálogo completo à evidência imutável da instalação; não regenera a baseline. Continua a verificar integridade dos dados originais e privilégios. Os gates documental e Fase B usam a mesma verificação completa.

O rollback anterior removia as guards e podia reabrir a exposição histórica entre empresas. Agora restaura somente a policy permissiva RH anterior, **sob as mesmas três guards restritivas de tenant**, mantendo RLS, helpers e evidência privada. `documentos_rh_tenant_rollback_postcheck.sql` verifica exatamente esse estado de compatibilidade. Não constitui desinstalação da proteção: remover o overlay exigirá uma substituição revista.

O postcheck antigo do hotfix deve detetar esse delta em vez de fingir igualdade. A sequência consolidada testa explicitamente o comportamento. Os bytes do Storage não são exportados, apagados nem substituídos nesta tarefa.

## H. R03 — precheck da Folha depois da proteção documental

O precheck da Folha primeiro exige o catálogo documental completo e válido. Verifica que as policies originais guardadas no backup documental coincidem com a instalação anterior do hotfix. Só depois projeta esse delta documental **exato** para as policies antigas no comparador histórico.

O resto do catálogo continua a ser comparado integralmente. Não existe wildcard, remoção de fingerprints nem atualização do backup histórico. Sem camada documental, com delta incompleto ou grant não aprovado, o precheck falha.

## I. Fingerprints e Fase B

Precheck, backup, migration e postcheck pós-hotfix de B passaram a inventariar também helpers documentais, funções Storage e tabelas `storage.objects`/`storage.buckets`. Todos exigem a mesma evidência documental.

O `expected_catalog` privado continua a exigir revisão independente do catálogo composto. Não foi fabricada aprovação real. Instalação Folha/documental/cutover altera o catálogo legitimamente; uma aprovação anterior passa a ser stale e deve ser revista após esses deltas, antes de B. O teste local reproduz a composição e prova recusa de drift artificial.

Os hashes históricos permanecem preservados. O cutover exige revisão do catálogo pré-cutover; B exige revisão do catálogo já com cutover. Isso evita reutilização indevida de uma assinatura antiga.

## J. R05 — origem legada identificada

Main usa o módulo antigo `attendance.js?v=2`, com `fn_guardar_ponto_obra`/`fn_validar_justificacao_ponto`. A Folha diária nova usa `attendance-sheet.js?v=8` e os clientes de `fn_folha_*_v2`.

A proteção de coexistência permanece durante a transição: a mesma pessoa/data não pode ganhar uma origem V2 sobre legado existente, nem legado sobre V2. O legado continua legível como histórico, sem edição pela nova UI.

Após cutover, trigger BEFORE STATEMENT impede INSERT, UPDATE, DELETE e TRUNCATE em `ponto_pessoal_obra`, incluindo chamadas das RPCs antigas. Não se apaga nem se converte história. A escrita V2 continua funcional.

## K. Estratégia de cutover e ordem de rollout

Ordem proposta, sujeita a futuras autorizações separadas:

1. Recolher o único snapshot real read-only e validar catálogo/calendário; auditar esta branch.
2. Documental: precheck → backup → migration → postcheck.
3. Folha: precheck → backup → `folha_ponto_v2.sql` → `folha_ponto_v2_gestao.sql` → postcheck de instalação vazia.
4. UAT curto do frontend V2 no preview; produção ainda tem o frontend legado. A guarda de coexistência já evita dupla origem por pessoa/data.
5. Publicar o frontend V2 exato, confirmar assets/funcionamento e obter evidência privada de frontend/backend validado. Estas ações não foram realizadas aqui.
6. Cutover: precheck → migration → postcheck. O gate exige frontend V2 já validado e fingerprint composto aprovado. Sem conflitos legado/V2. Usa advisory lock `(61001,1)` e locks exclusivos nas tabelas coordenadas.
7. Rever independentemente o catálogo resultante e obter nova autorização específica antes de qualquer Fase B.

Publicar V2 antes de fechar o writer antigo evita uma janela sem frontend capaz de registar. O curto período com duas entradas está protegido contra coexistência por pessoa/data. Os postchecks de instalação vazia são executados imediatamente após instalar, antes do UAT; não são testes de uma base já utilizada.

Rollback do cutover só é permitido sem quaisquer factos/histórico/operações V2 e com legado integralmente igual ao snapshot. Caso contrário recusa, preserva factos e exige plano específico/roll-forward. O rollback geral Folha recusa enquanto cutover estiver ativo.

## L. R04 — prova comportamental de Planeamento

O teste obsoleto exigia literalmente `especialidade_id: value(...)`. Foi substituído pela execução do handler real `captureInput` sobre a mesma tarefa, com alterações simultâneas de especialidade/executor. O teste percorre `planningChanges` e `requestPlanningBatch`, verifica preview/confirmação, payload e persistência mock, preservando a baseline original.

Não foi restabelecido PATCH/DELETE por linha. Não se alterou a lógica do Planeamento.

## M. Sweep correlato

| Classe | Resultado |
|---|---|
| Gestão ainda recusada por papel | Corrigidas guardas explícitas de ADM, HE e tarefas, incluindo replay e flags UI |
| Gerência herdando Gestão | Separada na correção ampliada/ADM e confirmação indireta de tarefa |
| Postcheck somente por nome | Documental e definições Folha passam a comparar instalação completa |
| Fingerprint stale | Delta documental projetado exatamente; gates B incluem composição documental/Storage |
| Writer legado | Cutover explícito fecha DML e conserva histórico |
| Teste textual obsoleto | Planeamento, assets, custos, arranque e adapters de diálogo revistos com prova do comportamento |
| Janela sem writer | Publicação V2 e validação antecedem o cutover |
| Rollback inseguro | Overlay documental mantido; cutover/Folha recusam rollback com factos |

## N. Achados adicionais corrigidos

1. O trigger de conclusão de Planeamento usava `admin()` e confirmava reporte por Gerência/Admin. Foi alinhado com o contrato de confirmação Gestão/Diretor/Adjunto.
2. O postcheck Folha não verificava integralmente corpos/config/ACL/owners dos helpers. Passou a comparar a evidência privada da instalação.
3. Rollback documental reabria a exposição original. Passou a rollback de compatibilidade, mantendo isolamento.
4. Regressões mais antigas fixavam versões de assets, texto/call-sites de custos já substituídos e confundiam importação não utilizada de constantes demo com fallback de autenticação. Agora verificam referência local válida, guardas de edição, fluxo de lote e executam o ramo real de arranque bloqueado.
5. As regressões identificaram quatro confirmações nativas remanescentes em fornecedores, importação do Mapa e confirmação de custo. Foram substituídas pelo adapter `platformConfirm` assíncrono existente. Os testes executam os prefixos reais: enquanto pendente/cancelado não ocorre escrita; confirmar permite prosseguir. Sem decisão de negócio nova. Referências de cache dos três módulos/app foram incrementadas.
6. Arranque intermitente de PostgREST local foi reproduzido também em execução serial; a suite financeira passou isolada. O harness passou a registar stdout/stderr e reservar portas HTTP verificadas fora do intervalo dinâmico TCP Windows (49152–65535 confirmado nesta máquina), evitando a corrida com ligações de saída. A matriz final executa suites em série, sem retries de resultados/asserções, e mantém diagnóstico local. A associação da falha inicial à corrida de bind é hipótese de infraestrutura, não um defeito confirmado do produto. Nenhum resultado falhado é contado como PASS.

## O. Matriz final de testes

**910 PASS / 0 FAIL / 3 SKIP**, 913 testes em 100 ficheiros únicos. Execução final completa: exit 0, 280,280 s. As execuções de diagnóstico anteriores não foram somadas ao resultado final.

Uma única execução final de 100 ficheiros `*.test.mjs`, sem duplicar ficheiros, cobre autorização, Vencimentos, férias/ausências, HE, Folha, Escritório, dia especial, legado/cutover, externos, Planeamento, Quadro, documental/Storage, Medicina, Viaturas, Financeiro, sessão, tenant, replay, concorrência e scripts/rollback.

Inclui PostgreSQL 17.6 efémero, PGlite e PostgREST 16.4 local. Os negativos são os cenários já preparados, mais os contratos locais exigidos nesta correção. Não foram procurados novos caminhos de exploração em produção.

Comando final: Node `--test --test-concurrency=1` sobre a lista única. Runtimes `QUADRO_PG_BIN`, `QUADRO_TEST_DEPS`, `QUADRO_POSTGREST`, `MEDICINA_PG_BIN`, `MEDICINA_TEST_DEPS`, `VIATURAS_PG_BIN`, `VIATURAS_PG_MODULE`, `LOCAL_PG_BIN`, `LOCAL_PG_DEPS` configurados explicitamente para ferramentas locais.

Os três SKIPs históricos de RH permanecem: suite PostgreSQL de cadastro dependente de `RH_TEST_DEPS`, formulário DOM dependente do mesmo runtime e interface contratual dependente do mesmo runtime. Não foram convertidos em PASS. Browser RH/Medicina, contratos estáticos e regressões de escopo/RPC foram executados separadamente. O fixture Excel real opcional não foi disponibilizado nem usado como prova adicional.

## P. Browser

As 12 suites browser principais foram repetidas após a última alteração frontend. Todas passaram, com tráfego externo interceptado e dados sintéticos; não provam instalação na BD real.

| Suite | Resultado |
|---|---|
| Folha diária | 57 grupos PASS |
| Consolidação Folha | 51 grupos PASS |
| Estados visíveis | 126 grupos PASS |
| Reconciliação estado | 81 grupos PASS |
| Regras ADM | 75 grupos PASS; Gestão/Admin/Gerência/Encarregado, 3 viewports |
| Segurança/visibilidade | 54 grupos PASS |
| Fronteira de sessão | 7 cenários PASS |
| Medicina | PASS; histórico, NULL, operações mock, inativo, 4 papéis, 3 viewports |
| Viaturas | PASS; atribuição controlada, stale, idempotência, desktop/mobile |
| Custos Planeamento | 33 verificações PASS; Encarregado sem RPC financeira, erros legítimos preservados |
| Quadro controlado | PASS; 3 viewports, operação não confirmada preserva UI |
| RH frontend | PASS; inativos, escopo Escritório, escaping e caminho Viaturas controlado |
| Confirmações correlatas | 12 grupos PASS; adapter DOM real, cancelar/confirmar, 3 viewports |

Console sem page errors nas suites. Screenshots/logs sintéticos permanecem no diretório temporário local, fora do Git. Não se somam estes grupos ao total Node para aumentar a contagem.

## Q. PostgreSQL efémero

- Baseline do catálogo histórico reconstruída sem linhas reais; hotfix instalado; sequência documental completa; precheck Folha PASS; backup/core/gestão/postcheck PASS.
- Drift de grant/policy/helper/bucket/RLS provoca recusa; delta documental incompleto recusa; postcheck não atualiza evidência.
- Cenário com cutover: DML legado recusado, histórico preservado, Folha V2 gravada com preview/confirmação, rollback inseguro recusado.
- Rollback seguro da Folha/cutover em fixture vazia passa; rollback documental preserva guards e dados.
- Testes com ligações independentes cobrem revisão, replay, tenant, concorrência, timeouts e rollback transacional.
- Script único read-only executado na baseline e na instalação V2 local, com leitura das saídas agregadas.

Nenhum cluster efémero utiliza host/credenciais/serviço de produção.

## R. Scripts de rollout

| Camada | Scripts |
|---|---|
| Recolha real, sem instalação | `pacote2_validacao_real_final_readonly.sql` |
| Documental | `documentos_rh_tenant_precheck.sql` → `documentos_rh_tenant_backup.sql` → `documentos_rh_tenant.sql` → `documentos_rh_tenant_postcheck.sql` |
| Folha | `folha_ponto_v2_precheck.sql` → `folha_ponto_v2_backup.sql` → `folha_ponto_v2.sql` → `folha_ponto_v2_gestao.sql` → `folha_ponto_v2_postcheck.sql` |
| Cutover | `folha_v2_legacy_cutover_precheck.sql` → `folha_v2_legacy_cutover.sql` → `folha_v2_legacy_cutover_postcheck.sql` |
| B, autorização futura separada | `quadro_fase_b_pos_hotfix_precheck.sql` → `quadro_fase_b_pos_hotfix_backup.sql` → `quadro_fase_b_pos_hotfix_migration.sql` → `quadro_fase_b_pos_hotfix_postcheck.sql` |

Scripts não são executados automaticamente pelo frontend. Nada desta tabela foi executado em produção nesta tarefa.

## S. Scripts de rollback

- `folha_v2_legacy_cutover_rollback.sql`: recusa com factos/histórico/operações V2; não apaga nem inventa factos.
- `folha_ponto_v2_gestao_rollback.sql` antecede o rollback do core; recusa histórico/factos de gestão. `folha_ponto_v2_rollback.sql`: exige ausência de factos/configuração e cutover já revertido de forma segura; restaura o estado anterior documentado.
- `documentos_rh_tenant_rollback.sql` → `documentos_rh_tenant_rollback_postcheck.sql`: compatibilidade com policy antiga sob isolamento de tenant mantido.
- `quadro_fase_b_pos_hotfix_rollback.sql`: disponível, testado localmente pelas regressões de B, não executado na BD real.

Não há promessa de rollback destrutivo após utilização. Se já existirem factos, parar e autorizar plano específico ou correção para a frente.

## T. Recolha real única preparada

`pacote2_validacao_real_final_readonly.sql` usa uma transação `REPEATABLE READ READ ONLY`, timeout e `ROLLBACK`. Não chama RPCs de negócio, não executa DDL/DML, não devolve nomes pessoais ou conteúdo documental.

Devolve catálogo completo necessário, policies (incluindo Storage), grants de tabela/coluna, owners/RLS, definições e SHA-256 de RPCs, triggers/constraints/indexes, fingerprints históricos/instalação, presença de camadas/writer/gate e contagens agregadas. Devolve também fontes/anos de calendário e configuração existente. Presença de objetos não é reportada como aprovação de compatibilidade.

E01: `VALIDAÇÃO BLOQUEADA PELO AMBIENTE`; não foi repetido o método MCP anteriormente bloqueado. E02: `CONFIG_REQUIRED`/completude real por confirmar; datas/feriados não foram inventados. Não inferir completude a partir da mera existência de linhas.

## U. Achados restantes

R01–R05 e achados correlatos acima tratados localmente. Nenhum P0/P1/P2/P3 adicional confirmado e aberto **nestas classes** ao terminar a matriz. A confirmação da instalação real e do calendário não é substituída por fixtures.

## V. Gates externos

`REAL_VALIDATION_REQUIRED`: recolher e rever o snapshot real único, confrontando o catálogo completo com estes scripts; confirmar fonte/anos/completude do calendário e configurações reais. Estas são as evidências externas pendentes. Não constitui autorização para instalar, publicar ou executar B.

O exportador oficial continua uma capacidade futura, explicitamente indisponível, já fora desta correção. Factos pendentes, motivos e revisões continuam a bloquear ações quando necessário; não são bugs de autorização.

## W. Decisão

**GO LOCAL para uma única auditoria final consolidada. NO-GO para rollout real enquanto faltar a validação read-only real.**

CORREÇÃO CONSOLIDADA CONCLUÍDA — TODOS OS ACHADOS DA VARREDURA TRATADOS, MATRIZ COMPLETA VERDE, PRONTO PARA UMA ÚNICA AUDITORIA FINAL CONSOLIDADA, CONDICIONADO APENAS À VALIDAÇÃO READ-ONLY REAL.

Nenhuma alteração de produção, dados reais, perfis reais, main, deploy ou Fase B. Próximo passo é **uma única auditoria final consolidada**, seguida da recolha read-only real mediante autorização.

## Anexo — ficheiros deste delta

- docs/pacote-2-correcao-consolidada-final-20261006.md
- index.html
- src/app.js
- src/management-map.js
- src/production-dashboard.js
- src/subcontractors.js
- supabase/documentos_rh_tenant_postcheck.sql
- supabase/documentos_rh_tenant_precheck.sql
- supabase/documentos_rh_tenant_rollback_postcheck.sql
- supabase/documentos_rh_tenant_rollback.sql
- supabase/documentos_rh_tenant.sql
- supabase/folha_ponto_v2_gestao.sql
- supabase/folha_ponto_v2_postcheck.sql
- supabase/folha_ponto_v2_precheck.sql
- supabase/folha_ponto_v2_rollback.sql
- supabase/folha_ponto_v2.sql
- supabase/folha_v2_legacy_cutover_postcheck.sql
- supabase/folha_v2_legacy_cutover_precheck.sql
- supabase/folha_v2_legacy_cutover_rollback.sql
- supabase/folha_v2_legacy_cutover.sql
- supabase/pacote2_validacao_real_final_readonly.sql
- supabase/quadro_fase_b_pos_hotfix_backup.sql
- supabase/quadro_fase_b_pos_hotfix_migration.sql
- supabase/quadro_fase_b_pos_hotfix_postcheck.sql
- supabase/quadro_fase_b_pos_hotfix_precheck.sql
- tests/attendance-adm-rules-browser.mjs
- tests/attendance-adm-rules-cases.mjs
- tests/attendance-backend-v2.test.mjs
- tests/attendance-consolidated-cases.mjs
- tests/attendance-rollout-consolidated.test.mjs
- tests/attendance-security-visibility-cases.mjs
- tests/calendar-commitments.test.mjs
- tests/documentos-rh-tenant.test.mjs
- tests/encarregado-autorizacao-rest.mjs
- tests/estimated-costs-final-model.test.mjs
- tests/financeiro-cross-tenant-cases.mjs
- tests/fixtures/documentos-rh-tenant-base.sql
- tests/local-postgrest-port.mjs
- tests/platform-confirm-regression-browser.mjs
- tests/platform-confirm-regression.test.mjs
- tests/post-audit-consolidated.test.mjs
- tests/procurement-planning-pending-consultations.test.mjs

## Anexo — 100 suites únicas da execução final

- tests/absences-workflow.test.mjs
- tests/access-control.test.mjs
- tests/active-collaborators-admission.test.mjs
- tests/adjunto-access-parity.test.mjs
- tests/alert-priority-email.test.mjs
- tests/alert-resolver-user-fk.test.mjs
- tests/alerts-expiry-resolution.test.mjs
- tests/attendance-backend-v2.test.mjs
- tests/attendance-domain.test.mjs
- tests/attendance-rollout-consolidated.test.mjs
- tests/attendance-v2-static.test.mjs
- tests/audit-log.test.mjs
- tests/audit-view.test.mjs
- tests/automatic-work-costs.test.mjs
- tests/calendar-commitments.test.mjs
- tests/cash-flow-sources.test.mjs
- tests/collaborator-complete-fields.test.mjs
- tests/collaborator-lifecycle.test.mjs
- tests/collaborator-rh-conformity.test.mjs
- tests/company-documents.test.mjs
- tests/comparative-map-dynamic.test.mjs
- tests/comparative-proposal-pdf-import.test.mjs
- tests/direct-debits.test.mjs
- tests/document-operational-indexes.test.mjs
- tests/document-version-subcontract-alert.test.mjs
- tests/documentos-rh-tenant.test.mjs
- tests/documents-center.test.mjs
- tests/duplicate-invoice-warning.test.mjs
- tests/employment-contract-alerts.test.mjs
- tests/encarregado-escopo.test.mjs
- tests/estimated-costs-consolidated.test.mjs
- tests/estimated-costs-final-model.test.mjs
- tests/estimated-costs-final.test.mjs
- tests/finance-operational-access.test.mjs
- tests/financeiro-cross-tenant.test.mjs
- tests/financial-map.test.mjs
- tests/foreman-action-plan.test.mjs
- tests/foreman-global-workforce-vacations.test.mjs
- tests/foreman-scope.test.mjs
- tests/invoice-delete-administrative.test.mjs
- tests/invoice-director-return-administrative.test.mjs
- tests/invoice-director-subcontract-link.test.mjs
- tests/invoice-extraction-editing.test.mjs
- tests/invoice-finance-actions.test.mjs
- tests/invoice-guide-warning.test.mjs
- tests/invoice-observation-approval.test.mjs
- tests/invoice-pending-detail-approval.test.mjs
- tests/invoice-pending-edit-payment-condition.test.mjs
- tests/invoice-workflow-readiness.test.mjs
- tests/mapa-comparativo.test.mjs
- tests/medicina-trabalho.test.mjs
- tests/medicine-client.test.mjs
- tests/meeting-alerts.test.mjs
- tests/operational-parameters.test.mjs
- tests/overtime-workflow.test.mjs
- tests/phase-b-hotfix-compatibility.test.mjs
- tests/planning-batch.test.mjs
- tests/planning-grid-collapsible.test.mjs
- tests/planning-import.test.mjs
- tests/planning-obra120-xlsx.test.mjs
- tests/planning-operational.test.mjs
- tests/planning-release-isolation.test.mjs
- tests/planning-safeupdate.test.mjs
- tests/platform-confirm-regression.test.mjs
- tests/platform-management-phase-budget.test.mjs
- tests/post-audit-consolidated.test.mjs
- tests/procurement-planning-pending-consultations.test.mjs
- tests/restricted-deletion-paths.test.mjs
- tests/rh-cadastro.test.mjs
- tests/rh-work-finance-crossing.test.mjs
- tests/rnc-module.test.mjs
- tests/session-boundary.test.mjs
- tests/session-isolation.test.mjs
- tests/subcontract-contract-control.test.mjs
- tests/subcontractor-specialties.test.mjs
- tests/supabase-collaborators.test.mjs
- tests/tees-forecast-foreman.test.mjs
- tests/ux-obras-alertas-comparativo.test.mjs
- tests/vehicle-assignment-client.test.mjs
- tests/vehicle-assignment-concurrency.test.mjs
- tests/vehicle-assignment.test.mjs
- tests/vehicle-deadlines.test.mjs
- tests/vehicle-validity.test.mjs
- tests/vehicles-module.test.mjs
- tests/workforce-absence-visual.test.mjs
- tests/workforce-admin-only.test.mjs
- tests/workforce-alerts.test.mjs
- tests/workforce-allocation-client.test.mjs
- tests/workforce-allocation-scroll.test.mjs
- tests/workforce-controlled.test.mjs
- tests/workforce-foremen-multiple-works.test.mjs
- tests/workforce-holidays-visual.test.mjs
- tests/workforce-movements-permissions.test.mjs
- tests/workforce-operational-report.test.mjs
- tests/workforce-p1-audit.test.mjs
- tests/workforce-p1-concurrency.test.mjs
- tests/workforce-preflight-local.test.mjs
- tests/workforce-vacations.test.mjs
- tests/writers-economicos-final-static.test.mjs
- tests/writers-economicos-static.test.mjs
