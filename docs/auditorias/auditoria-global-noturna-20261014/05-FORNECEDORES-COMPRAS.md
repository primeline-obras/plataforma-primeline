# Fornecedores, Subempreiteiros e Compras

## O que existe — CONFIRMADO no código

- Diretório comum em `src/subcontractors.js`: fornecedor/parceiro, cadastro completo, NIF, contactos, zonas operacionais, especialidades, avaliações, revisão manual de incompletos e eliminação/mesclagem controlada.
- `supabase/cadastro_fornecedor_unificado.sql`, `fornecedores_zonas_operacionais.sql`, `especialidades_subempreiteiros.sql`, `mesclar_fornecedores_seguro.sql`: normalização/relacionamentos. Cadastros existentes, duplicados ou incompletos reais são NÃO VERIFICADOS; não foram lidos.
- Consultas e candidatos/propostas em `procurement.js:200`, ligados a especialidade/fase/artigo MQT/tarefa pendente. Adjudicação e aditamentos são processos separados de consultar preços.
- Mapas comparativos em `comparative-map.js:175`: mapas/propostas/itens/preços/ajustes, PDF importado para preview/revisão, preços comparáveis e escopo incluído. `calculateBestPrices` (`:7`) não transforma a soma de menores em adjudicação.
- Histórico consultável de compras em `subcontractors.js:450`/`:607`: preços de `faturas_itens` + origem `faturas`, e `despesas_estaleiro`. Preço bruto, desconto, líquido unitário, unidade, fornecedor e data aparecem separados (`:462`/`:627`).

## Classificar corretamente os preços

| Fonte | O que prova | O que NÃO prova |
| --- | --- | --- |
| Proposta de consulta / comparativo | Cotação numa data para escopo/quantidade/condições | Preço pago, validade atual ou autorização de compra |
| Adjudicação / aditamento | Compromisso comercial aprovado | Entrega, faturação ou pagamento completo |
| Item de fatura | Preço faturado com quantidade/desconto registados | Preço atual aplicável a qualquer obra/quantidade |
| Estaleiro / lançamento material | Apontamento/custo daquela origem | Cotação formal comparável se unidade/IVA/fornecedor faltarem |
| Orçamento MQT | Estimativa/baseline | Custo efetivo ou proposta aceite |

Na interface histórica atual não há unificação de propostas/adjudicados/faturados numa fonte normalizada. A tag Material/Estaleiro é origem contabilística, não estado comercial. Não rotular o histórico de faturas como catálogo atual de preços.

## Lacunas e riscos

| ID | Classificação/prioridade | Evidência | Proposta |
| --- | --- | --- | --- |
| N-FOR-01 | P2 CONFIRMADO ausência de capability de consulta para Encarregado | `access-control.js:64`: Encarregado sem vista subcontractors; `subcontractors.js:486` contém histórico na vista geral. | Aprovar leitor de preços mínimo independente; não ampliar acesso a faturas ou diretório financeiro completo. |
| N-FOR-02 | P2 PROVÁVEL incompletude/paginação | `subcontractors.js:612`: consulta todos os cabeçalhos de faturas materiais e itens correspondentes sem paginação visível. Limite REST real NÃO VERIFICADO. | RPC/paginação com contagem/continuação; preview indicar resultado parcial; não alegar exaustividade. |
| N-FOR-03 | P2 CONFIRMADO limite de comparabilidade | `subcontractors.js:471`: unidade apresentada como texto; filtro é fornecedor; não prova conversão kg/t/m³/un/caixa. | Comparar só mesma unidade/base/escopo demonstrados; conversão explicitamente aprovada com fator/proveniência. |
| N-FOR-04 | P2 NÃO VERIFICADO qualidade de dados reais | Não consultar cadastros nesta missão. | Diagnóstico autorizado agregado de NIF/nome/links; classificação humana; não mesclar por nome sozinho. |
| N-FOR-05 | P3 PROVÁVEL diferença de origem | Query de itens pode devolver origem sem cabeçalho visível em erro/RLS (`subcontractors.js:620`). | DTO provado e sinal origem incompleta; preço/fornecedor desconhecido não virar zero/nome presumido. |

Usar testes existentes de duplicados NIF, mesclagem bloqueada com histórico, especialidades, unidades/escopo comparável e PDF. Não reconstruir estas funcionalidades. Compras/consultas fazem pedidos REST distintos em partes do circuito (`procurement.js:335`); atomicidade/idempotência desse fluxo não foi certificada nesta missão. Tratar como investigação, sem afirmar que já há duplicados reais.

## Proposta de mapa de preços para o Encarregado — NÃO IMPLEMENTADA

**Interface tablet:** uma pesquisa de artigo → unidade/grupo de comparação → lista vertical. Cada cartão mostra fornecedor, preço líquido por unidade, data, origem comercial (proposta/adjudicado/faturado), obra de referência apenas se autorizada, observação de validade/condições e “informação histórica”. Ação opcional PEDIR CONSULTA, sujeita a regra aprovada; nenhuma ação COMPRAR/ADJUDICAR/PAGAR.

**Contrato mínimo:** empresa do ator ativo, permission capability específica de leitura, artigos/unidades/condições identificados, preço decimal, moeda/base fiscal, data/vigência, quantidade de referência, proveniência verificável e aviso de incomparabilidade. Não enviar NIF privado, notas negociais confidenciais, faturas inteiras, custos RH nem dados de outras empresas.

**Backend:** reutilizar fontes já existentes através de um leitor dedicado; validar tenant das FKs e obra/origem permitida. Se a empresa aprovar partilha de preços de outras obras do mesmo tenant, aprovar expressamente essa extensão de leitura, sem conceder acesso à obra/fatura/subempreitada original. Filtrar dados no servidor, não “SELECT * + esconder no frontend”. O acesso direto a tabelas financeiras deve continuar negado ao Encarregado.

**Comparabilidade:** chave artigo normalizado + especificação/material + unidade aprovada + moeda + base IVA + transporte/serviço + quantidade/escopo. Não inferir equivalência de produtos por texto parecido, nem fator de densidade. Não eleger melhor preço em grupo incomparável. Preço ausente/pendente permanece desconhecido.

**Histórico:** referência ao objeto e revisão da fonte; distinguir informação conhecida na data de preços posteriores. Não copiar dados monetários para a Folha. Uma futura compra deve ter a sua própria decisão/autor/pedido e permissões independentes.

**Dependências para aprovação:** visibilidade comercial interobra; tipos de preços publicados; responsável pela qualidade/vigência; política de unidades; se Encarregado pode apenas consultar ou também enviar pedido. Recomendo começar por leitura de preços faturados/adjudicados identificados como históricos, sem cotação atual implícita e sem autorização de compra.

## Testes/limitações

Regressões específicas incluídas nos 108 PASS do bloco Financeiro/Compras: especialidades, zonas, cadastro, preenchimento seguro, comparativo dinâmico/PDF, descontos e propostas pendentes do Planeamento. Instalação, preços, duplicados, paginação e fornecedores reais NÃO VERIFICADOS. Não é levantamento exaustivo da qualidade dos cadastros.
