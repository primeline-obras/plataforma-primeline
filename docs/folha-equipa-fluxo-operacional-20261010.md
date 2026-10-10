# Folha de Ponto, equipa e Plano de Ação — 10/10/2026

## Resultado e âmbito

Implementação local consolidada, preparada para um único rollout. Branch `fix/folha-equipa-fluxo-operacional-20261010`, criada exatamente de `53f4823ed16af14265c20baea37724c851434aa4`. O SHA final publicado na branch consta da entrega operacional e de `git log -1`.

Nenhum SQL desta tarefa foi executado em produção. Não houve merge em main, deploy, Fase B, alteração de perfis ou dados reais. Os testes de escrita usaram bases PostgreSQL locais descartáveis e mocks de browser.

## Diagnóstico e decisão de modelo

`quadro_pessoal_alocacao` representa dias/períodos explícitos; não contém início/fim de permanência. Os movimentos são acontecimentos, não intervalos completos de lotação. Inferir uma equipa permanente a partir deles inventaria datas e destinos.

A fonte de verdade da permanência é agora `public.quadro_equipa_permanencias`, com `inicio` inclusivo e `fim` exclusivo. Não há backfill. `fn_quadro_resolver_data` projeta os intervalos válidos para a forma diária que os leitores existentes entendem, sem inserir linhas diárias. Folha e Quadro usam essa mesma projeção e o mesmo writer de permanências.

As alocações antigas permanecem integralmente guardadas. Antes da primeira permanência deliberada da pessoa, continuam a ser lidas como alocações explícitas. Uma pessoa já alocada à mesma obra pode ser selecionada para **confirmar explicitamente a permanência**. Após essa data, retirada/transferência determina a lotação; linhas antigas não fazem a pessoa reaparecer noutra obra. Conflitos históricos não são limpos nem convertidos automaticamente.

Permanência não prova presença nem cria horas, ausência ou jornada teórica. As regras de Vencimentos e o cálculo monetário permanecem inalterados; os factos administrativos continuam a vir das fontes existentes. A nova fonte não cria automaticamente pendências salariais para todos os dias de calendário.

## Funcionamento operacional

| Área | Comportamento final |
|---|---|
| Adicionar | Seleção múltipla; um preview e uma confirmação para todo o lote; inclusão atómica a partir da data escolhida. |
| Retirar | Fecha o intervalo na data efetiva; mantém identidade, registos, movimentos e história. Factos/ausências/conflitos na data mantêm as salvaguardas visuais existentes. |
| Transferir | Confirmação explícita, obra de origem autorizada, fecho/início na mesma transação. Não altera os factos já registados na origem. |
| Elegibilidade | `folha_privado.elegivel_equipa` centraliza empresa, atividade na data e cargo RH Pedreiro/Servente. Folha, candidatos e adapter do Quadro reutilizam a regra. |
| Horas próprias | Diretor/Adjunto/Preparador ligados univocamente ao colaborador podem imputar as próprias horas à obra de responsabilidade. Não cria permanência nem coloca a pessoa na equipa do Encarregado. |
| Individual | REGISTAR/EDITAR, intervalos factuais múltiplos, total imediato; saída vazia mantém aberto. Calendário não bloqueia registo manual. A janela de correção existente continua a aplicar-se. |
| Coletivo | Chegada/saída factual apenas no próprio dia; exclui ausências, conflitos, legado e pessoas sem permissão. Dia normal exige calendário/ano e horário validados, jornada já terminada e elegibilidade. |
| Estado do dia | SEM EQUIPA / NÃO INICIADO / EM PREENCHIMENTO / DIA COMPLETO, preservando regularização, justificação pendente e revisão de dia especial. Zero pessoas nunca significa dia completo. |
| Externos | Identidade separada, fornecedor autorizado, função diária obrigatória Pedreiro/Servente, intervalos factuais e total. 10–16 = 6h; 8–12 + 13–16 = 7h. Sem dia normal, HE automática, folha salarial ou cálculo de custo/pagamento. |
| Interface do Encarregado | Uma obra/data, lista vertical, horários e totais; sem blocos de tarefas/Planeamento ou mensagem técnica de geração de HE. |
| HE legítima | Revisão operacional de Diretor/Adjunto e gestão administrativa preservadas; nenhum mecanismo monetário ativado. |

O Quadro encaminha as operações de equipa física para `fn_equipa_operar_v2`; a função diária preservada fica privada para os fluxos não operacionais já existentes. O Encarregado não pode usar esse adapter para adicionar cargos inelegíveis. Operações de período parcial não criam uma segunda lotação física: os intervalos trabalhados pertencem à Folha.

Alocações futuras explícitas para destinos incompatíveis, ausência na data efetiva e factos de outra obra posteriores ao início pretendido abortam a operação. Uma transferência pode substituir a projeção de linhas explícitas da própria origem, mantendo essas linhas intactas. Não substitui silenciosamente um terceiro destino ou trabalho factual.

## Plano de Ação e conclusão

Todas as ações/blocos de tarefas foram retirados da Folha. O Plano de Ação chama a RPC existente `fn_folha_gestao_v2`, ação `task_report`.

O reporte mantém a tarefa aberta, apresenta **CONCLUSÃO REPORTADA · AGUARDA CONFIRMAÇÃO DO DIRETOR**, data/hora de Lisboa e nome do autor. A leitura enriquece somente os reportes já autorizados pelo reader instalado; não expõe um diretório global. Um reporte não altera estado, percentagem ou datas do Planeamento.

O alerta existente `folha_conclusao_reportada` inclui obra, tarefa, autor e momento do reporte, destinado ao Diretor responsável da mesma empresa; `enviar_email=false`. Request id/revisão e unicidade da tarefa impedem duplicações. O fecho oficial continua no Planeamento e o trigger existente confirma o reporte/resolve os alertas. Permissões especiais de Gestão já existentes são preservadas; o Encarregado nunca faz o fecho oficial.

## Delegações

Campos nullable `delegacao` em colaboradores, obras e utilizadores, limitados a `lisboa`/`algarve`; nenhuma linha é preenchida por esta migration.

- Configurada e igual à da obra/utilizador: apresentação normal.
- Configurada e diferente: LISBOA ou ALGARVE explícito.
- Não configurada: **DELEGAÇÃO POR CONFIGURAR**, inclusão permitida.
- Sem inferência por nome, obra ou cargo.

Vando e Alessandro = Algarve são informação explicitamente fornecida pela Jordane, mas não foram gravados em dados reais nem hardcoded no produto. Configuração de dados deve ocorrer apenas com autorização posterior.

## Mapa de Férias

`fn_folha_ferias_mapa_v2` oferece ao Encarregado todos os colaboradores internos da própria empresa relevantes no intervalo, independentemente de obra/cargo/delegação. Projeta somente id/nome/cargo e id/pessoa/data/tipo/estado de férias; não inclui comentários, dados económicos, direitos/saldos ou externos. Intervalo máximo 366 dias.

O consumidor do mapa usa esse diretório mínimo separado do diretório de equipa/Medicina. Não amplia RH nem concede qualquer escrita de férias. Falha da RPC não desencadeia fallback para leitura global de RH.

## Contratos e segurança

`fn_equipa_operar_v2(p_acao text,p_dados jsonb,p_confirmar boolean,p_versao text)`:

```json
{
  "version": 2,
  "request_id": "UUID novo por operação",
  "work_id": "UUID da obra",
  "date": "AAAA-MM-DD",
  "people": [{"person_id": "UUID", "expected_revision": 0}],
  "reason": "opcional"
}
```

Ações `team_add`, `team_remove`, `team_transfer`; esta última exige `source_work_id` em cada pessoa. O frontend permite um transferido por confirmação e inclusão múltipla de pessoas disponíveis/na mesma obra.

Preview: `version=2`, `committed=false`, `versao`, `summary`, `preview`. Confirmação: mesmo payload/request id, `p_confirmar=true`, token do preview; resposta `committed=true`, `request_id`, `changed_keys`, `result`. Erros de revisão/token obsoletos usam `40001`; autorização/tenant/elegibilidade usam `42501`. Conflitos de equipa, ausência, destinos futuros, factos e idempotência devolvem erros explícitos. Não há fallback para DML nem sucesso simulado.

As escritas coordenam o lock de tabela diário com o advisory lock existente `(61001,1)`, bloqueiam colaborador/ator e verificam revisão por pessoa. A confirmação verifica novamente o snapshot. Replay concorrente devolve o resultado original com uma só permanência/movimento. Isolamentos diferentes de READ COMMITTED são recusados com `40001`.

Responsabilidades/ligação própria ficam bloqueadas durante a imputação própria. Triggers impedem apagar permanências, modificar a sua origem ou criar sobreposição. O writer diário não pode competir com uma permanência ativa. Os helpers/clones são privados, com `search_path=pg_catalog`; novas tabelas têm RLS ativo e nenhum DML direto para authenticated/anon/service_role.

Auditoria usa os movimentos do Quadro, `folha_historico` e o ledger idempotente existentes. Não há zero vestígio: revisões, movimentos, alertas e história são preservados deliberadamente.

## Migration e proteção documental

Cinco scripts finais, completos e commitados; sem ficheiros geradores/intermediários:

1. `supabase/folha_equipa_operacional_precheck.sql`
2. `supabase/folha_equipa_operacional_backup.sql`
3. `supabase/folha_equipa_operacional.sql`
4. `supabase/folha_equipa_operacional_postcheck.sql`
5. `supabase/folha_equipa_operacional_rollback.sql`

Precheck readonly: owner, objetos ausentes, definições/assinaturas e fingerprints da base, cutover legado CLOSED instalado e ativo. Não executa cutover/gate antigos. O backup privado preserva definições/ACL/owners das funções, snapshots integrais de dez tabelas relacionadas e catálogo de policies/grants/RLS/colunas/constraints/triggers.

A migration é transacional, exige backup e igualdade dos dados/definições, usa lock timeout de 10 segundos e não contém importação/backfill. O pós-check exige tabelas novas vazias, integridade/ACL/RLS corretos, igualdade integral dos dados antigos descontando somente as novas colunas NULL, e catálogo legado inalterado exceto as adições previstas.

Rollback restaura definições originais e remove exclusivamente a camada nova, sem CASCADE. Recusa se já existirem permanências/revisões ou dados nas novas colunas, para não destruir uso real; nesse caso a recuperação exige plano específico autorizado. O backup privado é retido.

## Evidência local

| Conjunto | Resultado final |
|---|---|
| PostgreSQL 17.6 nativo, unitários/contratos, sessão, Plano/Férias e estáticos correlatos | 72 PASS / 0 FAIL / 0 SKIP |
| Browser dos novos fluxos, 375/430/768/1440 | 44 grupos PASS, 0 erros de consola/página |
| Regressão browser Folha | 57 grupos PASS, 0 erros de página |
| Estados visíveis backend→UI | 126 grupos PASS |
| Reconciliação férias/ausências→Folha | 81 grupos PASS |
| Regras ADM/HE/férias/Vencimentos correlatas | 75 grupos PASS |
| `git diff --check` e revisão de ficheiros/segredos | PASS |
| Segunda worktree detached limpa no commit entregue | Mesmas suites repetidas, PASS |

O total de grupos browser é 383, apresentado separado dos 72 testes Node. Não é evidência de UAT real nem de instalação na BD real. Fontes web foram simuladas nas fixtures para manter o browser local sem acesso externo. Screenshots sintéticos ficam em `%TEMP%\primeline-folha-equipa-20261010` e nos diretórios de cada suite; não entram no Git.

Matriz A–R reproduzida no teste PostgreSQL: A/B persistência/entrada, C retirada, D transferência, E/F cargo/recusa backend, G horas próprias sem equipa, H/I externo/total, J sem normal, K função externa, L tenant, M delegação, N férias globais mínimas sem DML, O reporte sem fecho, P alerta, Q fecho oficial, R legado CLOSED. Cobertura adicional de lote inválido atómico, ator inativo, obra não autorizada, idempotência, replay concorrente, revisão stale, calendário ausente e rollback vazio/com uso. As 227 alocações sintéticas originais são comparadas integralmente ao backup.

Comando das suites Node:

```powershell
node --test tests/folha-equipa-operacional.test.mjs tests/folha-equipa-ui-contract.test.mjs tests/attendance-domain.test.mjs tests/foreman-action-plan.test.mjs tests/foreman-scope.test.mjs tests/session-boundary.test.mjs tests/attendance-v2-static.test.mjs
```

Usar `QUADRO_PG_BIN` para PostgreSQL 17.6 local e `QUADRO_TEST_DEPS` para `pg`. Browser usa Playwright já instalado; `PLANNING_PLAYWRIGHT`/`PLANNING_CHROMIUM_EXE` permitem o runtime local existente. Não instalar nem ligar ao PostgreSQL remoto para estes testes.

## Revisão cruzada final

- Uma fonte de permanência; Quadro/Folha partilham writer/resolver.
- Nenhuma criação diária para a equipa física nova; compatibilidade diária não operacional continua privada e revista.
- Cargo inelegível recusado também pelo adapter do Quadro e pelo save do Encarregado.
- Horas próprias não geram permanência; mudança de data não perde a equipa.
- Retirada/transferência preservam factos e história.
- Externo sem normal, HE/payroll/custo automático.
- Folha sem tarefas; reporte não fecha Planeamento.
- Férias completas da empresa no mapa mínimo; delegações desconhecidas não bloqueiam inclusão.
- Sessão/epoch protege respostas antigas; reporte nunca usa PATCH no Planeamento.
- Nenhuma regra monetária, exporter, Fase B ou writer legado ativado.

## Ficheiros finais

Frontend: `index.html`, `src/app.js`, `src/action-plan.js`, `src/attendance-client.js`, `src/attendance-domain.js`, `src/attendance-management.js`, `src/attendance-sheet.js`, `src/attendance-sheet.css`, `src/foreman-scope.js`.

Backend: os cinco scripts acima. Testes novos: `tests/folha-equipa-operacional.test.mjs`, `tests/folha-equipa-ui-contract.test.mjs`, `tests/folha-equipa-operacional-browser.mjs`. Testes ajustados: `tests/attendance-domain.test.mjs`, `tests/foreman-action-plan.test.mjs`, `tests/attendance-sheet-browser.mjs`, `tests/attendance-adm-rules-browser.mjs`, `tests/attendance-v2-static.test.mjs`. Ajustes dos testes antigos refletem o novo contrato e o botão explícito de submissão; não reduzem verificações de autorização, história ou estados.

## Rollout único — somente após autorização expressa

1. Fixar o SHA entregue da branch e verificar working tree/remoto. Não reaplicar scripts antigos do cutover.
2. Supabase autenticado no projeto correto, SQL Editor, apenas precheck: exigir `FOLHA_EQUIPA_PRECHECK_OK`. Qualquer drift/objeto inesperado/erro: STOP, sem adaptação automática.
3. Executar backup uma vez; conferir schema privado e snapshots. Falha: STOP.
4. Executar integralmente a migration commitada. Falha: confirmar ROLLBACK da transação e STOP.
5. Executar imediatamente pós-check readonly: exigir `FOLHA_EQUIPA_POSTCHECK_OK`, tabelas novas vazias e igualdade do legado/catalogo. Divergência: STOP, não publicar frontend.
6. Publicar o frontend do mesmo SHA pelo fluxo Git existente, após o backend confirmado. Não criar lotações por inferência. Não executar Fase B.
7. Smoke readonly com Gestão e Encarregado real: obra/data, candidatos, delegações desconhecidas, férias completas, Plano de Ação e ausência de writer legado; desktop/mobile/tablet e consola/network.
8. Escrita real/UAT: apenas operação concreta previamente autorizada, com estado inicial conhecido e rasto previsto. Sem importação/invenção de equipa histórica ou preenchimento automático de delegações.

Riscos externos restantes: drift do catálogo real desde a base; autenticação/disponibilidade Supabase; autorização/execução do rollout; configuração factual de delegações e confirmação humana das primeiras permanências. Nenhum deles foi resolvido com escrita real nesta tarefa.

READY_FOR_SINGLE_ROLLOUT = YES (readiness local; execução real exige autorização).
