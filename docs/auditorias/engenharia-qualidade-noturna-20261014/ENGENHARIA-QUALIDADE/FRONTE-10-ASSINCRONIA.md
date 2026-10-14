# Frente 10 — ASSINCRONIA

Estado: **PARCIAL**.

## Verificações

Dois novos problemas em documentos; P2 anterior de Compras preservado. Sessão e stale/cancel nos painéis preparados passaram.

## Evidências

EVIDENCIAS-DOCUMENTOS-CONTEXTO.json;REGISTO-REGRESSOES.json

## Limites e próximo passo

Trocas de mês/pessoa/aba, todas as combinações de latência e cache ainda requerem expansão. Não concluir bypass de tenant a partir de troca de contexto.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Regressões preparadas de sessão

logs/REGRESSAO-SESSAO-COMERCIAL.txt:15 contagens Node PASS,0 FAIL,0 SKIP, mistura de assertions textuais e comportamento de cliente. session-boundary verifica logout síncrono, resposta REST/corpo atrasado, refresh antigo e download privado atrasado. Transporte sintético, sem GoTrue/Storage real. Não desbloqueia os24 pares de serviços ausentes e não elimina a corrida entre obras com a mesma identidade no módulo Documentos.
