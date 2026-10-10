import { platformConfirm } from './platform-dialogs.js?v=1';
// Identificador estável exposto pelo módulo servido; a prova operacional continua humana.
export const WORKFORCE_FRONTEND_CONTRACT = Object.freeze({ version: 1, releaseId: 'quadro_frontend_contract_v1' });
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
  if (/TEAM_SAME_WORK/i.test(message)) return 'A pessoa já integra esta equipa nesta data. Não é necessário voltar a alocar.';
  if (/TEAM_FULL_DAY_REQUIRED/i.test(message)) return 'A equipa permanece na obra até retirada ou transferência. Registe os períodos trabalhados na Folha de Ponto.';
  if (/TEAM_HISTORY_READ_ONLY/i.test(message)) return 'Esta linha diária é histórica. Confirme a permanência pela Folha de Ponto antes de a retirar.';
  return message || 'Não foi possível guardar a alocação. O estado anterior foi preservado.';
}

export function createWorkforceAllocationClient({ supabase, reload = async () => {}, requestId = () => crypto.randomUUID(), confirm = message => platformConfirm(message,{title:'Equipa da obra',confirmLabel:'CONFIRMAR'}) }) {
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
      if(preview.team_contract===1&&!await confirm(preview.summary||'Confirmar alteração da permanência da equipa?'))return null;
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
