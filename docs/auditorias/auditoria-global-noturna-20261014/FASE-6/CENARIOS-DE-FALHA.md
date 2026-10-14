# Cenários de falha e provas

-Consulta A pendente→selecionar B→A resolve: contexto B/dados A, TEMP-P3-C01 comprovado.
-Items200 presentes+headers200 vazios: preço sem origem/semwarning, TEMP-P3-C02 comprovado.
-Fatura1000→writer antigo recebe100→badgePAGO/ação escondida/saldo900: FIN-CONSUMERS, efeito de P1 conhecido.
-TEE300+SUB500→recusarTEE: forecast500 mas task persiste, FIN-TEE-CONSUMERS.
-Policysegura→SQLhistórico permissivo: leitura reaberta na fixture; rollback restaura, MIG-ORDER.
-LoteRH linha1 válida→linha2 inexistente→confirm: erro e rollback de cadastro/auditoria, RH7-BATCH correto.
-PreviewPlano→atorinativo ou empresaerrada:42501 sem factos, RH-REVOKE/TENANT corretos.
-Documento→entidadeinexistente numa tabela mínima: órfão permitido apenas por fixture incompleta; hipótese a testar no contrato real.

Preservados sem repetir causa: Fase2 linkfail/uploadfail/metadatafail/respostaperdida/misturaAPI/movimentosmensais. Cada risco relevante tem sequência ou etiqueta HIPÓTESE. Referência de garantia stale/overlap e invalidação mensal possuem casos no harness preservado executado; não reconstruir dados reais.
