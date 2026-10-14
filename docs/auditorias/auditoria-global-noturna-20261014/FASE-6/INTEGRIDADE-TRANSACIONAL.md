# Integridade transacional

**Correto na fixture:** plano multiobra recusa alvo estrangeiro integralmente; preview0; FALTOU/report/classify preservam UUID/história; lote RH com linha inválida não altera cadastro nem auditoria; mês fechado e rollback seguro preservados.

**Falhas anteriores com efeitos novos:** faturação cabeçalho/links/documentos em pedidos separados; fornecedor cabeçalho/artigos separado; escritor antigo de recebimento sem movimentos conflita com API parcial; caixa usa acumulado/data final. Não foram corrigidos.

**Nova falha de contexto:** load de consultas altera state.work antes de proteger concorrência; resposta anterior aparece sob nova obra. Isso é consistência cliente, não transação BD nem bypass comprovado. Proveniência de preço também pode desaparecer com header ausente/200.

**Observado, não automaticamente bug:** preços de proposta guardados antes de adjudicar; falha na segunda etapa deixa proposta legítima não adjudicada. Exigir etapa clara e retry idempotente de adjudicação; regra de apagar proposta não foi aprovada.

**Hipótese:** genérico INSERT metadata órfã na fixture, sem triggers reais de integridade. Não chamar prova de produto. Mudança de responsável global sem propagação e adjudicação parcialmente gravada no SQL requerem novos casos ligados; não executados.

No Storage, bytes e metadata são sistemas diferentes. Intenção/finalização/reconciliação com proveniência é proposta técnica; retenção e eliminação precisam decisão. Não apagar por nome/data.
