const MONTH_INTERVALS = { mensal: 1, trimestral: 3, anual: 12 };

export const DIRECT_DEBIT_CATEGORY_LABELS = {
  renda: "Renda",
  seguro: "Seguro",
  software: "Software",
  emprestimo: "Empréstimo",
  servico_publico: "Serviço público",
  remuneracoes_sede: "Remunerações e Encargos (Sede)",
  despesas_sede: "Despesas Sede",
  despesas_armazem: "Despesas Armazém",
  outro: "Outro",
};

export const DIRECT_DEBIT_RECURRENCE_LABELS = {
  mensal: "Mensal",
  trimestral: "Trimestral",
  anual: "Anual",
};

const isoDate = date => {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

const parseDate = value => value ? new Date(`${String(value).slice(0, 10)}T12:00:00`) : null;
const monthIndex = date => date.getFullYear() * 12 + date.getMonth();

export function directDebitOccurrences(debit, rangeStart, rangeEnd) {
  const interval = MONTH_INTERVALS[debit?.recorrencia];
  const start = parseDate(debit?.data_inicio);
  const from = parseDate(rangeStart);
  const to = parseDate(rangeEnd);
  const finish = parseDate(debit?.data_fim);
  if (!debit?.ativo || !interval || !start || !from || !to || from > to) return [];

  const firstMonth = new Date(from.getFullYear(), from.getMonth(), 1, 12);
  const lastMonth = new Date(to.getFullYear(), to.getMonth(), 1, 12);
  const requestedDay = Number(debit.dia_mes) || start.getDate();
  const rows = [];

  for (const cursor = new Date(firstMonth); cursor <= lastMonth; cursor.setMonth(cursor.getMonth() + 1)) {
    const distance = monthIndex(cursor) - monthIndex(start);
    if (distance < 0 || distance % interval !== 0) continue;
    const lastDay = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0, 12).getDate();
    const occurrence = new Date(cursor.getFullYear(), cursor.getMonth(), Math.min(requestedDay, lastDay), 12);
    if (occurrence < start || occurrence < from || occurrence > to || (finish && occurrence > finish)) continue;
    rows.push({
      debito_direto_id: debit.id,
      data: isoDate(occurrence),
      valor: Number(debit.valor_previsto || 0),
      descricao: debit.descricao,
      obra_id: debit.obra_id || null,
    });
  }
  return rows;
}

export function directDebitForecastByMonth(debits, rangeStart, rangeEnd) {
  const totals = new Map();
  debits.forEach(debit => {
    directDebitOccurrences(debit, rangeStart, rangeEnd).forEach(row => {
      const month = row.data.slice(0, 7);
      totals.set(month, (totals.get(month) || 0) + row.valor);
    });
  });
  return totals;
}
