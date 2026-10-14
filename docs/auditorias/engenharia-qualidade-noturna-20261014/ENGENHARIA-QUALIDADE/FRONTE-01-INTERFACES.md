# Frente 1 — INTERFACES

Estado: **PARCIAL**.

## Verificações

21 vistas/80 estados na aplicação inteira;45 capturas de estados adicionais; Folha170+34 checks; editor/equipa/painéis/RH/Medicina/Quadro/RNC/Viaturas/Planeamento em browser local.

## Evidências

screenshots/resultado.json;REGISTO-REGRESSOES.json

## Limites e próximo passo

Fluxos completos dos restantes módulos, estados de carregamento/erro e screenshot por formulário ainda por expandir.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Contexto e formulários adicionais

Obra sintética selecionada em Obras/Documentos/Planeamento:14 estados incluindo5 grupos documentais;1440/768/390,0 erro JS e0 contrato não preparado. Prova: full-navigation/EVIDENCIAS-CONTEXTO-OBRA.json. Os DTOs de leitura são sintéticos e não certificam autorização backend.

Formulário Nova Obra em4 viewports: preencher sem submeter e cancelar,0 escrita; foco/Escape com lacunas de acessibilidade DEEP-OBS-04. Screenshot768/390 inspecionada. Header de Documentos/Planeamento pode aparecer recortado: medição anterior ao click excede viewport, mas o click nativo do browser conseguiu trazer/acionar o seletor em todas as larguras. Não foi comprovada impossibilidade funcional de escolher obra; manter observação visual separada de bloqueador.
