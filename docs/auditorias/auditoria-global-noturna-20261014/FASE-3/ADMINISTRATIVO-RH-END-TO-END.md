# Administrativo e RH end-to-end

## Cadeia executada
RH-CHAIN: cadastro/contrato semeados → team_add real → preview do plano sem factos → confirmar480min → relatório factual e conferência480 → corrigir240min → conferência240, histórico aumentado, zero Vencimentos criados. Cadastro nesta cadeia é fronteira de fixture, não UI completa.

RH7-CADASTRO complementa a fronteira numa segunda BD: fn_rh_guardar real chama criador do ficheiro colaboradores_campos_completos, cria alocação de escritório explicitamente fornecida, contrato sem termo, auditoria e leitura por fn_rh_consultar. Cargo formal Preparador não foi convertido em papel de login. O criador usado é versão identificada no Git; não representa baseline hospedada confirmada.

RH-FALTOU: equipa → ausência neutra pela RPC → mapa administrativo com mesmo UUID/proveniência → classificação com motivo → história mensal. Zero pontos/horas/saídas/faltas compensatórias inventados. Conferência é processo diferente de payroll.

## Resiliência
Preview cancelado não escreve; ator inativo após preview recusa42501; obra de outra empresa no plano recusa integralmente. Suite nativa cobre duas conexões, idempotência, stale, referência histórica, multiobra, externos, HE informativa, férias, leitores e rollback antes/depois de uso. AD13/14/15/03 preservados. Nada foi ativado na produção.

Lote RH: preview de duas linhas não altera; confirmação com segunda linha inexistente recusa e faz rollback de primeira mudança e auditoria. Repetição de mesmo conteúdo é no-op, não cache de request_id. Gestão importa; Gerência/Admin leem mas não importam; Financeiro/Diretor/Adjunto/Preparador/Encarregado não obtêm cadastro completo pelo contrato testado. Empresa estrangeira retorna0; inativo recusado.

## Limites
Medicina e Viaturas têm provas nativas anteriores preservadas; não foi construída nova cadeia completa cadastro→documento→Medicina→viatura→alerta nesta missão. Storage hospedado e Auth real não acessados. Exportador externo/HR30 e HR27/31 regredidos no harness; não introduzir HE monetária. FP28/29/horário/almoço/tolerância intactos.

Evidências: RESULTADO-RH-LOCAL.txt; EVIDENCIAS-RH-TAREFAS.json; FASE-7/EVIDENCIAS-RH-LOTE.json. O total final do harness consta no log e RESULTADOS-FASES-3-A-7.json; não somar reexecuções.
