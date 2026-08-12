-- PRIMELINE | Leitura global e estritamente operacional para o encarregado.
-- Não alarga SELECT em obras nem concede qualquer escrita.

begin;

create or replace function public.fn_quadro_ferias_encarregado_global(
  p_data_inicio date,
  p_data_fim date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_utilizador_id uuid;
begin
  if p_data_inicio is null or p_data_fim is null or p_data_fim < p_data_inicio then
    raise exception 'Intervalo de datas inválido.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();

  if not exists (
    select 1
    from public.utilizadores u
    where u.id = v_utilizador_id
      and u.ativo is true
      and u.funcao = 'encarregado'
  ) then
    raise exception 'Esta consulta está reservada ao papel encarregado.';
  end if;

  return jsonb_build_object(
    'obras', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'numero', o.numero,
        'nome', o.nome,
        'situacao', o.situacao
      ) order by o.numero)
      from public.obras o
    ), '[]'::jsonb),
    'colaboradores', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'nome', c.nome,
        'funcao', c.funcao,
        'nivel', c.nivel,
        'permite_multiplas_obras', c.permite_multiplas_obras
      ) order by c.nome)
      from public.colaboradores c
      where c.data_saida is null
    ), '[]'::jsonb),
    'alocacoes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'colaborador_id', q.colaborador_id,
        'obra_id', q.obra_id,
        'tipo_alocacao', q.tipo_alocacao,
        'descricao_livre', q.descricao_livre,
        'semana_inicio', q.semana_inicio,
        'data', q.data,
        'periodo', q.periodo
      ) order by q.data, q.colaborador_id)
      from public.quadro_pessoal_alocacao q
      join public.colaboradores c on c.id = q.colaborador_id and c.data_saida is null
      where q.data between p_data_inicio and p_data_fim
    ), '[]'::jsonb),
    'ferias', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'colaborador_id', a.colaborador_id,
        'data', a.data,
        'tipo', a.tipo,
        'estado', a.estado,
        'comentario', a.comentario
      ) order by a.data, a.colaborador_id)
      from public.ausencias a
      join public.colaboradores c on c.id = a.colaborador_id and c.data_saida is null
      where a.tipo = 'ferias'
        and a.data between p_data_inicio and p_data_fim
    ), '[]'::jsonb),
    'responsaveis', coalesce((
      select jsonb_agg(jsonb_build_object(
        'obra_id', r.obra_id,
        'utilizador_id', r.utilizador_id,
        'papel', r.papel
      ))
      from public.obra_responsaveis r
    ), '[]'::jsonb),
    'utilizadores', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'nome', u.nome))
      from public.utilizadores u
      where u.ativo is true
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.fn_quadro_ferias_encarregado_global(date, date)
  from public, anon;
grant execute on function public.fn_quadro_ferias_encarregado_global(date, date)
  to authenticated;

commit;

select
  to_regprocedure('public.fn_quadro_ferias_encarregado_global(date,date)') is not null
    as leitura_global_encarregado,
  has_function_privilege('authenticated', 'public.fn_quadro_ferias_encarregado_global(date,date)', 'EXECUTE')
    as encarregado_pode_consultar;
