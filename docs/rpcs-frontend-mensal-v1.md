# Contratos finais exigidos pelo frontend

Estado: contratos propostos e testados com mocks; **não instalados nem validados na BD**. Não foi gerado ou executado SQL. O schema fornecido não contém estas capacidades. Todos os caminhos abaixo são POST `rpc/<nome>`; autenticação e autorização por obra são obrigatórias no servidor.

## Convenções

- Datas: `YYYY-MM-DD`; competência: `YYYY-MM`; ano: inteiro.
- O motor e as quatro RPCs mensais usam **cêntimos inteiros**, não negativos para valores dos seis estágios. Saldos podem ser negativos. Moeda EUR.
- Planeamento, TEE e recebimentos conservam os valores decimais em euros dos seus contratos existentes. Nunca misturar as unidades.
- `snapshot_id` identifica um resumo imutável com as respetivas origens. Uma paginação nunca atravessa snapshots.
- Estados: `real | fechado | em_fecho | aberto | previsao`. Não são inferidos pela data nem pelo valor realizado. `real/fechado` protegem a geração económica por competência; não bloqueiam caixa noutra data.
- Escritas com `p_request_id` devem ser idempotentes, vinculadas ao utilizador e conteúdo. Reutilização com conteúdo diferente: conflito. Token de planeamento exerce a mesma função.
- Erro HTTP não-2xx: `{ "code": string, "message": string, "conflicts": object[] }`. `conflicts` pode ser omitido quando vazio.
- Erros comuns: 401/403 `FORBIDDEN`, 409 `STALE_REVISION` / `STALE_SNAPSHOT` / `IDEMPOTENCY_CONFLICT`, 422 `VALIDATION_FAILED` / `PROTECTED_PERIOD` / `DUPLICATE_ORIGIN` / `UNRECONCILED_SOURCE`; 404 ou `PGRST202` significa serviço indisponível. Nunca confirmar escrita apenas por HTTP 200: a resposta deve cumprir o contrato.
- Ausência/erro deixa o frontend sem dados oficiais ou com o rascunho preservado. Não há fallback para PATCH/DELETE por linha nem soma com agregados legados.

## Tipo Summary (resposta partilhada)

Todos os campos abaixo são obrigatórios. `notes` é opcional. `rows` e `states` têm exatamente os doze meses do ano, sem duplicados. O backend calcula as parcelas mutuamente exclusivas a partir das origens, não de `previsao_financeira_mensal` legada.

```ts
type Summary = {
  version: 1;
  source: "traceable_v1";
  work_id: string;
  year: number;
  snapshot_id: string;
  as_of: string;             // data da posição de caixa
  operational_end: string;   // fim operacional; não fim contratual
  opening_balance: number;  // cêntimos, posição no início do ano
  current_balance: number;  // caixa efetivo até as_of
  overdue: number;          // saldo cliente vencido, não deslocar datas
  average_receipt_delay: number | null; // dias de atraso ponderados pelo recebido
  unprogrammed_count: number;
  outside_period_count: number; // parcelas fora do ano; consultar outros anos
  states: { month: string; state: "real"|"fechado"|"em_fecho"|"aberto"|"previsao"; revision: string }[];
  rows: {
    month: string;
    received: number;
    receivable: number;
    future_income: number;
    paid: number;
    payable: number;
    future_cost: number;
    notes?: string;
  }[];
};
type Preserved = {
  closed_months: true;
  historical_measurements: true;
  actual_movements: true;
};
```

Os totais, saldos mensal/acumulado, mínimo e necessidade de caixa são calculados no frontend por `summarizeRows`. Datas de caixa podem ultrapassar o fim operacional; o backend deve conservar essas parcelas e assinalar as que ficam fora do ano consultado. Ausência de programação não permite atribuir mês fictício. Um estado mensal em falta é erro de dados, não zero nem previsão implícita.

## 1. fn_resumo_financeiro_mensal_v1

Payload exato: `{ "p_obra_id": string, "p_ano": number }`.

Resposta: `Summary`. Leitura sem mutações. Uma chamada por obra/ano, sem carregar a empresa inteira ou todos os documentos. Se a origem não estiver reconciliada/rastreável, devolver `UNRECONCILED_SOURCE` em vez de um resumo aparentemente oficial.

Chamada: `monthly-map.js`, abertura, atualização ou mudança de obra/ano; adaptador `readMonthlySummary` em `monthly-api.js`.

Erros específicos: `UNRECONCILED_SOURCE`, `VALIDATION_FAILED`, `UNAVAILABLE`. Resposta com fonte legada, obra errada, mês repetido ou valores inválidos é recusada no cliente.

## 2. fn_origens_financeiras_mensais_v1

```ts
// Payload exato
{ p_obra_id: string; p_snapshot_id: string; p_mes: string;
  p_estagio: "received"|"receivable"|"future_income"|"paid"|"payable"|"future_cost";
  p_cursor: string | null; p_limite: 50 | 100 }
// Resposta
{ version: 1; work_id: string; snapshot_id: string; month: string;
  stage: string; total_amount: number; next_cursor: string | null;
  rows: { allocation_id: string; origin_id: string; origin_type: string;
    label: string; amount: number; date: string; competence_month: string;
    document_id?: string; movement_id?: string }[] }
```

`total_amount` é o valor integral da célula, não o subtotal da página. Ordem estável, IDs de parcela únicos em todas as páginas; último cursor null. O frontend valida snapshot, obra, mês, estágio, soma e duplicados. Sem leitura antecipada: abre apenas por clique numa célula, 50 linhas por página.

Chamada: `monthly-map.js:detailPage` → `readMonthlyOrigins`. Erros: `STALE_SNAPSHOT`, `DUPLICATE_ORIGIN`, `INVALID_CURSOR`, comuns. Um snapshot vencido obriga a atualizar o mapa, não a misturar detalhe novo com resumo antigo.

## 3. fn_definir_estado_mensal_v1

Payload exato: `{ p_obra_id: string, p_mes: string, p_estado: string, p_revisao_esperada: string, p_request_id: string }`.

Resposta: `{ version: 1, committed: true, month: string, state: string, revision: string }`.

Chamada: botão CONFIRMAR ESTADO em `monthly-map.js` → `changeMonthlyState`. O servidor valida permissões, revisão, condições reais de fecho e regista autor/data/transição. O frontend não permite reabrir `real/fechado`; reabertura exige processo auditado separado. Nenhum estado local é alterado antes da confirmação. Depois, relê o resumo.

Erros: `STALE_REVISION`, `PROTECTED_PERIOD`, `CLOSURE_INCOMPLETE` com pendências, comuns. Fechar competência não marca documentos como pagos/recebidos.

## 4. fn_recalcular_previsao_mensal_v1

Payload exato: `{ p_obra_id: string, p_snapshot_id: string, p_meses: string[], p_request_id: string }`.

Resposta: `{ version: 1, committed: true, preserved: Preserved, summary: Summary }`.

Chamada: botão RECALCULAR PREVISÃO ABERTA em `monthly-map.js` → `recalculateMonthly`. O cliente envia só competências não protegidas do ano apresentado. O servidor volta a validar estados sob lock; recalcula o remanescente económico e as suas datas de caixa numa transação. Preserva movimentos, autos históricos e snapshots económicos protegidos. A declaração `preserved` não substitui essas garantias no backend.

Erros: `STALE_SNAPSHOT`, `PROTECTED_PERIOD`, `UNRECONCILED_SOURCE`, `DUPLICATE_ORIGIN`, comuns. Triggers legados não podem gravar previsões concorrentes na mesma transação. Resposta sem preservação ou resumo válido não é sucesso no cliente; após resposta ambígua deve atualizar antes de repetir.

## 5. fn_guardar_planeamento_lote (blocos A/B, integração I)

```ts
{ p_lote: {
    version: 1; obra_id: string;
    changes: object[]; // {id, campos operacionais alterados, _new?, _archive?}
    expected_items: object[];
    dependencies: object[]; expected_dependencies: object[];
    archive_reason: string | null;
    approved_cascade: {id: string; data_inicio_prevista: string; data_fim_prevista: string}[];
  }; p_confirmacao: string | null }
// Preview, sem mutação
{ version: 1; confirmation_token: string; conflicts: object[];
  approved_cascade: {id: string; data_inicio_prevista: string; data_fim_prevista: string}[] }
// Confirmação
{ version: 1; committed: true; preserved: Preserved;
  financial_summary: Summary }
```

Chamada: `planning.js:confirmBatch` → `planning-batch.js:requestPlanningBatch`. O mesmo lote é enviado nas duas chamadas. Confirmar apenas cascata idêntica ao preview. Servidor valida pesos, datas, ciclos, referências/obra, concorrência e arquivo sem apagar relações. Atualiza planeamento, cascata, resumos de fase/progresso e previsão aberta numa só transação. Não executar um segundo recálculo cego a partir do browser.

Erros: `WEIGHT_CONFLICT`, `DEPENDENCY_CYCLE`, `MANUAL_DATE_COLLISION`, `ARCHIVED_DEPENDENCY`, `TOKEN_EXPIRED`, `STALE_REVISION`, comuns. Um lote confirmado com resumo ausente **não é repetido**: frontend informa “recálculo financeiro por confirmar” e invalida o mapa. Callback `onCommitted` em `app.js` chama `financialMapModule.invalidate`.

## 6. fn_importar_tees_revisoes (bloco E)

```ts
{ p_version: 1; p_obra_id: string; p_nome_ficheiro: string;
  p_linhas: {
    id?: string; expected: object | null;
    obra_id?: string; numero?: string; fase_id?: string | null;
    descricao?: string; especialidade?: string; valor?: number;
    preco_custo?: number; dias_prorrogacao?: number;
    data_envio?: string; data_resposta?: string; revisao?: string;
    data_inicio_execucao?: string; data_fim_execucao?: string;
    estado_aprovacao_cliente?: "pendente"|"aprovado"|"recusado";
    estado_operacional?: "em_elaboracao"|"aguarda_resposta"|"aprovado"|"rejeitado";
    itens?: { linha: number; numero_artigo: string; descricao: string;
      unidade: string | null; quantidade: number | null;
      preco_unitario: number | null; valor_total: number | null }[];
  }[] }
// Resposta
{ version: 1; committed: true; importadas: number }
```

Chamada: `xlsx-operational-import.js:confirmImport` → `tee-index.js:requestTeeRevisionImport`. Campos omitidos preservam os existentes. `expected` permite detetar concorrência e repetição: se as alterações já estiverem aplicadas com o mesmo snapshot de origem, devolver confirmação idempotente; não criar outra revisão. O servidor deve manter um histórico imutável com utilizador/data antes de alterar cabeçalho ou itens. Número normalizado único por obra; nunca copiar IDs entre `itens_tee` e `alteracoes_tee_itens`. Itens ausentes preservam itens atuais; não apagam medições ou documentos.

Erros: `AMBIGUOUS_TEE`, `STALE_REVISION`, `MEASURED_ITEM_CONFLICT`, `INVALID_STATE`, comuns. Sem fallback para `fn_importar_tees_xlsx`.

## 7. fn_registar_recebimento_parcial (bloco F)

Payload exato: `{ p_version: 1, p_faturacao_id: string, p_data: string, p_valor: number, p_request_id: string, p_valor_recebido_esperado: number }` (valores em euros).

Resposta: `{ version: 1, committed: true, billing: { id: string, valor: number, valor_recebido: number, estado_pagamento: string, ...campos_atualizados_da_faturacao } }`.

Chamada: `app.js:openPaymentDialog` → `financial-movements.js:recordReceipt`. Movimento imutável com identidade, faturacao_id, valor, data, autor e timestamp. Saldo oficial derivado da soma dos movimentos; tratar legado sem inventar parcelas históricas. `estado_pagamento` deve respeitar o schema suportado; recebimento parcial não pode ser “pago”. Backend deve ligar a revisão do mapa às alterações de movimentos.

Erros: `STALE_REVISION`, `AMOUNT_EXCEEDS_BALANCE`, `UNRECONCILED_SOURCE`, `IDEMPOTENCY_CONFLICT`, comuns. Sem chamada à marcação integral antiga e sem substituição local do acumulado.

## Contrato do motor puro

`monthly-engine.js` não faz I/O. `projectSource` recebe uma origem económica identificada (`id`, `origin_type`, `direction`, `amount`, `competence_month`) com documentos e movimentos em cêntimos. Soma documentos contra a origem e movimentos contra cada documento, distribuindo apenas o remanescente. `remaining_calendar` refere-se exclusivamente ao remanescente; depois aplica due_date, subcontract_date ou active_months iguais. TEEs exigem approved=true e calendário/meses de execução reais. Datas de envio/resposta nunca são usadas.

Saída: parcelas `{ allocation_id, origin_id, origin_type, stage, amount, date, competence_month, document_id?, movement_id?, due_date?, preserved? }`. `allocation_id` deve identificar uma parcela económica única: o backend não pode representar o mesmo valor sob dois IDs. Cada documento/movimento repartido por várias origens deve ter alocação explícita e soma validada no servidor.

`monthlyEngine` recebe `{version:1, source:"traceable_v1", entries, states, from, to, today, opening_balance}`. Rejeita duplicados, dados inválidos e previsão genérica numa competência protegida. `preserved:true` só pode vir de um snapshot económico protegido e auditado, nunca de um pedido de edição do cliente. Mantém caixa na data própria. Parcelas fora do intervalo são devolvidas em `outsidePeriod`, não descartadas silenciosamente.

## Testes e limites

- `monthly-state.test.mjs`: estados explícitos e bloqueio de reabertura.
- `monthly-engine.test.mjs`: conservação dos estágios, parciais, vencidos, calendário e proteção da competência.
- `monthly-api.test.mjs`: mocks das quatro RPCs mensais e da confirmação financeira do lote, payloads, 404, conflito e respostas inválidas.
- `planning-batch.test.mjs`, `tee-index.test.mjs`, `financial-movements.test.mjs`: mocks das três RPCs anteriores e ausência de fallback.
- `monthly-browser.mjs`: navegador offline, resumo indisponível, detalhe lazy, conflito sem sucesso, recálculo preservado, snapshot errado e invalidação após planeamento.
- `planning-browser.mjs`: lote local permanece intacto sem RPC.

Sem validação PostgreSQL, RLS, concorrência real ou triggers. Essas verificações ficam pendentes da implementação do backend fora deste repositório. Não houve deploy, merge ou backfill.
