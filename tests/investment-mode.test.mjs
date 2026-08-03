import assert from "node:assert/strict";
import { investmentFinancialValues, isInvestmentWork, totalClientBilling } from "../src/production-dashboard.js";

const work118 = { numero: 118, modalidade: "investimento_proprio" };
const investment118 = {
  orcamento_inicial_sem_iva: 39907.94,
  orcamento_revisto_sem_iva: 53390.37,
};
assert.equal(isInvestmentWork(work118), true);
assert.deepEqual(investmentFinancialValues(investment118, 0), {
  initialBudget: 39907.94,
  revisedBudget: 53390.37,
  actualCost: 0,
  deviation: -53390.37,
});

const work120 = { numero: 120, modalidade: "cliente_externo" };
const contract120 = { valor_adiantamento: 110723.84 };
assert.equal(isInvestmentWork(work120), false);
assert.equal(totalClientBilling(contract120, [{ valor_a_faturar: 106248.68 }]), 216972.52);

console.log("Modalidades financeiras validadas para as obras 118 e 120.");
