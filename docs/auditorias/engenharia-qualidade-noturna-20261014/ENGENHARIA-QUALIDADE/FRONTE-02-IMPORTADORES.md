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
