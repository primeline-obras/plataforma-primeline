-- PRIMELINE | Entrada do mapa comparativo de subempreitadas
-- Executar no SQL Editor depois de subempreitadas_mapa_comparativo_workflow.sql.

begin;

alter table public.itens_orcamento
  add column if not exists quantidade numeric,
  add column if not exists unidade text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'itens_orcamento_quantidade_positiva_check'
      and conrelid = 'public.itens_orcamento'::regclass
  ) then
    alter table public.itens_orcamento
      add constraint itens_orcamento_quantidade_positiva_check
      check (quantidade is null or quantidade > 0);
  end if;
end
$$;

create or replace function public.fn_criar_consulta_subempreitada(
  p_obra_id uuid,
  p_fase_id uuid,
  p_trabalho text,
  p_item_ids uuid[]
)
returns public.consultas_subempreitada
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_consulta public.consultas_subempreitada%rowtype;
  v_total_pedido integer;
  v_total_valido integer;
begin
  if not public.fn_pode_editar_obra(p_obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para criar consultas nesta obra.';
  end if;

  if nullif(btrim(p_trabalho), '') is null then
    raise exception using errcode = '23514', message = 'A especialidade é obrigatória.';
  end if;

  if p_item_ids is null or cardinality(p_item_ids) = 0 then
    raise exception using errcode = '23514', message = 'Selecione pelo menos um item do orçamento.';
  end if;

  if not exists (
    select 1 from public.fases f
    where f.id = p_fase_id and f.obra_id = p_obra_id
  ) then
    raise exception using errcode = '23514', message = 'A fase selecionada não pertence a esta obra.';
  end if;

  select count(distinct requested.item_id)
    into v_total_pedido
  from unnest(p_item_ids) as requested(item_id);

  select count(distinct i.id)
    into v_total_valido
  from public.itens_orcamento i
  where i.id = any(p_item_ids)
    and i.fase_id = p_fase_id
    and i.quantidade > 0;

  if v_total_valido <> v_total_pedido then
    raise exception using
      errcode = '23514',
      message = 'Um ou mais itens não pertencem à fase/obra indicada ou não têm quantidade válida.';
  end if;

  insert into public.consultas_subempreitada (
    obra_id,
    fase_id,
    trabalho,
    data_pedido,
    estado
  )
  values (
    p_obra_id,
    p_fase_id,
    btrim(p_trabalho),
    current_date,
    'em_consulta'
  )
  returning * into v_consulta;

  insert into public.consultas_subempreitada_itens (
    consulta_subempreitada_id,
    item_orcamento_id
  )
  select
    v_consulta.id,
    requested.item_id
  from (
    select distinct unnest(p_item_ids) as item_id
  ) requested;

  return v_consulta;
end;
$$;

revoke all on function public.fn_criar_consulta_subempreitada(uuid, uuid, text, uuid[]) from public, anon;
grant execute on function public.fn_criar_consulta_subempreitada(uuid, uuid, text, uuid[]) to authenticated;

create or replace function public.fn_guardar_precos_candidato_subempreitada(
  p_candidato_id uuid,
  p_precos jsonb
)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_obra_id uuid;
  v_total numeric;
begin
  select consulta.obra_id
    into v_obra_id
  from public.consultas_subempreitada_candidatos candidato
  join public.consultas_subempreitada consulta
    on consulta.id = candidato.consulta_subempreitada_id
  where candidato.id = p_candidato_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidato não encontrado.';
  end if;

  if not public.fn_pode_editar_obra(v_obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para editar esta consulta.';
  end if;

  if p_precos is null or jsonb_typeof(p_precos) <> 'array' then
    raise exception using errcode = '23514', message = 'A lista de preços é inválida.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_precos) as preco(item_orcamento_id uuid, preco_unitario numeric)
    group by preco.item_orcamento_id
    having count(*) > 1
  ) then
    raise exception using errcode = '23514', message = 'A lista contém o mesmo artigo mais de uma vez.';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_precos) as preco(item_orcamento_id uuid, preco_unitario numeric)
    left join public.consultas_subempreitada_candidatos candidato
      on candidato.id = p_candidato_id
    left join public.consultas_subempreitada_itens consulta_item
      on consulta_item.consulta_subempreitada_id = candidato.consulta_subempreitada_id
     and consulta_item.item_orcamento_id = preco.item_orcamento_id
    left join public.itens_orcamento item
      on item.id = preco.item_orcamento_id
    where consulta_item.id is null
       or item.quantidade is null
       or item.quantidade <= 0
       or (preco.preco_unitario is not null and preco.preco_unitario < 0)
  ) then
    raise exception using errcode = '23514', message = 'Existe um preço inválido ou um artigo que não pertence à consulta.';
  end if;

  delete from public.consultas_subempreitada_candidatos_itens
  where candidato_id = p_candidato_id;

  insert into public.consultas_subempreitada_candidatos_itens (
    candidato_id,
    item_orcamento_id,
    preco_unitario,
    preco_total
  )
  select
    p_candidato_id,
    preco.item_orcamento_id,
    preco.preco_unitario,
    preco.preco_unitario * item.quantidade
  from jsonb_to_recordset(p_precos) as preco(item_orcamento_id uuid, preco_unitario numeric)
  join public.itens_orcamento item on item.id = preco.item_orcamento_id
  where preco.preco_unitario is not null;

  select coalesce(sum(preco_total), 0)
    into v_total
  from public.consultas_subempreitada_candidatos_itens
  where candidato_id = p_candidato_id;

  update public.consultas_subempreitada_candidatos
  set valor_total = v_total
  where id = p_candidato_id;

  return v_total;
end;
$$;

revoke all on function public.fn_guardar_precos_candidato_subempreitada(uuid, jsonb) from public, anon;
grant execute on function public.fn_guardar_precos_candidato_subempreitada(uuid, jsonb) to authenticated;

commit;

select
  p.proname as funcao,
  pg_get_function_identity_arguments(p.oid) as argumentos
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fn_criar_consulta_subempreitada',
    'fn_guardar_precos_candidato_subempreitada'
  )
order by p.proname;
