export function summaryFixture() {
  return { version: 1, source: 'traceable_v1', work_id: 'work', year: 2026, snapshot_id: 'snap1', as_of: '2026-09-28', operational_end: '2026-12-31', opening_balance: 0, current_balance: 100, overdue: 20, average_receipt_delay: 3, unprogrammed_count: 1, outside_period_count: 0,
    states: Array.from({ length: 12 }, (_, index) => ({ month: `2026-${String(index + 1).padStart(2, '0')}`, state: index === 0 ? 'fechado' : 'aberto', revision: `r${index}` })),
    rows: Array.from({ length: 12 }, (_, index) => ({ month: `2026-${String(index + 1).padStart(2, '0')}`, received: index === 8 ? 100 : 0, receivable: index === 9 ? 20 : 0, future_income: 0, paid: 0, payable: 0, future_cost: 0 })) };
}
export const preservedFixture = { closed_months: true, historical_measurements: true, actual_movements: true };
