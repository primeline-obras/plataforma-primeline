# AD-14 — invariantes da avaliação diária — 12/10/2026

## Resultado

**AD-14 CORRIGIDO LOCALMENTE.** Não é GO do módulo. AD-03 e AD-13 continuam pendentes e não foram iniciados. Nenhum SQL real, push, merge, deploy ou ativação real.

Branch isolada: fix/folha-avaliacao-constraints-20261012, criada exatamente de e74ed66fa06985ca55b5ad1148c4c4670a07809e (AD-15). Repositório primeline-obras/plataforma-primeline confirmado; working tree inicial limpo. A implementação original a273227 e a auditoria 396e616d permanecem intactas. Faltas não foi incorporada.

## Diagnóstico

Tabela: public.folha_avaliacoes_diarias, definida em supabase/folha_avaliacao_diaria.sql, linhas 33–66. Catálogo aprovado contém 39 constraints, incluindo PK, UNIQUE, FKs, enums, limites de minutos/revisões, formatos de fingerprints e checks de referência/HE. Todas são preservadas.

Validações adicionais existentes: folha_privado.diaria_guardar (identidade imutável, tenant, FKs/referência), diaria_recalcular (estado/minutos/pendências), diaria_referencia, diária_decisao_hash e RPC administrativa corrigida no AD-15. Os dados são escritos por RPC SECURITY DEFINER; RLS/grants continuam fechados.

Causas:

- CHECK aceita resultado SQL NULL. A expressão excedente_minutes>0 não recusa HE decidida quando esse valor é NULL.
- horario_snapshot IS NOT NULL aceita o valor JSON null, arrays, objetos incompletos e referências sem forma válida.
- Não existe equivalência completa entre estado, referência, minutos, HE e pendências.
- Campos de decisão têm uma validação parcial: uma string com 64 hexadecimais não prova que o fingerprint corresponde à referência/factos atuais.
- Evidência administrativa IS NOT NULL não garante objeto não vazio.

Reprodução antes da instalação AD-14, já com AD-15 instalado: os quatro casos originais foram aceites e revertidos em transações sintéticas. Output AD14_BEFORE: regular com falta; regular com HE pendente; snapshot JSON null; HE validada com excedente SQL NULL. O modo before terminou 63 testes observacionais; isto confirma a reprodução, não aprova os estados inválidos.

## Contrato validado

| Grupo | Invariante |
| --- | --- |
| Enums/identidade/revisões/limites | As 39 constraints originais continuam existentes e validadas. |
| Contexto | Objeto JSON com regra diaria_v1 e data de ativação em formato de data. |
| Revisões factuais | Array de objetos com UUID e revisão positiva; sem IDs duplicados. Array vazio permanece válido quando não existem factos. |
| Pendências | Array unidimensional, sem NULL, texto vazio ou duplicados. Motivos adicionais não são excluídos por um enum novo; continuam a bloquear estado regular. |
| Referência pendente | Expected SQL NULL, horário SQL NULL, sem captura fictícia; motivo presente; origem automática. IDs parciais de origem conhecidos podem permanecer, como no resolver aprovado. |
| Referência capturada | Expected entre 1 e 1440; autor/data/request completos; snapshot objeto com expected numérico igual ao da avaliação e 1–16 intervalos completos em formato válido. |
| Captura automática | Permanência/obra/versão presentes; snapshots objetos; UUIDs de pessoa/empresa/obra/permanência/versão coerentes com a avaliação. |
| Captura administrativa | Motivo e evidência como objeto não vazio; sem permanência/versão automática inventadas. Obra opcional e validação tenant continuam no AD-15. |
| Minutos mensuráveis | Falta e excedente ambos preenchidos e iguais às diferenças não negativas entre esperado e realizado. Não se recalculam factos ou salários. |
| Não mensurável | Referência pendente, intervalo aberto ou conflito: diferenças SQL NULL e HE nao_avaliavel. |
| HE decidida | Excedente explicitamente não NULL/positivo; autor, timestamp, motivo e fingerprint presentes. Fingerprint final deve corresponder à função de decisão aprovada. |
| HE não decidida | Nenhum resíduo de autor/motivo/fingerprint de decisão. |
| Marcadores reservados | referencia_diaria_pendente, horas_em_falta, he_diaria_pendente e he_validada_aguarda_processamento correspondem aos estados respetivos. |
| Estado principal | Mesma prioridade do contrato: inativa → referência pendente → conflito → aberto → falta → potencial HE → outras pendências → regular. |

Regular com excedente explicitamente não considerado continua válido quando não existe outra pendência. Não se exige realizado=esperado nesse caso. HE validada mantém potencial_he e a pendência de processamento. Avaliação inativa continua conservada e fora do gate laboral ativo, sem apagar referência/história.

Não se validou a soma da jornada versus expected, dois períodos de ativação ou a origem técnica AD-03: essas decisões continuam nos bloqueadores separados AD-13/AD-03. O pacote valida a forma/coerência da avaliação e não configura jornadas.

## Correção aditiva

Dois objetos privados novos:

- folha_privado.diaria_ad14_valida(public.folha_avaliacoes_diarias,boolean): SQL, IMMUTABLE, SECURITY INVOKER, search_path pg_catalog. Todos os predicados terminam em IS TRUE, sem aceitação de SQL NULL.
- folha_privado.diaria_ad14_final(): trigger SECURITY DEFINER, search_path pg_catalog, leitura da última versão da linha. Sem DML e sem flags/GUC de autorização.

Duas garantias novas:

1. CHECK folha_diaria_ad14_shape: valida imediatamente snapshots/estrutura/metadados.
2. CONSTRAINT TRIGGER folha_diaria_ad14_final: AFTER INSERT OR UPDATE, DEFERRABLE INITIALLY DEFERRED; valida a coerência final e devolve 23514 quando inválida.

A validação final diferida é necessária porque daily_reference_correct atualiza a referência e depois recalcula a avaliação na mesma transação. CHECK imediato de toda a máquina de estados bloquearia essa regularização legítima. O trigger lê a última linha, não o snapshot intermédio de cada evento. Um COMMIT inválido é recusado mesmo sem SET CONSTRAINTS; SET CONSTRAINTS ALL IMMEDIATE também prova a recusa. Não há bypass/exceção administrativa nem autorização por configuração de sessão.

Nenhuma função original foi substituída, incluindo a RPC AD-15. Nenhum cálculo de minutos/salário foi alterado; nenhuma linha histórica foi apagada/reescrita. Não há alteração de src/, index.html, RLS/policies/grants dos módulos existentes.

## Scripts completos e dependências

Novo pacote: supabase/folha_avaliacao_ad14{,_precheck,_backup,_postcheck,_rollback}.sql.

- Precheck READ ONLY → AD14_PRECHECK_OK: exige AD-15 corrigido/hash/metadados, 39 constraints exatas e validadas, RLS/owner/ACL/guard originais e ausência de instalação parcial. Valida todas as linhas existentes com o contrato novo; qualquer inválida aborta mostrando somente UUIDs. Não corrige dados.
- Backup → AD14_BACKUP_OK: schema privado primeline_ad14_backup; constraints originais, definição/metadados AD-15, sete tabelas relacionadas completas e ledger. Não substitui backup existente.
- Migration → AD14_MIGRATION_OK: repete gates/snapshot, cria somente os dois helpers/duas garantias; REVOKE dos helpers para aplicação; verifica igualdade de dados e preservação integral do AD-15.
- Postcheck READ ONLY → AD14_POSTCHECK_OK: catálogo/definições/volatilidade/SD/ACL/helpers/trigger e 41 constraints exatos; valida dados; compara rows/ledger e AD-15 ao backup.
- Rollback → AD14_ROLLBACK_OK: apenas manual; recusa drift/uso posterior; remove exclusivamente objetos AD-14. Não restaura dados antigos sobre novos. AD-15 permanece instalado; backup privado preservado.

Dependência futura de instalação, não autorização: pacote diário original → hotfix AD-15 → AD-14, cada um com precheck/backup/migration/postcheck no respetivo ponto. Pós-checks antigos com fingerprints originais não substituem os novos pós-checks depois dos hotfixes. Nenhuma ativação enquanto os restantes bloqueadores não forem resolvidos.

Reversão estrutural, se expressamente autorizada e sem uso: AD-14 antes de AD-15; depois, eventualmente rollback do pacote diário. O helper AD-14 recebe o tipo composto da tabela e deve ser removido antes de tentar remover a tabela. Não executar rollback automaticamente.

Gerador reproduzível: tests/attendance-daily-ad14-package.mjs. O precheck usa os mesmos predicados inline em modo READ ONLY, sem criar função para conseguir validar o catálogo. Os scripts contêm definições completas e não remendam corpos instalados.

## Testes finais

PostgreSQL 17.6 descartável em localhost, dados sintéticos; nenhuma conexão/credencial de produção. Runner AD-14 reutiliza em memória o runner AD-15 e o bootstrap original; originais não alterados.

- Matriz final integrada: **131 PASS / 0 FAIL / 0 SKIP**.
- Inclui todos os testes focados AD-15, concorrência/replay/tenant, toda a regressão backend diária e 65 mutações negativas AD-14.
- Quatro casos originais: aceites antes; depois recusados 23514, sem efeitos persistidos.
- Negativos adicionais: SQL NULL/JSON null/arrays/objetos incompletos, carga incompatível, decisão sem autor/motivo/fingerprint ou fingerprint errado, minutos/diferenças, estados/revisões inválidos, pendências fictícias/duplicadas, referências administrativas incompletas.
- Positivos: regular, falta, HE pendente, validada aguardando processamento, não considerada, referência pendente, intervalo aberto, conflito/inatividade e correção administrativa por RPC, sem mudança dos factos.
- COMMIT de estado final inválido recusado; transição intermédia que termina válida aceita; estado final válido é verificado, sem suprimir a transição administrativa.
- Sequência local precheck → backup → migration → postcheck → rollback → reinstalação PASS; pré-check de dados existentes inválidos recusa; rollback após uso recusa drift sem sobrescrever dados.
- Regressões adicionais de domínio/cliente/sessão/contratos estáticos: **43 PASS / 0 FAIL / 0 SKIP**.
- Total final selecionado: **174 PASS / 0 FAIL / 0 SKIP**. Não se somam novamente os 63 testes observacionais before.

A regressão estática antiga tem uma asserção sensível a CRLF; como no AD-15, as 43 regressões foram executadas sobre exportação temporária da fonte original com SQL normalizado para LF. Os ficheiros originais relevantes são idênticos nesta branch. Nenhuma asserção foi relaxada.

Reprodução: configurar QUADRO_PG_BIN e QUADRO_TEST_DEPS; executar node tests/attendance-daily-ad14.test.mjs (after por defeito); AD14_STAGE=before reproduz os quatro casos na base AD-15 sem instalar AD-14. Para regenerar scripts: node tests/attendance-daily-ad14-package.mjs.

## Riscos e limites

- AD-03 e AD-13 continuam bloqueadores; sem GO global, catálogo real ou HTTP/JWT novo certificados.
- Dados existentes incompatíveis exigem reconciliação humana separada; precheck não os altera.
- Trigger diferido garante COMMIT, não cada estado intermédio. Forçar IMMEDIATE antes de uma regularização multi-etapa pode recusá-la atomicamente; nunca permite guardar estado inválido.
- A implantação/validação faz scans e locks sobre as tabelas relacionadas; janela real precisará de autorização e planeamento próprios.
- Rollback devolve os checks incompletos anteriores, mantendo AD-15: só por decisão explícita, sem apagar história.

Commit apenas local. SHA final e working tree limpo entregues na resposta. Não houve push nem alteração de main.
