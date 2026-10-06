# Pacote 2 — reconciliação do estado da Folha

## A. Identificação e limites

- Branch: `fix/pacote-2-reconciliacao-estado-final-20261006`.
- Base exata: `bb3d77315c2e72ad399018f15e4ca5625917a03b`.
- Data: 06/10/2026.
- Implementação e testes exclusivamente locais. Nenhuma consulta ou escrita na produção, alteração de perfil, publicação, merge em main ou execução real da Fase B.
- Este relatório descreve o commit que o contém; o SHA final é o HEAD da branch.

## B. Auditoria preservada

`audit/pacote-2-p2-visibilidade-final-20261006`, commit `f576726473691e11ac7d84f50a51ea357b2aa180`, foi enviado para origin antes da implementação. Não foi alterado nem incorporado como produto. A nova branch parte diretamente da base aprovada.

## C. Causa raiz

`vacation_remove` alterava `ausencias`, mas não reconciliava `folha_registos.estado`. O reader diário recalculava o resumo pelos intervalos e a UI ignorava `sheet.state`; Vencimentos continuava a usar o estado persistido. Assim, a mesma folha podia aparecer como Registado/DIA COMPLETO e continuar em regularização no backend mensal.

Havia também fotografias mensais guardadas em `folha_vencimentos.factos` sem invalidação automática quando os factos mudavam, e uma lista diária em memória que não era atualizada ao alterar férias no painel administrativo da própria Folha.

## D. Regra canónica e referências históricas

O helper privado `folha_privado.estado_efetivo(integer,boolean,integer,boolean,boolean)` é usado tanto na gravação de intervalos como na reconciliação de dependências:

| Factos | Estado persistido |
|---|---|
| Ausência/férias ou conflito real | `regularization` |
| Sem conflito, intervalo aberto | `open` |
| Intervalos fechados, carga desconhecida | `regularization` |
| Minutos abaixo da carga | `missing` |
| Minutos iguais/superiores à carga, sem conflito | `registered` |

Os conflitos incluem alocações incompatíveis, legado e intervalos sobrepostos noutra folha/obra da mesma pessoa/data. Trabalho e ausência continuam a exigir regularização, mesmo após justificação: justificar uma ausência não apaga os factos de trabalho nem a ausência.

Cada folha guarda `expected_minutes` na primeira gravação, além de `special_day`. Estes parâmetros permanecem estáveis nas correções de intervalos e alterações de ausência. O reader devolve os mesmos parâmetros. Carga desconhecida permanece desconhecida; não é preenchida por inferência.

**Política de configuração:** configurar horário/carga/calendário não percorre nem reclassifica folhas existentes. A configuração corrente é usada na criação explícita de novos factos; inclui uma nova entrada retroativa autorizada, não um recálculo silencioso de folhas históricas. Não se introduziu nesta tarefa um calendário de vigências por data nem uma ação de rebase retroativo dos parâmetros de uma folha existente. Esse rebase exige operação própria, explícita e auditada; não pode ser feito alterando silenciosamente a configuração global. As regras correntes de habilitação/calendário também são verificadas antes de gerar uma nova HE.

## E. Writers e dependências cobertos

| Origem | Proteção |
|---|---|
| `fn_folha_gestao_v2`: `vacation_set/remove/replace` | Triggers de ausência dentro da mesma transação; `request_id` correlacionado com a RPC |
| POST direto de ausência no fluxo RH existente (`registerAbsence`) | Mesmo trigger `AFTER INSERT` |
| PATCH de justificação (`justifyAbsence`) | Mesmo trigger `AFTER UPDATE`; não converte o tipo automaticamente |
| PATCH/remoção de ausência/férias no fluxo legado do Quadro | Mesmo trigger em UPDATE/DELETE |
| Qualquer outro writer autorizado de `ausencias` | Cobertura por tabela, incluindo mudança de pessoa/data; reconcilia as chaves OLD e NEW |
| Alocações autorizadas do Quadro | Trigger em INSERT/UPDATE/DELETE para conflitos e fotografia mensal |
| Gravação V2 de intervalos | Mesmo cálculo canónico e reconciliação de HE; fotografia mensal atualizada |
| Ponto legado | Fotografia mensal atualizada; guarda anterior contra mistura legado/V2 mantida |
| Horário/carga/calendário | Referências das folhas existentes preservadas; UI recarrega a configuração após gravação |

Não foi criado um endpoint público adicional. Não foram ampliadas policies/grants nem substituídos os writers antigos de ausência. O frontend da Folha continua a usar exclusivamente as RPCs controladas.

## F. Férias/ausências e atomicidade

- Adicionar férias a uma folha registada passa a folha para regularização imediatamente.
- Remover férias restaura `registered`, `missing` ou `open` conforme os factos restantes.
- Um conflito independente mantém regularização depois da remoção da ausência.
- `vacation_replace` reconcilia as datas retiradas e as acrescentadas.
- Justificação altera a classificação documental da ausência, mantendo trabalho + ausência em regularização.
- Mudança da data de uma ausência reconcilia origem e destino.
- Falha após a primeira data de uma seleção multidata reverte integralmente ausência, folhas, revisões, HE e histórias.

## G. Revisão, histórico e concorrência

Uma mudança de estado incrementa a revisão da folha e grava antes/depois, ator, timestamp e request_id, com origem `vacation_reconciliation`, `absence_reconciliation` ou `allocation_reconciliation`. Sem mudança de estado, não há incremento artificial da revisão da folha. A história administrativa de férias permanece independente e preservada.

As operações reutilizam o lock transacional global `61001,1` e os locks existentes de pessoa/dia. Os triggers BEFORE STATEMENT adquirem o lock antes das escritas legadas, e a reconciliação bloqueia as folhas afetadas com FOR UPDATE. As duas ordens concorrentes foram testadas com duas ligações reais ao PostgreSQL local: Folha primeiro/ausência depois e ausência primeiro/confirmação da Folha depois. Uma confirmação com revisão antiga devolve `40001`, sem duplicação.

REPEATABLE READ/SERIALIZABLE são recusados antes das escritas nas dependências legadas com `40001 / RETRY_READ_COMMITTED`: não se usa um snapshot antigo para decidir o estado. O GUC de request_id serve exclusivamente para correlação; não concede autorização. Os helpers são SECURITY DEFINER, com search_path `pg_catalog`, sem EXECUTE externo, e verificam ator ativo, empresa e âmbito. Uma operação que não consiga reconciliar todas as folhas afetadas com segurança falha integralmente.

## H. HE

O helper privado partilhado marca HE anterior como `superseded` quando a fonte muda de revisão/estado. Só cria novo potencial na revisão corrente se houver obra, pessoal Primeline, estado registado, carga conhecida excedida, geração habilitada, calendário completo, dia útil não especial/feriado e ausência de HE manual legada. Escritório e externos não geram HE.

A unicidade `(folha_id, folha_revision)` é preservada. Replay não cria outro potencial. Os registos anteriores e as decisões administrativas continuam preservados no modelo de história existente.

O reader devolve explicitamente `overtime.estado = none` quando não existe potencial/decisão aplicável, ou `pending_rule` para dia especial da folha. A UI não inventa potencial HE a partir dos minutos quando o backend devolve `none`.

## I. Vencimentos

`payroll_facts` usa diretamente o estado persistido da Folha. As fotografias mensais já guardadas são sincronizadas por triggers em Folha, ausência, alocação e Ponto legado. Alteração de factos devolve uma validação anterior a `draft`, incrementa a revisão e grava `payroll_reconcile` com origem `facts_reconciliation`, preservando valores manuais.

Factos de mês `closed/exported` não são alterados silenciosamente: a mutação da fonte é recusada atomicamente com `PAYROLL_CLOSED_FACTS_CHANGED`. Fecho/exportação e regras salariais permanecem desativados na configuração inicial; não foram ativados.

Um dia com legado não é também contado como Ponto não registado em `pending_days`; mantém a categoria separada `legacy_days`, necessária à reconciliação administrativa do legado. Não se transforma legado em V2.

## J. Paridade backend → UI

O estado recebido em `sheet.state` é autoritativo, inclusive quando os intervalos isoladamente sugerem outro estado. O cálculo local de minutos permanece disponível para apresentação e pré-visualizações não persistidas. O resumo backend, linha diária, contador pendentes, DIA COMPLETO e estado mensal foram comparados na mesma fonte real sintética.

Depois de set/remove/replace de férias, a lista e o resumo da Folha são recarregados sem perder o painel administrativo. Alterações de configuração recarregam o contexto. Revisões antigas de um formulário não ganham nova autorização nem passam silenciosamente.

## K. Outros casos da mesma classe encontrados

1. Fotografias mensais stale: atualizadas/invalidadas transacionalmente.
2. Alocações e Ponto legado alterando pendências mensais: cobertos pelos mesmos mecanismos.
3. Legado contado também como ausência de Ponto: removida a pendência fictícia duplicada; a categoria legado permanece.
4. Horário/calendário reinterpretando folhas antigas: parâmetros por folha preservados.
5. UI diária stale após alteração no painel de férias: atualização imediata.
6. UI inferindo potencial HE quando backend não o permitia: estado `none` explícito.

## L. Testes locais

PostgreSQL 17.6 efémero, PostgREST local nos testes existentes, dados exclusivamente sintéticos. **41 suites: 599 PASS / 0 FAIL / 3 SKIP**, 602 testes no total. Os três SKIPs RH anteriores permanecem SKIP; não foram convertidos em aprovação.

O backend da Folha tem **87 PASS**, incluindo 19 novos grupos de reconciliação: cenário exato da auditoria; transições full/short/open; conflito remanescente; replace multidata; falha injetada na segunda data e rollback integral; justificação; mudança da data; HE/replay; bloqueios de geração/calendário/feriado/manual; Escritório; fotografia mensal e preservação de manuais; alocação/legado; snapshots de carga/calendário; preview stale; isolamento; concorrência nos dois sentidos; helpers privados.

Regressões abrangem matriz A–AN, histórias V2/legado, Folha, Escritório, externos, HE, férias, vencimentos, tarefas/reportes, Quadro, RH, Medicina, sessão, Planeamento, Financeiro, Subempreitadas/comparativos, RNC, Viaturas, scripts e rollbacks, e compatibilidade **local** da Fase B. `git diff --check` passou.

Na preparação, uma nova fixture usava uma data já semeada por um teste anterior de legado; mudou-se apenas a data sintética desse teste para uma chave livre. A execução consolidada acima foi repetida depois dessa correção.

## M. Browser local

| Suite | Resultado |
|---|---|
| Reconciliação/estados | 81 grupos PASS, 0 FAIL, 0 erros JS; 1440/820/390 px |
| Visibilidade de estados | 126 grupos PASS; quatro perfis/três viewports |
| Folha | 57 grupos PASS |
| Consolidação administrativa | 51 grupos PASS; seis perfis/três viewports |
| Sessão | 7 cenários PASS |
| Acesso a custos do Planeamento | 33 cenários PASS |
| Medicina, RH frontend, RNC, Viaturas e Quadro | PASS nas suites browser existentes |

A suite nova abre os formulários reais do frontend com RPCs mockadas e verifica adicionar férias → Regularização/pendência → remover férias → Registado/DIA COMPLETO, com refresh da lista e request_id estável entre preview/confirmação. Também verifica estados persistidos que divergem da interpretação isolada dos intervalos e HE proibida. Todo tráfego externo dos browsers é bloqueado. Não houve sessão/conta real nem escrita real.

## N. Scripts e limites restantes

- Precheck e backup existentes continuam aplicáveis à instalação inicial vazia: foram executados sinteticamente e não necessitam novas precondições sobre dados legados para estes helpers.
- `folha_ponto_v2.sql` e `folha_ponto_v2_gestao.sql` contêm a implementação consolidada.
- Postcheck exige coluna de referência, triggers de reconciliação, locks e helpers com search_path seguro, além das proteções existentes de catálogo/dados/ACL.
- Rollbacks removem explicitamente os novos triggers/helpers e continuam a recusar a remoção de evidência persistida. Rollback vazio PASS local, sem CASCADE.
- Não aplicar estes scripts de instalação inicial a uma BD que já tenha V2 instalado; as precondições continuam a recusar esse cenário.
- Nenhum P0/P1/P2 conhecido permanece nesta classe pelas evidências locais. Não houve revalidação do catálogo real; esse gate permanece obrigatório para rollout real, assim como as decisões ADM desativadas e a auditoria independente.
- Não existe rebase retroativo de carga/calendário exposto nesta entrega. Referências desconhecidas continuam em regularização, sem inferir dados históricos.

## O. Decisão

**GO LOCAL para reauditoria final focada.** Não constitui autorização nem GO para aplicar em produção, publicar frontend ou executar Fase B.
