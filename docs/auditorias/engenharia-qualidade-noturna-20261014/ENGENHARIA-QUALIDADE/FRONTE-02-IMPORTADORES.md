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

## Lotes500 até ao writer

Dois cenários novos:500 Subempreitadas e500 TEEs/itens. Cada preview manteve500 linhas selecionadas; cada RPC gravou500 cabeçalhos, TEE também500 itens. Soma50.000 por família; todas as operações revertidas depois das verificações.6 contagens Node incluindo prechecks/grupo. Prova EVIDENCIAS-IMPORT-LOTE500.json e logs/IMPORT-LOTE500.txt. Duração do writer local cerca de0.3s não é benchmark de produção.

## Mapa de Gestão — workbook binário sintético

Cinco casos PASS em EVIDENCIAS-MAPA-GESTAO-XLSX.json: categorias materiais/estaleiro/subempreitadas/mão de obra/faturação; faturação opcional; falta de folha/cabeçalho; obra reservada com aviso; duplicado exato contado;1000linhas preservadas com ordem/documentos. SheetJS real, nenhuma planilha de pessoas reais lida. Fixture: fixtures/management-five-synthetic.xlsx.

Limite: parser/prepareManagementImportRows, não writer. src/management-map.js confirma por batches500; o catch informa que lotes já gravados serão reconhecidos como duplicados. Atomicidade é por confirmar na função real e não pode ser inferida da integridade deste XLSX.

## Ponte XLSX → PostgreSQL MGO e P2 DEEP-IMP-03

Dois controlos PASS: material com data_pagamento admite preview sem escrita, grava uma linha e replay deduplica; lote com segunda linha de fornecedor inexistente levanta P0001 e não deixa a primeira gravada.

Falha de segurança funcional mantida como FAIL: o mesmo material sem data_pagamento, permitido pelo parser e writer, é gravado novamente no replay. Primeiro criado1, segundo criado1, armazenadas2linhas. A deduplicação consulta fn_mapa_gestao_obras(), cuja projeção de materiais omite data_pagamento NULL. Portanto o registo persistido não entra no universo de duplicados.

Fixture PostgreSQL17.6 com funções reais capturadas/hotfix, role authenticated e autor Gestão sintético; NOTNULL id/obra_id/data/estado_aprovacao explícitos e id default real. Não reconstrói todos os triggers/constraints nem prova catálogo hospedado atual. O filtro também está em supabase/mapa_gestao_obras.sql.

EVIDENCIAS-MGO-PARSER-WRITER.json:2controlos PASS/1FAIL. Runner Node:5PASS/2FAIL, contando três controlos de setup e falha do parent; não são2bugs. Primeiro log arquivado em logs/MGO-FIRST-REPLAY-EXPECTED-FAIL.txt. Sem alteração do produto.

### Qualificação e concorrência — atualização obrigatória

O teste adicional de duas conexões com material pago também duplicou na fixture (ambas commitadas). Totais atuais:2controlos PASS/2cenários FAIL; runner5PASS/3FAIL incluindo parent. Não interpretar como três bugs.

A captura não contém inventário completo dos índices/triggers de materiais. A integridade NOTNULL foi reposta, mas isso não prova ausência de chave factual única no catálogo integral. A duplicação fora desta fixture permanece CONDICIONAL; o problema do universo de dedup é visível no corpo. Ver MGO-DUPLICACAO-LIMITES.md. Não promover a confirmação de produção nem apagar os resultados locais.
