import { dateDay } from "./planning-operational.js?v=1";
export function cents(value) {
  if (value === null || value === undefined || value === "" || !Number.isFinite(Number(value))) throw new Error("Valor monetário inválido.");
  const result = Math.round(Number(value) * 100);
  if (!Number.isSafeInteger(result)) throw new Error("Valor monetário fora do limite.");
  return result;
}
export function movementBalance(total, movements) {
  const expected = cents(total), seen = new Set();
  const received = movements.reduce((sum, row) => {
    if (!row.id || seen.has(row.id)) throw new Error("Movimento sem identidade ou duplicado.");
    seen.add(row.id);
    if (dateDay(row.data) === null || cents(row.valor) <= 0) throw new Error("Movimento inválido.");
    return sum + cents(row.valor);
  }, 0);
  if (expected < 0 || received > expected) throw new Error("Movimentos excedem o valor do documento.");
  return { settled: received / 100, outstanding: (expected - received) / 100, state: received === expected ? "pago" : received > 0 ? "parcial" : "por_pagar" };
}
export async function recordReceipt(request, billing, movement) {
  const value = cents(movement.valor), outstanding = cents(billing.valor) - cents(billing.valor_recebido ?? 0);
  if (dateDay(movement.data) === null || value <= 0 || value > outstanding || !movement.requestId) throw new Error("Indique uma data válida e uma parcela positiva até ao saldo por receber.");
  const response = await request("rpc/fn_registar_recebimento_parcial", { method: "POST", body: JSON.stringify({ p_version: 1, p_faturacao_id: billing.id,
    p_data: movement.data, p_valor: value / 100, p_request_id: movement.requestId, p_valor_recebido_esperado: billing.valor_recebido ?? 0 }) });
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(response.status === 404 || result?.code === "PGRST202" ? "O registo de parcelas ainda não tem suporte transacional. Nenhum valor local foi substituído." : result?.message || "Não foi possível confirmar o recebimento.");
  if (result?.version !== 1 || result?.committed !== true || result?.billing?.id !== billing.id) throw new Error("O serviço não confirmou o movimento e o saldo da fatura.");
  // Official totals must come from the server's movements, including legacy
  // reconciliation. Never increment the cached aggregate as a substitute.
  const updated = result.billing;
  if (cents(updated.valor) !== cents(billing.valor) || cents(updated.valor_recebido) < cents(billing.valor_recebido ?? 0) + value || cents(updated.valor_recebido) > cents(updated.valor)) throw new Error("Saldo devolvido inconsistente; atualize a fatura antes de continuar.");
  return updated;
}
