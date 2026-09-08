-- PRIMELINE | Recupera orçamentos históricos para a fonte consolidada por fase.
-- Migração idempotente: não substitui linhas já existentes em orcamento_fases.
begin;

with totais_por_fase as (
  select
    o.id as obra_id,
    f.id as fase_id,
    f.descricao,
    coalesce(sum(io.venda_prevista), 0) as venda_prevista,
    coalesce(sum(
      coalesce(io.custo_materiais, 0)
      + coalesce(io.custo_mao_obra, 0)
      + coalesce(io.custo_deslocacoes, 0)
      + coalesce(io.custo_maquinas, 0)
    ), 0) as custo_total_estimado,
    coalesce(sum(io.margem_prevista), 0) as margem_prevista,
    coalesce(sum(io.custo_deslocacoes), 0) as deslocacoes,
    coalesce(sum(io.custo_mao_obra), 0) as mao_obra,
    coalesce(sum(io.custo_maquinas), 0) as maquinas,
    coalesce(sum(io.custo_materiais), 0) as materiais,
    coalesce(sum(io.custo_mao_obra_subcontratada), 0) as mao_obra_sub,
    coalesce(sum(io.custo_subempreitada), 0) as subempreitada
  from public.obras o
  join public.fases f on f.obra_id = o.id
  join public.itens_orcamento io on io.fase_id = f.id
  where o.numero in (118, 120, 128)
    and coalesce(io.estado_item, 'ativo') <> 'cancelado'
  group by o.id, f.id, f.descricao
  having coalesce(sum(
    coalesce(io.custo_materiais, 0)
    + coalesce(io.custo_mao_obra, 0)
    + coalesce(io.custo_deslocacoes, 0)
    + coalesce(io.custo_maquinas, 0)
  ), 0) > 0
)
insert into public.orcamento_fases (
  obra_id, fase_id, descricao, venda_prevista, custo_total_estimado,
  margem_prevista, deslocacoes, mao_obra, maquinas, materiais,
  mao_obra_sub, subempreitada, nome_ficheiro_origem, importado_por, importado_em
)
select
  t.obra_id, t.fase_id, t.descricao, t.venda_prevista, t.custo_total_estimado,
  t.margem_prevista, t.deslocacoes, t.mao_obra, t.maquinas, t.materiais,
  t.mao_obra_sub, t.subempreitada, 'Recuperação de itens_orcamento históricos',
  public.fn_utilizador_atual_id(), now()
from totais_por_fase t
on conflict (fase_id) do nothing;

commit;

select
  o.numero as obra,
  count(ofa.id) as fases_com_orcamento,
  coalesce(sum(ofa.custo_total_estimado), 0) as custo_total_orca,
  coalesce(sum(ofa.materiais), 0) as materiais,
  coalesce(sum(ofa.mao_obra), 0) as mao_obra,
  coalesce(sum(ofa.deslocacoes), 0) as deslocacoes,
  coalesce(sum(ofa.maquinas), 0) as maquinas,
  coalesce(sum(ofa.mao_obra_sub), 0) as mao_obra_sub,
  coalesce(sum(ofa.subempreitada), 0) as subempreitada
from public.obras o
left join public.orcamento_fases ofa on ofa.obra_id = o.id
where o.numero in (118, 120, 128)
group by o.numero
order by o.numero;
