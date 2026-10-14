# Segunda passagem — provas independentes

- Económicos:76 variantes por inatividade/outra empresa/revogação;0 FAIL.
- Restantes:73 variantes,56 com ator inativo e17 com responsabilidade removida;0 FAIL. Log SEGUNDA-PASSAGEM-RESTANTES.txt; JSON EVIDENCIAS-SEGUNDA-PASSAGEM-RESTANTES.json.
- Horas:72 variantes de utilizador inativo;72 PASS. Regressão cumulativa364 contagens Node/0 FAIL/0 SKIP; não somar grupos como casos únicos.
- REST:30 provas com Auth ID distinto, revogação, token expirado, assinaturas inválidas, revisão/replay e valores de recebimento;0 FAIL. Não é login GoTrue.
- Escopo RNC/Viaturas/Alertas:12 provas;4 FAIL de isolamento em RNC/Alertas Gestão/Gerência preservados.

São variantes adicionais, não novos pares na matriz203. Snapshot de dados antes/depois e rollback local em cada operação negativa. A fixture não reconstrói todos os triggers/defaults/constraints. Não prova o catálogo hospedado nem os percursos Auth/Storage bloqueados.
