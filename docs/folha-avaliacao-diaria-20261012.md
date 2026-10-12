# Avaliação diária de horário personalizado — preparação local

## Estado e escopo

Branch `feat/folha-avaliacao-diaria-20261012`, criada de `origin/main` em `1c5fa5b7874a7ac8c3da9a11999b6f068c0e2bf0`.

Este pacote prepara somente backend, scripts de rollout e testes. Não inclui a branch anterior do botão FALTA, não altera frontend e não executa qualquer SQL na produção. Não ativa empresas na migration. A ativação dos testes ocorre exclusivamente em clusters PostgreSQL descartáveis com pessoas/obras sintéticas.

## Ficheiros SQL completos

- `supabase/folha_avaliacao_diaria_precheck.sql`: transação READ ONLY, conflitos de nomes, baseline completa das funções, owner/definer/search_path, horários válidos e catálogo atual.
- `supabase/folha_avaliacao_diaria_backup.sql`: schema privado `primeline_diaria_backup`, cópias lógicas das tabelas envolvidas, ledger, funções completas/ACL/owners, colunas/defaults/ACL, constraints, triggers/policies/índices.
- `supabase/folha_avaliacao_diaria.sql`: migration transacional completa, funções completas, novas RPCs, guards, RLS e ACL. Recusa backup ausente, exposto ou divergente. Não usa substituição textual de funções instaladas.
- `supabase/folha_avaliacao_diaria_postcheck.sql`: READ ONLY; exige instalação ainda sem ativação, dados/ledger idênticos ao backup, schema exato, SHA-256 de funções, ACL de tabela/coluna, helpers privados e triggers ativos.
- `supabase/folha_avaliacao_diaria_rollback.sql`: reversão completa antes do uso, restaura definições/owners/ACL e a constraint anterior. Preserva backup privado. Recusa após ativação, versões, avaliações ou alterações nos dados; não apaga factos nem história para forçar uma reversão.

O pós-check de instalação e o rollback não devem ser utilizados como se fossem scripts de processamento diário depois da ativação.

## Modelo

`folha_horarios` mantém a configuração atual. `folha_horarios_versoes` guarda configuração, revisão, snapshot, vigência DATE `[vigente_desde,vigente_ate)`, autor/data/request/motivo. As versões são imutáveis, exceto o encerramento de vigência controlado. O lock da obra e o trigger impedem sobreposição; versões substituídas na mesma data podem ter intervalo vazio e permanecem referenciáveis.

`folha_avaliacoes_diarias` tem uma linha por empresa/colaborador/data, com revisão, referência congelada, snapshot da permanência e horário, FK da versão, contexto/corte, minutos diários, estado, pendências, decisão HE, autoria e fingerprints. Identidade imutável. FKs de pessoas referenciam `colaboradores`; todos os autores referenciam `utilizadores`. As FKs de permanência, obra e versão preservam referências históricas. Os guards validam tenant e identidade.

Não existe novo estado principal `he_aguarda_processamento`. Estados principais: `regular`, `horas_em_falta`, `potencial_he`, `referencia_pendente`, `intervalo_aberto`, `conflito`, `outras_pendencias`, `inativa`.

HE: `nenhum`, `nao_avaliavel`, `pendente`, `validada`, `nao_considerada`.

- `pendente`: `he_diaria_pendente`; bloqueia validação/fecho.
- `validada`: estado `potencial_he` e `he_validada_aguarda_processamento`; continua a bloquear.
- `nao_considerada`: remove somente as duas pendências específicas de HE; outras pendências mantêm o bloqueio.

Não são criadas HE por destino, nem linhas em `folha_he`, nem pagamentos para dias personalizados/mistos. Uma conversão de dia normal que já tenha histórico em `folha_he` é recusada com `NORMAL_HE_REQUIRES_ADMIN_REVIEW`; preserva a HE anterior para tratamento explícito.

## Corte e referência

A configuração da empresa recebe quatro campos de ativação inicialmente NULL. `daily_activation` exige data atual de Lisboa, revisão da configuração e confirmação; guarda autor/data/request, cria versões-base dos horários existentes a partir desse dia, sem backfill. Não é possível mover posteriormente esse corte pela aplicação.

Na primeira confirmação personalizada:

1. resolver a única permanência principal da pessoa válida na data;
2. resolver a versão de horário dessa obra válida na mesma data;
3. congelar ambos os snapshots e contexto na mesma transação dos factos.

Abaixo do corte, sem permanência inequívoca ou sem horário vigente comprovado, gravar referência pendente, expected NULL e motivo explícito. Nunca selecionar uma obra visitada como origem por conveniência.

Alterações posteriores de horário/equipa e edições dos intervalos mantêm a referência congelada. Remover o último personalizado desativa a avaliação; reintroduzir reativa a mesma identidade/referência. Correções comprovadas exigem a ação administrativa explícita, motivo e evidência, e não modificam os intervalos factuais.

## RPCs e operações

Mantém-se `fn_folha_operar_v2('periods_save', dados, confirmar, token)` com versão 2, request UUID, pessoa/data, `sites` e revisões factuais. Para um dia com personalizado ou uma avaliação anteriormente existente, acrescentar `expected_daily_revision` (0 no primeiro registo).

Cada intervalo personalizado usa `mode: "personalizado"`, `period: null` e start/end exatamente fornecidos. Não é dividido. Nos factos por destino que incluem personalizado, expected_minutes permanece NULL. Intervalos normais mantêm a classificação existente. Limites: quatro destinos e dezasseis intervalos no dia. O plano tem de incluir todos os destinos factuais anteriores, incluindo os que são esvaziados.

O preview não escreve; o token inclui plano, revisões factuais, avaliação corrente e referência candidata. Confirmação grava factos e avaliação atomicamente. Revisão antiga/token inválido recusam a operação. Mesmo request/payload confirmado devolve o resultado anterior; payload diferente recusa.

`fn_folha_diaria_gestao_v2(acao,dados,confirmar=false,token=NULL)` e o wrapper `fn_folha_gestao_v2` usam o mesmo protocolo versão 2:

- `daily_activation`: date atual + expected_revision da configuração.
- `configure_schedule`: work_id, intervals normais, expected_minutes, expected_revision atual; vigência somente hoje. Datas passadas/futuras neste caminho recusadas.
- `schedule_retro_correct`: work_id, version_id, expected_revision da versão, vigente_desde anterior a hoje e não anterior ao corte, intervals/expected_minutes e reason obrigatório. Preview lista avaliações afetadas; nenhuma é reescrita. A configuração atual só é atualizada se a correção abranger a versão corrente.
- `daily_reference_correct`: person_id/date, expected_revision diária, schedule completo, evidence não vazia, reason e work_id opcional comprovado.
- `daily_he_validate` / `daily_he_disregard`: person_id/date, expected_revision diária e reason obrigatório. Guarda decisão, autor, data e fingerprint; motivo não é escolhido pelo Encarregado.

As novas decisões, ativação e correções exigem Administrativo/Gestão, reutilizando `folha_privado.adm()`. A configuração normal conserva os perfis administrativos já autorizados. Tenant/ator ativo são verificados também em replay. Nenhuma função interna nova tem EXECUTE para roles da aplicação. Leitura das tabelas novas é feita pelos readers autenticados existentes com escopo, não por SELECT direto.

## Avaliação, história e fecho

Quando existe personalizado, somar uma única vez todos os factos normais/personalizados da pessoa na data. Exemplo A=4h/B=1h30/C=1h30: realizado 420 minutos, esperado único 480, falta 60. Um intervalo 10:30–14:30 permanece um facto de 240 minutos.

O fingerprint SHA-256 é calculado no servidor sobre arrays posicionais: versão, empresa/pessoa/data, linhas ordenadas por UUID com collation C, revisões, destino, intervalos na ordem original (ordinal/start/end/period/mode), revisão especial e ausências relevantes. NULL é JSON null. Fingerprint/regra são versionados. A decisão HE vincula esse hash à revisão e snapshot de referência. Alterações relevantes invalidam a decisão corrente; a anterior permanece no histórico imutável.

Ações novas em `folha_gestao_historico`: ativação, criação/recálculo/desativação/reativação da avaliação, correção de referência, validação/desconsideração/invalidação HE e correção retroativa de horário.

`payroll_facts` prevalece com avaliação diária nos dias personalizados/mistos; folhas por destino deixam de gerar gate paralelo por carga esperada. Dias exclusivamente normais mantêm a estrutura do snapshot anterior, sem acrescentar arrays vazios que invalidariam competências antigas. Dias especiais, conflitos, referência pendente e horas em falta continuam bloqueantes.

Fecho/validação recusam HE pendente e validada não processada. Competência fechada/exportada recusa alterações; a reabertura existente continua necessária. Nenhum cálculo monetário foi adicionado. A futura integração de processamento HE precisa de contrato próprio e vínculo auditado antes de resolver `he_validada_aguarda_processamento`.

Dia Normal não completa automaticamente um dia personalizado: exige editor explícito; não altera equipa nem horas existentes. Os readers expõem avaliação diária mínima e a gestão expõe detalhe autorizado. O frontend ainda precisa de adaptação separada para enviar modo/revisão diária e apresentar os novos estados; este pacote não deve ser ativado com um cliente incompatível.

## Testes e limitações

Execução em PostgreSQL 17.6 local, com duas ligações independentes. A fixture instala a baseline versionada do main e a migration completa, sem stubs das funções novas. Os cenários históricos usam exclusivamente dados sintéticos de um segundo tenant.

Cobertura: instalação inativa, precheck/backup/postcheck/rollback, ACLs de tabela/coluna, função alterada, trigger disabled, constraint retirada, normal, 8h/7h30/9h, HE/fecho, misto/multiobra, intervalo único, edição, snapshots, vigências retroativas/correção, pré-corte/sem origem, desativação/reativação, limites, preview, revisão/token, idempotência, permissões, GUC falso e concorrência real.

Os resultados finais e comandos ficam registados ao concluir a execução. Skips/falhas de ambiente ou testes antigos não serão contados como aprovados.

## Aplicação futura — ainda não autorizada

Revisar este commit → precheck real read-only → autorização de backup → backup real → autorização de migration → migration/postcheck sem ativação → cliente compatível e validação autenticada → autorização explícita de ativação por empresa na data efetiva. Não executar agora qualquer um desses passos reais.
## Resultados finais — 12/10/2026

- Novo pacote: **51 testes PASS, 0 FAIL, 0 SKIP**, em PostgreSQL 17.6 nativo local. Inclui três cenários com duas ligações independentes e prova de espera por lock real em `pg_stat_activity`.
- A configuração normal foi testada também através de `createAttendanceManagementClient` real contra as RPCs PostgreSQL. A revisão de `folha_horarios` mantém incremento +1 para compatibilidade; `version_revision` é a sequência própria das versões e pode diferir após uma correção histórica.
- Regressão unitária/SQL existente: **222 PASS**, uma suite terminou por ausência de `QUADRO_POSTGREST`. A prova REST local correspondente não foi concluída nem contada como aprovada. Nenhuma ligação HTTP à produção foi usada como alternativa.
- Browsers offline aprovados: `attendance-sheet` (57), `attendance-visible-state` (126), `attendance-adm-rules` (75 grupos), `attendance-consolidation` (48 grupos), `attendance-reconciliation-state` (81), `encarregado-fecho-final` (170), `encarregado-tablet-ux` (89). Todos reportaram zero erros JS. São provas com mocks, separadas das provas PostgreSQL.
- Dois browsers antigos falharam sobre ficheiros idênticos ao main: `attendance-security-visibility` espera a aba `tasks` já removida; `folha-equipa-operacional` só implementa `save` no mock e não `periods_save`, aguardando `facts.p` que nunca é preenchido. Não foram corrigidos neste pacote.
- Nenhum ficheiro de `src/`, HTML ou CSS foi modificado; o frontend e os dois browsers antigos são byte-identicamente os do main de base.
- Scripts de precheck/backup/migration/postcheck/rollback executados apenas no cluster sintético. Rollback vazio e reinstalação passaram. Depois da ativação sintética, o rollback recusou destruir versões/avaliações/histórico.
- Nenhum SQL real, ativação real, deploy, merge ou push.

Comando novo:

```text
node --test tests/attendance-daily-backend.test.mjs tests/attendance-daily-static.test.mjs
```

Regressão executada:

```text
node --test tests/attendance-backend-v2.test.mjs tests/attendance-domain.test.mjs tests/attendance-v2-static.test.mjs tests/attendance-rollout-consolidated.test.mjs tests/folha-equipa-operacional.test.mjs tests/folha-equipa-ui-contract.test.mjs tests/encarregado-fecho-final.test.mjs tests/encarregado-tablet-ux.test.mjs tests/encarregado-escopo.test.mjs
```

Para reproduzir: `QUADRO_PG_BIN` aponta para PostgreSQL 17.6 completo, `QUADRO_TEST_DEPS` para o módulo `pg`; browsers usam `PLANNING_PLAYWRIGHT` e `PLANNING_CHROMIUM_EXE`. Não há credenciais nem dados de produção nestes testes/fixtures.

**GO para revisão técnica local do pacote preparado. NO-GO para aplicação/ativação real nesta etapa:** exige revisão/autorização separada, precheck real atualizado e cliente compatível antes da ativação. As limitações de regressão acima permanecem explicitamente abertas.