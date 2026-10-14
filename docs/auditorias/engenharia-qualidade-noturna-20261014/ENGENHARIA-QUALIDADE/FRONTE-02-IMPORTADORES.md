# Frente 2 — IMPORTADORES

Estado: **PARCIAL**.

## Verificações

CSV real com 1000 linhas, BOM, multilinha e aspas; parsers operacionais e Mapa Financeiro ligados ao writer local.

## Evidências

EVIDENCIAS-IMPORT-COMERCIAL.json;EVIDENCIAS-FINANCEIRO-IMPORT-INTEGRADO.json

## Limites e próximo passo

XLSX binários já descodificados; roundtrip de todos os exportadores e commits de todas as famílias ainda por ampliar.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Excel externo real

O exportador do produto gerou external-product-export.xlsx com dois períodos, total7h, revisão factual4 e confirmação revisão2. A leitura de células com SheetJS confirmou Horas/Confirmação e ausência de colunas de salário/tarifa/custo. Seis recusas adicionais: intervalo aberto, minutos divergentes, revisão ausente, fingerprint divergente, mês diferente e confirmação ausente. Total7 assertions PASS. Prova: EVIDENCIAS-EXCEL-EXTERNO-CONTEUDO.json. DTO sintético autorizado; não substitui prova da autorização backend.

## Subempreitadas/TEE integradas

EVIDENCIAS-IMPORT-COMERCIAL-INTEGRADO.json liga os parsers reais/SheetJS às RPCs que confirmImport chama: fn_importar_subempreitadas_xlsx e fn_importar_tees_xlsx. Um cabeçalho por família e um item TEE persistem conforme esperado na transação local. Lote com primeira linha válida e segunda inválida recusa e reverte todos os objetos observados.8 contagens Node PASS/0 FAIL/0 SKIP, incluindo3 prechecks e grupo.

A primeira execução encontrou tabela não capturada no inventário do próprio teste, abortando a transação25P02. Corrigido usando to_regclass antes da leitura; log anterior guardado em logs/IMPORT-COMERCIAL-FIRST-FIXTURE-ERROR.txt. Não é falha do produto. Limites: estruturas/defaults/triggers parcialmente reconstruídos; não prova catálogo real ou importação integral de500 linhas no backend.
