# Auditoria final consolidada — Pacote 2

Auditoria executada em 07/10/2026. Nomes da branch/relatório preservam a data pedida. **NO-GO LOCAL.** Produto inalterado. Nenhuma ligação ou operação em produção, main, deploy, migration real ou Fase B real.

## A. Branch/SHA auditado

- Candidato: `fix/pacote-2-correcao-consolidada-final-20261006`.
- SHA exato: `32e9493e6083f042ee29dbf2f09dab66e7a55e04`.
- Base anterior: `5e0feb3454243bdf11fe09292bd9e3db2d40e9b3`.
- Auditoria criada diretamente no candidato: `audit/pacote-2-final-consolidada-20261006`.
- O SHA do commit de auditoria e a confirmação remota são entregues após o commit. Esta branch acrescenta apenas relatório, testes e evidência sintética.

## B. Delta auditado

42 ficheiros: documentação, entrada HTML/imports, quatro módulos frontend, scripts documental/Folha/cutover/B e testes/fixtures. Foi revista a alteração inteira, incluindo as mudanças de testes e as dependências dos rollbacks, e não apenas R01–R05. O inventário e SHA-256 de cada ficheiro do candidato estão em `tests/fixtures/audit-pacote2-final-evidence-20261007.json`.

O delta separa os helpers de Gestão/ADM, endurece a evidência documental, compõe fingerprints, introduz cutover legado e troca quatro confirmações nativas por `platformConfirm`. Não acrescenta um motor legal de férias, exportador salarial ou monetização de HE.

## C. Cobertura e limites

Foram executados os 100 ficheiros Node listados no candidato, os 38 restantes `*.test.mjs` existentes e cinco ficheiros novos de auditoria. Não se somam repetições de diagnóstico. As 13 suites browser anteriores e quatro transições adicionais de sessão foram executadas localmente.

PostgreSQL 17.6 efémero, PGlite e PostgREST 16.4 local. O catálogo histórico é reconstruído por fixtures; alguns helpers periféricos são stubs declarados. Browser usa mocks e tráfego externo interceptado. Estas provas não certificam o catálogo, calendário, Storage HTTP ou permissões efetivamente instalados em produção.

**REAL_VALIDATION_REQUIRED permanece externo. VALIDAÇÃO BLOQUEADA PELO AMBIENTE:** não foi repetido o método MCP anteriormente bloqueado. Há também uma suite adicional que não arranca por ausência de `jsdom`; esse resultado não é tratado como PASS.

## D. Permissões

Gestão é superutilizador funcional **da própria empresa**, sujeita a factos, revisão, estado, motivo, locks, auditoria e idempotência. Administrativo e Gerência foram avaliados separadamente.

| Grupo de ações | Gestão | Administrativo | Gerência | Operacionais |
|---|---|---|---|---|
| Folha de obra normal/coletiva | Permitido | Permitido | Apenas registo sobre alocação existente/janela | Encarregado no âmbito; Diretor/Adjunto consulta |
| Alocar/transferir/retirar pela Folha | Permitido | Permitido | Recusado | Encarregado no âmbito |
| Correção além de um dia | Permitido com motivo | Permitido com motivo | Recusado | Recusado |
| Configuração/férias/direito informado | Permitido | Permitido | Direitos aprovados preservados | Recusado |
| Ausência administrativa/dia especial | Permitido | Permitido | Recusado | Recusado |
| Aprovar/rejeitar HE | Permitido | Sem aprovação operacional | Recusado | Diretor/Adjunto no âmbito |
| Validar/processar HE | Permitido | Permitido | Recusado | Recusado |
| Rascunho Vencimentos | Permitido | Permitido | Permitido pela decisão anterior | Recusado |
| Validar/fechar/reabrir Vencimentos | Permitido | Permitido | Recusado | Recusado |
| Reportar tarefa | Permitido | Recusado | Recusado | Encarregado no âmbito |
| Confirmar tarefa efetivamente concluída | Permitido | Recusado | Recusado | Diretor/Adjunto no âmbito |
| Escritório próprio | Administrativo | Administrativo | Administrativo/janela | Diretor/Adjunto/Preparador, vínculo único |

Preview/commit, raw JSON, revisão stale, ator inativo, perda de âmbito e replay de Gestão/HE/tarefas passam nas suites existentes. **FC-06:** o replay do core não repete as guardas específicas de alocação/janela; a redução Gestão→Gerência ainda recupera operações que o novo papel não pode iniciar. Não concede nova escrita, mas viola o contrato exigido de autorização atual no replay.

## E. Tenant/RLS

Negativos por UUID conhecido de outra empresa cobertos nas suites locais de documentos/anexos/Storage, colaboradores, ausência, Folha, HE, férias, Vencimentos, externos/fornecedores/subempreitadas, Viaturas, Quadro, Planeamento e alertas. Os writers financeiros preservam o guard tenant; despesas gerais continuam explicitamente fechadas.

As tabelas Folha são privadas, com RLS ativo e sem DML direto de authenticated; as seis RPCs públicas têm EXECUTE autenticado e helpers privados não. SECURITY DEFINER usa `search_path=pg_catalog` nas funções novas; referências qualificadas. Não foi encontrado um novo ramo que aceite a empresa indicada pelo cliente como autoridade. `to_jsonb` administrativo continua confinado à empresa; o JSON operacional de HE é projetado e os blocos administrativos são removidos.

## F. Documental

Passaram: acesso legítimo A/B, UUID estrangeiro recusado, guard restritiva AND sobre policies permissivas existentes, anexo de doença, paths RH, trabalho não-RH preservado, policy `false`/`true`/sem tenant/check incorreto/OR adicional/tabela errada, helper/ACL/RLS alterados e bucket `public=true` recusados pelo postcheck existente.

**FC-01:** a evidência guarda as linhas de `storage.buckets`, mas não o owner/RLS/force RLS/ACL de tabela/coluna/policies dessa tabela. Cinco mutações independentes desses metadados passam no postcheck. Não se afirma que esse drift esteja instalado em produção. A falha é o falso PASS de um gate que deveria verificar o estado documental completo.

## G. Fingerprints

Baseline histórica reconstruída → hotfix → documental → precheck Folha passa. Delta incompleto, grant público alargado, helper/policy adulterados e drift não aprovado recusam. A projeção das policies documentais usa o delta exato e preserva o resto da comparação histórica.

Catálogo composto B conhecido passa; assinatura stale e grant adicional recusam. Cutover altera o catálogo, a aprovação anterior é recusada e uma nova aprovação sintética permite seguir. **FC-01** limita o gate documental; **FC-03** limita o coletor da aprovação privada. Nenhuma aprovação real foi criada.

## H. Rollout

Ordem analisada: documental → backend core/gestão → postcheck vazio → UAT V2 → publicar/validar V2 → cutover → nova revisão do catálogo → B separado. Publicar V2 antes do fecho legado evita fechar o writer utilizado pelo frontend antigo. A coexistência da mesma pessoa/data é recusada nas duas direções.

**FC-02:** a ordem está documentada, mas os scripts B não a impõem: com aprovação exata pré-cutover, o precheck B passa. A suite anterior chega a instalar B antes de instalar cutover. A sequência correta também passou independentemente nesta auditoria; não resolve a ausência da precondição.

## I. Rollback

| Rollback | Resultado |
|---|---|
| Documental | PASS de compatibilidade: mantém guards/tenant/RLS/evidência; não reabre a policy antiga sem proteção |
| Gestão sem factos, seguido de core | PASS de desinstalação vazia nas suites existentes |
| Gestão com factos já visíveis | Recusa, PASS |
| Gestão com commit legítimo em curso | **FAIL FC-04:** pode eliminar o facto recém-confirmado após esperar pelo lock |
| Gestão parcial, core ainda instalado | **FAIL FC-05:** remove coluna ainda usada por funções core; erro `42703` |
| Core com factos/configuração ou cutover ativo | Recusa nas suites existentes, PASS |
| Cutover com factos/histórico/operações V2 | Recusa, PASS |
| Cutover vazio e legado igual | PASS local |
| B | PASS local; conserva dados/histórico/revisões, não reabre o writer Ponto fechado nem reutiliza aprovação consumida |

A prova de FC-04 utiliza um RPC legítimo `payroll_save`, duas ligações, transação ainda não commitada, espera observada por `pg_blocking_pids`, COMMIT e conclusão do rollback. `folha_vencimentos` deixa de existir. Não foi necessário contornar RLS ou fabricar uma escrita autenticada direta. A ausência de proteção equivalente no core merece revisão na mesma correção; não é declarada aqui como perda concorrente reproduzida no core.

## J. Folha e estados

Paridade local exercitada entre PostgreSQL/RPC/cliente/UI/resumo/DIA COMPLETO/Vencimentos. As suites de estados visíveis, reconciliação e regras ADM passaram.

| Estado/facto | Apresentação/ação e pendência |
|---|---|
| none | Não registado; pendência verdadeira |
| open | Em aberto; completar, dia incompleto |
| registered | Registado; não dispensa revisão especial ou outro conflito |
| missing | Horas em falta; não convertido em presença completa |
| vacation | Férias; excluído de coletivo; facto no payroll |
| absence | Tipo/estado factual; não gera presença |
| pending justification | JUSTIFICAÇÃO PENDENTE; contador e dia incompleto; não classificada automaticamente |
| regularization | Regularização; não escondida por retirada/alocação/ausência |
| legacy-only | REGISTO LEGADO; histórico; sem edição/coletivo/pendência fictícia |
| legacy + V2 | Conflito/regularização; não normalizado silenciosamente |
| special pending | REQUER REVISÃO; pendente; DIA COMPLETO false |
| special reviewed | REVISTO; deixa de pendente apenas por esse motivo |
| potential HE | Potencial HE; aprovação/rejeição no âmbito |
| pending_rule | Regra pendente; sem monetização inventada |
| pending_validation | Aguarda validação administrativa |
| rejected | Rejeitada; não convertida em validada |
| validated_pending_rule | Validada, regra financeira pendente; processamento identificado separadamente |
| processed | Metadados de processamento visíveis ao ADM; sem cálculo financeiro |
| superseded | Origem substituída, excluída de HE ativa; história/revisões preservadas |
| task reported | Conclusão reportada; Planeamento não concluído automaticamente |
| task confirmed | Confirmação após conclusão real; tarefa sai da lista ativa, reporte permanece |
| payroll pending facts | Factos pendentes; validar/fechar bloqueados |

Não foi identificado novo estado pendente apresentado como completo neste delta. Esta conclusão limita-se às regras/fixtures executadas, não a um calendário real ainda não validado.

## K. Férias

PASS para úteis completos, sábado/domingo/feriado conhecido excluídos, meio dia recusado, avulsas/intervalos/replace/remove, revisão/histórico/reconciliação, direito informado com fonte, transitado até 30/04 e adicional autorizado. Configuração incompleta mantém consumo pendente. Não há cálculo automático de um direito legal novo. Gestão e ADM exercitados separadamente; Gerência mantém apenas o aprovado.

## L. Ausências

Doença, injustificada, justificada remunerada/não remunerada, maternidade e parental cobertas nas suites de reconciliação/ADM. Justificação pendente permanece explícita. Doença não confirma sem documento; remoção do último anexo e troca de tipo são protegidas. Conflito trabalho+ausência permanece regularização no contexto e payroll. Tenant/histórico e concorrência anexo/confirmação foram exercitados localmente.

## M. HE

Cargo formal RH, elegibilidade Pedreiro/Servente e configuração explícita; Motorista não é default. Fluxo potential→approve/reject→validate→process, revisão stale, source stale, replay, superseded e filtragem administrativa/operacional passaram. Gestão executa os dois níveis; Administrativo valida/processa; Diretor/Adjunto fazem aprovação operacional; restantes não herdam poderes.

HE continua separada do Mapa de Vencimentos e sem monetização automática. `processado_em` identifica o marco administrativo, não prova cálculo/pagamento financeiro efetuado pela plataforma. Calendário incompleto mantém o prazo pendente.

## N. Dias especiais

Sábado/domingo/feriado exige factos reais e revisão administrativa. Antes de revisão: pendente/dia incompleto. Depois: REVISTO e dia completo possível. Mudança factual ou reconciliação invalida a revisão; payroll acompanha. Coletivo normal não preenche dias especiais. Gestão/ADM permitidos; Gerência não herda essa ação.

## O. Vencimentos

Save/validate/close/reopen, km, ajudas de custo, observação, recibos, factos/pendências, história, revisão/replay/concorrência passaram nas suites normais. Prémio e HE não entram; exportador oficial bloqueado para todos. Guardas tenant e separação Administração/Gestão/Gerência preservadas. **FC-04 é uma falha do rollback durante uso concorrente**, não do fluxo normal save/validate.

## P. Escritório

Horários/intervalos reais, vínculo único para self-service Diretor/Adjunto/Preparador, horas em falta, excesso sem HE automática, correção e payroll cobertos. Encarregado não recebe Escritório. Hoje/ontem e janela de um dia; além disso ADM/Gestão com motivo, Gerência recusada. **FC-05** afeta também Escritório depois de rollback parcial de Gestão.

## Q. Legado/cutover

Legacy-only sem alocação aparece, mantém histórico e não admite edição, coletivo ou retirada que esconda factos. Outra obra/empresa é filtrada. Legado+V2 mantém conflito; não há backfill/conversão. Antes de cutover, a coexistência é bloqueada; depois, INSERT/UPDATE/DELETE/TRUNCATE legado são recusados, SELECT histórico e escrita V2 preservados. Cutover vazio e rollback com factos foram testados. **FC-02:** exigir este estado efetivamente antes de B ainda não está implementado nos scripts B.

## R. Externos

Identidade própria, fornecedor da empresa, obra/data/horas, reutilização noutra obra, UUID estrangeiro, replay/histórico e exclusão de payroll Primeline exercitados. Homónimos/identidade existente exigem seleção explícita; não foi criado vínculo falso a colaborador RH.

## S. Planeamento

O handler real `captureInput` foi executado com especialidade e executor simultâneos; passou por `planningChanges`, preview/commit de `requestPlanningBatch` e persistência mock. Preserva baseline e não reintroduz PATCH/DELETE por linha. A persistência real da RPC não foi testada em produção.

Reporte pelo Encarregado não conclui Planeamento. Gestão/Diretor/Adjunto confirmam após conclusão; Gerência/Admin não confirmam reporte pelo trigger por acidente. Lista ativa, alertas e história preservados. Encarregado continua sem chamadas financeiras.

## T. Quadro/Fase B

Regressões Phase A, períodos, transferência confirmada, ausências/conflitos, revisão/histórico, integração Folha, Gestão e tenant passaram. B foi instalada e revertida **apenas localmente** em fixtures, também depois de cutover e de nova assinatura. Stale/drift recusam. **FC-02** permanece: um catálogo exato pré-cutover também é aceite. Nenhum marker ou gate real foi criado/consumido.

## U. RH/Medicina/Viaturas

Browser RH/Medicina/Viaturas passou: inativos, ficha/histórico, próxima NULL, permissões, escaping, escopo, caminho controlado de responsável, idempotência/stale e layouts. Documentos RH legítimos preservados nas fixtures A/B; metadata upload e proteção de anexos testados. As três suites RH históricas sem `RH_TEST_DEPS` permanecem SKIP. Não há prova adicional de upload/download real ao serviço Storage.

## V. Financeiro

Regressões da classe dos writers económicos, seis RPCs financeiras, tenant, custos autorizados e Encarregado sem financeiro passaram. Despesas gerais continuam explicitamente recusadas antes de escrita; débito direto sem tenant não foi reativado. Gestão mantém suporte funcional legítimo. Alterações frontend de confirmações não ampliam autorização backend.

## W. Sessão

PASS browser: Gestão→Encarregado, Encarregado→Gestão, Diretor→Encarregado, Gestão→Admin, Admin→Gestão, Admin→Diretor, Gerência→Gestão, logout em Medicina/Obra, expiração e mudança efetiva de identidade. Realm/documento renovado, DOM antigo ocultado/removido, seleção/cache de obra limpos, resposta retida não repõe DOM de outra identidade. Tráfego externo interceptado; nenhuma conta real usada.

As provas semeiam sentinelas e verificam a fronteira global de sessão. Não se trata de uma sessão real de todos os módulos simultaneamente. **FC-06** é replay de autorização no backend, distinto desta limpeza do frontend.

## X. Confirmações/assets

Quatro call-sites alterados revistos: merge fornecedor, apagar duplicado, confirmar compromisso e confirmar importação do Mapa. Novos testes executam os handlers completos com RPCs mock: cancelamento=zero chamadas mutantes; confirmação simples=uma. As suites DOM do adapter passaram em três viewports.

**FC-07:** duas ativações simultâneas de `confirmImport` antes da resposta do adapter chegam a duas execuções de lotes. `state.importing` é definido só depois do await. A prova é de reentrada do handler; não reproduz duplo clique físico através da inertness do modal nativo nem prova duplicação persistida, pois o importador tem deduplicação. Classificado P3, sem alegação de corrupção real. A suite anterior verificava somente prefixos e não garantia esse contrato.

Entradas/imports atualizadas: app185, dashboard25, subcontractors9, management13. CSS e módulos locais existem; arranque/imports exercitados no browser. Folha nova usa clientes V2; não chama o módulo Ponto legado por engano. **FC-08:** duas suites fora da lista de 100 continuam a exigir versões/confirm nativo antigos.

## Y. Script real read-only

`pacote2_validacao_real_final_readonly.sql`: transação REPEATABLE READ READ ONLY, timeout, catálogo, grants tabela/coluna, owners/RLS, funções/hashes, triggers/constraints/indexes, contagens agregadas, calendário/configuração e ROLLBACK. O DO apenas lê via SELECT e emite NOTICE; não faz DDL/DML/GRANT/REVOKE nem chama RPC mutante. Não devolve linhas pessoais, URLs ou montantes económicos. Foi executado em PostgreSQL local antes/depois de V2; nenhuma execução real.

| Variante local | Distinguível na saída? |
|---|---|
| A. Catálogo conhecido | Sim: catálogo pode ser comparado à baseline local aprovada; não declara GO automaticamente |
| B. Policy documental antiga | Sim: expressão difere no inventário; restauração exata entre variantes |
| C. `expected_catalog` da aprovação B stale | **Não — FC-03:** outputs iguais, removendo apenas timestamp |
| D. Writer legado ativo | Sim: ausência de helper/trigger de cutover no catálogo; presença não é aprovação |
| E. Calendário incompleto | Sim: flags/anos/contagem explícitos; não infere completude |
| F. Drift de grant inesperado | Sim: ACL/table_grants/column_grants diferem |

FC-03 não desativa o precheck B: esse precheck recusa stale corretamente. O problema é que a recolha única, limitada à presença da tabela de aprovação, não permite verificar essa condição privada. Hashes históricos/instalação anteriores não equivalem ao `expected_catalog` da aprovação B.

## Z. Node/PostgreSQL/browser

| Execução final única por ficheiro | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| 100 suites do candidato, 913 testes | 910 | 0 | 3 |
| 38 suites restantes, 96 testes | 93 | 3 | 0 |
| 4 novas suites de auditoria, 20 testes | 7 | 13 | 0 |
| Nova suite de replay, 3 testes | 0 | 3 | 0 |
| **Total: 143 ficheiros Node, 1032 testes** | **1010** | **19** | **3** |

Os 19 FAIL brutos incluem quatro containers-pai que falham porque os subtestes falham. Não representam 19 defeitos distintos. Nas provas novas há 12 asserções negativas falhadas e quatro containers; nas 38 suites adicionais há duas asserções obsoletas e um erro de runtime `MODULE_NOT_FOUND: jsdom`. Não se ocultam os FAIL e não se transformam containers em achados adicionais.

Os SKIPs preservados são cadastro RH PostgreSQL, formulário RH DOM e interface contratual RH dependentes de `RH_TEST_DEPS`. O teste `login-password.test.mjs` é **VALIDAÇÃO BLOQUEADA PELO AMBIENTE** por falta de jsdom e aparece como FAIL no runner original; não foi editado para o tornar verde.

Browser: 13 suites PASS mais quatro transições adicionais PASS; zero page errors relevantes nos resultados. Folha57, consolidação51, estados126, reconciliação81, ADM75, segurança54, sessão7+4, Planeamento33, confirmações12; Medicina/Viaturas/Quadro/RH PASS. Grupos browser não são somados ao total Node.

PostgreSQL: sequência integral e rollbacks vazios passaram; novos negativos reproduzem os achados abaixo. Falhas do harness exploratório (CRLF na extração dos handlers, data de hoje com hora futura) foram corrigidas **apenas nos testes novos**, antes de guardar a execução final; não são contadas como produto nem como PASS adicional. Nenhum ficheiro do candidato foi modificado.

## Lista consolidada de todos os achados

| ID | Prioridade | Área | Causa | Impacto | Bloqueia rollout? |
|---|---|---|---|---|---|
| FC-01 | P1 | Documental/Storage | Snapshot/postcheck omitindo metadados de segurança de `storage.buckets` | PASS documental apesar de ACL/RLS/owner/policy não aprovado | Sim |
| FC-02 | P2 | Ordem B/cutover | B não exige o guard/snapshot de cutover efetivo | Pode consumir aprovação e concluir B com writer legado aberto | Sim |
| FC-03 | P2 | Recolha read-only | Só presença da aprovação B, sem conteúdo/hash/estado relevante | Aprovação válida e stale indistinguíveis na recolha única | Sim |
| FC-04 | P1 | Rollback Gestão | Check de ausência de factos antes de coordenar/bloquear writers | Commit legítimo concorrente pode ser eliminado pelo DROP subsequente | Sim |
| FC-05 | P2 | Rollback Gestão/core | DROP de `calendar_validated_years`, ainda usado no core | RPC de Folha restante falha com `42703` no intervalo/estado parcial | Sim |
| FC-06 | P2 | Autorização/replay core | Retorno de operação antiga antes de guardas específicas do papel/janela | Gerência recupera replay que não pode iniciar atualmente; sem nova escrita | Sim |
| FC-07 | P3 | Confirmação assíncrona | Lock de importação só depois de await | Duas ativações pendentes executam dois lotes; robustez do handler não garantida | Não isoladamente |
| FC-08 | P3 | Regressões/testes | Suites omitidas/desatualizadas após alteração de assets/confirm | A matriz de 100 não representa todas as suites do repositório | Não isoladamente |

### Evidência e critérios para a única correção consolidada

- **FC-01:** `documentos_rh_tenant.sql:51`, `documentos_rh_tenant_postcheck.sql:12`; mesma seleção documental reutilizada em Folha/cutover/B/rollback documental. `audit-pacote2-final-bucket-drift.test.mjs` exige recusa de cinco deltas e recebe sucesso. Incluir os metadados completos do bucket na evidência/gates e repetir negativos, preservando a baseline.
- **FC-02:** `quadro_fase_b_pos_hotfix_precheck.sql` exige RPC Folha e catálogo aprovado, mas não cutover. `audit-pacote2-final-rollout.test.mjs` confirma ausência de `legacy_closed`, depois espera recusa e recebe sucesso. B só deve prosseguir com fecho efetivo/exato; aprovação pré-cutover não basta. Sequência correta depois de cutover passou.
- **FC-03:** coletor `:62`; alterar somente `aprovacao.expected_catalog` para `{}` não altera catálogo/NOTICE emitidos, exceto tempo que foi normalizado. Recolher evidência agregada segura da aprovação e comparação, sem PII e sem fabricar aprovação.
- **FC-04:** `folha_ponto_v2_gestao_rollback.sql:3–6` verifica factos antes dos locks implícitos posteriores; `:36` apaga Vencimentos. Prova em `audit-pacote2-final-rollout.test.mjs`: commit RPC confirmado, rollback esperado em lock, commit do ator, rollback conclui, tabela ausente. Coordenar writers antes do check e revalidar sob os locks; verificar também os restantes rollbacks.
- **FC-05:** rollback Gestão `:22`; core `folha_ponto_v2.sql:328`, `:427`, `:518`. `audit-pacote2-final-core-rollback.test.mjs` aplica rollback Gestão vazio, mantém core, executa o preview válido de uma gravação de Escritório histórico e o commit falha por coluna ausente. Preservar dependências até desinstalação integral, ou garantir uma sequência atómica que não deixe RPCs quebradas disponíveis. Não foi tentada perda concorrente no core depois deste erro.
- **FC-06:** `fn_folha_operar_v2`, ramo `IF FOUND` de `folha_privado.operacoes`; guarda obra/empresa permanece, mas autorização específica está depois do retorno. `audit-pacote2-final-replay.test.mjs`: nova alocação por Gerência=42501; replay da alocação antiga=aceite. Nova correção retroativa=CORRECTION_WINDOW_EXCEEDED; replay antigo=aceite. Revalidar direitos atuais sem reaplicar/escrever factos já commitados.
- **FC-07:** `management-map.js:255`; testes completos cancelamento/uma confirmação passam, invocação concorrente com adapter pendente produz duas chamadas. Reentrância deve ser bloqueada antes de await e cancelamento libertar o lock. Validar também o gesto real/modal; não há prova de escrita duplicada persistida.
- **FC-08:** `supplier-operational-zones.test.mjs:125` exige `window.confirm`, contradiz a alteração deste delta. `global-scroll-safeguard.test.mjs:18` exige CSS v7 quando o candidato usa v9; esta segunda asserção já é antiga, não regressão visual reproduzida. Atualizar contratos de testes, não restaurar confirm nativo/CSS antigo. Falta jsdom é limitação separada, não um defeito adicional.

**Totais distintos: P0=0, P1=2, P2=4, P3=2.** Nenhum outro achado confirmado nas restantes áreas após terminar a cobertura. Achados locais não afirmam exposição ou perda já ocorrida em produção.

## Decisão e preservação

**NO-GO LOCAL**, por FC-01–FC-06. A correção seguinte deve ser uma única rodada consolidada dos oito achados, incluindo as lacunas de testes. Depois, nova auditoria e `REAL_VALIDATION_REQUIRED`: catálogo/calendário/configuração reais continuam por confirmar. A falta de jsdom deve ficar resolvida ou explicitamente bloqueada; não invalida os findings já reproduzidos em PostgreSQL.

Git diff --check aprovado antes do commit; apenas ficheiros de auditoria adicionados. Working tree e SHA remoto confirmados na entrega após push. Nenhum fix, SQL aplicado na BD real, perfil real, main, deploy, marker ou Fase B real.

**AUDITORIA FINAL CONSOLIDADA CONCLUÍDA — TODOS OS ACHADOS FORAM CONSOLIDADOS PARA UMA ÚNICA RODADA DE CORREÇÃO.**
