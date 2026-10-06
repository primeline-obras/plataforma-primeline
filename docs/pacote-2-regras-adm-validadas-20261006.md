# Pacote 2 — regras ADM validadas

Data: 06/10/2026. Evidência exclusivamente local, com dados sintéticos.

## A. Base e branch

- Base exata: `09b586bcf7e5905da46fdd67ca5efd46d96a6eac`.
- Branch: `fix/pacote-2-regras-adm-validadas-20261006`.
- O SHA de entrega é o commit que introduz este relatório; consultar `git log -1` nessa branch.
- Nenhum SQL aplicado à BD real; nenhuma consulta nova ao catálogo, alteração de main, deploy ou Fase B.

## B. Auditoria anterior preservada

`audit/pacote-2-reconciliacao-estado-final-20261006` foi enviada para origin e reconfirmada em `253492a35d5aa8542d838e056563d2d85d17766c`. O produto parte do candidato auditado, sem incorporar o relatório da auditoria como alteração funcional.

## C–E. Regras implementadas e dependências

| Regra | Implementação / limite |
|---|---|
| Janela de correção | Hoje e ontem civil em Europe/Lisbon; depois exige perfil administrativo autorizado e motivo. Backend recusa a ampliação da janela. |
| Horas em falta | Estado explícito de regularização, sem férias, falta ou desconto automático. |
| Escritório | Intervalos reais preservados; sem converter total em intervalos e sem HE automática. |
| Dias especiais | Trabalho permitido, revisão explícita; preenchimento coletivo de dia normal bloqueado em fins de semana/feriados conhecidos. |
| Férias | Dias inteiros úteis; excluir fins de semana e feriados conhecidos antes de criar linhas. Consumo desconhecido se calendário não validado. |
| Direito anual | Dias manuais com fonte; saldo transitado e dias adicionais com autorização e histórico. Sem atribuição automática de 22 dias. |
| Baixas | Doença, maternidade e parental; justificação pendente preservada; confirmação apenas Administrativo. |
| Vencimentos | km em quantidade, ajudas de custo em euros e nota manual; sem prémio nem HE no mapa. |
| Fecho | Administrativo valida/fecha/reabre; pendências bloqueiam validar/fechar; fecho regista recibos recebidos, ator e data. |
| HE | Elegibilidade pelo cargo RH, Pedreiro/Servente por defeito; configuração apenas Administrativo. Diretor/Adjunto aprova ou rejeita; Administrativo valida/processa. |
| Calendário | Configuração explícita de anos validados e feriados, sem presumir datas reais. |

Continuam apenas estruturados/desativados: valorização monetária de HE, taxas por defeito/exceção, cálculo salarial/descontos e exportador oficial. `validated_pending_rule` não representa montante calculado nem pagamento bancário. `he_process` regista confirmação administrativa de processamento sem criar débito, transferência ou lançamento financeiro.

Dependências técnicas antes de rollout: reconfirmar catálogo real e instalação das dependências de documentos/ausências; validar calendário efetivo da empresa; auditar os scripts consolidados e o template oficial. Estas dependências não voltam a classificar as regras ADM já decididas como regras de negócio pendentes.

## F. Janela de correção

`correction_days` fica fixo em 1. Ator operacional pode registar/corrigir hoje e ontem; motivo facultativo. Diferença superior a um dia exige autorização administrativa já existente e motivo não vazio, inclusive numa primeira entrada histórica. Mantêm-se intervalos, request_id, revisão, preview/confirmar e histórico. Não se ignora conflito de revisão.

## G. Férias

A seleção sexta→segunda consome dois dias quando ambos são úteis conhecidos. Datas não úteis não geram novos registos de férias. Linhas históricas permanecem disponíveis para remoção/reconciliação explícita. Seleção parcial em horas/período/fração é recusada. Calendário incompleto ou ano não validado devolve `calendar_pending=true`, `consumed_days=null`, `pending_rule=false`.

Direito anual usa `year`, `days`, `source`; ajustes usam `carry`, `additional`, `authorization`. O ano é o ano de utilização do saldo transitado: saldo proveniente do ano anterior expira em 30/04 deste ano. Não se deduz consumo histórico nem se inventa saldo. Os direitos não constituem um motor automático de afetação do consumo entre parcelas.

## H. Ausências/documentos

Novos tipos: `baixa_doenca`, `baixa_maternidade`, `baixa_parental`. A confirmação administrativa exige estado/tipo esperado e motivo. Para doença, exige registo em `ausencias_anexos` com `arquivo_url` não vazio. A UI apresenta DOCUMENTO PENDENTE e bloqueia confirmar sem essa evidência.

Reutiliza-se a associação documental existente, sem novo upload/Storage. A existência do anexo não prova por si só validade clínica nem disponibilidade permanente dos bytes. A etapa não acrescenta diagnóstico, patologia ou observações clínicas. O último anexo de doença confirmada não pode ser removido/desassociado/esvaziado. O lock comum de escrita coordena confirmação e alteração de anexos. Políticas documentais existentes não são ampliadas.

No Quadro, baixas usam indicação `A`; pendentes usam `?` e JUSTIFICAÇÃO PENDENTE, evitando apresentar estes casos como férias.

## I. HE

O cargo é `colaboradores.funcao`, não `utilizadores.funcao`. Motorista não é elegível por defeito. Alterar a configuração não autoriza papéis novos: Gerência/Gestão não recebe as ações reservadas ao Administrativo. Aprovação/validação verifica novamente a elegibilidade e a revisão da Folha.

Prazo de processamento: terceiro dia útil do mês seguinte, excluindo feriados configurados, somente com calendário validado para esse ano. Caso contrário, prazo nulo e indicação de dependência do calendário. O prazo fica registado na validação; completar posteriormente o calendário não recalcula automaticamente HE previamente validadas com prazo nulo.

`processado_em/por` regista confirmação administrativa; não é prova de pagamento bancário nem cálculo de valor. Histórico preservado e replay sem duplicação.

## J. Vencimentos

Campos manuais permitidos: `{km, allowance, note}`. `premium` e qualquer outro campo são recusados. km não são euros; allowance são euros; nota não é gerada pelo sistema. HE mantém circuito separado.

Validar/fechar exige calendário confirmado, ausência de factos pendentes/legado em conflito, Folhas registadas, dias especiais revistos, ausências justificadas e km/ajudas preenchidos (zero explícito permitido). Sem auto-fecho por data. Fecho grava `recibos_recebidos_em/por`; reabertura volta a rascunho e limpa esses campos correntes, preservando histórico. Motivo de reabertura não obrigatório. Exportação oficial permanece recusada.

## K. Notificações

HE validada com prazo conhecido cria alerta interno `folha_he_processamento` para utilizadores ativos da mesma empresa com papel literal Administrativo. `enviar_email=false`. Processamento resolve os alertas pendentes desse registo. Calendário desconhecido não gera prazo/alerta fictício. Não foi enviado qualquer alerta real.

Alertas de tarefas e respetiva resolução mantêm o circuito anterior; testes de regressão preservam o histórico.

## L. Contratos/payloads

Sem novas RPCs públicas. Mantêm-se:

- `fn_folha_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean,p_versao text)`.
- `fn_folha_gestao_v2(p_acao text,p_dados jsonb,p_confirmar boolean,p_versao text)`.
- RPCs de contexto/histórico V2 já existentes.

Envelope comum: `p_dados.version=2`, `request_id` UUID novo por operação, `expected_revision` inteiro. Preview usa `p_confirmar=false`; confirmação usa o mesmo payload/request_id e o token devolvido em `versao`. Retorno de preview: `version:2, committed:false, versao`; confirmação conserva resultado idempotente. Payload alterado com request_id repetido dá `IDEMPOTENCY_CONFLICT`; token/revisão/fonte obsoleta recusam a confirmação.

| Ação | Campos específicos em p_dados |
|---|---|
| save | `work_id`, `date`, `key:{kind,person_id,work_id,date}`, `intervals:[{start,end}]`, `reason` quando exigido |
| configure_company | `office_expected_minutes`, `correction_days:1`, `overtime_enabled`, `calendar_complete`, `holiday_dates:[data ISO]`, `calendar_validated_years:[ano]`, campos estruturais já existentes |
| configure_he_eligibility | `roles:[cargo RH]` |
| vacation_set/remove | `person_id`, `dates:[data ISO]` ou `from/to`; `admin_override` quando autorizado |
| vacation_replace | campos anteriores e `scope_dates` |
| vacation_entitlement | `person_id`, `year`, `days`, `source`, `carry`, `additional`, `authorization` |
| absence_confirm | `id`, `expected_state`, `expected_type`, `reason`; expected_revision=0 e token cobre o registo completo |
| special_review | `id` da Folha, revisão esperada |
| he_approve/reject/validate/process | `id` da HE, revisão esperada |
| payroll_save | `person_id`, `month` no primeiro dia, `manual:{km,allowance,note}` |
| payroll_validate/close/reopen | `person_id`, `month`, revisão esperada |

Erros funcionais relevantes: `PERMISSION_DENIED/42501`, `STALE_SOURCE`, `STALE_PREVIEW/40001`, `RETRY_READ_COMMITTED/40001`, `DOCUMENTO_PENDENTE`, `VACATION_FULL_DAYS_ONLY`, `VACATION_NON_WORKING_DAY`, `ENTITLEMENT_ADJUSTMENT_INVALID`, `HE_ROLE_NOT_ELIGIBLE`, `HE_PROCESS_INVALID`, `PAYROLL_PENDING_FACTS`, `MANUAL_FIELDS_INVALID`, `OFFICIAL_EXPORTER_REQUIRED`. Frontend mostra a recusa; não simula gravação.

## M–O. Evidência local

Execução final de 41 suites: **482 PASS / 0 FAIL / 3 SKIP**, 485 testes. Os três SKIPs anteriores de dependências RH permanecem SKIP. Abrange Folha, reconciliação, históricos, HE, férias, ausências, Escritório, externos, tarefas, Quadro, sessão, RH, Medicina, Planeamento, Financeiro, RNC, Viaturas, scripts/rollback e compatibilidade Fase B exclusivamente sintética.

Novos casos ADM: oito grupos PostgreSQL com atores/revisões reais na base efémera, incluindo janela, dias úteis, calendário desconhecido, direito com fonte, doença/documento, dias especiais, cargo HE, validação/processamento/replay e fecho/reabertura.

Browser local, mocks e bloqueio de tráfego externo:

| Suite | Resultado |
|---|---|
| ADM | 48 grupos PASS, três perfis × desktop/tablet/mobile, zero pageErrors |
| Estados visíveis | 126 grupos PASS, zero pageErrors |
| Reconciliação | 81 PASS |
| Folha | 57 PASS |
| Consolidação | 51 PASS |
| Sessão | 7 PASS |
| Planeamento/custos | 33 PASS |
| RH, Quadro, Medicina, Viaturas | PASS |
| RNC | seis perfis e RPC ausente PASS, sem fallback direto |

Inspeção visual de screenshots ADM desktop 1440 e mobile 390: ações e estados legíveis, disposição vertical mobile, sem sobreposição observada. Estes screenshots usam o módulo isolado, não constituem validação visual de produção nem das contas reais.

Testes anteriores foram ajustados apenas onde contradiziam as regras decididas (janela, dias úteis, prémio, papel Administrativo e nomenclatura Folha de Ponto). O teste de pendência de ausência fornece calendário/km/ajudas já resolvidos para isolar a pendência que pretende medir. O novo teste visual executa a função real de apresentação de baixas e pendentes.

`git diff --check`: PASS. Sem credenciais/dados reais/ficheiros temporários no pacote. SQL é apenas material de rollout local preparado, não aplicado.

## P–Q. Decisão

Nenhum P0/P1/P2 bloqueante identificado nos cenários locais executados desta classe. Isso não substitui auditoria independente nem validação do catálogo real.

**GO LOCAL para auditoria focada das regras ADM.**

Rollout real, main, deploy e Fase B continuam não autorizados. Calendarização real, regras monetárias e exportador oficial permanecem dependências explícitas; nenhum valor foi inventado para os ativar.
