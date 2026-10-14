# Migrations e publicação — manifesto proposto

Ordem errada comprovada localmente: policy tenant simplificada → autos_faturacao_workflow.sql histórico → policy permissiva true passa a OR com a segura → authenticated lê linha fora do scope da fixture. Rollback da transação restaura policy/grants e leitura0. Não é reconstrução de catálogo real nem prova de exposição atual em produção.

575 declarações dollar-quoted/1.713 chamadas qualificadas no grafo novo;136 nomes com múltiplas definições e370 ocorrências de conflito. Diferem do inventário geral588/140 da Fase1 porque o scanner novo não cobre toda sintaxe, sobrecargas, SQL dinâmico ou pg_depend. Hashes são texto normalizado do Git, não fingerprints pg_get_functiondef. Seeds reais excluídos.

## Sequência proposta (não operacional)
1. Reconciliar catálogo/versionamento/grants reais numa tarefa futura read-only autorizada.
2. Distinguir scripts históricos, ativos, checks e rollback por assinatura/hash/owner/ACL.
3. Preservar cadeia FolhaV2→equipa persistente→fecho reconciliado→cutover CLOSED; preparar avaliação AD15→AD14→AD13→AD03 e extensões HR27/FALTOU/readers/mensal/destinos/plano/mapas segundo prechecks.
4. Financeiro/autos: hotfix tenant precede writers e compatibilidade de consumidores; scripts antigos permissivos não reaplicar.
5. DD-TENANT abc160d e FaseB b7bf4c1 são branches separadas; não integram esta base automaticamente.
6. Backup/migration/postcheck/rollback futuro exigem baseline concreta e autorização; Storage não é transação SQL.

Rollback histórico pode restaurar definição/permissão antiga; nunca executar em lote por nome/ordem alfabética. Após uso, guards atuais preservam referências/histórico. Ver grafo/risco detalhado na Fase6. Nenhum manifesto operacional alterado. Publicação NO-GO com P1 financeiro/HTML/HR38 aberto.
