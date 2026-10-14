# Financeiro end-to-end

## Provas ligadas
FIN-CHAIN liga a RPC protegida de orçamento de fases a uma fase/obra sintética, TEE aprovado aos triggers de tarefa e previsão, handlers reais submitMeasurement/submitBilling a INSERTs PostgreSQL e decisão da fatura à RPC real. Orçamento2000; auto bruto1200 menos adiantamento200 produz1000; draft pendente passa a emitida após decisão.

**Limites importantes:** MQT→TEE é associação de fase, não reconciliação de artigos. Não foi encontrada/provada ponte granular TEE-itens→auto. A aprovação do auto foi semeada por UPDATE na fixture. Auth financeira foi permitida por stubs; esta suite verifica transições e consumidores, não ACL. Não chamar isto de processo completo do UI até à produção.

## Consumidores
Receber100 de1000 pela API antiga produz badge PAGO e esconde a ação de receber restante em renderMeasurementsTab, enquanto a Visão Geral por diferença ainda tem saldo900. É efeito de N-FIN-05, cuja causa já foi provada na Fase2. A RPC parcial preparada continua sem chamada no frontend deste checkpoint.

FIN-DRAFT: auto rascunho250 com avanço contratual200 resulta450 no helper chamado faturado, sem fatura emitida. FIN-MAPS executa buildRows real: valor efetivo zero cai no inicial; mês com entrada100 e saída com IVA123/semIVAzero resulta-23; caixa entrada100 continua100. Margem de mapa não é caixa; bases e nomes precisam Q05/06/08/10.

TEE300 e subempreitada500 com execução outubro/novembro entram integralmente no início: outubro800, um mês, mesmos totais sem/comIVA. Recusar TEE remove300 da previsão mas a tarefa persiste. Mês fechado não muda após alterar compromisso. N-FIN-06/08/09 preservados; não reescrever fórmulas por suposição.

## Integridade e futuro gate
Falhas entre cabeçalho/links/itens/Storage e replays financeiros da Fase2 preservados, sem repetir a exploração. Exigir transação BD, fonte de parcelas por data, recovery auditado de bytes, entidade/tenant comprovados, autorizações correntes, revisão e consumidores concordantes. Dados históricos sem parcelas não podem ser reconstruídos por inferência.

Evidência: EVIDENCIAS-FINANCEIRO.json; tests/night-phase3-finance.test.mjs. **9 PASS Node incluindo grupo; reprodução aprovada não significa produto seguro.** Nenhum valor real usado. NO-GO destes fluxos com P1 aberto.
