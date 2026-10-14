# Divergências e documentação

1. Fase1 descreve a ponte TEE→Auto em diagrama como sequência de negócio. Nesta fase não foi provada FK/reconciliação granular por artigo. Tratar a seta como intenção/processo conceitual, não contrato técnico implementado.
2. Inventário Fase1 dizia não encontrar ledger no fluxo. Fase2 encontrou fn_registar_recebimento_parcial/faturacao_recebimentos no SQL; a UI continua usando a antiga. Preservar história e atualizar interpretação, sem editar relatórios anteriores.
3. Ausência de literal task_confirm no frontend não é UI ausente: trigger tarefa_concluida implementa a confirmação indireta quando ator autorizado conclui no Planeamento.
4. Relatório RH23/09 antigo tem lacunas já implementadas, N-ADM-10. Não convertê-lo automaticamente em novos requisitos.
5. Histórico de produção informado: assets63/63 e smoke leituraPASS, writerCLOSED. Esta auditoria não reabre esses resultados nem verifica novo deploy. Gestão de Horas desta base é candidato local; não presumir publicado.
6. Débitos/FaseB estão preparados em outras branches; precheck anteriorPASS não significa migration instalada/autorizada.
7. Contagens de scanners diferem por método;588 ocorrências antigas e575 funções dollar-quoted não são objetos instalados. MJS/suites/filecounts não representam cobertura funcional.

Nenhuma documentação histórica apagada ou sobrescrita. Novas conclusões remetem à evidência atual.
