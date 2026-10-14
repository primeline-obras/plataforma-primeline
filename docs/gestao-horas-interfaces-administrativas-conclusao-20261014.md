# Gestão Integrada de Horas — conclusão local das interfaces administrativas

Data: 14/10/2026, Europe/Lisbon.
Branch: `feat/gestao-horas-integrada-20261013`.
Checkpoint inicial confirmado e limpo: `2f7b64160b0338af713b1721621f2169a8e601a6`.
O checkpoint final é o commit local desta entrega; consultar `git rev-parse HEAD`. Este relatório sucede ao relatório de montagem anterior, preservado como histórico.

## Estado integrado e navegação

| Painel | Localização | Estado local |
|---|---|---|
| Editor/equipa operacional | Equipa → Folha de Ponto | Preservado e regredido em tablet retrato/paisagem e mobile |
| Conferência RH, FALTOU, HE informativa | Folha de Ponto → Gestão Integrada de Horas → Conferência RH | Montado; pendências obrigatórias continuam bloqueantes; HR-27/HR-31 não bloqueiam por si só |
| Externos/Excel | Gestão Integrada → Externos · Excel | Montado; revisão atual confirmada, motivo e histórico |
| Horas/custo da obra | Gestão Integrada → Horas / Custo da Obra | RH mantém detalhe autorizado; Diretor/Adjunto/Preparador recebem somente agregados HR-29 |
| Associação Garantia/Outra | Gestão Integrada → Associar Garantia / Outra, obra + data das referências | Montado, ação administrativa autorizada |
| Aprovação/consulta tarifa RH | Gestão Integrada → Custo/Hora RH, colaborador | Montado; aprovação apenas Administrativo/Gestão, consulta conforme capacidade do backend |
| Produção/UAT PostgREST real | Fora desta execução | Não executada; nenhum SQL real ou escrita em produção |

Os botões e seletores usam UUIDs e capacidades do contexto backend. Não existe matching por nome/email. A função do colaborador é apresentada como identidade profissional, nunca como fonte da tarifa. Nenhum salário é consultado para inferir custo.

## Associação Garantia/Outra

Estado visível `Por associar` ou `Associada`, obra associada, data/hora e autor a partir do registo/histórico reais. Uma referência associada oferece `ALTERAR ASSOCIAÇÃO`, não nova confirmação imediata. A mesma obra é recusada no frontend sem chamar o writer.
Alteração requer escolha deliberada, motivo e confirmação explícita do cliente controlado. Campos corrigidos limpam mensagens de validação. Falha/stale mantém os dados do formulário, recupera controlos e não repete automaticamente a RPC.
O writer `fn_folha_referencia_operar_v3` foi reutilizado sem alteração. Referência original, obra original, data, horários, revisões/histórico e permanência são preservados. `10:30–14:30` permanece um único intervalo personalizado. Obra legítima encerrada pode ser associada sem reabrir a obra.

## Tarifa RH

Nome e função no painel; UUID apenas técnico. Valor aprovado, evidência, motivo e data efetiva são explícitos, sem pré-seleção de preço. Todas as versões e o histórico ficam consultáveis. O leitor recebeu somente campos de autoria/motivo derivados dos registos existentes, sem ampliar permissões.
O fim da vigência é apresentado como exclusivo, conforme intervalos `[início,fim)`. O frontend respeita a última versão, inclusive futura; o writer já existente impede nova vigência anterior/igual ao último início, sobreposição, revisão antiga e alteração direta/GUC. Factos da Folha não são reescritos ao aprovar tarifa.
Não foi implementado pagamento/custo de HE, nem alteração salarial. HR-31 continua pendente/NULL quando existe excedente; não equivale a zero e não bloqueia a conferência factual.

## HR-29 — incompatibilidade, solução e limites

Causas anteriores: `folha_privado.obra` não permite Preparador, e o mapa detalhado usa `money := folha_privado.admin()`. Assim, Preparador era recusado e Diretor/Adjunto não recebiam valores.
Não foi aberto o helper legado, não foi concedido acesso a tabelas confidenciais e não foi alterado o writer RH. O registo operacional legado continua recusado ao Preparador; a navegação agregada não depende da autorização desse registo.

Novo contrato readonly: `fn_folha_custos_operacionais_contexto_v3(uuid,date)`.

- Autor ativo; mesma empresa; Diretor/Adjunto/Preparador com responsabilidade exata pela obra, ou perfil administrativo autorizado.
- DTO `scope = work_aggregate`: totais de horas/estimativas da obra, agregados diários, grupos pendentes e HR-31. Sem pessoas, nomes, IDs de registo/tarifa, valores por pessoa, evidências RH ou salário.
- Total pendente permanece NULL; subtotal conhecido é identificado como parcial. Externos continuam apenas com horas. Sem lançamentos financeiros, pagamento, custo HE ou dupla contagem com `lancamentos_mao_obra`.
- O cliente usa uma lista fechada de campos; recusa campos individuais/informação aninhada inesperada, âmbito errado e zero apresentado como total pendente.
- Helpers privados são gerados a partir dos leitores/cálculo aprovados; o gerador reutiliza a definição fonte e exige o hash dos leitores originais. Não existe segunda fórmula manual de HR-31 ou tarifa.
- Helpers sem EXECUTE para PUBLIC/anon/authenticated/service_role; apenas o RPC agregado público tem EXECUTE authenticated, sujeito à autorização interna. Uma alteração indevida da ACL é recusada pelo postcheck.

| Perfil | Agregado da obra autorizada | Tarifa individual | Aprovação tarifa |
|---|---|---|---|
| Administrativo/Gestão | Sim | Sim | Sim |
| Gerência | Sim | Consulta autorizada | Não |
| Diretor responsável | Sim | Não | Não |
| Adjunto responsável | Sim | Não | Não |
| Preparador responsável | Sim | Não | Não |
| Encarregado | Não por este contrato administrativo | Não | Não |
| Fora da empresa/responsabilidade ou inativo | Recusado | Recusado | Recusado |

Privacidade provada nesta entrega: ausência de dados individuais no DTO e recusa de leitura/aprovação confidencial. Agregados de grupos muito pequenos ou subtotais com poucos participantes podem permitir inferências por comparação com outros relatórios; isso não é uma prova de anonimização. A granularidade operacional deve ser revista na UAT/security review antes de GO. Não foi inventada uma regra de tamanho mínimo de equipa que contrariasse HR-29.

## FALTOU → mapa → classificação → mês

Regressão real LOCAL PostgreSQL: uma linha em `ausencias`, mesmo UUID após classificação, obra de origem/autor/data preservados, histórias de reporte e classificação presentes na conferência mensal. Sem segunda ocorrência, sem alteração de equipa/permanência ou criação de horas.
A falta neutra não usa os antigos handlers de PATCH. Classificação inicia vazia e só usa a RPC controlada com motivo e estado/tipo esperados. Leitores não disponíveis/capacidade ausente falham fechados. Os fluxos comuns de Ausências permanecem preservados.

## Testes executados nesta entrega

| Grupo | Resultado |
|---|---|
| PostgreSQL 17.6 integrado, duas ligações | 292/292, 0 skips: AD-03/13/14/15, concorrência/idempotência, ACL, tenant, revisão/stale, FALTOU, HR27/30/31, HR29, lifecycle/backup/rollback |
| Unitários/contratos/sessões | 104/104, 0 skips; incluindo DTO agregado fechado e campos confidenciais inesperados |
| Regressões Medicina, Viaturas, Planeamento, RH e wrapper | 67 aprovados, 0 falhas, 1 skip adicional do ficheiro real RH de 47 colaboradores |
| Navegador Folha legada | 57/57 cenários, 0 erros JS |
| Editor operacional | 3 suites: 768×1024, 1024×768, 390×844, 0 erros JS |
| Equipa operacional integrada | 3 suites nos mesmos formatos, 0 erros JS |
| RH/externos/mapa desktop | 1 suite, incluindo navegação, cancel/stale, histórico, revisão atual e XLSX real |
| Associação/tarifa/HR29 montados | 1 suite: origem/intervalo intactos, obra encerrada, estados/autoria, confirmação redundante bloqueada, validação limpa, tarifa explícita/stale e Preparador via navegação real da Folha com backend sintético |
| Syntax + git diff --check | PASS |

Os três SKIPs anteriores de RH foram resolvidos usando dependências isoladas em TEMP: (1) PostgreSQL/cadastro/lote atómico, (2) formulário preserva dados e grava uma vez, (3) aviso contratual/confirmar/células vazias. Expectativas originais intactas. A execução dedicada de RH teve 20 aprovações e um skip distinto: workbook real de 47 colaboradores indisponível via RH_XLSX. Não foi substituído por um ficheiro artificial nem contado como PASS.
Na preparação, foi corrigida uma referência inválida a helper de data no novo teste; a regressão final está verde. A expectativa de recusa do Preparador foi ajustada somente para o novo leitor agregado autorizado; a recusa do leitor confidencial/legado continua testada.

## Ficheiros e SQL completos

Aplicação: `src/attendance-hours-admin.js`, `src/attendance-hours-client.js`, `src/attendance-hours-review.js`, `src/attendance-hours-review.css`, `src/attendance-sheet.js`, `src/app.js`, `index.html`. Cache-busting atualizado somente para esta montagem.
Testes/geração: `tests/attendance-hours-admin.test.mjs`, `tests/attendance-hours-prepared-browser.mjs`, `tests/attendance-hours-review-browser.mjs`, `tests/attendance-operational-readers-package.mjs`, `tests/fixtures/attendance-operational-readers-core.sql`, `tests/fixtures/attendance-operational-readers-suite.txt`.
SQL local completo do último estágio:

- [Precheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_precheck.sql)
- [Backup privado](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_backup.sql)
- [Migration](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos.sql)
- [Postcheck](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_postcheck.sql)
- [Rollback](C:/Users/Cristiana/Documents/plataforma-primeline-horas-integrada/supabase/folha_operacional_contextos_rollback.sql)

Sem novas tabelas operacionais. A migration cria leitores/helpers e amplia DTOs de leitura; os writers e permissões gerais existentes são preservados. Backup captura definições/ACL e fotografias privadas; rollback restaura leitores originais e remove novos helpers. A ordem global dos restantes estágios está no relatório de retoma anterior. O ciclo foi validado só em ambiente sintético; não se deve executar estes scripts na produção sem preflight/autorização separados.

## Entrega visual e próximo passo

[ZIP final — oito capturas](C:/Users/Cristiana/.codex/visualizations/2026/09/29/01a0ec35-6391-74e1-adf3-642847f49889/primeline-horas-admin-concluidas-20261014.zip). Imagens sintéticas fora do Git.
Os dois modelos já aprovados estão montados; não precisam de nova aprovação visual para as pequenas alterações desta entrega.
FP-28 e FP-29 continuam em standby. Não foram alterados almoço, tolerância de 15 minutos, horários/contratos V3, limites 4/16 ou persistência de minutos.
Próximo passo obrigatório: UAT autenticada/PostgREST em ambiente autorizado, por perfil, empresa/obra, author/time/history, revisão/concorrência e privacidade do agregado. A sessão não disponibiliza Chrome DevTools MCP; não há validação autenticada real declarada. Produção continua intacta.
Estado: interfaces administrativas concluídas e testadas LOCALMENTE; HR-29 implementado no candidato local. Sem GO de produção. Restam UAT, revisão de granularidade dos agregados, workbook RH opcional e preflight/rollout autorizados. Nenhum SQL real, push, merge ou deploy nesta entrega.
