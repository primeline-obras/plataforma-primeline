# Auditoria final focada — fecho do Pacote 1 Quadro

02/10/2026. **PACOTE 1 APTO PARA ROLLOUT REAL CONTROLADO.**

Conclusão técnica local para o candidato exato abaixo: P1 ACL fechado, nenhum novo P0/P1 confirmado. Não é autorização para executar SQL real, publicar frontend ou endurecer B. As etapas reais continuam a exigir precheck/backup, validação operacional e autorização separada.

## A. Branch/SHA da auditoria

- Candidato: `feat/quadro-controlado-20261001`, **d6db2c3c9e48170a3d4c6ec937b5f7ad76e411fb**.
- Base confirmada por leitura remota: `origin/main`, **9e0e6c40b439160201289823db8cfee0b9adad02**.
- Auditoria anterior preservada: `audit/quadro-controlado-aceitacao-20261002`, **f6c60fce9b6002ef8107d1b2c80a8d00c2d4b25e**.
- Nova branch criada exatamente do candidato: `audit/quadro-controlado-fecho-20261002`.
- Worktree: `C:\Users\Cristiana\Documents\plataforma-primeline-quadro-fecho`.
- Entrega: somente este relatório e `tests/audit-quadro-fecho.test.mjs` / `tests/audit-quadro-fecho-browser.mjs`. SHA do commit da auditoria na resposta final e no Git.

Candidato, main, urgent e auditorias anteriores não foram modificados. Nenhum acesso à produção/BD real/Chrome pessoal, execução SQL real, merge ou deploy. PostgreSQL 17.6 real **local**, PGlite e browsers offline com API sintética; fixtures não são prova do catálogo real atual.

## B. Último P1 — ACL de coluna

**PASS / P1 fechado.** O check de `pg_attribute.attacl` percorre todas as colunas não eliminadas da referência, sem hardcode de `estrutura`. `aclexplode` recusa grantee/grantor diferente do owner postgres. A verificação adicional de `has_any_column_privilege` recusa acesso efetivo de anon/authenticated/service_role.

Matriz independente: duas colunas (`estrutura` e `fecho_coluna` criada somente dentro de transação sintética), cinco grantees e quatro privilégios = **40 cenários**, cada um contra B e alias.

| Role/grantee | SELECT | INSERT | UPDATE | REFERENCES |
| --- | --- | --- | --- | --- |
| authenticated | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| anon | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| service_role | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| PUBLIC | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| fecho_unexpected | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |

A mesma tabela de resultados foi comprovada nas **duas** colunas. FAIL/FAIL significa recusa correta B/alias, não falha do runner.

Em cada ataque isolado:

1. Instalação íntegra passa, incluindo a coluna adicional limpa.
2. GRANT de coluna deixa `relacl` igual e altera `attacl`.
3. `has_column_privilege` retorna true; para PUBLIC, o teste usa anon como beneficiário efetivo. PostgreSQL 17.6 permite os quatro grants PUBLIC.
4. B/alias lançam `POSTCHECK_FAILED: ACL de coluna inesperada...`.
5. SAVEPOINT recupera o erro, REVOKE remove o privilégio e ambos passam; `has_column_privilege` volta a false.
6. ROLLBACK final restaura a fotografia e ambos passam novamente.

O teste do candidato também comprovou grants herdados por authenticated e acesso owner exclusivamente previsto. Backup B cria referência com attacl NULL; nenhum grant legítimo para a aplicação foi encontrado. B/rollback/forward-fix não concedem/restauram ACL da referência, apenas das tabelas operacionais previstas. Drift não é limpo silenciosamente: o pós-check recusa-o.

## C. B / alias

**PASS / PASS para instalação íntegra.** Equivalência de conteúdo integral comprovada no teste; ficheiros deste worktree byte-idênticos. SHA256 dos dois ficheiros de trabalho: `48BA36C2737396B1BDFF48AB412EC9C894AF3F246AABF5BED7CD297CC4404FE8`.

Quebras de linha podem mudar entre checkouts Windows/Git; a leitura dos testes normaliza CRLF e mantém comparação integral. O hash não é prova de autorização privada nem substitui a inspeção do catálogo.

Negativos adicionais continuam recusados: referência ausente/vazia/duplicada, índice global removido/redefinido, coluna/default/tipo/revisão/tabela/helper ausente, RLS desligada, trigger extra, ACL schema e marker alterado. Instalação A com drift antes do backup B é recusada; a referência não legitima esse drift.

## D. P1 anteriores — regressão focada

| Caso | Resultado nesta execução |
| --- | --- |
| Trigger de histórico ausente | PASS: B/alias recusam. |
| Trigger disabled | PASS: recusam. |
| Trigger rebound/definição com WHEN divergente | PASS: recusam. |
| Notifier no-op com assinatura igual | PASS: recusa. |
| Corpo de função crítica alterado | PASS: recusa de histórico/v1/contexto/helper de validação. |
| Policy eliminada/extra/permissiva ou ACL divergente | PASS: recusa. |
| Saving após falha | PASS pelo handler real de browser, 11 casos por viewport. |
| Tablet/mobile: data visual = payload | PASS, 27 alvos físicos em três semanas. |
| Múltiplos destinatários/colisão 23505 | PASS com índice real capturado, A/B; índice global intacto. |
| Gate privado/GUC/payload spoof | PASS, recusas e privacidade mantidas. |

Browser independente: mouse/tap, boundingBox/elementFromPoint/labels/sete colunas, scroll, mover/retirar/split/merge, cancelar/reload. Nenhum force-click ou hook de save. Classe saving/pointer recuperam depois de erro de preview/confirmação, ausência/conflito, STALE, rede/resposta inválida; retry manual funciona, sem retry automático. Duplo clique/operação ativa não duplica confirmação.

Viewports 1440×1000, 820×1180 e 390×844: menor célula medida 48,42px; scrollWidth 1600px; data enviada coincide com alvo nos nove dias testados por viewport. Quando um toast cobre o alvo, o teste espera que desapareça naturalmente e repete o hit-test antes de clicar.

## E. Rollout A/B

| Frontend | Backend | Resultado |
| --- | --- | --- |
| Antigo | Antigo | PASS funcional. |
| Antigo | A | PASS funcional. |
| Novo | A | PASS funcional v1. |
| Novo | B | PASS funcional v1. |
| Antigo | B | PASS de segurança: recusa, sem persistência. |

Contratos repetidos em PostgreSQL local e matriz por browser offline. Assets antigos vêm exatamente da base 9e0e6c...; o backend do browser é simulado, não Supabase/PostgREST real.

Aba antiga continua antiga depois de o servidor servir assets novos; B recusa, reload carrega novo frontend e funciona. RPC de contexto ausente/deploy parcial fecha edição. Resposta perdida não gera retry nem sucesso presumido; reload recupera contexto. Preview A válido pode confirmar em B; pedido DML antigo em espera durante hardening é recusado depois do DDL.

Não se certificou CDN/cache real nem todas as combinações arbitrárias de assets incompletos. São gates operacionais antes de B.

## F. Regressões essenciais e diff final

| Execução final | Total Node | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| Quadro/RH/Ponto-Férias/Medicina/Viaturas/Planeamento/wrapper/acesso | 469 | 468 | 0 | 1 |
| Auditoria independente focada PG | 73 | 73 | 0 | 0 |
| Alertas/Agenda/documentos/reuniões/Horas Extra legado | 24 | 23 | 1 | 0 |
| **Total sem somar reruns** | **566** | **564** | **1** | **1** |

Grupos-pai Node incluídos. Falha única: Agenda já documentada (versions styles v98/app v145), não corrigida. Skip: Excel externo RH_XLSX opcional; **não aprovado**. O browser RH com Excel sintético passou, mas não substitui essa fixture externa.

Browsers: **dez scripts executados, nove PASS e um FAIL/P2 conhecido**. Oito originais passaram: workforce-controlled, rh-frontend, **medicine ORIGINAL**, planning, planning-selection, vehicle-assignment, vehicle-validity e rh-cadastro. Novo audit-quadro-fecho-browser passou. Original workforce-p1-browser falhou novamente no hit-test mobile 09/10 depois de TERMINAR, devido ao toast temporário já confirmado na auditoria anterior. Não foi corrigido nem apresentado como pass; independente espera desaparecimento natural, sem manipular DOM/force-click, e passa.

Medicina original executada sem alteração. O candidato já contém a adaptação de uma linha de fixture Quadro relativa à base; não foram removidas assertions Medicina. RH Windows usa bootstrap temporário/dependências preexistentes.

Ponto: funções legadas não redefinidas; novo Quadro só lê alocações explícitas. **DÍVIDA TRANSITÓRIA INTENCIONAL — REMOVER NO PACOTE 2.**

Diff revisto `507fb139... → d6db2c3...`: exatamente cinco ficheiros e 190 linhas acrescentadas — 21 em cada pós-check, 42 no teste, 102 no relatório e quatro no documento principal. Nenhuma alteração de src/frontend, RPCs A, gate, locks, alerta, Cadastro RH, Ponto ou outros módulos. Checks não corrigem nem escrevem dados; somente recusam privacidade divergente.

Logs em `%TEMP%`: quadro-fecho-global.log, quadro-fecho-acl.log, quadro-fecho-browser.log, quadro-fecho-alertas.log e nove quadro-fecho-*-browser.log. Screenshots offline em primeline-quadro-fecho-browser/primeline-quadro-fecho-regression. Não contêm dados reais e não são versionados.

## G. Novos P0

Nenhum confirmado nesta auditoria local focada.

## H. Novos P1

Nenhum confirmado. P1 ACL fechado e P1 anteriores continuam corrigidos. Não foi feita prova formal de todos os schedules/catálogos possíveis, nem validação real; o diff não invalida a auditoria histórica.

## I. P2/P3 restantes

- Toast temporário sobre alvo mobile e coluna de obra não congelada no scroll; cabeçalho mobile compacto. Data errada/saving preso não reproduzidos no teste independente atual.
- Replay próprio de receipt depois de perda de papel/âmbito: política por decidir, sem nova escrita/cross-tenant.
- Alertas históricos preservados depois de remover origem: navegação/resolução pendentes.
- Ausência criada depois de alocação pode coexistir; ordem inversa recusa. Invariável inversa futura.
- Transação explícita RH multi-op x Quadro pode deadlock 40P01; rollback da vítima. Não generalizar batches sem ordem comum de locks.
- Lock global causa contenção; fairness/starvation sob carga real não certificadas.
- Recuperação A rollback/forward-fix preserva dados, mas regresso B requer rotação autorizada de backups com nomes fixos. Não apagar backups para contornar.
- Cadastro novo RH sem idempotência geral; não repetir automaticamente após resposta perdida.
- Regra de obra encerrada a confirmar; rollback A restaura notifier baseline e risco legado, forward-fix volta a corrigir.
- Agenda preexistente/Excel externo; dívida temporal Ponto. P3 de manutenção de SQL duplicado/UX futura.

Questões permanecem documentadas, não agravadas pelo diff de ACL. Não devem ser confundidas com testes de produto aprovado ou desaparecer do plano operacional.

## J. GO/NO-GO LOCAL — Fase A

**GO LOCAL**, condicionado aos prechecks reais e plano de recuperação/P2 aceites. A mantém compatibilidade antiga e atomicidade. Não aplicar sem autorização própria.

## K. GO/NO-GO LOCAL — frontend

**GO LOCAL**, com P2 do toast/scroll documentado e validação autenticada real obrigatória. Não publicar sem autorização própria; assets/cache e perfil real são parte do gate antes de B.

## L. GO/NO-GO LOCAL — Fase B

**GO LOCAL.** Pós-checks íntegros PASS/PASS e negativos de ACL/triggers/corpos/policies/objetos recusados. B depende de prova operacional privada verdadeira, backup válido desta instalação e autorização separada. Não aplicar com referência reconstituída a partir de B ou drift.

**PACOTE 1 APTO PARA ROLLOUT REAL CONTROLADO.**

## M. Sequência exata recomendada para rollout real

1. **Fixar a release:** candidato d6db2c3..., conferir SHA remoto/base main atual e diff completo do pacote. Se main/catálogo tiver avançado ou surgirem writers/dependências diferentes, parar e rever. Esta auditoria é deste SHA/base, não de futuras integrações.
2. **Preflight real somente leitura:** verificar versão PG, funções/callers/DML dinâmico, owner/ACL/RLS/grants de schema/tabela/coluna, triggers/constraints, índice/default de alertas, estados RH/ausências/responsáveis. Executar `supabase/quadro_controlado_precheck.sql` e guardar fotografia real de alocações/movimentos/conflitos/revisões/alertas/RH/Ponto. Nenhum backfill/correção de legado. Divergência material → parar.
3. **Autorizar A e preparar recuperação:** confirmar janela/escritores/locks e scripts rollback/forward-fix; identificar backups existentes/rotação autorizada. Executar `quadro_controlado_backup.sql` como postgres, confirmar privacidade e exportar backup verificável fora do repositório. Nunca sobrescrever cópias.
4. **Aplicar A autorizada:** conteúdo raw integral de `quadro_controlado_fase_a.sql`, preservando delimitadores, uma transação. Falha → confirmar rollback e parar. Executar `quadro_controlado_fase_a_postcheck.sql`, comparar fotografia/grants/compatibilidade/RH/Ponto/alertas. Só avançar com checks aprovados.
5. **Publicar frontend autorizado:** integrar somente o candidato revisto em main pelo método aprovado conforme base atual; push/deploy dependem dessa autorização. Confirmar SHA/assets realmente servidos e cache-busting. A continua a suportar abas antigas durante esta etapa. Não aplicar B antes disso.
6. **Validar real em A:** utilizadores/perfis autorizados e sem escrita, empresa/obra/colaborador/ausência, desktop/tablet/mobile/dispositivo, data visual/payload, saving/retry manual, histórico/autor/data/alertas, RH e Ponto. Operações que alterem dados reais exigem plano/autorização explícitos; usar testes sintéticos controlados com rollback quando apropriado. Conferir console/network, respostas perdidas, cache/reload e versão servida. Parar se qualquer P0/P1.
7. **Registar prova privada:** apenas depois da validação verdadeira, operador postgres executa `quadro_controlado_marcar_frontend_validado.sql` para a instalação/tentativa/contrato atuais. Não usar GUC/payload como substituto nem registar confirmação sem evidência.
8. **Pré-check e backup B:** executar `quadro_controlado_fase_b_precheck.sql`; executar `quadro_controlado_fase_b_backup.sql`, validar snapshot privado da A/prova e todas as attacl da referência, exportar cópia. Não aceitar backup de instalação anterior nem fabricar referência de um B já instalado. Backups com nomes existentes exigem arquivo/rotação autorizados.
9. **Aplicar B separadamente autorizada:** `quadro_controlado_fase_b.sql` integral/raw. Falha de statement → confirmar rollback e parar. Executar `quadro_controlado_fase_b_postcheck.sql` e alias `quadro_controlado_postcheck.sql`; ambos devem passar, com marker consumido e acesso da aplicação fechado. Comparar fotografia real antes/depois.
10. **Aceitação operacional B:** novo frontend funciona; aba/API antiga/DML direto recusam de modo seguro; Cadastro/Importação, alertas/destinatários, histórico, Ponto e restantes módulos preservados. Nenhum grant inesperado na referência. Não manter writes de teste persistentes.
11. **Monitorizar/encerrar:** verificar erros/23505/locks/contenção/retries; manter backups, fotografia e evidência. Se pós-check/validação falhar, parar e usar somente o plano de rollback previamente autorizado, sem reparar SQL/dados por improvisação. Brollback invalida a prova; nova tentativa/forward-fix requer validação/prova atuais. Recuperação após reconstruir A exige rotação de backups explicitamente planeada.

Esta sequência é recomendação, não ações executadas nesta tarefa. Commit/push somente relatório/testes desta auditoria; nenhum SQL real, deploy ou merge.