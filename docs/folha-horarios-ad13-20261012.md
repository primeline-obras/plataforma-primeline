# AD-13 — coerência dos horários — 12/10/2026

## Resultado e base

**AD-13 CORRIGIDO LOCALMENTE.** O módulo continua sem GO global: AD-03 não foi iniciado e permanece pendente. Nenhum SQL real, ativação real, push, merge ou deploy.

Base exata: fix/folha-avaliacao-constraints-20261012, 12e87b89026348c00dcec37b47ffaca6b3e64d24. Ancestral AD-15 e74ed66fa06985ca55b5ad1148c4c4670a07809e confirmado. Repositório primeline-obras/plataforma-primeline e working tree limpo confirmados antes de criar fix/folha-horarios-coerencia-20261012.

Todas as implementações/migrations originais e os ficheiros AD-14/AD-15 são preservados. O pacote AD-13 é aditivo; a sua migration publica uma definição completa da RPC cumulativa, com cinco alterações estritamente ligadas aos horários e todos os blocos AD-15 preservados.

## Contrato e diagnóstico antes de implementar

- public.folha_horarios (supabase/folha_ponto_v2.sql): configuração por obra, intervalos JSONB, expected_minutes inteiro 1–1440 e revisão.
- public.folha_horarios_versoes (supabase/folha_avaliacao_diaria.sql): snapshot, vigência [desde,até), revisão e autoria. Conteúdo histórico imutável; encerramento da vigência permitido pelo contrato.
- configure_schedule já exige soma dos intervalos=expected, dois períodos distintos manha/tarde e intervalos completos.
- schedule_retro_correct usa a mesma validação e preserva referências capturadas; daily_reference_correct admite uma referência administrativa com intervalos livres, motivo e evidência.
- diaria_referencia obtém expected da versão vigente na data; diaria_recalcular congela essa referência/snapshot e avalia os factos sem recapturar uma versão nova por simples alteração posterior.

Não foi encontrada uma exceção implementada que permita expected diferente da soma dos intervalos em folha_horarios ou no snapshot normal. A pausa entre os períodos não integra a soma. Dias especiais têm tratamento factual/revisão próprio; não são um offset oculto da jornada formal. A carga de Escritório é configuração separada (office_expected_minutes) e não foi submetida a uma regra de igualdade com intervalos inexistentes.

Contrato normal: dois intervalos completos, sem sobreposição; primeiro cronológico manha, segundo tarde; mode ausente ou normal; carga igual à soma. Não foi inventada uma fronteira fixa às 12h nem uma carga fixa de 8h. Uma jornada de 4h em dois períodos também é válida.

Referência administrativa: pode continuar a usar 1–16 intervalos completos, sem impor dois períodos normais. A soma precisa corresponder à carga documentada; a evidência e os restantes controlos continuam no AD-14/AD-15.

Causa AD-13: daily_activation fazia PERFORM folha_privado.facts(...) e descartava minutes/open/classificação. Podia copiar uma configuração contraditória para a versão histórica. As tabelas também só tinham checks de forma superficiais. Além disso, facts aplica relógio/futuro dos factos laborais; essa regra não é apropriada para validar um template formal ainda antes do fim do dia.

Reprodução original feita com AD-15 + AD-14 instalados, antes do AD-13: dois intervalos somavam 240 minutos, expected=480; ator Administrativo da empresa legítima; confirmação committed=true e snapshot de versão expected=480. Prova observada na transação e revertida por rollback. AD13_BEFORE marcou contract=FAIL. Os 132 testes observacionais antes não constituem aprovação do bug.

## Implementação

Novos helpers privados:

1. horario_ad13_valido(jsonb,boolean): IMMUTABLE/invoker. Valida objeto, array, valores numéricos inteiros, SQL NULL/JSON null, início/fim HH:MM, duração positiva, sobreposição, soma, limites e classificação normal quando aplicável. Não depende de relógio/data atual.
2. horario_ad13_factos(jsonb,boolean): devolve duração já validada e open=false, ou 23514 SCHEDULE_INCOHERENT. Usado exclusivamente na validação formal; facts dos factos laborais permanece intacta.
3. horario_ad13_guardar(): trigger invoker; impede ativação direta com configuração incoerente e captura de referência com snapshot/carga incoerentes.

Garantias adicionais:

- CHECK folha_horario_ad13_coerencia em folha_horarios.
- CHECK folha_versao_ad13_coerencia em folha_horarios_versoes.
- Trigger BEFORE INSERT/UPDATE folha_diaria_ad13_ativacao em folha_config_empresa.
- Trigger BEFORE INSERT/UPDATE folha_diaria_ad13_referencia em folha_avaliacoes_diarias.

A RPC cumulativa fn_folha_diaria_gestao_v2 foi preparada integralmente a partir da definição corrigida AD-15. Cinco alterações verificadas pelo gerador:

- lock de folha_horarios antes do preview/snapshot, depois do lock global existente;
- validação de todos os horários da empresa antes de construir o preview de ativação;
- validação formal de configure_schedule/schedule_retro_correct;
- validação formal livre de daily_reference_correct;
- repetição da validação ao criar cada versão na confirmação da ativação.

Ao reverter em memória exatamente estas cinco substituições, o gerador exige igualdade integral com a RPC AD-15. Não há delta adicional dos blocos de tenant/permissões/autoria/revisão/idempotência/HE. Todas as funções AD-14 são idênticas e conferidas contra o backup.

Nenhuma configuração ou linha de negócio é atualizada automaticamente na instalação. Não se altera facts, os cálculos de realizado/falta/HE/salários, nem a recusa de horas futuras nos factos reais. Templates formais podem conter o restante horário do dia sem FUTURE_TIME indevido. Datas de vigência, retroatividade, motivo, tenant e permissões existentes continuam obrigatórios.

## Scripts completos e ordem

Cinco ficheiros novos supabase/folha_horarios_ad13{,_precheck,_backup,_postcheck,_rollback}.sql:

1. Precheck READ ONLY → AD13_PRECHECK_OK: exige base AD-15/AD-14, metadados/hashes e ausência de instalação parcial; analisa configurações, versões e referências capturadas. Qualquer incoerência exige STOP com tipo/UUID, sem nomes/valores financeiros nem correção automática.
2. Backup → AD13_BACKUP_OK: schema privado primeline_ad13_backup; RPC original completa/metadados, definições/ACL AD-14, oito tabelas e ledger integral. Sem substituir backup anterior.
3. Migration → AD13_MIGRATION_OK: repete gates e comparação dos dados; instala helpers/checks/triggers e RPC completa; verifica catálogo/hashes/ACL e igualdade integral dos dados.
4. Postcheck READ ONLY → AD13_POSTCHECK_OK: RPC/helper/checks/triggers exatos, todas as jornadas/snapshots coerentes, backup privado e dados/ledger preservados. Exige expressão exata das CHECKs, deteta CHECK(true) e trigger desativado.
5. Rollback → AD13_ROLLBACK_OK: somente manual; recusa uso/drift desde backup; restaura a definição AD-15 anterior e remove exclusivamente objetos AD-13. AD-14 preservado. Não apaga nem restaura dados laborais sobre atividade posterior.

Ordem futura condicionada: diário original → AD-15 → AD-14 → AD-13; cada etapa usa os seus próprios precheck/backup/migration/postcheck. Nenhuma ativação real enquanto AD-03 não estiver resolvido e não houver autorização.

Os gates antigos continuam com hashes exatos do respetivo predecessor. Depois do AD-13, os rollbacks AD-15/AD-14 devem recusar a RPC mais recente; não se alteraram hashes antigos para os fazer passar. Reversão, se autorizada e segura: AD-13 primeiro, depois eventualmente AD-14/AD-15. Rollback nunca automático.

## Testes antes/depois e regressões

Ambiente PostgreSQL 17.6 descartável em localhost, dados sintéticos. Runner tests/attendance-daily-ad13.test.mjs reutiliza os runners anteriores em memória e não altera os testes AD-14/AD-15.

- **164 PASS / 0 FAIL / 0 SKIP** na matriz cumulativa final, incluindo AD-14, AD-15 e regressões backend originais.
- **43 PASS / 0 FAIL / 0 SKIP** nas regressões adicionais de domínio, cliente, sessão e contratos estáticos.
- **Total final: 207 PASS / 0 FAIL / 0 SKIP.** Os 132 testes observacionais before não são somados novamente.

Provas:

- Jornadas normais de 480 e 240 minutos configuradas/ativadas pela RPC: PASS; versões correspondem exatamente à configuração; replay não duplica.
- Cenário original 240/480: depois, 23514 em preview e confirmação, zero alteração parcial da configuração/versões/histórico/ledger.
- Sobreposição, horários/intervalos inválidos, campos ausentes, esperado textual/fracionário/zero, períodos duplicados/invertidos/null, modo personalizado indevido e arrays vazios: recusados.
- SQL NULL versus JSON null em snapshot/intervalos/carga: explicitamente recusados.
- Snapshot histórico incoerente recusado pela constraint de tabela, antes de ser congelado.
- Referência administrativa livre coerente continua permitida; snapshot incoerente da avaliação é recusado.
- Template formal com horas ainda futuras no dia: aceite; regra de futuro dos factos laborais não foi removida.
- Alteração legítima 4h cria nova versão; snapshots anteriores e avaliações congeladas integralmente preservados.
- Concorrência, request repetido, payload diferente e revisão stale: comportamentos anteriores preservados.
- Registo retroativo usa a versão vigente na data, dias normais, HE, inatividade, regularização administrativa, RLS e tenant: regressões anteriores PASS sob a instalação cumulativa.
- Sequência local precheck → backup → migration → postcheck → rollback → reinstalação: PASS. Rollback após uso recusado sem sobrescrita.
- Postcheck deteta CHECK substituída por true e trigger de ativação desativado.

Adaptações explícitas no runner cumulativo: rollbacks de etapas antigas esperam a recusa por drift da função mais recente; o probe de precheck AD-14 reconstrói o predecessor da RPC dentro da própria transação já isolada, antes de testar o estado inválido, e reverte tudo. Nenhuma asserção de tenant/estado/idempotência foi relaxada; nenhum ficheiro antigo foi alterado.

As 43 regressões estáticas adicionais usam a exportação temporária LF da fonte original, devido à asserção CRLF sensível já documentada. Os ficheiros originais usados são idênticos nesta branch; não houve alteração de frontend/teste antigo.

Reprodução: definir QUADRO_PG_BIN e QUADRO_TEST_DEPS; node tests/attendance-daily-ad13.test.mjs. AD13_STAGE=before reproduz o bug com AD-15+AD-14, sem instalar AD-13. Regeneração: node tests/attendance-daily-ad13-package.mjs.

## Limitações e entrega

- AD-03 permanece bloqueador; não declarar GO global nem ativar o mecanismo.
- Sem catálogo real ou HTTP/JWT novos certificados; identidade SQL da fixture é sintética.
- Horários históricos incoerentes existentes exigem revisão humana separada. Precheck não os corrige.
- Configuração Escritório, calendário especial e factos trabalhados ficam fora da igualdade de template normal desta tabela; nenhum horário é inferido.
- A janela real deve considerar locks/scans/backup e autorização própria. Não houve execução real.
- Os P2 da auditoria original fora desta classe permanecem sem correção nesta tarefa.

Commit apenas local; SHA e working tree final entregues na resposta. Nenhum push, merge, deploy ou alteração de main.
