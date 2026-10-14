# Gestão integrada de horas — relatório único de retoma local — 14/10/2026

## Identidade e estado

Branch: feat/gestao-horas-integrada-20261013.
Base preservada: 3aef80f6e43b69bfa08a123912c4698fd6c4c517.
Checkpoint WIP de recuperação: 5c010ae9e3e7fefb032f3997030ab9e9c51dce3e (preserva as falhas anteriores).
Worktree: C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada.

Produção intacta. Nenhum SQL real, ativação de mecanismos na BD, push, merge ou deploy. Somente PostgreSQL 17.6 sintético e navegador offline. Este relatório substitui os estados de implementação descritos no relatório histórico de 13/10; o checkpoint WIP continua como evidência histórica.

Editor/equipa: aprovação visual expressa recebida nesta sessão; montados LOCALMENTE em attendance-sheet.js/app.js. Se os contratos V3 não estiverem instalados, o formulário mostra erro e não usa o writer antigo como fallback. Escritório conserva a interface existente. Os painéis desktop preparados ainda não estão montados: aprovação visual correspondente pendente no momento desta redação.

## Recuperação e causa das falhas

Os 5 modificados e 61 novos foram inspecionados, sem candidatos a credenciais, dados pessoais reais ou backups reais. Fixtures usam identidades sintéticas. Dependências temporárias ficam fora do Git. Nenhuma alteração foi descartada.

O log anterior contabilizava 276 testes, 273 PASS e 3 FAIL: TEAM, EXTERNAL e agregador. O teste TEAM repetia um pós-check de instalação após uma operação RH que alterava o ledger; o pós-check recusou corretamente a deriva. Esse pós-check já é executado no lifecycle, antes das operações funcionais. Foi retirada somente a repetição fora desse momento. Acrescentou-se ataque explícito ao ledger, FAIL esperado com ADDON_DATA_DRIFT, ROLLBACK em finally, comparação integral antes/depois e PASS do pós-check após restaurar a transação. O teste externo deixou de receber 25P02 e passou com as mesmas expectativas. Nenhum gate foi enfraquecido.

A revisão encontrou variáveis de ator obtidas antes do lock. Os escritores agora bloqueiam/releem a conta antes de usar empresa/perfil/hints; o helper relê após a autorização. Duas ligações provaram espera por lock seguida de recusa após desativação ou troca de empresa, sem factos/histórico/ledger novo. O leitor do dia valida também a obra contra a empresa do seu próprio snapshot.

Na montagem foi corrigida a libertação do busy após sucesso e recarregamento destruir o cartão antigo. O navegador prova recuperação, nova mudança de data e backend ausente sem fallback de escrita.

## Matriz única de implementação

| Bloco | Estado local | Evidência / pendência |
|---|---|---|
| Manhã/Tarde/Dia Inteiro | Domínio, writer V3 e editor montado | Sugestões legítimas congeladas; 5h/3h sem HE artificial; campos editáveis |
| Personalizado | Implementado e montado | Dois slots iniciais; 4 destinos/16 intervalos; NULL/personalizado; 10:30–14:30 permanece um intervalo |
| Encarregado de destino | Writer e leitura implementados | Só obras autorizadas, factos ocultos preservados; permanência de origem intacta; registo recuperável na equipa de destino |
| Dia Normal internos/externos | Implementado e montado | Lote atómico; exclui ausência, horas/referências/obras ocultas e apoios temporários acrescentados manualmente; nenhuma substituição; loading bloqueia data/ações |
| Garantia/Outra | Persistência/revisão/auditoria e editor implementados | Original imutável, obra encerrada como referência; associação administrativa separada; painel de associação ainda por ligar |
| Faltou neutro | RPC e botão montado | Hoje/ontem, internos, conflito com pontos/referências, equipa conservada; classificação administrativa preparada no painel desktop |
| Relatório de horas | Leitor factual implementado; histórico da obra encaminhado para V3 | Sem classificação HE; referências incluídas; legado fora dos totais |
| RH mensal | RPCs/client e painel desktop preparados/testados | Mês integral, pendências/fecho/revisão/história; devolução suporta referência; montagem administrativa pendente |
| HE HR-27 | Backend/client e painel informativo preparados | Reconhecida não gera folha_he/pagamento/custo e não bloqueia por si só; não existe botão monetário no painel preparado |
| Externos/Diretor/Excel | RPCs/client/codec XLSX e painel desktop preparados/testados | Leitor de revisão atual/história; confirmação exclusiva do Diretor; invalidação por fingerprint; XLSX real versionado, sem CSV; montagem pendente |
| Custos RH e HR-31 | Tarifa temporal protegida, RPC/client e mapa preparados | Sem valor_hora inferido; excedente diário inteiro pendente/NULL; não bloqueia RH; UI de aprovação de tarifa ainda por ligar |
| Mapas | Fonte e painel preparados/testados | Provisório/consolidado exclusivos; não soma lancamentos_mao_obra; não altera os mapas financeiros atuais; montagem pendente |
| Operação antiga | Compatibilidade preservada/testada | 57 cenários da Folha existente; ações de equipa controladas preservadas; writer legado não reaberto |

Não há hardcode de pessoas/obras reais. Nenhuma aproximação remuneratória, pausa, corte manhã/tarde ou custo HE foi introduzido. A última tarefa de um destino existente não é eliminada silenciosamente pelo novo editor: o fluxo de arquivamento/removal factual ainda precisa de contrato e UI específicos, se requerido.

## Testes executados

| Execução final | Resultado |
|---|---|
| PostgreSQL 17.6, attendance-hours-backend | 282 PASS / 0 FAIL / 0 SKIP (contagem do runner, inclui agregador) |
| Unit/static/session/client/Excel | 93 PASS / 0 FAIL / 0 SKIP |
| Editor offline | 3 viewports PASS: 768×1024, 1024×768, 390×844 |
| Equipa + montagem Folha offline | 3 viewports PASS; V3 efetivo, data correta, recuperação, sem fallback |
| Folha existente offline | 57 cenários PASS / 0 erros JS |
| Protótipos históricos offline | 31 estados e 3 suítes PASS |
| Painéis desktop preparados | 1 suíte PASS: RH, neutral, HE, cancel/stale, Diretor, XLSX real, HR-31 |
| git diff --check e sintaxe JS | PASS |

AD-03/13/14/15, concorrência/replay, scope/tenant, direct DML/GUC, backups privados, instalação/rollback/reinstalação e fonte financeira separada estão na cadeia PostgreSQL. A execução inicial de attendance-hr27.test junto aos unitários falhou por falta de QUADRO_PG_BIN nessa invocação; não foi contada como aprovada. HR-27 foi executada com runtime correto dentro da cadeia integrada final. Não se alterou o teste para permitir SKIP.

As contagens não somam execuções repetidas. Navegadores usam mocks expressamente identificados e rede limitada ao loopback; não certificam autorização na BD real. O PostgreSQL usa JWT/ator sintéticos; não é certificação PostgREST real. O codec XLSX é SheetJS 0.20.3, a versão já usada no index, com roundtrip binário e prevenção de fórmula. Runtime temporário deve ser fornecido por HOURS_XLSX ao repetir noutro computador.

## SQLs completos e procedimento proposto — não executar agora

Pré-condição: base AD-03/13/14/15 correspondente às fontes versionadas. Não inferir que a produção já possui essa base. Cada pacote abaixo contém definição completa e gates. Ordem local validada:

| Ordem | Precheck | Backup privado | Migration completa | Pós-check | Rollback |
|---|---|---|---|---|---|
| 1. folha_hr27 | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_hr27_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_hr27_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_hr27.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_hr27_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_hr27_rollback.sql) |
| 2. folha_faltou_neutro | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_faltou_neutro_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_faltou_neutro_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_faltou_neutro.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_faltou_neutro_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_faltou_neutro_rollback.sql) |
| 3. folha_horas_leituras | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_leituras_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_leituras_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_leituras.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_leituras_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_leituras_rollback.sql) |
| 4. folha_conferencia_mensal | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_conferencia_mensal_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_conferencia_mensal_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_conferencia_mensal.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_conferencia_mensal_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_conferencia_mensal_rollback.sql) |
| 5. folha_destino_operacional | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_rollback.sql) |
| 6. folha_externos_conferencia | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_rollback.sql) |
| 7. folha_referencias_controladas | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_rollback.sql) |
| 8. folha_horas_mapas_custos | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_rollback.sql) |
| 9. folha_plano_integrado | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_rollback.sql) |
| 10. folha_operacional_contextos | [precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_precheck.sql) | [backup](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_backup.sql) | [migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos.sql) | [postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_postcheck.sql) | [rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_rollback.sql) |

Para um rollout futuro, obter autorização separada, ler catálogo/definições reais e executar somente o precheck read-only do estágio, parar em divergência, capturar backup privado, aplicar a transação integral e fazer pós-check imediatamente ANTES de operações funcionais. Não repetir gates de igualdade de fotografia após uso legítimo; fases posteriores redefinem funções e os gates anteriores não representam o estado final. Não adaptar hashes para contornar divergência real.

Rollback técnico em ordem inversa apenas enquanto os gates permitirem: é recusado depois de uso/deriva, para não apagar história. Depois de uso, avaliar forward-fix ou recuperação controlada, sem rollback cego. Backups privados não devem ser exportados para Git. Nenhum destes procedimentos autoriza SQL real.

RPCs operacionais: fn_folha_plano_integrado_v3(jsonb,boolean,text), fn_folha_destino_operar_v3(jsonb,boolean,text), fn_folha_dia_normal_v3(jsonb,boolean,text), fn_folha_referencia_operar_v3(text,jsonb,boolean,text). Todas seguem preview ligado a ator/empresa/factos, confirmação/revisões/request_id, sem retry automático.
RPCs administrativas: fn_folha_conferencia_v3(text,jsonb,boolean,text), fn_folha_faltou_v2(text,jsonb,boolean,text), fn_folha_diaria_gestao_v2(text,jsonb,boolean,text), fn_folha_externos_confirmar_v3(jsonb,boolean,text), fn_folha_custo_hora_aprovar_v3(jsonb,boolean,text). fn_folha_externos_conferencia_contexto_v3 e fn_folha_custo_hora_contexto_v3 permitem consultar a revisão/história antes de confirmar, inclusive tarifa futura. O histórico RH é resolvido pela FK nova_versao_id, não por um colaborador_id inexistente; a primeira tentativa desse leitor foi recusada em teste e o join corrigido foi revalidado. Leituras específicas retornam fonte atual/revisão; não há matching por nome/email.

## Ficheiros e evidência

Inventário comparado com o checkpoint original, incluindo ficheiros ainda novos no momento da redação:

- [checkpoint-gestao-horas-wip-20261014.md](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/docs/checkpoint-gestao-horas-wip-20261014.md)
- [index.html](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/index.html)
- [app.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/app.js)
- [attendance-hours-client.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-client.js)
- [attendance-hours-domain.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-domain.js)
- [attendance-hours-editor.css](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-editor.css)
- [attendance-hours-editor.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-editor.js)
- [attendance-hours-excel.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-excel.js)
- [attendance-hours-map.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-map.js)
- [attendance-hours-review.css](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-review.css)
- [attendance-hours-review.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-review.js)
- [attendance-hours-team.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-hours-team.js)
- [attendance-sheet.js](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/src/attendance-sheet.js)
- [folha_destino_operacional.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional.sql)
- [folha_destino_operacional_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_backup.sql)
- [folha_destino_operacional_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_postcheck.sql)
- [folha_destino_operacional_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_precheck.sql)
- [folha_destino_operacional_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_destino_operacional_rollback.sql)
- [folha_externos_conferencia.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia.sql)
- [folha_externos_conferencia_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_backup.sql)
- [folha_externos_conferencia_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_postcheck.sql)
- [folha_externos_conferencia_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_precheck.sql)
- [folha_externos_conferencia_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_externos_conferencia_rollback.sql)
- [folha_horas_mapas_custos.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos.sql)
- [folha_horas_mapas_custos_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_backup.sql)
- [folha_horas_mapas_custos_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_postcheck.sql)
- [folha_horas_mapas_custos_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_precheck.sql)
- [folha_horas_mapas_custos_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_horas_mapas_custos_rollback.sql)
- [folha_operacional_contextos.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos.sql)
- [folha_operacional_contextos_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_backup.sql)
- [folha_operacional_contextos_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_postcheck.sql)
- [folha_operacional_contextos_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_precheck.sql)
- [folha_operacional_contextos_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_rollback.sql)
- [folha_plano_integrado.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado.sql)
- [folha_plano_integrado_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_backup.sql)
- [folha_plano_integrado_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_postcheck.sql)
- [folha_plano_integrado_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_precheck.sql)
- [folha_plano_integrado_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_plano_integrado_rollback.sql)
- [folha_referencias_controladas.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas.sql)
- [folha_referencias_controladas_backup.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_backup.sql)
- [folha_referencias_controladas_postcheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_postcheck.sql)
- [folha_referencias_controladas_precheck.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_precheck.sql)
- [folha_referencias_controladas_rollback.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_referencias_controladas_rollback.sql)
- [attendance-addon-lifecycle.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-addon-lifecycle.mjs)
- [attendance-cost-map-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-cost-map-package.mjs)
- [attendance-destination-lifecycle.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-destination-lifecycle.mjs)
- [attendance-destination-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-destination-package.mjs)
- [attendance-external-month-client.test.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-external-month-client.test.mjs)
- [attendance-external-month-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-external-month-package.mjs)
- [attendance-hours-backend.test.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-backend.test.mjs)
- [attendance-hours-editor-browser.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-editor-browser.mjs)
- [attendance-hours-excel.test.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-excel.test.mjs)
- [attendance-hours-map.test.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-map.test.mjs)
- [attendance-hours-operational.test.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-operational.test.mjs)
- [attendance-hours-review-browser.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-review-browser.mjs)
- [attendance-hours-team-browser.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-hours-team-browser.mjs)
- [attendance-integrated-plan-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-integrated-plan-package.mjs)
- [attendance-operational-readers-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-operational-readers-package.mjs)
- [attendance-references-package.mjs](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/attendance-references-package.mjs)
- [attendance-cost-map-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-cost-map-core.sql)
- [attendance-cost-map-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-cost-map-suite.txt)
- [attendance-destination-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-destination-core.sql)
- [attendance-destination-generated.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-destination-generated.sql)
- [attendance-destination-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-destination-suite.txt)
- [attendance-external-month-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-external-month-core.sql)
- [attendance-external-month-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-external-month-suite.txt)
- [attendance-integrated-plan-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-integrated-plan-core.sql)
- [attendance-integrated-plan-generated.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-integrated-plan-generated.sql)
- [attendance-integrated-plan-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-integrated-plan-suite.txt)
- [attendance-operational-readers-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-operational-readers-core.sql)
- [attendance-operational-readers-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-operational-readers-suite.txt)
- [attendance-references-core.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-references-core.sql)
- [attendance-references-destination.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-references-destination.sql)
- [attendance-references-generated.sql](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-references-generated.sql)
- [attendance-references-suite.txt](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/tests/fixtures/attendance-references-suite.txt)

## Modelos e encerramento local

ZIP operacional aprovado: C:/Users/Cristiana/.codex/visualizations/2026/09/29/01a0ec35-6391-74e1-adf3-642847f49889/primeline-horas-operacional-final-20261014.zip (21 capturas).
ZIP administrativo submetido: C:/Users/Cristiana/.codex/visualizations/2026/09/29/01a0ec35-6391-74e1-adf3-642847f49889/primeline-horas-revisao-admin-20261014.zip (5 capturas).
Nenhuma captura contém dados reais. Imagens fora do Git; entrega apenas ZIP.

A Folha montada usa integratedHours=true somente neste candidato local. Escritório e Gestão legada não foram redesenhados; a montagem administrativa preparada ainda precisa substituir/ligar os fluxos correspondentes, inclusive classificação neutra e HE informativa. Não confundir backend/client preparados com todas as páginas concluídas.

Sem processo de teste/migration pendente no encerramento; bases PostgreSQL sintéticas são paradas pelo harness. O SHA de encerramento é o HEAD local após o commit desta entrega; consultar git rev-parse HEAD. Nenhum remoto foi atualizado.

## Retoma exata e limite de entrega

1. Aprovar os modelos desktop finais antes de os montar (pergunta enviada nesta sessão).
2. Ligar os painéis aprovados à seleção autenticada de colaborador/competência e obra/fornecedor, reutilizando metadados autorizados existentes.
3. Completar interfaces administrativas de associação de referências e aprovação de custo/hora com prova/autor/vigência; não inventar prova a partir de valor_hora.
4. Executar auditoria adversarial final dos novos escritores + integração montada, e repetir os testes pertinentes às novas ligações.
5. Só depois: preflight real autorizado e plano de aplicação por estágio. Não existe GO de produção nesta entrega.

Estado: retoma segura e operação local montada estabilizadas; preparação global ainda parcial nos pontos explicitados. Candidato NÃO publicável agora. Os modelos aprovados de editor/equipa estão integrados; os administrativos novos permanecem fora de app.js. SQL real/push/merge/deploy continuam proibidos.
