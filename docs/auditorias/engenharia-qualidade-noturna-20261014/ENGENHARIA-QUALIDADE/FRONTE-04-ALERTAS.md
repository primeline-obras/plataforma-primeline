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

## Extensão do mesmo P1 tenant

DEEP-SEC-02 abrange também Administrativo/Financeiro. Corroboração com alerta financeiro geral da empresa1, sem destinatário individual, todos os campos obrigatórios preenchidos e NOT NULL efetivamente impostos na fixture. Quatro atores da empresa2 conseguem resolver/receber a linha completa. Prova EVIDENCIAS-ALERTAS-OUTRA-EMPRESA-SEM-DESTINATARIO.json na pasta validacao-profunda. Não é novo ID/cause adicional; a matriz agora tem6 chaves FAIL (RNC2 + Alertas4). Sem prova de ocorrência em produção.

## Canal SQL, sem entrega

Dois cenários/6 contagens Node PASS: o trigger real força enviar_email apenas em pedido_semanal_horas/informacao_reuniao_semanal/informacao_reuniao_producao e recalcula ao mudar tipo. Flags fornecidas pelo chamador são substituídas.6 verificações de dados no JSON, não6 cenários independentes. Prova EVIDENCIAS-ALERTAS-CANAL-SQL.json e logs/ALERTAS-CANAL-SQL.txt.

Operação owner na fixture; não é autorização do produtor, agendamento cron, SMTP ou entrega a um destinatário. N-ADM-11 permanece. Não foi enviado qualquer email.

## Produtor de contratos — execução SQL específica

Fonte instalada na fixture: supabase/parametros_operacionais.sql, funções texto/dias e fn_verificar_alertas_fim_contrato(). Índice real de ocorrência de alertas_vencimentos_resolucao_corrigido.sql. PostgreSQL17.6 descartável, seed sintético, operação owner.

- 60/45/30 dias: três ocorrências distintas, empresa correta e destinatário administrativo.
- Duas execuções do mesmo evento: uma ocorrência.
- Dois contratos no mesmo dia: duas ocorrências.
- 61dias, contrato inativo e colaborador com saída: nenhuma ocorrência.
- Lista administrativa10dias: respeitada sem usar60dias.
- Prazo mudado de60 para61dias: esta rotina preserva a ocorrência anterior. É observação do produtor, não prova de que inexiste reconciliação noutra rotina nem um novo defeito aprovado.

Seis cenários PASS;10 contagens Node incluindo parent e três verificações de setup. Não somar10 aos203pares. Cron, entrega SMTP, autorização do chamador e catálogo hospedado continuam não demonstrados por estes casos. A primeira falha42P10 era índice ausente na fixture e está arquivada separadamente.

Evidências: EVIDENCIAS-ALERTAS-CONTRATOS-SQL.json, logs/ALERTAS-CONTRATOS-SQL.txt. Nenhum produto alterado.

## Integração Folha/Planeamento → destinatários → confirmação

EVIDENCIAS-ALERTAS-CONCLUSAO-INTEGRADA.json: dois cenários adicionais no runner cumulativo das migrations reais. Preview não cria alerta; confirmar report cria destinatários atuais; replay não duplica nem muda resultado; concluir a tarefa confirma reporte e resolve alertas. Novos alertas excluem um responsável desativado e outro cuja responsabilidade foi removida. Estados anteriores dos utilizadores/responsabilidades restaurados na fixture.

Resultado da suite:294 contagens Node PASS/0FAIL/0SKIP. Inclui regressões existentes; não somar294 como novos cenários nem aos203pares. Não é prova do trigger antigo de tarefa impedida, da entrega de email ou da reconciliação de alertas históricos após revogação.
