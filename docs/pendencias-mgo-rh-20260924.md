# Estado local — 24/09/2026

Não publicado. Nenhuma escrita na base de produção nesta etapa.

## MGO

- Classificação explícita diario / mensal; mês de referência nos mensais.
- Ausências bloqueiam diários na pré-visualização e gravação. Custo mensal não significa presença no último dia do mês.
- Não altera férias nem a tabela de ponto. Rejeita mistura de mensal/diário e múltiplos totais na mesma pessoa/obra/mês.
- Mantém chaves de deduplicação, valores, horas e datas.
- Excel DIARIO_MENSAL preparado: 1294 linhas, 35 mensais e 634 diárias de mão de obra. Valores comparados antes/depois e após reabrir o ficheiro.
- Os 35 mensais usam os sete nomes explícitos do script e a confirmação do utilizador, nunca uma inferência apenas pelas horas.
- Migração aditiva: supabase/mgo_mao_obra_periodicidade.sql.
- Correção histórica com backup: supabase/mgo_mensais_classificar_existentes_20260924.sql. Só altera metadados de correspondências exatas; nada cria; aborta ambiguidades e sobreposição de custos.
- SQL verifica âncoras das funções instaladas e anula tudo se divergirem. Não aplicar o antigo SQL completo do MGO.
- Próximo passo: conferir versão principal remota, aplicar e conferir migrações, publicar frontend e validar novamente Excel DIARIO_MENSAL. Não assumir que continuam 254 por criar.
- Lotes anteriores podem permanecer gravados após erro num lote posterior; reimportar reconhece duplicados.

Testes em PostgreSQL isolado: mensal com férias aceite; diário bloqueado; 3 linhas criam 3 e depois 0; migração repetível; permissões preservadas; erro reverte o lote; 33 históricos sintéticos classificados sem criar os 2 ausentes nem alterar valores.
Testes MGO existentes: 15/15. RH completo: 21/21. Login: 2/2.

## Interface

- Documento/número da fatura primeiro no MGO; filtros adaptáveis.
- Nomenclatura dos contratos atualizada, sem modificar valores internos.
- Aba PONTO DE OBRA renomeada FOLHA DE PONTO; IDs/RPCs mantidos.
- Olhinho preparado; publicação não confirmada.
- Auditoria visual de todas as abas/perfis em produção ainda não realizada.

## Digit / códigos RH

- Modelo recebido: 37 colaboradores, códigos únicos de três dígitos como texto, quantidades vazias. Setembro sem ano explícito.
- Código RH deve usar código Digit após conferir ID e cadastro atual. Não usar códigos antigos como identificador de correspondência.
- Excel RH anterior: 9 nomes exatos, 28 sem correspondência exata. Nenhum código atualizado.
- docs/Codigos_RH_Digit_PARA_REVISAO.xlsx é conferência, NÃO importação.
- Pedir exportação atual de id/nome/codigo_rh/data_saida para fechar correspondências e conflitos.
- Ajudas de Custo e Km manuais. Falta confirmar unidade das ausências e tratamento do Prémio.
- Não equiparar falta justificada a não remunerada; não usar custos MGO para inferir vencimentos.
- Relatório existente de horas por obra NÃO é mapa Digit. Exportação Digit ainda não implementada.

## Outros

- Fornecedores: CSV com 626 IDs únicos conferido. Utilizador enviou para revisão externa. Nenhuma importação/mesclagem automática.
- Mapa anual de férias e auditoria geral de layout pendentes. Não recriar as 3 férias incorretas do Adilson já removidas pelo utilizador.
