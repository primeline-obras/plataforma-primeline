# Correção da ACL de coluna da referência privada B

02/10/2026. Branch `feat/quadro-controlado-20261001`. Base: `507fb1390c793b62e9d804e7cbf61445916e0480`. Auditoria: `audit/quadro-controlado-aceitacao-20261002`, `f6c60fce9b6002ef8107d1b2c80a8d00c2d4b25e`.

**GO LOCAL para a auditoria final focada no novo SHA. Não é GO de produção.** Nenhum novo P0/P1 confirmado nesta correção local. P2 anteriores permanecem, incluindo a obstrução temporária por toast no teste mobile original.

Nenhum SQL real, alteração de dados reais, deploy ou merge. Os ensaios PostgreSQL 17.6/PGlite usam dados sintéticos locais; os browsers usam API simulada e não o Chrome pessoal.

## Causa e correção

O grant de coluna altera `pg_attribute.attacl`, não `pg_class.relacl`. O pós-check verificava ACL de schema/tabela da referência, mas a comparação estrutural das colunas não incluía a própria tabela de referência. Por isso grants SELECT/INSERT/UPDATE/REFERENCES nessa referência podiam passar.

Foram acrescentadas somente duas verificações a `quadro_controlado_fase_b_postcheck.sql`, antes de ler `estrutura`:

1. Percorrer **todas** as colunas atuais, não eliminadas, da referência, com `attnum > 0` e `NOT attisdropped`; explodir `attacl` e recusar qualquer grantee ou grantor diferente do owner postgres já exigido pelo check existente. Inclui PUBLIC, roles da aplicação e qualquer outro role. Nenhum nome de coluna hardcoded no check.
2. Recusar privilégio efetivo SELECT/INSERT/UPDATE/REFERENCES de anon/authenticated/service_role via `has_any_column_privilege`, incluindo PUBLIC/herança. O facto de o schema não ter USAGE não é usado para aceitar um grant indevido.

Trecho novo, idêntico no alias:

```sql
IF EXISTS(
 SELECT 1 FROM pg_attribute col JOIN pg_class ref ON ref.oid=col.attrelid
 CROSS JOIN LATERAL aclexplode(col.attacl) acl
 WHERE ref.oid=to_regclass('primeline_backup.quadro_fase_b_estrutura_20261001')
   AND col.attnum>0 AND NOT col.attisdropped
   AND (acl.grantee<>ref.relowner OR acl.grantor<>ref.relowner)
) THEN
 RAISE EXCEPTION 'POSTCHECK_FAILED: ACL de coluna inesperada na referência estrutural privada';
END IF;
IF EXISTS(
 SELECT 1 FROM pg_roles app_role WHERE app_role.rolname IN('anon','authenticated','service_role')
   AND (has_any_column_privilege(app_role.oid,'primeline_backup.quadro_fase_b_estrutura_20261001','SELECT')
     OR has_any_column_privilege(app_role.oid,'primeline_backup.quadro_fase_b_estrutura_20261001','INSERT')
     OR has_any_column_privilege(app_role.oid,'primeline_backup.quadro_fase_b_estrutura_20261001','UPDATE')
     OR has_any_column_privilege(app_role.oid,'primeline_backup.quadro_fase_b_estrutura_20261001','REFERENCES'))
) THEN
 RAISE EXCEPTION 'POSTCHECK_FAILED: privilégio efetivo de coluna da aplicação na referência estrutural privada';
END IF;
```

Só o owner/operador postgres mantém o acesso previsto; os seus privilégios implícitos e grants explícitos exclusivamente de/para owner passam. Não há exceção para outro role ou RPC pública. Não se pretende limitar o superutilizador/administrador da infraestrutura por ACL de aplicação.

## Alias

`supabase/quadro_controlado_postcheck.sql` é byte-idêntico ao pós-check B nesta entrega. Verificação positiva nos testes e SHA256 igual dos ficheiros de trabalho: `7897FC789E1C464C99A461C42D52309776285477D21A6E0A848217F65A56FA79`. Git normaliza LF; o critério de equivalência continua a comparação do conteúdo integral, não uma versão/hash registada como autorização.

## Backup / B / rollback / forward-fix revistos

- Backup B usa CREATE TABLE AS para uma referência nova: as ACL de coluna não são copiadas da origem. Teste confirma attacl NULL em todas as colunas criadas, owner postgres, zero privilégios efetivos dos três roles da aplicação.
- Backup não sobrescreve referência existente; mantém REVOKE de tabela/schema já existente.
- Não existe GRANT legítimo de coluna da referência para a aplicação. O operador lê como postgres; não necessita grant adicional.
- B/forward-fix alteram ACL das tabelas operacionais alocação/movimentos, não da referência.
- `quadro_fase_b_acl_colunas_20261001` fotografa apenas alocação/movimentos. Rollback B restaura essas ACL operacionais; não inclui/restaura grants da referência privada.
- Drift introduzido por um operador na referência não é reparado silenciosamente: o pós-check agora recusa-o. Não foi acrescentada lógica de limpeza automática ou alterado o gate.
- Rollback/forward-fix foram novamente exercitados na suite A/B. O P2 de rotação de backups depois de reconstruir A permanece documentado; não foi corrigido neste escopo.

Nenhuma alteração necessária nos scripts backup/B/rollback/forward-fix.

## Negativos PostgreSQL 17.6

`tests/workforce-controlled.test.mjs` acrescenta 30 testes: uma instalação limpa, 20 combinações role/privilégio, quatro de coluna adicional, quatro de herança e um de owner. Cada cenário executa B **e** alias, em transação isolada, com restauro final.

| Grantee | SELECT | INSERT | UPDATE | REFERENCES |
| --- | --- | --- | --- | --- |
| authenticated | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| anon | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| service_role | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| PUBLIC | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |
| quadro_column_unexpected | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL | FAIL/FAIL |

FAIL/FAIL significa recusa correta de B/alias, não falha do runner. PostgreSQL 17.6 permite os quatro grants de coluna para PUBLIC; `has_column_privilege(anon,...)` prova o privilégio efetivo PUBLIC.

Em cada ataque: relacl igual ao anterior, attacl alterada e `has_column_privilege` true; o pós-check recusa precisamente a ACL de coluna. SAVEPOINT permite remover o grant por REVOKE na mesma transação e provar PASS novamente; ROLLBACK final restaura a fotografia e B/alias voltam a passar.

Coluna adicional sintética `acceptance_extra`: limpa passa; quatro grants authenticated recusados; REVOKE volta a passar. Não é criada em nenhum script de produto. Role pai sintético com grant e membership para authenticated: privilégio herdado comprovado e recusado. Owner postgres conserva os quatro privilégios; grant explícito só de/para owner passa.

O teste original da auditoria foi copiado temporariamente, **sem alterar assertions**, para ler o SQL corrigido deste worktree: **37/37 PASS**, incluindo os quatro casos antes vermelhos. A cópia foi removida; branch/ficheiros da auditoria permanecem intactos. Isto é regressão da prova anterior, não substitui a nova auditoria independente do SHA final.

## Regressões/resultados

| Execução | Total Node | Pass | Fail | Skip |
| --- | ---: | ---: | ---: | ---: |
| Quadro/RH/Ponto-Férias/Medicina/Viaturas/Planeamento/wrapper/acesso | 469 | 468 | 0 | 1 |
| Alertas/Agenda/documentos/reuniões/Horas Extra legado | 24 | 23 | 1 | 0 |
| Reprodução do teste independente da auditoria | 37 | 37 | 0 | 0 |
| **Total, sem somar reruns** | **530** | **528** | **1** | **1** |

A execução isolada Fase A/B passou **160/160**, incluindo novos negativos, gate privado, bodies/triggers/policies, RH/importação/atomicidade e concorrência. Está incluída nos 469, não somada novamente. Contagens Node incluem grupos-pai. Um skip de Excel externo RH_XLSX não é aprovação.

Agenda: falha preexistente de assertions styles v98/app v145, não corrigida nem relaxada. Nenhuma falha nova nos testes Node.

**Browsers originais: oito PASS, um FAIL/P2 conhecido.** Passaram workforce-controlled, rh-frontend, medicine ORIGINAL, planning, planning-selection, vehicle-assignment, vehicle-validity e rh-cadastro. `workforce-p1-browser` voltou a falhar no centro da célula mobile 09/10 após TERMINAR, com toast temporário sobre o alvo, conforme auditoria f6c60fc. Não alterei UX, saving, tablet/mobile ou esse teste. Não declaro todos os browsers verdes.

Medicina original foi executada sem alteração. RH Windows usa bootstrap temporário e dependências existentes. Nenhuma instalação nova necessária. Logs em `%TEMP%`: quadro-column-acl-targeted.log, quadro-column-acl-global.log, quadro-column-acl-alertas.log, quadro-column-acl-audit-replay.log e nove logs quadro-column-acl-*-browser.log. Sem dados reais, não versionados.

## Escopo e próximo passo

Ficheiros desta correção: dois pós-checks, teste Fase A/B, esta documentação e link no documento principal. Sem alteração de A/RPCs/gate/locks/alertas/RH/Ponto/Férias/Medicina/Viaturas/Planeamento/frontend/cache-busting.

`git diff --check` no final. Commit/push apenas na branch candidata solicitada; main, urgent e auditoria não alterados. SHA novo consta da resposta final/commit.

**Novos P0/P1: nenhum confirmado. GO LOCAL para uma auditoria final focada no novo SHA.** Depois dela, se não houver P0/P1, decidir rollout controlado com precheck/backup/autorização separados. Não há GO de produção nem aplicação SQL real nesta entrega.