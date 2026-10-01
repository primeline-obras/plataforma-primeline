// Alocação explícita da data; responsabilidade por obra não cria presença.
export function allocationsForDate(items, date) {
  return items.filter(item => item.data === date);
}

export function allocationError(error) {
  const message = String(error?.message || error || '');
  if (/STALE_REVISION/i.test(message)) return 'A alocação foi alterada por outro utilizador. O Quadro foi recarregado; reveja antes de voltar a guardar.';
  if (/IDEMPOTENCY_CONFLICT/i.test(message)) return 'Este pedido já foi usado para outra operação. Recarregue o Quadro antes de tentar novamente.';
  if (/LEGACY_CONFLICT|OVERLAP_CONFLICT/i.test(message)) return 'Há alocações sobrepostas neste dia/período. Solicite revisão ao Administrativo; nenhuma alocação foi alterada.';
  if (/ABSENCE_CONFLICT|férias\/ausente/i.test(message)) return 'O colaborador tem uma ausência neste dia. Não é possível criar uma alocação incompatível.';
  if (/PERMISSION_DENIED|42501|permission denied/i.test(message)) return 'Não tem permissão para alterar esta origem ou destino na empresa atual.';
  if (/CONTRACT_VERSION|function .* does not exist|PGRST202/i.test(message)) return 'O backend de alocação controlada ainda não está disponível. Nenhuma alteração foi guardada.';
  return message || 'Não foi possível guardar a alocação. O estado anterior foi preservado.';
}

export function createWorkforceAllocationClient({ supabase, reload = async () => {}, requestId = () => crypto.randomUUID() }) {
  async function rpc(acao, dados, confirmar, versao = null) {
    const response = await supabase('rpc/fn_quadro_operar_v1', {
      method: 'POST', body: JSON.stringify({ p_acao: acao, p_dados: dados, p_confirmar: confirmar, p_versao: versao }),
    });
    const result = await response.json().catch(() => null);
    if (!response.ok) throw new Error(result?.message || result?.error || `Erro HTTP ${response.status}`);
    return result;
  }
  async function execute(acao, values) {
    const dados = { ...values, version: 1, request_id: requestId() };
    try {
      const preview = await rpc(acao, dados, false);
      if (preview?.version !== 1 || preview.committed !== false || typeof preview.versao !== 'string') {
        throw new Error('Resposta inválida do preview; nenhuma confirmação foi enviada.');
      }
      // Uma confirmação. Sem retry automático, inclusive após erro de rede/revisão.
      const result = await rpc(acao, dados, true, preview.versao);
      if (result?.version !== 1 || result.committed !== true) throw new Error('O backend não confirmou a gravação. Recarregue para verificar o estado.');
      if (acao !== 'renomear_linha' && (!Array.isArray(result.allocations) || !Number.isInteger(result.revision))) {
        throw new Error('Resposta incompleta do backend. Recarregue para verificar a alocação.');
      }
      return result;
    } catch (error) {
      if (/STALE_REVISION/i.test(error.message)) await reload();
      const friendly = new Error(allocationError(error)); friendly.cause = error;
      throw friendly;
    }
  }
  return { execute };
}
