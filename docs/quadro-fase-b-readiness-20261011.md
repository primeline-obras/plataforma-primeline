# Fase B atualizada — preparação local de 11/10/2026

## Decisão e isolamento

Base exata: `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`.
Branch: `chore/fase-b-readiness-20261011`.

Pacote apto para revisão local. Não constitui autorização nem prova de prontidão do catálogo atual de produção. Nenhuma consulta ou escrita em produção foi realizada nesta tarefa. Nenhum ficheiro frontend, jornada, ligação RH ou dado real foi alterado. Main, deploy e gates reais permanecem intactos.

## Diagnóstico dos scripts anteriores

`quadro_controlado_fase_b*` pressupõe o catálogo, policies e backup da Fase A original de 01/10. Recria policies e concede EXECUTE a um helper interno. Essas escolhas não preservam integralmente o catálogo posterior ao hotfix e à Folha V2.

`quadro_fase_b_pos_hotfix*` preserva policies, mas usa o checkpoint documental/gate e release anterior `pacote2_folha_v2_20261005`. Não representa o cutover CLOSED, equipa persistente, externos e fecho final de 11/10. Não foi adaptado para aceitar artificialmente os novos fingerprints.

Os scripts antigos não foram substituídos. O pacote novo tem backup, contrato e estado próprios, sem consumir marcadores antigos.

## Writers e fronteira de encerramento

| Caminho | Tratamento |
| --- | --- |
| `fn_quadro_operar(text,jsonb,boolean,text)` | API antiga: retirar EXECUTE de PUBLIC, anon, authenticated e service_role; manter definição para rollback. |
| DML direto em `quadro_pessoal_alocacao` e `quadro_pessoal_movimentos` | Retirar INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER e grants de coluna de escrita. Preservar SELECT e policies. |
| `fn_equipa_operar_v2` | Preservar corpo, ACL, tenant, revisão, permanências e auditoria. |
| `fn_quadro_operar_v1` | Preservar: integra operações de equipa V2 e o caminho diário controlado. Não é o writer obsoleto acima. |
| `fn_quadro_aplicar_interno` e `fn_registar_movimento_quadro` | Preservar caminhos internos controlados e trigger de movimentos. |
| `fn_criar_colaborador_com_alocacao` e helper interno | Preservar as duas assinaturas e o fluxo de cadastro RH com alocação controlada. |
| `fn_folha_operar_v2`, RPCs de leitura e `folha_privado` | Preservar integralmente. |
| Writers antigos de Ponto | Permanecem instalados quando necessário ao contrato legado; o trigger CLOSED continua a impedir escrita. Leituras legadas não são retiradas. |

A função `fn_quadro_proteger_escrita` passa a exigir a capacidade privada da mesma transação, pessoa, data e utilizador. Impede também trocar ID/pessoa/data num UPDATE. O proprietário não recebe exceção para DML direto sem essa capacidade.

A busca residual local encontra quatro definições que escrevem diretamente alocações/movimentos: equipa V2, aplicação interna, trigger de movimentos e API antiga. O precheck recusa outro writer direto não inventariado. Os caminhos indiretos acima são preservados e exercitados. Esta busca é focada nesta classe, não uma auditoria geral da plataforma.

Nenhum GRANT é feito pela migration. Nenhuma policy é criada, removida ou modificada. Se um papel de aplicação herdar DML de outro papel, a migration aborta integralmente; não altera memberships por iniciativa própria.

## Encarregado antes e depois

`ENCARREGADO_BEHAVIOR_UNCHANGED = YES`

| Comportamento atual | Antes | Depois |
| --- | --- | --- |
| Gestão visual do Quadro | Somente leitura | Somente leitura |
| Contexto Quadro, Folha e pessoas disponíveis | Mesmo âmbito | JSON idêntico |
| Preview de inclusão em equipa V2 | Permitido no âmbito | Idêntico |
| Preview de compatibilidade de equipa via Quadro v1 | Conforme contrato atual | Idêntico |
| Outra obra sem responsabilidade | Recusada | Mesma recusa |
| Capacidade privada de escrita | Inacessível | Inacessível |
| Folha própria, equipa, retirada e transferência | Funcionais | Funcionais; horas preservadas |
| Multiobra, externos, histórico e revisão | Funcionais | Funcionais |
| EXECUTE dos RPCs atuais | ACL atual | Idêntico |
| Writer legado da Folha | CLOSED | CLOSED |

Distinção necessária: o encerramento do DML legado é intencional. Um UPDATE/DELETE sem linhas autorizadas podia devolver zero linhas por RLS; depois devolve 42501 por falta de privilégio. Em ambos os casos não altera factos. O teste compara esse efeito como `BLOCKED_NO_CHANGE` e testa separadamente a recusa explícita depois da Fase B. A API obsoleta perde EXECUTE. Isto não retira uma ação atual da interface do Encarregado nem concede gestão global.

## Scripts novos e ordem

1. `supabase/quadro_fase_b_20261011_precheck.sql` — REPEATABLE READ READ ONLY; resultado `QUADRO_B_20261011_PRECHECK_OK`.
2. `supabase/quadro_fase_b_20261011_backup.sql` — backup privado novo; resultado `QUADRO_B_20261011_BACKUP_OK`.
3. `supabase/quadro_fase_b_20261011.sql` — migration transacional; resultado `QUADRO_B_20261011_MIGRATION_OK`.
4. `supabase/quadro_fase_b_20261011_postcheck.sql` — REPEATABLE READ READ ONLY; resultado `QUADRO_B_20261011_POSTCHECK_OK`.
5. `supabase/quadro_fase_b_20261011_rollback.sql` — apenas preparado para execução manual autorizada; resultado `QUADRO_B_20261011_ROLLBACK_OK`.

Qualquer erro exige STOP. Não executar o passo seguinte nem rollback automático. O precheck requer estado A, writer legado CLOSED, triggers e policy restritiva esperados, capacidades privadas e contrato de 78 funções atuais (definição, owner, ACL e search_path). A referência é reconstruída localmente a partir dos artefactos commitados; um novo catálogo real é condição necessária antes de autorizar execução real.

O backup cria `primeline_quadro_b_20261011` privado e não substitui backups existentes. Guarda catálogo completo dos schemas public/folha_privado, ACL de tabela/coluna/função, owners, policies, RLS, triggers, constraints e índices. Copia 26 tabelas operacionais para tabelas tipadas e calcula hashes SHA-256 das linhas completas. Não usa contagens antigas fixas como prova de integridade atual.

A migration bloqueia as tabelas durante a janela transacional, exige igualdade com o backup e verifica que só o guard e ACL legada mudaram. O postcheck exige igualdade integral dos dados, privacidade do backup, estado/control corretos e catálogo aplicado. Nem horas nem permanências são reescritas.

## Rollback

Restaura a definição anterior do guard e ACL exatas da API antiga e das duas tabelas/colunas, incluindo grant options. Preserva policies e factos criados legitimamente depois da Fase B. Não copia dados antigos por cima de dados laborais novos.

Exige catálogo aplicado sem drift, verifica o catálogo restaurado e repõe o estado de controlo anterior. Guarda a evidência privada como `rolled_back`; não permite reutilizá-la para reinstalação automática. Um novo ciclo real exige preparação revista.

## Evidência local

PostgreSQL 17.6 descartável, ligado exclusivamente a localhost; fixtures sintéticas. Nenhum teste depende de credencial de produção.

- Matriz atual expandida: **32 PASS / 0 FAIL / 0 SKIP**, incluindo precheck → backup → migration → postcheck, comportamento antes/depois, Gestão, Diretor/Adjunto/Preparador, cadastro RH, Folha própria, equipa, retirada/transferência preservando horas, multiobra, externos, concorrência, stale revision, replay, negativas e rollback após novos factos.
- Runner do pacote: **2 PASS / 0 FAIL / 0 SKIP**; exige PostgreSQL configurado, sem SKIP silencioso.
- Regressões relacionadas (runner incluído): **232 PASS / 0 FAIL / 0 SKIP**. Os 32 testes da subprocess suite são apresentados separadamente, sem somá-los duas vezes.
- Suites: attendance-domain, attendance-v2-static, folha-equipa-ui-contract, encarregado-tablet-ux, workforce-allocation-client, workforce-controlled, workforce-admin-only, workforce-foremen-multiple-works, session-boundary e session-isolation.
- As regressões históricas workforce-controlled continuam úteis, mas a prova do pacote novo é a matriz atual expandida, executada depois da nova migration.
- Casos de drift de contrato, writer desconhecido, marker exposto, legado aberto, DML herdado, backup desatualizado, backup privado exposto e alteração posterior de dados abortam conforme esperado.

O runner reutiliza o bootstrap atual aprovado e escreve apenas a suite expandida e logs sintéticos num diretório temporário fora do Git. O manifest de funções contém definições de catálogo, não dados pessoais. Nenhum screenshot adicional é necessário para uma alteração sem frontend; os contratos visuais existentes permanecem testados.

## Verificação em segunda worktree

Após commit e push, repetir o mesmo runner e regressões num checkout limpo do commit da branch, sem instalar SQL real. Confirmar SHA, working tree limpo e sequência completa local. O resultado dessa repetição e o SHA remoto são entregues no relatório final da tarefa.

## Limites e gate seguinte

GO para revisão independente local. Execução real permanece não autorizada nesta tarefa. Antes de qualquer rollout futuro, confirmar o catálogo real contra o precheck novo e rever janela de locks/backup, capacidade de armazenamento e autorização expressa.

O snapshot de catálogo preserva também objetos periféricos, mas fixtures locais não substituem uma validação factual de todos os subsistemas em produção. Não foi demonstrado qualquer novo acesso do Encarregado. Main, frontend publicado, jornadas e ligações RH não foram tocados.

`READY_FOR_PHASE_B_REVIEW = YES`
