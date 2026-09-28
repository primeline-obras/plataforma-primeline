// Permissões específicas do quadro; não herdar poderes gerais de RH/Gerência.
export const canManageGeneralWorkforce = role => ["gestao_plataforma", "administrativo"].includes(role);
export const canReadWorkforceHistory = role => canManageGeneralWorkforce(role) || role === "encarregado";
export async function workforceRequest(api, action, payload, confirm = false, version = null) {
  const response = await api("rpc/fn_quadro_operar", {
    method: "POST",
    body: JSON.stringify({ p_acao: action, p_dados: payload, p_confirmar: confirm, p_versao: version }),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message || "Não foi possível alterar o quadro.");
  return result;
}
