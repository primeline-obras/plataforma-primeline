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
