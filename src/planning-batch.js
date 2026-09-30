import { previewPlanningBatch } from './planning-operational.js';

export function planningChanges(original, current) {
  const previous = new Map(original.map(item => [item.id, item]));
  return current.flatMap(item => {
    const before = previous.get(item.id);
    if (!before) return item._archive ? [] : [{ ...item, _new: true }];
    const changes = Object.fromEntries(Object.entries(item).filter(([key, value]) => key !== 'id' && (key === '_archive' ? Boolean(value) !== Boolean(before[key]) : value !== before[key])));
    return Object.keys(changes).length ? [{ id: item.id, ...changes }] : [];
  });
}

export function batchPreview(original, current, phases, dependencies) {
  return previewPlanningBatch({ items: original, changes: planningChanges(original, current), phases, dependencies });
}

// This protocol requires server validation, preview token and atomic confirmation.
// An unavailable RPC must leave the local draft intact. Never fall back to PATCH.
export async function requestPlanningBatch(api, payload, confirmationToken = null) {
  const response = await api('rpc/fn_guardar_planeamento_lote', {
    method: 'POST', body: JSON.stringify({ p_lote: payload, p_confirmacao: confirmationToken }),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    if (response.status === 404 || error.code === 'PGRST202') throw new Error('A gravação em lote aguarda suporte transacional no servidor. As alterações continuam locais.');
    throw new Error(error.message || 'O lote não foi guardado. As alterações continuam locais.');
  }
  const result = await response.json();
  if (result?.version !== 1 || (confirmationToken ? result.committed !== true : typeof result.confirmation_token !== 'string')) throw new Error('Resposta de lote inválida; confirme o estado antes de repetir a operação.');
  return result;
}
