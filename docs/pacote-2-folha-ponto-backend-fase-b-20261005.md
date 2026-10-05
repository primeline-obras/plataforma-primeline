# Pacote 2 — Folha de Ponto v2 e Fase B pós-hotfix

Data: 05/10/2026. Branch: `feat/adm-rh-fecho-folha-ponto-20261005`.
Base preservada: `c0bc01b4a3ba80e133c7efc11bf2c928693d73ca`.
Main/produção de referência: `3df019a2f2813c0cbf7f36a8d13000431d33dd50`.

## Resultado e limites

Backend v2 implementado e instalado **apenas em PostgreSQL 17.6 efémero local com dados sintéticos**. Frontend reconciliado e testado em browser local. Não houve consulta/escrita em produção, mudança de perfil real, merge, deploy ou Fase B real.

GO para revisão independente local; **NO-GO para publicação desta branch ou execução real**. `REAL CATALOG VALIDATION REQUIRED` continua aberto. A instrução explícita desta tarefa autoriza preparar SQL local e prevalece sobre a restrição antiga de `instrucoes.txt`; não autoriza aplicá-lo no Supabase.

O relatório anterior `fecho-adm-rh-financeiro-20261005.md` permanece como fotografia do checkpoint. As referências nele a contratos ainda propostos e indisponibilidade do servidor local são superadas pelas evidências desta ronda, sem reescrever o histórico.

## A. Frontend reconciliado

Folha vertical por obra/dia, alocação explícita, intervalos efetivos, entrada em aberto, edição, histórico, adicionar/transferir, retirar e externos separados. Permissões recebidas da RPC são booleanas obrigatórias; contrato incompleto/ausente falha fechado. Não existe fallback para o writer antigo nem sucesso presumido.

Ações coletivas usam a hora efetiva no próprio dia. A saída fecha somente intervalos abertos e preserva os já fechados; não usa o fim previsto do horário. O horário configurado determina a carga esperada, inclusive manhã/tarde. Não se assume HE por terminar depois das 17h.

Externo cadastrado não aparece automaticamente em todos os dias: exige associação diária explícita. O formulário pode reutilizar o mesmo trabalhador externo na mesma obra, preservando identidade e histórico.

O editor semanal de férias passa a uma única `vacation_replace` com seleção, âmbito da semana e revisão capturada ao abrir. Removeu-se desse consumidor o POST/DELETE por linha e a simulação offline. Outros fluxos de ausências/HE legados permanecem identificados; não se afirma ausência de DML legado em toda a aplicação.

## B. Três divergências corrigidas

1. Motivo opcional: formulário não exige justificativa; RPC aceita `reason=null`. Histórico antes/depois, ator, data e revisão permanece obrigatório.
2. `RETIRAR DA EQUIPA DE HOJE`: preview/confirmação, IDs exatos e revisão do Quadro. Folha existente, ausência, Escritório ou conflito exigem tratamento; nunca DELETE direto do cliente.
3. Resumo: pessoas, registadas, em aberto e pendentes. `DIA COMPLETO ✓` é derivado, sem ação de fecho. Ausência/férias válida não cria pendência; trabalho com ausência é regularização.

## C. Modelo novo

| Estrutura | Finalidade |
|---|---|
| `folha_config_empresa` | Janela nullable, HE automática desligada, calendário verificado e preparação salarial |
| `folha_horarios` | Horário efetivo por obra, intervalos e carga esperada, revisão |
| `folha_registos` | Pessoa Primeline ou externa, empresa/obra/dia, intervalos, minutos factuais, estado, revisão, autores, timestamps/request |
| `folha_historico` | Antes/depois, ação, ator, timestamp, revisão/request, motivo opcional/origem; append-only |
| `folha_externos` / `folha_externos_dias` | Identidade independente do RH e presença explícita por dia |
| `folha_he` | Origem única `(folha_id, folha_revision)`, minutos e workflow sem valor monetário |
| `folha_direitos_ferias` / `folha_ferias_revisoes` | Direito anual com fonte e revisão por pessoa |
| `folha_vencimentos` | Rascunho mensal com factos e campos manuais ADM |
| `folha_tarefas_reportes` | Conclusão reportada, sem concluir Planeamento |
| `folha_gestao_historico` | Histórico administrativo, HE/férias/vencimentos/tarefas |
| `folha_privado.operacoes` | Idempotência persistente por empresa/ator/request |

FKs, unicidade, checks, índices por chave/dia e triggers de integridade reforçam o isolamento. Nenhuma conversão/backfill de `ponto_pessoal_obra`; o histórico legado é devolvido com a origem original. Coexistência pessoa/dia produz `LEGACY_CONFLICT`, nos dois sentidos. Não há herança de alocação anterior.

## D. Contratos implementados

| RPC | Parâmetros | Resultado |
|---|---|---|
| `fn_folha_contexto_v2` | `p_data date, p_obra_id uuid DEFAULT NULL` | `version=2`, data/obra, obras autorizadas, horário, pessoas e externos daquele dia, permissões, resumo/diagnósticos |
| `fn_folha_pessoas_v2` | `p_data date, p_obra_id uuid` | Candidatos da mesma empresa, situação pontual, disponibilidade, revisão e possibilidade de alocar/transferir |
| `fn_folha_operar_v2` | `p_acao text, p_dados jsonb, p_confirmar boolean DEFAULT false, p_versao text DEFAULT NULL` | Preview sem escrita persistente e token; confirmação `committed=true`, request e `changed_keys` |
| `fn_folha_historico_v2` | `p_chave jsonb` | Eventos v2 e legado autorizado, separados por origem |
| `fn_folha_gestao_contexto_v2` | `p_obra_id uuid DEFAULT NULL, p_colaborador_id uuid DEFAULT NULL, p_competencia date DEFAULT NULL` | Configuração/HE/tarefas por âmbito; direitos, férias, revisão e vencimentos apenas para administração |
| `fn_folha_gestao_v2` | Mesmo envelope de operação | Preview/token, revisão, confirmação e histórico administrativo |

Envelope operacional: `{version:2, request_id:UUID, work_id:UUID, date:YYYY-MM-DD, ...}`.

- `save`: `key:{person_id,work_id,date,kind}`, `expected_revision`, `intervals:[{start:HH:MM,end:HH:MM|null}]`, `note`/`reason` opcionais.
- `bulk`: `operation:start|finish`, `effective_time:HH:MM`, `items` com chave/revisão/intervalos; tudo atómico.
- `allocate/transfer/remove_from_day`: `person_id`, `period`, `expected_allocation_revision`; transferência inclui `source_work_id`, retirada inclui IDs exatos.
- `external_register`: fornecedor/nome ou `external_id` existente; associação ao dia e histórico próprios.
- Histórico: `{person_id,work_id,date,kind:primeline|external}`.
- `vacation_replace`: `person_id`, `dates`, `scope_dates`, `expected_revision`, `reason:null`, `admin_override:false`; uma operação para adicionar e retirar no âmbito selecionado.

A gestão também implementa `configure_company`, `configure_schedule`, `he_approve`, `he_reject`, `he_validate`, `vacation_set`, `vacation_remove`, `vacation_entitlement`, `payroll_save`, `payroll_validate`, `payroll_close`, `task_report`, `task_confirm`. Os payloads completos e as respostas são exercitados em `attendance-backend-v2.test.mjs`; `payroll_export` recusa com `OFFICIAL_EXPORTER_REQUIRED`.

Erros explícitos: `PERMISSION_DENIED/42501`, `STALE_REVISION/40001`, `STALE_PREVIEW/40001`, `IDEMPOTENCY_CONFLICT`, `LEGACY_CONFLICT`, `ABSENCE_CONFLICT`, `INTERVAL_CONFLICT`, `FUTURE_TIME`, janela não configurada/excedida, origem HE duplicada e regras/exportador pendentes. O cliente não transforma recusa em sucesso e não repete automaticamente uma operação stale.

## E. Scripts e ordem futura

Folha: `folha_ponto_v2_precheck.sql` → `folha_ponto_v2_backup.sql` → `folha_ponto_v2.sql` → `folha_ponto_v2_gestao.sql` → `folha_ponto_v2_postcheck.sql`.

Desinstalação estrutural: `folha_ponto_v2_gestao_rollback.sql` antes de `folha_ponto_v2_rollback.sql`. Ambos exigem owner técnico e recusam apagar factos/histórico; o rollback base também recusa configurações, externos e operações. Uma instalação já usada exige plano específico, sem truncar dados reais.

Precheck incorpora integralmente o postcheck auditado do hotfix económico, seguido da verificação pré-v2. É somente leitura e aborta em divergência. Não foi executado contra produção. O backup é privado, captura dados legados, definições/ACL, policies, estrutura/colunas e triggers. Migration compara integralmente os dados sob locks. Postcheck exige tabelas novas vazias, RLS, RPCs privadas/controladas, triggers ativos e preservação de dados/definições/ACL/policies/colunas/triggers antigos, exceto o núcleo explicitamente adaptado.

## F. RLS/grants/perfis

Todas as tabelas novas têm RLS e nenhum acesso direto de `PUBLIC`, `anon`, `authenticated` ou `service_role`. As seis RPCs públicas concedem EXECUTE somente a `authenticated`; owner técnico continua responsável pela instalação. Helpers privados não são executáveis pelos papéis de aplicação. SECURITY DEFINER usa `search_path=pg_catalog`, referências qualificadas e ator ativo/empresa/obra autorizada.

Encarregado escreve Folha apenas nas suas obras. Diretor/Adjunto consultam Folha no seu âmbito e tratam HE/reportes; não ganham escrita administrativa de ponto. Administrativo/Gestão/Gerência conservam autoridade de Folha, mas alocação respeita a regra v1: não se alarga Quadro à Gerência por esta migration. RH/Financeiro não recebem permissões novas por inferência. Nenhum perfil real foi alterado.

## G. Idempotência, locks e atomicidade

Preview não insere operação, folha, capacidade, movimento ou histórico. Pode adquirir locks; não é apresentado como RPC executável numa transação SQL READ ONLY. Contexto foi testado em READ ONLY.

Token SHA-256 do payload/snapshot; confirmação exige mesmo request/token e snapshot vigente. Chave persistente empresa+ator+request; payload diferente recusa; replay devolve o resultado sem novos efeitos. Locks seguem o núcleo Quadro global e pessoa/dia; operações exigem READ COMMITTED. Utilizador ativo e responsáveis são bloqueados durante escrita. Triggers coordenam writes legados e v2 para evitar coexistência concorrente.

O núcleo `fn_quadro_aplicar_interno` recebe uma origem privada `folha_v2`, com autorização independente para origem/destino da mesma empresa e destino próprio do Encarregado. A origem `quadro` e os writers RH mantêm regras anteriores. Não há GUC/capacidade controlada pelo cliente nem segundo motor de alocação. Movimentos, revisões e alertas do núcleo continuam preservados. Transferência entre obras requer preview/confirmação; Escritório permanece conservador.

## H. Externos

Fornecedor da mesma empresa com vínculo autorizado à obra; pessoa externa separada de `colaboradores`, com autoria, associação diária explícita, revisão e histórico. Não entra em vencimentos Primeline nem gera custo, fatura, auto ou pagamento. Vínculo financeiro futuro permanece uma etapa separada.

## I. HE

Geração automática desligada por default. Só é ativável com calendário verificado, horário e origem compatíveis; ausência, dia especial ou HE manual legado impedem geração automática indevida. Minutos normais comparam carga configurada, não hora de saída fixa.

Workflow persistente: potencial → Diretor/Adjunto aprova ou rejeita → Administrativo valida → `validated_pending_rule`. Alteração da Folha substitui a origem anterior por `superseded`. Unique por Folha/revisão, histórico e replay sem duplicação. Sem taxas, pagamento ou lançamento em custos.

## J. Férias

Backend suporta dias não contíguos, intervalo, remoção, substituição atómica, revisão/request, histórico e override administrativo explícito. Direito anual exige fonte própria; nenhum default de 22 dias. Consumo de fins de semana/feriados e calendário não verificado permanece null/pendente. A UI semanal usa a operação controlada; os consumidores legados de outras ausências não foram portados indiscriminadamente.

## K. Vencimentos

Rascunho mensal persistente com factos Primeline, ausências/férias e campos manuais Prémio/Km/Ajudas/Observações. Estados draft/validated/closed/exported previstos; fecho depende de regras aprovadas e factos sem pendências. Exportação final permanece recusada mesmo que exista hash de modelo: não há exportador oficial implementado. Não se calculam taxas, salário ou pagamento.

## L. Tarefas e alertas

Encarregado cria reporte, não conclui `planeamento_itens`. Diretor confirma depois de conclusão real no Planeamento. Trigger reconcilia apenas alertas pendentes da origem controlada conhecida, preservando resolvidos/histórico. Reporte gera destinatários Diretor/Adjunto responsáveis, sem inventar destinatários financeiros. Tarefa concluída/arquivada sai das listas ativas existentes. Tipos de alertas legados adicionais exigem catálogo real; não se resolve todo alerta por aproximação.

## M. Fase B pós-hotfix

Cinco scripts novos `quadro_fase_b_pos_hotfix_{precheck,backup,migration,postcheck,rollback}.sql`. Preservam `encarregado_sem_dml_direto`, v1, Cadastro RH e hotfix económico. Revogam DML de tabela/coluna do Quadro e fecham API antiga com erro de upgrade, sem apagar policies.

Exigem aprovação privada independente pós-hotfix/v2 com catálogo completo, instalação, evidência frontend/backend e hash dos assets. Este pacote **não cria nem atualiza essa aprovação**. No teste sintético ela é criada exclusivamente para exercitar recusa de drift/instalação/rollback; não é aprovação de produção. Scripts B antigos ficam preservados como histórico e não são a opção de rollout desta entrega.

Dívida do writer Ponto legado não é removida cegamente: é preservado até v2 comprovadamente pronta, plano de conflitos históricos e autorização separada. Portanto esta B fecha Quadro, não declara toda a transição Ponto concluída.

## N. Testes executados

| Grupo Node, sem somar repetições | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Backend Folha + domínio + busca estática final | 60 | 0 | 0 |
| Quadro controlado + Medicina, PostgreSQL local | 197 | 0 | 0 |
| Financeiro cross-tenant + âmbito Encarregado, PostgreSQL/PostgREST local | 155 | 0 | 0 |
| 19 ficheiros de regressão frontend/contratos | 71 | 0 | 3 |
| Compatibilidade antiga Fase B | 3 | 0 | 0 |
| **Total Node** | **486** | **0** | **3** |

Backend inclui contratos reais usados pelo cliente, bulk start/finish atómico, janela nullable, ausência/regularização, externals, HE, férias, vencimentos, tarefas, tenants/perfis e locks. Duas ligações reais verificam mesma revisão, request simultâneo idempotente e legado/v2 nos dois sentidos. Backup/postcheck/rollback são executados somente nessa base efémera.

Browser: Folha **45 grupos PASS / 0 FAIL / 0 pageErrors**, 1440×900, 820×1180 e 390×844; inspeção visual desktop/mobile e largura/touch targets. Sessão 7 cenários PASS; custos Planeamento 33 PASS; Medicina PASS; RH-01/02/08/15 PASS (49 combinações de autorização); Quadro controlado PASS. Dados sintéticos, tráfego externo interceptado, sem consulta real. Grupos browser não são somados a testes Node.

Screenshots sintéticos fora do Git: `%TEMP%\primeline-folha-v2-synthetic`. Não são evidência de produção.

Falhas de preparação foram resolvidas: PostgREST precisava das DLLs PostgreSQL no PATH do processo; teste de férias antigo exigia DELETE contrário à decisão atómica; dois casos novos usavam coluna incorreta e partilhavam pessoa sintética. Após correção, suites repetidas sem FAIL. Nenhuma dependência nova instalada.

`git diff --check`, revisão de segredo/artefactos, sintaxe JS e busca residual focada: PASS. Não há novo DML direto no cliente Folha/férias controladas, writer anónimo, externo inserido no RH, duplicação de HE, sucesso sem commit ou apagar histórico de tarefa.

## O. SKIPs

Os três SKIPs são os testes opcionais RH que exigem PGlite/jsdom em `RH_TEST_DEPS`; continuam sem aprovação. O quarto SKIP do checkpoint (servidor efémero para comparador B) deixou de ser SKIP: foi encontrada a distribuição completa PostgreSQL 17.6 já existente e o teste passou. Não se alterou o teste para esconder a limitação nem se contou SKIP como PASS.

## P. Riscos e trabalho restante concreto

- Catálogo atual não reconfirmado; tipos/grants/owners/definições serão gates reais, não suposições.
- Publicar antes do backend torna Folha/férias indisponíveis por desenho; nenhuma publicação autorizada nesta tarefa.
- Serialização global garante coordenação com v1, mas exige avaliação de latência/carga antes de produção.
- Conflitos legados não são limpos nem reinterpretados; precisam de tratamento autorizado antes de transição completa.
- Intervalos atravessando meia-noite não são suportados; exigem contrato explícito.
- Backend HE/férias/vencimentos/tarefas está implementado; painéis completos de aprovação HE, mapa salarial e reporte/confirmar tarefas ainda precisam de consumidores dedicados e validação UX. A API, estados e testes não são apresentados como esses painéis concluídos.
- Férias possuem consumidor semanal controlado; range/override/direito anual existem na RPC, sem formulário administrativo novo para todos os modos.
- Não há prova autenticada real, teste de carga nem auditoria independente do pacote novo.

## Q. Decisões ADM pendentes

Janela de correção retroativa; classificação/remuneração de dias especiais e consumo de férias; regras financeiras HE/vencimentos; direito anual com fonte; modelo oficial/exportador. Defaults seguros: janela null, auto-HE false, consumo especial null, validação financeira pendente. Nenhum pagamento implícito.

## R. Gates de catálogo real

Reconfirmar o postcheck do hotfix, v1/controle A, owners/ACL/RLS/policies/índices/triggers, schemas dos consumidores legados, origem e tipos dos alertas relevantes, privilégio do owner e disponibilidade de SHA-256. Verificar conflitos e origens manuais existentes sem PII nem correção automática. Depois revisar a evidência pós-instalação e a aprovação privada B independentemente. Qualquer divergência aborta; não regenerar fingerprint para obter PASS.

## S. GO/NO-GO por submódulo

| Submódulo | Local | Produção |
|---|---|---|
| Folha, externos, alocar/transferir/retirar e histórico | GO para auditoria; PostgreSQL/browser PASS | NO-GO: catálogo, auditoria e rollout separado |
| HE persistente | GO backend | NO-GO automático: ADM, origem legada e consumidor de aprovação |
| Férias | GO backend/editor semanal | NO-GO: catálogo/rollout; dias especiais permanecem pendentes |
| Vencimentos | GO estrutura/factos/rascunho | NO-GO fecho/exportação: regras/modelo/exportador/UX |
| Tarefas/alertas | GO backend e filtro existente | NO-GO: origem de alertas e consumidor dedicado |
| Fase B pós-hotfix | GO mecânico: gate/drift/rollback testados | NO-GO: aprovação independente/readiness; dívida Point explícita |

## T. Sequência mínima antes de produção

1. Auditoria independente do novo backend/cliente/scripts, incluindo origem v2 do núcleo Quadro e coordenação com writers legados.
2. Catálogo real READ ONLY e precheck estrito; resolver divergências sem relaxar guards.
3. Decisões ADM necessárias à ativação pretendida; completar consumidores administrativos a publicar, mantendo funcionalidades financeiras pendentes desligadas.
4. Autorização explícita para backup/instalação v2/postcheck, seguida de preview autenticado com perfis reais e testes controlados autorizados separadamente.
5. Aprovação independente do catálogo pós-hotfix/v2 e da prontidão frontend; autorização distinta para B. Não fechar Point legado até reconciliação/readiness comprovadas.

Nenhum destes passos reais foi executado nesta tarefa.
