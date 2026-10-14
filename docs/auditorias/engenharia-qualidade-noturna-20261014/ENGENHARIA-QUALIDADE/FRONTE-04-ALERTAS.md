# Frente 4 — ALERTAS

Estado: **PARCIAL**.

## Verificações

Filtros reais preservam eventos distintos e retiram obra revogada; produtor Quadro e idempotência/retry: 28 contagens Node.

## Evidências

EVIDENCIAS-ALERTAS-FILTROS.json;logs/ALERTAS-PRODUTOR-LOCAL.txt

## Limites e próximo passo

Rotinas globais de Medicina/contratos/documentos/Financeiro não ligadas ponta a ponta. Nenhum alerta real lido/apagado.

Não houve alteração de produto, produção, permissões ou regras. A aprovação de uma assertion de diagnóstico não significa aprovação do comportamento vulnerável observado.

## Reconciliação de Medicina e rastreabilidade

Regressão existente medicina-trabalho.test.mjs:37 contagens Node PASS,0 FAIL,0 SKIP. Inclui primeira consulta, consulta corrente, preservação de resolvidos, alteração da admissão/saída, falha de auditoria e concorrência em sessões independentes. Prova: logs/MEDICINA-PRODUTOR-REGRESSAO.txt. A fixture contém helpers de sessão/perfil e rotinas periféricas substituídos; esta execução valida o ciclo de Medicina, não certifica permissões reais nem os203 pares.

ALERTAS-PRODUTORES-RASTREABILIDADE.csv inventaria definições com INSERT/UPDATE/DELETE em alertas, incluindo versões históricas e rollback. Tokens de tenant/deduplicação não equivalem a validação de segurança. ALERTAS-AGENDAMENTOS-LEXICAIS.json localiza agendamentos preparados; não prova jobs instalados/ativos.

Canal email: bloco_09_alertas_prioridade_email.sql define apenas enviar_email para pedido_semanal_horas/informacao_reuniao_semanal/informacao_reuniao_producao. Não configura SMTP. O N-ADM-11 anterior permanece; não contar sinalização como entrega. O produtor corrente de Medicina está em medicina_trabalho_controlada.sql; scripts antigos de primeira consulta podem conter seleção da primeira empresa e não devem ser reaplicados por esta auditoria.
