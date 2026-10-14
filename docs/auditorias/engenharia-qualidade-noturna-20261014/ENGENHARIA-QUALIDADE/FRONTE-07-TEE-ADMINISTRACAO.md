# Frente 7 — TEE por administração direta: cenário sintético 128

Estado: estudo conceptual concluído; nenhuma implementação. A obra e todos os valores abaixo são sintéticos, sem acesso à Obra128 real.

## Separação obrigatória

| Camada | Exemplo sintético | Fonte/controlo proposto |
|---|---|---|
| Estimativa | Custo previsto700; venda prevista1000 | Orçamento identificado; revisão própria |
| Autorização | Serviço autorizado com limite e descrição | Decisão comercial registada; não equivale a fatura |
| Trabalho realizado | 2 dias; intervalos e quantidades reais | Factos operacionais preservados e rastreáveis |
| Materiais reais | 80 | Documento/quantidade efetivamente aplicada |
| Equipamento real | 40 | Uso/contrato/unidade explícitos |
| Mão de obra real | Por apurar | Sem tarifa comprovada: NULL; nunca zero inferido |
| Custo conhecido | 120 parcial | Mostrar incompletude; custo total permanece pendente |
| Preço contratual final | Por decidir | Contrato/aditamento aprovado e vigência |
| Valor faturável | Pendente | Não copiar custo real, estimativa ou autorização para faturação |

## Percurso

Estimativa → aprovação com âmbito → registo diário por recurso/obra → revisão técnica → reconciliação dos custos comprovados → decisão de preço contratual → medição/faturação segundo contrato.

Interrupção e aumento de quantidade não podem reescrever factos anteriores. Cada alteração requer revisão, autor e motivo. Corrigir um recurso não apaga o registo original nem muda automaticamente o preço do cliente.

## Proposta de apresentação administrativa

- Cabeçalho: TEE/obra/estado comercial/revisão.
- Coluna Estimativa: custos/venda e fonte.
- Coluna Execução: dias, pessoas, materiais, equipamento e documentos.
- Coluna Reconciliação: custo conhecido, parcelas pendentes, custo total por confirmar.
- Coluna Comercial: preço contratual e faturável, separados e pendentes quando necessário.
- Histórico: revisões e autorizações; referências aos factos, sem tarifas RH expostas à equipa técnica.

## Decisões necessárias

Quem aprova o preço final; como o contrato prevê administração direta; critérios de afetação de equipamento/transporte; tratamento comercial de interrupções e excedentes. Nenhuma inferência automática de salário/tarifa. Não foi criado writer, tabela, ecrã, migration ou cálculo salarial.

## Mapa explícito das13 etapas

| Etapa | Contrato existente / proposta | Estado e controlo |
|---|---|---|
|1 Trabalho identificado|alteracoes_tee e descrição por obra/fase|Identidade/obra explícitas; não criar custo|
|2 Estimativa preparada|valor/preco_custo e itens do TEE|Estimativa separada do realizado; fonte/revisão|
|3 Cliente aprova|estado_aprovacao_cliente/data_resposta|Autorização de execução não fixa automaticamente preço final por administração|
|4 Execução em vários dias|Factos Folha V2 por pessoa/obra/data|Ligação granular ao TEE ainda exige desenho; não duplicar minutos|
|5 Vários trabalhadores|colaborador_id/externo_id e intervalos|Identidades explícitas; externo mantém modelo separado|
|6 Materiais consumidos|Documento/itens e afetação comprovada|Proposta de vínculo ao TEE; não inferir consumo pelo orçamento|
|7 Equipamentos utilizados|Recurso/quantidade/unidade e prova|Proposta de vínculo; utilização não implica tarifa conhecida|
|8 Quantidade diferente da estimada|Estimativa10m2 versus realizado8m2 no estudo|Manter ambos; não reescrever estimativa|
|9 Interrupção|Evento do estudo com hours_created=false|Não inventar horas, ausência ou preço|
|10 Correção do apontamento|Revisão2 ligada à1 com motivo|180min substituídos por150 ativos; original preservado|
|11 Conferência técnica|Revisão/autorização identificada|Conferência factual separada de decisão de tarifa RH|
|12 Apuramento do custo|Materiais80 + equipamento40 =120 conhecido|Mão de obra desconhecida; custo totalNULL, não zero|
|13 Valorização contratual|Regra/preço final ainda por decidir|Preço contratual/faturávelNULL; sem lançamento financeiro|

Provas conceptuais: fixtures/tee-administracao-128-synthetic.json e EVIDENCIAS-TEE-ESTUDO.json.870min ativos em5 revisões factuais, sem lançamento financeiro. Não são dados da Obra128 real.

Reutilização técnica: importador atual xlsx-operational-import.js.openTees chama fn_importar_tees_xlsx; fn_importar_tees_revisoes também existe no backend mas não é a RPC usada por esse botão neste checkpoint. planeamento_itens possui relação tee_id em tees_previsao_encarregados.sql. A tabela base folha_registos não contém ligação granular ao TEE; não alegar que o ciclo de custos por recurso/TEE já está implementado.
