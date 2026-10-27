export const VALIDITY_COLUMNS = { seguro: 'seguro_data', inspecao: 'data_inspecao_proxima' };

export function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(value + 'T12:00:00Z');
  return Number.isFinite(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

export function renewalExpiry(base, option, custom) {
  if (!validDate(base)) throw new Error('Indique uma data de renovação válida.');
  if (option === 'outra') {
    if (!validDate(custom) || custom <= base) throw new Error('O novo vencimento deve ser posterior à data da renovação.');
    return custom;
  }
  const years = { '1_ano': 1, '2_anos': 2 }[option];
  if (!years) throw new Error('Escolha a validade.');
  const [year, month, day] = base.split('-').map(Number);
  const lastDay = new Date(Date.UTC(year + years, month, 0)).getUTCDate();
  const result = String(year + years).padStart(4, '0') + '-' + String(month).padStart(2, '0') + '-' + String(Math.min(day, lastDay)).padStart(2, '0');
  if (!validDate(result)) throw new Error('Data de vencimento fora do intervalo permitido.');
  return result;
}

export function validityPayload(vehicle, type, operation, fields, requestId) {
  if (!Object.hasOwn(VALIDITY_COLUMNS, type) || !['editar_data', 'renovar'].includes(operation) || !vehicle?.id || !requestId) throw new Error('Pedido de validade inválido.');
  const reason = String(fields.motivo || '').trim();
  if (operation === 'editar_data' && (!validDate(fields.nova_data) || !reason)) throw new Error('Indique a nova data e o motivo da correção.');
  if (operation === 'renovar') renewalExpiry(fields.data_base, fields.validade_opcao, fields.nova_data);
  return {
    p_version: 1, p_viatura_id: vehicle.id, p_tipo: type, p_operacao: operation,
    p_data_atual_esperada: vehicle[VALIDITY_COLUMNS[type]] ?? null,
    p_data_base: operation === 'renovar' ? fields.data_base : null,
    p_validade_opcao: operation === 'renovar' ? fields.validade_opcao : null,
    p_nova_data: operation === 'editar_data' || fields.validade_opcao === 'outra' ? fields.nova_data : null,
    p_motivo: reason || null, p_request_id: requestId,
  };
}

export async function saveVehicleValidity(api, payload) {
  let response;
  try { response = await api('rpc/fn_guardar_validade_viatura', { method: 'POST', body: JSON.stringify(payload) }); }
  catch { throw new Error('Não foi possível confirmar a gravação. Verifique a ligação e atualize os dados antes de repetir.'); }
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    const code = result?.code;
    const message = code === 'STALE_REVISION' ? 'A validade foi alterada por outro utilizador. Atualize a frota antes de tentar novamente.'
      : response.status === 401 || response.status === 403 || ['FORBIDDEN', '42501'].includes(code) ? 'Não tem permissão para alterar esta validade.'
      : ['VALIDATION_FAILED', '22023', '23514'].includes(code) || response.status === 422 ? 'Dados de validade inválidos. Reveja as datas e o motivo.'
      : 'Não foi possível guardar a validade.';
    const error = new Error(message + (result?.message ? ' ' + result.message : ''));
    error.code = code;
    throw error;
  }
  if (result?.version !== 1 || result.committed !== true || result.vehicle?.id !== payload.p_viatura_id
      || !validDate(result.vehicle?.[VALIDITY_COLUMNS[payload.p_tipo]])) {
    throw new Error('O serviço não confirmou a validade e a viatura atualizada. Atualize os dados antes de repetir.');
  }
  return result;
}
