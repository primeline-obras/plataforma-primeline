// Operational projections; the corresponding backend authorization is mandatory.
export async function loadForemanDirectory(supabase, date) {
  const call = async (name, body) => {
    const response = await supabase(`rpc/${name}`, {method:'POST', body:JSON.stringify(body)});
    if (!response.ok) throw new Error('Não foi possível confirmar o âmbito da equipa.');
    return response.json();
  };
  const scope = await call('fn_listar_ponto_obra', {p_data:date,p_obra_id:null});
  if (!Array.isArray(scope.obras)) throw new Error('Âmbito da equipa inválido.');
  const people = new Map();
  for (const work of scope.obras) {
    const result = await call('fn_listar_ponto_obra', {p_data:date,p_obra_id:work.id});
    if (!Array.isArray(result.linhas)) throw new Error('Equipa autorizada inválida.');
    for (const row of result.linhas) {
      people.set(row.colaborador_id, {id:row.colaborador_id,nome:row.nome,funcao:row.funcao,data_saida:null});
    }
  }
  // Medicine uses this installed predicate, which differs from the point's
  // per-period temporal selector. Do not infer permission from board history.
  const medicineIds = new Set();
  for (const person of people.values()) {
    if (await call('fn_colaborador_na_obra_atual_encarregado', {p_colaborador_id:person.id}) === true) medicineIds.add(person.id);
  }
  return {people:[...people.values()],medicineIds};
}

export async function loadForemanAbsences(supabase, start, end, vacationsOnly = false) {
  const response = await supabase('rpc/fn_ausencias_equipa_encarregado', {
    method: 'POST', body: JSON.stringify({p_inicio:start,p_fim:end}),
  });
  if (!response.ok) return response; // Never retry against the raw RH table.
  const rows = await response.json();
  if (!Array.isArray(rows)) return Response.json({message:'Resposta de disponibilidade inválida.'}, {status:502});
  return Response.json(vacationsOnly ? rows.filter(row=>row.tipo==='ferias') : rows);
}
