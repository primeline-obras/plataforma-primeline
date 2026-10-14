# Frente 6 — FORNECEDORES

Estado: **PARCIAL**.

## Verificações

Completude sem especialidade; múltiplas especialidades; entidade ambos; nomes normalizados não fundem IDs; cotação excluída/não comparável não vence.

## Evidências

EVIDENCIAS-FORNECEDORES.json;EVIDENCIAS-IMPORT-COMERCIAL.json

## Limites e próximo passo

Unidade/IVA/moeda/validade/transporte/mínimos não são campos decididos automaticamente pelo helper de melhor preço. Nenhuma interface nova concedida ao Encarregado.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Comparabilidade comercial aprofundada

Seis verificações do helper real confirmam que unidade, moeda, IVA, validade, transporte e quantidade mínima não são avaliados automaticamente: a seleção usa total e flags de âmbito/comparabilidade. Marcar explicitamente a proposta não comparável retira-a da escolha. Prova: EVIDENCIAS-COMPARABILIDADE-COMERCIAL.json.

Rastreabilidade: comparative-map.js apresenta valores em euros e normalização manual de unidade/quantidade/preço; a importação PDF guarda unidade original, condições de pagamento, entrega, montagem, garantia, exclusões e validade. mapa_comparativo_importacao_pdf.sql valida validade_dias entre0 e3650 e estados de âmbito. Isto não implementa conversão cambial, equivalência de unidades, inclusão de IVA/transporte ou bloqueio automático por prazo expirado.

Recomendação para decisão: manter revisão explícita antes de marcar comparável; definir futuramente quais diferenças exigem impedimento ou apenas aviso. Não foi alterado o contrato nem contado um novo defeito de permissões. As seis assertions documentam o limite; não certificam equivalência comercial das propostas.
