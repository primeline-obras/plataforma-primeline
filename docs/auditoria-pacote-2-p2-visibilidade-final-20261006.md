# Reauditoria final focada — visibilidade do Pacote 2

Data: 06/10/2026. Evidência exclusivamente local/sintética. Não houve acesso a produção ou catálogo por método bloqueado.

## A–B. Identidade e preservação

- Candidato auditado: `fix/pacote-2-p2-visibilidade-final-20261006`, SHA exato `bb3d77315c2e72ad399018f15e4ca5625917a03b`.
- Branch de auditoria: `audit/pacote-2-p2-visibilidade-final-20261006`, criada diretamente nesse SHA com working tree inicialmente limpo.
- Auditoria anterior preservada: `audit/pacote-2-correcao-final-20261006`, `a2688669d05af2b669fa84a7d8905a55858d64e8`.
- O commit que contém este relatório identifica o SHA da auditoria. Não se inclui hash autorreferente no documento.
- Delta desta auditoria: uma chamada adicional no teste backend, dois módulos independentes de teste e este relatório. `src`, `supabase` e `index.html` permanecem idênticos ao candidato. Nenhum produto foi corrigido.

## C. P2 legado-only — PASS

Prova independente na fixture PostgreSQL: pessoa sintética 45, obra 100, 24/09/2026. Contagens por pessoa/data comprovam zero alocações e zero folhas V2; existe ponto legado. O reader inclui a pessoa para Encarregado, Diretor, Adjunto e Administrativo autorizados.

| Critério | Resultado |
|---|---|
| Somente legado aparece no dia | PASS; flag mínima legacy=true, sheet=null, conflict=null |
| REGISTO LEGADO explícito | PASS nos três viewports |
| HISTÓRICO acessível | PASS; events vazio, legacy com uma linha, interpretação original |
| Edição V2 indisponível | PASS; can_write=false, sem editor; chamada forjada recusada |
| Ações coletivas excluem | PASS; presente, completar e dia normal sem RPC de escrita para a linha |
| Retirada não oculta legado | PASS; can_remove=false, sem botão e backend recusa |
| Sem pendência fictícia | PASS; estado legacy, pending=0, complete=true para a linha isolada |
| Legado + V2 | PASS; LEGACY_CONFLICT / Regularização, pending=1 |
| Outra obra/empresa | PASS; não acrescenta pessoa à lista da obra selecionada |

O MD5 da projeção integral do ponto sintético antes/depois das consultas permanece igual. Não houve conversão, revision no histórico legado ou exposição de observação/justificação. A guarda de writer legado noutro local continua alinhada com a capacidade anunciada, sem identificar esse outro local.

## D. P2 justificação pendente — PASS

Prova independente: pessoa sintética 20, obra 100, 03/01/2026. O JSON devolve `tipo=falta_injustificada`, `estado=ausente_pendente`. O resumo backend e o cliente devolvem pending=1 / complete=false; o tipo/estado original continuam iguais na fixture.

- JUSTIFICAÇÃO PENDENTE visível em desktop/tablet/mobile.
- DIA COMPLETO ausente, ações coletivas excluídas, retirada indisponível/recusada.
- Não há transformação automática do tipo ou estado da ausência.
- Trabalho + ausência continua Regularização, com justificação pendente explícita.
- Ausência justificada/confirmada e férias confirmadas continuam tratadas.
- Vencimentos conta a justificação pendente; Férias administrativas mantém estado pendente/confirmado explícito.

## E. Matriz final backend → cliente → UI

| Estado/situação | Resultado | Evidência/limite |
|---|---|---|
| none | PASS | Não registado; pendente |
| open | PASS | Em aberto; entrada sem saída |
| registered | PASS | Registado; jornada completa no cenário normal |
| missing | PASS no cenário normal | Horas em falta com carga atual superior aos intervalos |
| vacation | PASS | Férias tratadas, sem pendência fictícia |
| absence | PASS | Ausência resolvida com tipo e estado identificados |
| pending justification | PASS | Indicador explícito; pending +1 |
| regularization com causa atual | PASS | Trabalho + ausência preservado |
| regularization persistida sem causa atual | **FAIL** | O JSON conserva state, mas cartão/resumo diário transformam em Registado |
| legacy | PASS | Origem explícita e somente leitura |
| legacy conflict | PASS | Conflito real e regularização |
| potential HE | PASS | Potencial HE; nenhuma remuneração inferida |
| pending_rule | PASS | Dia especial/regra pendente identificado |
| pending_validation | PASS | Validação administrativa pendente |
| rejected | PASS | HE rejeitada |
| validated_pending_rule | PASS | HE validada, regra financeira pendente |
| task reported | PASS | Reportada sem concluir silenciosamente a tarefa |
| task confirmed | PASS | Confirmada permanece em reportes mesmo sem tarefa ativa |
| payroll pending facts | PASS na projeção própria | Conta estado persistido regularization; diverge do diário no achado abaixo |

As quinze situações normais da matriz independente passaram nos três viewports: 45 verificações PASS. O caso adicional de regularização persistida falhou nos três: 3 FAIL. Reportes/tarefas e pendências administrativas foram também reexecutados nas suites PostgreSQL e de consolidação já existentes. Não se afirma que um estado persistido missing sobreviva a alterações de carga: o achado identificado mostra uma falha da mesma estratégia de recalcular sem consultar state.

## H. P2 adicional confirmado — regularização persistida é achatada

**P2 bloqueante desta classe.** Nenhum novo P0/P1 confirmado.

Fontes: `src/attendance-domain.js:31`, `src/attendance-domain.js:96`, `src/attendance-sheet.js:12`, `src/attendance-sheet.js:27`, `supabase/folha_ponto_v2.sql:326`, `src/attendance-management.js:29`.

### Reprodução legítima, sem cenário de exploração

1. A suite existente regista férias e uma folha V2 para a pessoa sintética 34, obra 100, 25/09/2026, através do writer autorizado. A folha fica com `estado=regularization` porque trabalho e ausência coexistem.
2. A auditoria usa `fn_folha_gestao_v2 / vacation_remove` pelo ator administrativo sintético para remover esse dia de férias, com preview/confirmação, request_id e revisão corretos.
3. O registo V2 continua `regularization`; não há atualização do seu estado nessa operação de férias.
4. `fn_folha_contexto_v2` devolve `sheet.state=regularization`, `absence=null`, `conflict=null` e os intervalos completos.
5. O resumo diário backend diminui pending em um e aumenta registered em um. `analyseSheet` ignora sheet.state e devolve registered; `daySummary` considera a linha completa.
6. A UI mostra Registado / 0 pendentes / DIA COMPLETO nas três larguras.
7. `fn_folha_gestao_contexto_v2` ainda devolve o mesmo facto com state=regularization em live_facts. Vencimentos conta esse facto como pendente.

O teste repõe a ausência sintética no finally. Nenhum registo real foi consultado ou alterado. A prova não depende de criar folha inconsistente por SQL: a folha é produzida pelo caminho legítimo já preparado e a remoção ocorre pela RPC autorizada.

### Causa e impacto

O serializer mantém state, mas o classificador diário não o consome; recalcula a partir de intervalos, ausência e carga atual. O resumo SQL diário usa a mesma estratégia. Já o domínio administrativo consulta o estado persistido diretamente. Assim, a mesma folha fica tratada no diário e pendente no administrativo, sem transição explícita da folha que justifique a alteração de interpretação.

Não se está a afirmar que a regularização tenha de ficar pendente para sempre. Falta um contrato coerente para a sua resolução: ou preservar/mostrar a pendência persistida até transição autorizada, ou resolver/recalcular explicitamente a fonte de forma auditável e consistente entre diário e administrativo. Essa decisão/correção pertence à próxima tarefa; não foi implementada na auditoria.

## F–G. Regressões e contagens

| Execução | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| 41 suites integradas do candidato, sequenciais | 580 | 0 | 3 |
| Backend final, com três novas provas independentes | 71 | 0 | 0 |
| Casos Node distintos executados, substituindo os 68 backend da execução integrada pelos 71 finais | 583 | 0 | 3 |
| Matriz browser independente (16 situações × 3 larguras) | 45 | **3** | 0 |

Os três testes backend adicionais incluem uma asserção de evidência que confirma a perda de estado; o seu PASS prova a reprodução do defeito, não aceitação funcional. Os três FAIL do browser não foram ocultados ou convertidos em PASS. Não se misturam grupos browser com casos Node num total artificial.

- Integração: 583 testes totais, 140,01 s; backend final: 12,41 s.
- Três SKIP RH preservados: cadastro/lote PostgreSQL, formulário e aviso contratual, runtime não configurado. Não são PASS.
- Browser visibilidade do candidato: 126 grupos PASS; Folha: 57; consolidação: 51, seis perfis/três viewports.
- Browser sessão: 7 cenários PASS; Planeamento/custos: 33 PASS. Medicina, RH frontend, RNC, Viaturas e Quadro: PASS.
- Matriz A–AN, Escritório, históricos V2/legado, coletivo, externos, HE, férias, vencimentos, tarefas/reportes, replay, concorrência, payload por perfil e isolamento: regressões existentes PASS.
- Nenhuma falha PostgREST de infraestrutura nesta execução. Todos os demais browsers foram executados após o FAIL independente, sem parar no primeiro achado.

Logs locais fora do Git: `%TEMP%/primeline-p2-reaudit-final-full.log`, `primeline-p2-reaudit-state-backend.log`, `reaudit-final-*-browser.log`. São dados sintéticos, não exportações de produção.

## Scripts e limites

Precheck/postcheck, instalação sintética, backup e rollbacks locais foram reexecutados pelas suites existentes. Fase B pós-hotfix local recusa gate ausente/drift; instalação e rollback passam; rollback V2 recusa factos persistentes e restaura o núcleo V1 apenas no cenário vazio autorizado. Nenhum script ou hash real foi editado/regenerado.

`git diff --check`: PASS. Produto idêntico ao candidato. Não houve produção, main, deploy, migration real, marker, Fase B real, contas/perfis reais ou nova tentativa de catálogo bloqueado.

## I. Decisão

**NO-GO LOCAL.** Os dois P2 anteriores estão fechados, mas existe um P2 bloqueante de regularização persistida e três FAIL na matriz independente. As regressões existentes verdes não satisfazem o critério de nenhum estado funcional omitido/transformado.

Requer correção específica da coerência do estado persistido entre fonte, resumo diário, UI e factos administrativos, seguida de revalidação. Catálogo real e regras ADM ainda desativadas continuam gates separados. Nenhuma correção foi feita nesta auditoria.
