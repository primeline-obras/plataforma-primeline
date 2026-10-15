# Falhas comprovadas — checkpoint progressivo

## Isolamento

DEEP-SEC-01: fn_criar_rnc aceita alvo de outra empresa para Gestão/Gerência na montagem local. DEEP-SEC-02: fn_resolver_alerta resolve alerta de outra empresa para Gestão/Gerência e, na expansão, Administrativo/Financeiro. Seis pares FAIL, duas causas/contratos a corrigir. Provas: EVIDENCIAS-ESCOPO-RESTANTES.json, EVIDENCIAS-RESTANTES-OUTRA-EMPRESA.json e EVIDENCIAS-ALERTAS-OUTRA-EMPRESA-SEM-DESTINATARIO.json. Esta última usa alerta com todos os campos obrigatórios NOT NULL e sem destinatário individual, validando os quatro perfis. O teste de recusa falha efetivamente; a reprodução não é contabilizada como segurança aprovada.

A fixture usa funções reais capturadas, hotfix consolidado e guarda documental posterior de Viaturas. Não reconstrói todos os triggers/constraints do sistema nem confirma o catálogo hospedado. Os achados são locais e devem orientar correção/revisão, sem alegar exploração em produção. Viaturas recusou ambos os atores estrangeiros com o wrapper atual.

## Leitura direta de metadados — baseline local

DEEP-SEC-03 reforça a classe N-SEC-02: Gestão/Gerência leem uma linha documental estrangeira com role authenticated, RLS on, BYPASSRLS false e tabela com RLS ativo. São2 recusas falhadas parciais; os24 fluxos completos Auth/Storage continuam bloqueados. A policy é a capturada na baseline20261004; não afirmar que o catálogo hospedado atual contém a mesma policy sem consulta futura autorizada.

## Qualidade

Documentos: resposta obsoleta A em contexto B; pedido de metadados pode usar obraB com ficheiro de A. Importação: texto inválido transformado em número e gravado localmente; duplicações contraditórias sobrescrevem o ajuste sem aviso, enquanto linha desconhecida desaparece do preview. Ver NOVAS-DESCOBERTAS.csv na pasta ENGENHARIA-QUALIDADE. DEEP-IMP-03: replay do mesmo material sem data de pagamento cria2linhas na baseline local; controlo com pagamento deduplica e lote inválido recusa atomicamente. Não somar este cenário aos203pares.

## Risco condicional adicional

DEEP-DOC-03: o cliente de proposta PDF pede DELETE após resposta2xx cujo corpo falha. O pedido de compensação é comprovado; perda persistente depende do commit e de aceitação pelo Storage, não certificados nesta prova. Ver EVIDENCIAS-PDF-COMPENSACAO-AMBIGUA.json na Engenharia de Qualidade. Não contabilizar a assertion diagnóstica como aprovação funcional.

## Preservado

P1 financeiros/HTML e riscos HR38 anteriores continuam sem correção. Não foram repetidas cargas HTML nem alteradas permissões. FP28/29 continuam em standby.
