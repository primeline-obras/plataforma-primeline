# DEEP-IMP-03 — alcance da prova

## Factos observados

A função real de importação forma as chaves já existentes a partir de fn_mapa_gestao_obras(). Esta projeção omite materiais sem data_pagamento. O parser e o writer aceitam esse campo ausente. Na fixture, replay criou duas linhas. Com pagamento, replay sequencial deduplicou; duas conexões READ COMMITTED com o mesmo facto pago criaram uma linha cada e ambas commitaram.

Dois controlos passaram: preview sem escrita com gravação/repetição paga; lote posterior inválido reverte integralmente. Dois cenários de unicidade falharam. Runner8contagens:5PASS/3FAIL, incluindo o parent falhado. Não são3vulnerabilidades.

## Limite essencial

A captura não inventaria integralmente índices/constraints/triggers de lancamentos_materiais; o repositório não contém o CREATE TABLE desta tabela. Foram instalados id default real e NOTNULL id/obra/data/estado_aprovacao. Não há prova suficiente para afirmar que o catálogo integral/hospedado aceita duplicação; índice único ou trigger desconhecido pode recusá-la.

Portanto:
- A incoerência entre universo de deduplicação e factos aceites é observada no corpo real.
- Duplicação efetiva é comprovada nesta fixture, condicionada ao catálogo completo.
- Não apresentar como incidente de produção nem remover o FAIL dos testes.
- Não adicionar este achado à contagem dos203pares, que é outra matriz.

## Próximo passo seguro

Manter o risco P2 condicionado no backlog. Numa revisão futura autorizada, comparar índices/triggers completos por metadados; verificar replay e concorrência num clone integral sintético. Não consultar produção nesta missão nem criar uma segunda regra de deduplicação para contornar o teste.

Uma correção futura deve usar identidade factual persistida e serialização/constraint adequadas; preservar autoria/auditoria e comportamento de batches. Nenhuma correção implementada.
