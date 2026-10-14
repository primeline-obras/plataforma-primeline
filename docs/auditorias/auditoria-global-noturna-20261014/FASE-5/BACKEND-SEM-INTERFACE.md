# Backend sem referência direta de interface

256 nomes públicos no scanner;132 não têm literal correspondente nos src. É correlação estática, não132 funcionalidades órfãs. Pode haver trigger, rotina automática, helper privado, overload, SQL dinâmico, job, contrato futuro ou legado. BACKEND-CANDIDATOS.json conserva candidatos e definições.

## Casos relevantes reconciliados
- fn_registar_recebimento_parcial: definição no hotfix e provas locais; nenhuma chamada nos src. Writer antigo usado no diálogo. Contrato preparado desconectado, ligado a N-FIN-05; não ligar silenciosamente.
- task_confirm explícito: cliente genérico poderia chamar, mas ponto direto não encontrado. **Existe trigger tarefa_concluida** que confirma/recolhe alertas quando Planeamento conclui autorizado. Não é órfão nem motivo de nova UI automática.
- fn_atualizar_tarefa_encarregado e fn_guardar_ponto_obra: vias antigas substituídas/revogadas pelos fluxos V2. Não classificá-las como funcionalidades atuais a reativar.
- Helpers folha_privado e funções de trigger não precisam UI nem EXECUTE externo. Grants privados negados nos testes nativos.
- Rotinas de alerta/email precisam job/integração externa não inspecionada; enviar_email não prova entrega.
- Débitos tenant-safe/FaseB/HR38 padrão operacional: branches/futuro ou decisão, não produto integrado nesta base.

Critério para chamar órfão confirmado: percurso previsto não tem interface/caller indireto legítimo, assinatura e instalação comprovadas, requisito aprovado. Esse critério não foi aplicado automaticamente ao132.
