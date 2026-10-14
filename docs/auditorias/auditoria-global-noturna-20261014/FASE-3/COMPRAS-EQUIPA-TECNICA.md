# Compras e equipa técnica

## Compras: resultados novos
TEMP-P3-C01 (P2): loadA fica pendente; loadB altera state.work e retorna devido loading; respostaA preenche consultas e loadedWorkId=A, mas renderiza contexto B. Função real src/procurement.js:175–237 executada em VM. Não houve outra identidade/empresa nem prova de bypass RLS; existe risco de ações no alvo errado.

TEMP-P3-C02 (P2, N-FOR-05/02): as três consultas retornam200; header de fatura ausente e item presente. loadPriceRows produz preço sem fornecedor e priceError vazio. Falha de proveniência provada em fixture; ausência real por RLS/paginação não demonstrada. Queries não têm paginação visível; cap real desconhecido.

saveCandidate guarda proposta100 antes de adjudicação falhada; withButton mostra erro e reativa botão. Não é automaticamente corrupção: preço de proposta pode legitimamente existir sem adjudicação. Necessita indicação clara de etapa. Comparativo real: menor140/estimado160/adjudicado180/venda240 → negociação40/desvio20/margem60. Não tratar soma dos menores como preço adjudicado.

**Fronteira não concluída:** criação de fornecedor/consulta → adjudicação SQL → Storage/documentos → fatura não foi ligada integralmente em uma BD. Rastreabilidade do código identifica RPCs, vínculos e readers; nenhum PASS end-to-end integral foi atribuído a essa cadeia.

## Equipa técnica
Tarefa em execução → reporte do Encarregado → três alertas para responsáveis únicos → confirmação autorizada resolve alertas/história. Reporte não altera conclusão oficial. Adjunto confirma; Preparador não confirma; stale/replay após inativação recusados.

Há também ligação indireta correta: folha_privado.tarefa_concluida (folha_ponto_v2_gestao.sql:411–431) confirma reporte e resolve alertas quando Diretor/Adjunto/Gestão conclui a tarefa. Por isso ausência de literal task_confirm no frontend **não prova operação órfã**. A RPC explícita é alternativa; não criar botão novo nesta auditoria. Teste TASK-AUTO-CONFIRM verifica o trigger com ator válido; UPDATE oficial foi fronteira de fixture, sem executar batch completo de Planeamento.

Pesos/progressos/dependências têm13 regressões puras; não foi certificado que todos indicadores globais/reunião/MGO propagam automaticamente esta conclusão. HR29 permanece aprovado no âmbito; HR38 continua bloqueio de confidencialidade a mitigar, sem nova regra de limiar.
