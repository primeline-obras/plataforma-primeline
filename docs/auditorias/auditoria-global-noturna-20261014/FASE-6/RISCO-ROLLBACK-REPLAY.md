# Rollback e replay

## Sequências concretas
1. Policy tenant da fixture → autos_faturacao_workflow antigo com USING(true) → SELECT externo lê cabeçalho. Rollback da transação retorna policy/grants e0leituras. MIG-ORDER; não prova catálogo atual.
2. Backup/precheck de pacote → drift de ACL/função/trigger → check rejeita; rollback do ensaio restaura. Casos do harness299.
3. Avaliação/jornada/conferência utilizadas → rollback do pacote recusado com DATA_DRIFT/AFTER_USE, sem destruição de história. Antes de uso os lifecycles permitem rollback/reinstalação.
4. Mesmo request Folha/Equipa/FALTOU retorna resposta idempotente; payload diferente ou revogação atual recusa. Duas sessões verificadas no harness.
5. Reimport RH de conteúdo igual é no-op; versão antiga diferente recusa; IDs repetidos fazem rollback do lote. Não equivale a cache de request_id.
6. Retry financeiro depois de commit perdido cria risco de draft duplicado (prova Fase2). Não reconstruir nem compensar documentos reais nesta missão.

## Riscos que não foram executados
Rollback histórico completo do hotfix Financeiro/Storage sobre a baseline atual pode restaurar assinatura/ACL incompatível; não simulado sem fixture de catálogo suficiente. SQL avulso sem pre/postcheck é risco de manutenção, não prova de instalação errada. Triggers e grants de Storage hosted não certificados.

Hash Git normalizado não substitui pg_get_functiondef+owner+ACL instalados. Prechecks devem recusar divergência; não atualizar hash para fazer passar. Nenhum rollback real ou writer legado reaberto.
