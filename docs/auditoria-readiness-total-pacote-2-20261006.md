# Varredura consolidada de readiness — Pacote 2

## A. SHA auditado

Candidato `5e0feb3454243bdf11fe09292bd9e3db2d40e9b3`; branch de auditoria
`audit/pacote-2-readiness-total-final-20261006`, criada exatamente desse commit.
Auditoria anterior `f1520ea307518a29b07c5f57284b9170b77061b3` preservada.
Main de referência `3df019a2f2813c0cbf7f36a8d13000431d33dd50`.
Commit documental isolado `cec13e621af6cb299bcc23e0536a2a6531efa784`.
Alterações desta auditoria: relatório, auxiliares READ ONLY e testes; produto inalterado.

## B. Ambiente real consultado

Aba existente do Chrome reutilizada: SQL Editor autenticado do projeto
Primeline-Obras `znttyadndpkxuekhjamd`, main PRODUCTION.
O MCP recusou o preenchimento do editor visível com
`Element with uid 3_30 no longer exists on the page`.
Nenhuma query foi executada. Não se tentou outra API, extrair tokens,
contornar o bloqueio ou insistir na navegação. **VALIDAÇÃO BLOQUEADA PELO AMBIENTE.**
Autenticação não é apontada como causa. O dashboard mostra aviso de incidente
do Supabase, mas isso não prova a causa da falha do MCP.

## C. Cobertura completa e limites

As 25 áreas pedidas foram revistas pelo código, scripts, decisões preservadas e
matriz local; todos os ensaios possíveis nesta sessão foram concluídos.
Ambiente sintético: PostgreSQL 17.6 efémero, PGlite, browser local com tráfego
externo interceptado. Não corresponde ao catálogo atual de produção.
Não se afirma completude formal de todos os schedules concorrentes possíveis.
As áreas dependentes da BD real ficam BLOCKED/INCONCLUSIVE, não PASS.

## D. Segurança / tenant / RLS

PASS local dos contratos V2: empresa derivada do utilizador ativo; actor e obra
revalidados, IDs externos recusados, referências cruzadas protegidas pelos triggers;
helpers privados sem EXECUTE externo e search_path pg_catalog; novas tabelas com
RLS e sem DML direto anon/authenticated/service_role. RPCs públicas só authenticated.
Documentos/Storage: permissivas OR fechadas por AND restritivo; metadata e ownership
colaborador/viatura/anexo exercitados em duas empresas, incluindo acesso legítimo.
Financeiro: writers/guardas económicos e RPCs financeiras exercitados localmente.
Não declarar inexistência universal de leaks reais sem catálogo. Ver achados R01/R02.

## E. Folha de Ponto

PASS local para none/open/registered/missing/regularization/vacation/absence/
absence_pending/legacy/legacy conflict, potencial HE e dia especial.
Contexto, cliente, UI, summary e payroll exercitados; nenhum novo flattening
confirmado nos estados testados. Guarda de futuro, conflitos, revisions e
idempotência recusa escritas parciais. Ações start/finish/normal excluem ausência,
legado, revisão velha e pessoa inelegível; bulk reverte integralmente quando falha.
Alocação/transferência usam o núcleo v1, períodos e confirmação, sem DML frontend.

## F. Férias

PASS local: dias inteiros úteis, sábados/domingos/feriados sintéticos excluídos;
intervalos/avulsos/replace/remove/replay e falhas multidata atómicos. Direito com
fonte, saldo transitado com validade 30/04, adicionais com autorização; consumo
não definitivo se calendário incompleto/ano não validado. Sem motor legal inventado.
Ausência posterior e remoção reconciliam estado, HE e fotografia mensal.
Não se comprovou fonte de feriados real: ver V.

## G. Ausências

PASS local dos tipos ocupacionais e pendência, confirmação apenas Administrativo,
motivo, anexo para doença e preservação do último anexo de baixa confirmada.
Mudança de data/tipo e reconciliação origem/destino testadas; regularização não
converte automaticamente justificação pendente. Guards de metadata/Storage
verificados localmente. Bytes reais, ficheiros e URLs não foram consultados.

## H. HE

PASS local: elegibilidade por cargo RH Pedreiro/Servente, Motorista excluído por
default, configuração explícita; perfil operacional não altera cargo formal.
Diretor/Adjunto aprova/rejeita; Administrativo valida/processa; folha editada ou
ausência posterior supersede/regenera apenas revisão corrente.
Raw JSON, históricos e replay operacionais sem campos administrativos;
Encarregado sem array HE de gestão. Redução de papel antes de commit/replay
administrativo recebe 42501. Alertas administrativos sem obra/email indevidos.
Nenhuma monetização nem integração automática de HE em Vencimentos.

## I. Dias especiais

PASS local: não revisto → revisão/pending/incompleto; revisto → REVISTO sem
pendência apenas por esse facto; edição factual/ausência invalida review e preserva
história. Browser com RPCs PostgreSQL reais locais comparou DB/contexto/UI/
summary/payroll nos três viewports. Revisão concorrente stale recusada.

## J. Vencimentos

PASS local para factos, km quantidade, ajudas em €, observações manuais, pendências,
revisão, validar/recibos/fechar/reabrir, reconciliação e história.
HE/prémio não incluídos; exporter oficial continua recusado.
**R01 — classificação corrigida pela decisão definitiva da Jordane:** payroll_save é permitido a Administrativo e Gestão da Plataforma. Gerência mantém acesso a rascunhos anteriormente preservado; esse acesso não constitui P1 confirmado. O P1 é a exclusão indevida de Gestão das ações reservadas por adm() e de outras ações limitadas a papéis específicos. Tenant, auditoria, revisão, concorrência, integridade e RLS continuam obrigatórios.

## K. Escritório e janela

PASS local: Diretor/Adjunto/Preparador self-service com vínculo inequívoco ao
colaborador e cargo formal preservado; intervalos flexíveis, abaixo da carga missing,
acima não gera HE automática. Hoje/ontem permitidos; +2 recusado para Encarregado;
administrativo corrige fora da janela com motivo. Bulk normal preserva atomicidade.
Replay verifica papel/âmbito corrente, sem segunda escrita; replay legítimo conserva
receipt original, não é uma nova correção retroativa.

## L. Legado

PASS local de leitura: legado-only sem alocação aparece, histórico acessível,
sem edição/ação coletiva/retirada/pending fictício; outra obra/empresa excluída.
Legado+V2 é conflito; não há conversão silenciosa. **R05:** o writer legado permanece
transitoriamente possível nos dias sem V2; a guarda é de coexistência, não de
encerramento global. Isto está explicitamente preservado no script de Fase B.

## M. Externos

PASS local: fornecedor da empresa/obra, identidade externa reutilizável e associação
diária; horas/intervalos e história separados, rejeição de tenant/pessoa inadequada;
nenhuma criação de colaborador Primeline ou folha salarial automática.

## N. Planeamento / tarefas

PASS local: reporte não conclui tarefa; conclusão real filtra lista ativa,
confirma reporte e resolve alertas mantendo história. Custos sem chamadas/DOM no
Encarregado. **R04:** teste antigo de especialidade/executor falha por exigir
serialização literal já substituída por captureInput e gravação em lote.

## O. Quadro / Fase B

PASS local de instalação A, movimentações v1/V2, ausência/conflictos, revisões,
história, gates e rollback. Catálogo Fase B real: **RECHECK_REQUIRED**.
Nenhum marcador/aprovação criado, nenhuma B executada na BD real.
As suites históricas de pré-varredura também instalam A/B antigos: testes intitulados
"P0/P1 reproduzido" ou "caracterização P2" não comprovam defeito no candidato final.
Não contabilizar vulnerabilidade de uma fixture anterior como P0/P1 novo.

## P. Documentos / RH / Medicina / Viaturas

PASS local dos readers, metadata, Storage sintético, acesso legítimo, upload frontend
com mocks, alertas, histórico Medicina e atribuição controlada de viaturas.
24 verificações browser documentais usam respostas SQL/RLS reais locais;
não constituem teste de upload/download dos bytes pelo serviço Storage real.
Rollback documental preserva dados e restaura policies antigas; requer autorização
própria, pois pode restaurar exposição anterior. Ver R02 e T.

## Q. Financeiro

PASS local de proteção por actor/empresa/obra, payload misto atómico, inativo/papel
indevido recusados, helpers privados, custos ocultos ao Encarregado e alertas.
DESPESAS_GERAIS_BLOQUEADAS está na definição consolidada e nos ensaios locais.
Não foi reconfirmado na BD real. Não se reativou débito direto sem tenant.

## R. Sessão

PASS browser sintético das cinco transições exigidas: Gestão→Encarregado,
Encarregado→Gestão, Diretor→Encarregado, Admin→Diretor, Admin→Encarregado.
Também logout de Medicina/Obra, expiração e troca auth_user_id sem logout:
9 cenários; DOM privado e seleção persistida removidos antes da resposta nova.
Respostas retidas/antigas, generations e limpeza de módulos exercitadas localmente.
Não se efetuaram trocas de contas reais nesta tarefa.

## S. Catálogo real

BLOCKED: tabelas/colunas/tipos/defaults/nullability/FKs/índices/triggers/ACLs/
RLS/RPCs/signatures/security_definer/search_path não reconfirmados.
Novos objetos ainda não consultados: ausência será EXPECTED_ABSENT apenas depois
da evidência real. Lista exata no auxiliar READ ONLY, incluindo folha_privado.operacoes.
Não atribuir MATCH/DRIFT/UNEXPECTED_MISSING com base em ficheiros históricos.

## T. Policy documental real

**C. INCONCLUSIVO.** A definition vulnerável histórica está no repositório;
o estado real não foi obtido. Não declarar P1 REAL nem REAL JÁ SEGURO sem catálogo.
Não se tentou ler metadata/bytes de outra empresa.

## U. Fingerprints

**R03:** FINGERPRINT_UPDATE_REQUIRED_AFTER_DOCUMENT_HOTFIX.
O precheck Folha compara catálogo público integral com instalacao do hotfix anterior.
O hotfix documental altera policies públicas: a sequência cec13e6 → precheck atual
gera POSTCHECK_CATALOG_DRIFT. Não atualizar automaticamente o snapshot.
Hashes dos writers, núcleo Quadro e snapshots reais não foram calculados/reconfirmados.
Gate B compara catálogo pós-V2 e exige aprovação independente futura, não basta SHA Git.

## V. Calendário

**INCONCLUSIVE real.** Nenhuma fonte atual/ano completo comprovado.
Configuração futura esperada: correction_days=1, calendar_complete e anos/datas
validados com fonte, geração HE condicionada; monetização/exportadores desativados.
Não preencher holiday_dates por inferência. Readiness real fica pendente.

## W. Scripts rollout / rollback

Lidos precheck/backup/core/gestão/postcheck/dois rollbacks Folha, cinco scripts B
pós-hotfix e cinco scripts documentais. Instalações/rollbacks executados somente em
bases efémeras. Ordem proposta, após gates resolvidos: documental precheck→backup→
migration→postcheck; revisão explícita de catálogo/fingerprints; Folha precheck→
backup→core→gestão→postcheck; UAT/frontend; Fase B em gate separado.
Rollback V2: gestão antes de core; dados presentes recusam perda de factos.
Scripts com nomes fixos falham de forma fechada em repetição: rotação/recuperação
após rollback exige plano autorizado, não são instaladores idempotentes automáticos.
R02/R03/R05 precisam integrar a rodada consolidada, sem executar nada agora.

## X. Precheck real

11 blocos DO do precheck aprovados são leitura/claims locais/validações em READ ONLY;
nenhum INSERT/UPDATE/DDL operacional. Não executados na BD real.
Auxiliar `pacote2_precheck_blocos_readonly_20261006.sql` preserva cada bloco
integralmente, isola falhas e devolve todas em NOTICE; não transforma FAIL em PASS.
Sintaxe/isolamento verificados em PGlite efémero; fixtures incompletas não representam
sucesso de precheck real. Auxiliar de inventário em `pacote2_readonly_manual_20261006.sql`.
Executar inventário primeiro e revisar definições antes do runner; nenhuma API de escrita.

## Y. Dados agregados

Todos os valores atuais reais **INCONCLUSIVE**: legado, ausências, HE manuais,
alocações/movimentos, conflitos, folhas anteriores e objetos inesperados.
Não repetir 227/100 como contagens atuais: são checkpoints históricos.
Auxiliar devolve somente counts e catálogo; nenhum nome, salário ou ficheiro real.

## Z. Testes e interpretação

Matriz final de 55 suites: **767 PASS / 1 FAIL / 3 SKIP**, 771 testes.
Um FAIL R04; três SKIPs RH originais preservados. Primeira execução teve uma falha
de configuração pg em Viaturas, resolvida por VIATURAS_PG_MODULE apontar ao driver
já instalado; reexecução final passou. Não se contam ambas as execuções.
Provas R01/R02 são testes PASS que caracterizam comportamento inadequado; não
significam aceitação do produto. Mesma distinção aplica-se às fixtures históricas.

12 suites browser locais concluídas: Folha (57), consolidação (51), estados (126),
reconciliação (81), regras ADM (48), visibilidade/segurança (54), sessão (9 na versão
final), Medicina, Viaturas, custos Planeamento (33), Quadro e RH — PASS.
Não somar grupos de suites com cenários sobrepostos como testes independentes novos.
Testes recuperados da auditoria anterior: 24 checks documentais + 21 Folha/HE
com PostgreSQL real LOCAL em desktop/tablet/mobile, incluídos nas suites finais.
Nenhuma gravação real. Logs/screenshots sintéticos em TEMP, fora do Git.

## Lista consolidada de todos os achados confirmados nesta varredura

| ID | Severidade | Área | Produção/local | Bloqueia rollout? | Correção recomendada |
|---|---|---|---|---|---|
| R01 | P1 | Autorização funcional de Gestão | Código local confirmado; V2 não aplicado nesta tarefa | Sim, face à regra definitiva | Garantir ações autorizadas de gestao_plataforma na RPC/UI, preservando todos os mecanismos de integridade; avaliar Gerência separadamente |
| R02 | P2 | Postcheck documental | Script local; estado real não consultado | Sim para aceitar instalação documental | Comparar tabela+expressões completas+helpers/ACLs com definições aprovadas |
| R03 | P2 | Fingerprints/ordem | Incompatibilidade local conhecida | Sim após hotfix documental | Preparar baseline pós-documental revisto sem afrouxar gates nem reescrever backup histórico |
| R05 | P2 | Writer Ponto legado | Dívida explícita nos scripts; catálogo real não reconfirmado | Sim para encerrar dívida/Fase B; não exige apagar legado | Definir fecho autorizado do writer após validação V2 e plano de conflitos; manter histórico READ ONLY |
| R04 | P3 | Regressão estática Planeamento | Local confirmado | Bloqueia matriz verde | Substituir expectativa textual obsoleta por prova do fluxo genérico/lote e preservação dos dois campos |

### Reprodução, causa e impacto

**R01 — decisão definitiva e evidência por perfil.** A interpretação anterior de "apenas Administrativo" foi substituída pela correção expressa da Jordane. Não restringir gestao_plataforma. payroll_save usa admin() e permanece legitimamente disponível à Gestão. A decisão anterior em docs/pacote-2-correcao-auditoria-final-20261006.md, secção de contexto de gestão, preserva Administrativo/Gestão/Gerência; não foi identificada uma regra específica que proíba rascunhos à Gerência. Isso não autoriza equipará-la à Gestão nas restantes ações.

| Perfil | payroll_save | Validar/fechar/reabrir Vencimentos | Interpretação |
|---|---|---|---|
| administrativo | Permitido | Permitido pela guarda de papel | Preservar |
| gestao_plataforma | Permitido | Atualmente recusado por adm() | P1: deve ser permitido, sujeito aos restantes requisitos |
| gerencia | Permitido no comportamento anterior preservado | Recusado por adm() | Não ampliar automaticamente; aplicar requisito específico |

adm() exige funcao = administrativo e utilizador ativo com empresa. A RPC aplica essa guarda a payroll_validate, payroll_close, payroll_reopen, he_validate, he_process, configure_he_eligibility, absence_confirm e special_review. O contexto/UI também usa permissions.adm e restringe he_review/task_report/task_review por papel. Essas restrições excluem Gestão e precisam de revisão na futura correção autorizada. A guarda de confirmação de ausência também usa adm(). Papéis exclusivos de reportes/aprovações não podem excluir Gestão pela nova regra, nem conceder automaticamente essas ações à Gerência.

O teste local existente de rascunhos dos atores 11/12 prova comportamento atual e autoria; passa a ser evidência de preservação, não prova de autorização indevida. Esta reclassificação resulta de revisão de código e decisões, sem nova execução de suites, alteração de produto ou consulta à produção. Não alterar cargos/perfis RH, nem assumir leak entre empresas.

**R02.** `documentos_rh_tenant_postcheck.sql`: busca guards por nome/permissividade/
comando/roles, sem comparar qual/with_check nem associar cada nome à tabela esperada.
Reprodução local conservadora: substituir temporariamente expressão da guarda
documentos por false (nega todo acesso), executar postcheck → PASS; SELECT próprio
retorna zero. Expressão original restaurada e regressões verdes. Nenhum caminho
de exposição de dados criado. Um postcheck PASS não certifica a expressão instalada.

**R03.** `folha_ponto_v2_precheck.sql`, DO post: live integral deve ser igual à
instalacao pré-documental; as novas guards e pl_documentos_rh alterada quebram essa
igualdade. Sequência conhecida na auditoria preservada, não descoberta real nova.
Impacto: aborto correto, impossibilidade de rollout sequencial sem revisão explícita.

**R05.** `folha_ponto_v2.sql`, proteger_legado: só recusa INSERT/UPDATE quando existe
Folha V2 para pessoa/data. `quadro_fase_b_pos_hotfix_migration.sql` conserva
explicitamente o writer legado como dívida inventariada. Portanto "writers bloqueados"
não é fechamento global; cliente antigo ainda pode disputar a origem dos dias sem V2
conforme permissões legadas. Não alegar escrita cross-company nem eliminar história.

**R04.** `procurement-planning-pending-consultations.test.mjs:27` exige
especialidade_id: value(...), ausente desde adoção de captureInput genérico.
`planning.js` conserva inputs, captureInput guarda item[input.name], planningChanges
gera o lote. Impacto comprovado é falso negativo estático, não perda de dados provada.
Não modificar o teste nesta auditoria para produzir verde artificial.

### Blockers de evidência, sem inventar severidade de vulnerabilidade

E01: catálogo/policies/Storage/grants/precheck/contagens reais BLOCKED pelo MCP.
E02: calendário real/anos confiáveis INCONCLUSIVE.
P1 documental real: não confirmado nem excluído. Nenhum P0 atual confirmado.
Totais confirmados: **0 P0 / 1 P1 / 3 P2 / 1 P3**.

### Dívidas históricas e aplicabilidade

Documentos anteriores do Pacote 1 registam coexistência ausência/alocação,
deadlock em transação RH multi-op, alertas históricos, retry/rotação de backup,
RH sem idempotência geral e contenção global. Suites de caracterização preservam
esses comportamentos em A/B antigos. No candidato V2, reconciliação/locks globais
foram exercitados; não se transfere automaticamente um achado da fixture antiga.
Carga real, batches RH fora das RPCs exercitadas e semântica de alertas históricos
continuam limites operacionais; não foi criada uma nova classificação de vulnerabilidade.

## Decisão e uma única rodada de correção

**NO-GO PARA ROLLOUT. GO para UMA rodada consolidada de correção/preparação.**
Ordem: obter catálogo real por execução manual permitida → confirmar policy/calendário
sem expor dados → fechar R01/R02/R03/R04 numa rodada única → preparar gate explícito
R05 sem conversão/perda de história → regressão consolidada e revisão independente →
autorizações separadas de hotfix/Pacote 2/UAT/frontend/Fase B.

**VARREDURA COMPLETA CONCLUÍDA — ACHADOS CONSOLIDADOS PRONTOS PARA UMA ÚNICA
RODADA DE CORREÇÃO.**

Esta conclusão refere-se a todas as verificações possíveis; validação real continua
BLOCKED e não se declara prontidão de produção. Nenhum achado foi corrigido, nenhuma
migration/backup/marker/main/deploy/Fase B real ou alteração de perfil/dado executada.
