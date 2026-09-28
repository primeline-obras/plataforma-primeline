// The supplied schema has no reconciliation record. Keep its official legacy
// values until a backend exposes an explicitly reconciled, audited composition.
export const RECONCILIATION_NOTICE = "COMPOSIÇÃO HISTÓRICA POR RECONCILIAR";
const amount = value => value === null || value === undefined || value === "" || !Number.isFinite(Number(value)) ? null : Number(value);
export function legacyContractValues(contract = {}) {
  const initialSale = amount(contract.venda_contratual_inicial);
  const initialCost = amount(contract.custo_direto_inicial);
  return { status: "por_reconciliar", notice: RECONCILIATION_NOTICE,
    initialSale, initialCost,
    sale: amount(contract.venda_contratual_efetiva) ?? initialSale,
    cost: amount(contract.custo_direto_efetivo) ?? initialCost,
    reconciledResult: null };
}

export function clientFinancialComposition(contract = {}, approvedTees = []) {
  const legacy = legacyContractValues(contract);
  const total = field => approvedTees.reduce((sum, row) => sum + (amount(row[field]) ?? 0), 0);
  const sale = [legacy.initialSale, legacy.sale, total("valor"), null];
  const cost = [legacy.initialCost, legacy.cost, total("preco_custo"), null];
  return { ...legacy, sale, cost,
    margin: sale.map((value, index) => value === null || cost[index] === null ? null : value - cost[index]),
    fixedCosts: cost.map(value => value === null ? null : Math.round(value * 0.085 * 100) / 100) };
}
