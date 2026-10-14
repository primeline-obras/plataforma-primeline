# Segunda passagem — provas independentes

- Económicos:76 variantes por inatividade/outra empresa/revogação;0 FAIL.
- Restantes:73 variantes,56 com ator inativo e17 com responsabilidade removida;0 FAIL. Log SEGUNDA-PASSAGEM-RESTANTES.txt; JSON EVIDENCIAS-SEGUNDA-PASSAGEM-RESTANTES.json.
- Horas:72 variantes de utilizador inativo;72 PASS. Regressão cumulativa364 contagens Node/0 FAIL/0 SKIP; não somar grupos como casos únicos.
- REST:30 provas com Auth ID distinto, revogação, token expirado, assinaturas inválidas, revisão/replay e valores de recebimento;0 FAIL. Não é login GoTrue.
- Escopo RNC/Viaturas/Alertas:12 provas;4 FAIL de isolamento em RNC/Alertas Gestão/Gerência preservados.

São variantes adicionais, não novos pares na matriz203. Snapshot de dados antes/depois e rollback local em cada operação negativa. A fixture não reconstrói todos os triggers/defaults/constraints. Não prova o catálogo hospedado nem os percursos Auth/Storage bloqueados.


## Reconciliação com203 chaves

MATRIZ-SEGUNDA-PASSAGEM-203.csv mantém os mesmos203 pares e liga cada variante ao índice da prova. Todos os179 pares com backend executado têm agora variante de utilizador inativo aprovada;24 continuam bloqueados. Isto não cobre automaticamente todas as variantes de outra empresa/revogação, que permanecem explícitas na matriz. As6 chaves com falha de isolamento continuam FAIL (duas causas P1). A recusa de Gestão no FALTOU mantém contrato pendente apesar de o teste de inatividade passar.

Financeiro:27 variantes,24 inativos42501 e3 técnicos após revogação recusados com P0001 explícito de falta de permissão. Primeiro ensaio exigia42501 também nesses3; logs/JSON FIRST-STRICT-ERROR-CODE preservados como divergência da expectativa do harness, não autorização indevida. Não se aceita um erro P0001 genérico para certificar a recusa.

## Responsabilidade pela obra

Nove variantes de Horas recusadas após remoção das responsabilidades, com reposição exata da fixture entre casos;301 contagens na regressão cumulativa. Seis dessas variantes pertencem às chaves originais, três são suplementares. A matriz soma38 chaves com prova de revogação;48 ações autorizadas por papel e92 já proibidas ao papel não dependem de responsabilidade individual;1 contrato de Gestão/FALTOU continua pendente;24 serviços bloqueados. NÃO APLICÁVEL à revogação de obra não absolve uma falha de tenant.

A tentativa inicial deste teste não iniciou por timeout da revisão automática. A ferramenta permitiu uma repetição, que foi aprovada e concluída. Não houve rejeição de mérito nem contorno da revisão. O outro encerramento de PID previamente rejeitado continua sem ser repetido.
