import { dateDay } from "./planning-operational.js?v=1";
export const teeIdentity = value => String(value ?? "").trim().normalize("NFKC").replace(/\s+/g, " ").toLocaleLowerCase("pt-PT");
const present = value => value !== null && value !== undefined && String(value).trim() !== "";
const fields = ["fase_id", "descricao", "especialidade", "valor", "preco_custo", "dias_prorrogacao", "data_envio", "data_resposta", "revisao", "data_inicio_execucao", "data_fim_execucao"];
export function teeState(value, sentDate) {
  const state = teeIdentity(value).replaceAll(" ", "_");
  if (!state || state === "pendente") return { operational: sentDate ? "aguarda_resposta" : "em_elaboracao", client: "pendente", suggested: !state };
  const mapping = { em_elaboracao: "pendente", aguarda_resposta: "pendente", aprovado: "aprovado", rejeitado: "recusado", recusado: "recusado" };
  if (!mapping[state]) throw new Error("Estado TEE inválido.");
  return { operational: state === "recusado" ? "rejeitado" : state, client: mapping[state], suggested: false };
}

export function previewTeeIndex(incoming, existing, workId) {
  const counts = new Map();
  incoming.forEach(row => counts.set(teeIdentity(row.numero), (counts.get(teeIdentity(row.numero)) || 0) + 1));
  return incoming.map(row => {
    const errors = [], warnings = [], key = teeIdentity(row.numero);
    const matches = existing.filter(item => item.obra_id === workId && teeIdentity(item.numero) === key);
    if (!key || counts.get(key) > 1 || matches.length > 1) errors.push("Número TEE vazio ou ambíguo nesta obra.");
    if (row.obra_id !== workId) errors.push("TEE de outra obra.");
    const previous = matches[0], changes = {};
    for (const field of fields) if (present(row[field]) && row[field] !== previous?.[field]) changes[field] = row[field];
    let state;
    try {
      const operational = present(row.estado_operacional) ? teeIdentity(row.estado_operacional).replaceAll(" ", "_") : null;
      const client = present(row.estado_aprovacao_cliente) ? teeIdentity(row.estado_aprovacao_cliente).replaceAll(" ", "_") : null;
      if (operational && !["em_elaboracao", "aguarda_resposta", "aprovado", "rejeitado"].includes(operational)) throw new Error("Estado operacional TEE inválido.");
      if (client && !["pendente", "aprovado", "recusado"].includes(client)) throw new Error("Estado do cliente TEE inválido.");
      if (client && client !== previous?.estado_aprovacao_cliente) changes.estado_aprovacao_cliente = client;
      if (operational && operational !== previous?.estado_operacional) changes.estado_operacional = operational;
      if (!previous) {
        changes.estado_aprovacao_cliente = client || "pendente";
        changes.estado_operacional = operational || teeState(changes.estado_aprovacao_cliente, row.data_envio).operational;
      }
      state = {
        operational: changes.estado_operacional ?? previous?.estado_operacional,
        client: changes.estado_aprovacao_cliente ?? previous?.estado_aprovacao_cliente,
        suggested: !previous && !operational,
      };
    } catch (error) { errors.push(error.message); }
    if (!previous) Object.assign(changes, { obra_id: workId, numero: String(row.numero || "").trim(), fase_id: row.fase_id || null });
    const merged = { ...previous, ...changes };
    if (!present(merged.descricao)) errors.push("Descrição obrigatória.");
    for (const field of ["valor", "preco_custo", "dias_prorrogacao"]) if (present(merged[field]) && !Number.isFinite(Number(merged[field]))) errors.push(`${field} inválido.`);
    for (const field of ["data_envio", "data_resposta", "data_inicio_execucao", "data_fim_execucao"]) if (present(merged[field]) && dateDay(merged[field]) === null) errors.push(`${field} inválida.`);
    if (merged.data_inicio_execucao && merged.data_fim_execucao && merged.data_inicio_execucao > merged.data_fim_execucao) errors.push("Fim de execução anterior ao início.");
    const unprogrammed = merged.estado_aprovacao_cliente === "aprovado" && (!merged.fase_id || !merged.data_inicio_execucao || !merged.data_fim_execucao);
    if (unprogrammed) warnings.push("TEE aprovado · execução por programar");
    const items = row.itens?.length ? row.itens : undefined;
    if (items) changes.itens = items;
    const sale = present(merged.valor) ? Number(merged.valor) : null;
    const cost = present(merged.preco_custo) ? Number(merged.preco_custo) : null;
    const margin = sale !== null && cost !== null ? sale - cost : null;
    return { status: errors.length ? "BLOQUEADO" : !previous ? "NOVO" : Object.keys(changes).length ? "VAI ATUALIZAR" : "SEM ALTERAÇÃO",
      errors, warnings, previous, changes, state, unprogrammed, margin, marginPercent: margin !== null && sale ? margin / sale * 100 : null };
  });
}

export async function requestTeeRevisionImport(api, payload) {
  const response = await api('rpc/fn_importar_tees_revisoes', { method: 'POST', body: JSON.stringify(payload) });
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(response.status === 404 || result?.code === 'PGRST202' ? 'A importação de revisões aguarda suporte transacional. O preview foi preservado.' : result?.message || 'A revisão TEE não foi confirmada.');
  if (result?.version !== 1 || result.committed !== true || !Number.isInteger(result.importadas) || result.importadas < 0) throw new Error('A revisão TEE não foi confirmada pelo serviço transacional.');
  return result;
}
