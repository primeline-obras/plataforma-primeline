-- PRIMELINE — especialidades controladas e consultas pendentes do planeamento
-- Migração aditiva. Não elimina texto histórico de consultas ou subempreitadas.

begin;

-- A lista controlada passa a usar capitalização normal.
update public.especialidades
set nome = initcap(lower(btrim(nome)))
where nome is distinct from initcap(lower(btrim(nome)));

alter table public.planeamento_itens
  add column if not exists especialidade_id uuid references public.especialidades(id) on delete set null,
  add column if not exists executado_por text;

alter table public.planeamento_itens
  drop constraint if exists planeamento_itens_executado_por_check;

alter table public.planeamento_itens
  add constraint planeamento_itens_executado_por_check
  check (executado_por is null or executado_por in ('PL', 'subempreitada'));

create index if not exists planeamento_itens_especialidade_idx
  on public.planeamento_itens (especialidade_id);

create index if not exists planeamento_itens_consulta_pendente_idx
  on public.planeamento_itens (data_inicio_prevista, fase_id)
  where executado_por = 'subempreitada' and subempreitada_id is null;

alter table public.consultas_subempreitada
  add column if not exists planeamento_item_id uuid
    references public.planeamento_itens(id) on delete set null;

create unique index if not exists consultas_subempreitada_planeamento_item_uidx
  on public.consultas_subempreitada (planeamento_item_id)
  where planeamento_item_id is not null;

create or replace view public.consultas_pendentes_planeamento
with (security_invoker = true)
as
select
  pi.id as planeamento_item_id,
  f.obra_id,
  pi.fase_id,
  pi.especialidade_id,
  e.nome as especialidade,
  pi.data_inicio_prevista
from public.planeamento_itens pi
join public.fases f on f.id = pi.fase_id
left join public.especialidades e on e.id = pi.especialidade_id
where pi.executado_por = 'subempreitada'
  and pi.subempreitada_id is null;

grant select on public.consultas_pendentes_planeamento to authenticated;

create or replace function public.fn_criar_consulta_planeamento(
  p_obra_id uuid,
  p_fase_id uuid,
  p_trabalho text,
  p_item_ids uuid[],
  p_planeamento_item_id uuid
)
returns public.consultas_subempreitada
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_consulta public.consultas_subempreitada%rowtype;
  v_item public.planeamento_itens%rowtype;
  v_especialidade_nome text;
begin
  select pi.* into v_item
  from public.planeamento_itens pi
  join public.fases f on f.id = pi.fase_id
  where pi.id = p_planeamento_item_id
    and pi.fase_id = p_fase_id
    and f.obra_id = p_obra_id
    and pi.executado_por = 'subempreitada'
    and pi.subempreitada_id is null
  for update of pi;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'A tarefa deixou de estar disponível para consulta ou não pertence à obra/fase indicada.';
  end if;

  select nome into v_especialidade_nome
  from public.especialidades
  where id = v_item.especialidade_id;

  if v_item.especialidade_id is null or v_especialidade_nome is distinct from p_trabalho then
    raise exception using
      errcode = '23514',
      message = 'A especialidade da consulta tem de corresponder à especialidade controlada da tarefa.';
  end if;

  v_consulta := public.fn_criar_consulta_subempreitada(
    p_obra_id,
    p_fase_id,
    p_trabalho,
    p_item_ids
  );

  update public.consultas_subempreitada
  set planeamento_item_id = p_planeamento_item_id
  where id = v_consulta.id
  returning * into v_consulta;

  return v_consulta;
end;
$$;

revoke all on function public.fn_criar_consulta_planeamento(uuid, uuid, text, uuid[], uuid) from public, anon;
grant execute on function public.fn_criar_consulta_planeamento(uuid, uuid, text, uuid[], uuid) to authenticated;

-- Integra a tarefa que originou a consulta no sincronizador já existente.
-- Para subempreitadas sem consulta de planeamento, preserva o comportamento
-- anterior de criar automaticamente uma tarefa.
create or replace function public.fn_sincronizar_subempreitada_planeamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_planeamento_item_id uuid;
  v_fornecedor text;
  v_inicio date;
  v_fim date;
  v_estado text := lower(coalesce(new.estado, ''));
begin
  if new.fase_id is null
     or v_estado not in ('adjudicado', 'adjudicada', 'em_execucao', 'concluido', 'concluida') then
    return new;
  end if;

  select nome into v_fornecedor
  from public.fornecedores
  where id = new.fornecedor_id;

  v_inicio := nullif(to_jsonb(new)->>'data_inicio_prevista', '')::date;
  v_fim := nullif(to_jsonb(new)->>'data_fim_prevista', '')::date;

  select planeamento_item_id into v_planeamento_item_id
  from public.consultas_subempreitada
  where id = new.consulta_id;

  if v_planeamento_item_id is not null then
    update public.planeamento_itens
    set
      subempreitada_id = new.id,
      fase_id = new.fase_id,
      descricao = coalesce(nullif(new.especialidade, ''), descricao),
      responsavel = v_fornecedor,
      executado_por = 'subempreitada',
      duracao_dias = case when v_inicio is not null and v_fim is not null then v_fim - v_inicio else duracao_dias end,
      data_inicio_prevista = coalesce(v_inicio, data_inicio_prevista),
      data_fim_prevista = coalesce(v_fim, data_fim_prevista),
      estado = case
        when v_estado in ('concluido', 'concluida') then 'concluido'
        when v_estado = 'em_execucao' then 'em_execucao'
        else 'por_iniciar'
      end
    where id = v_planeamento_item_id
      and subempreitada_id is null;
  else
    insert into public.planeamento_itens (
      fase_id, subempreitada_id, descricao, responsavel, executado_por, duracao_dias,
      data_inicio_prevista, data_fim_prevista, estado
    )
    values (
      new.fase_id,
      new.id,
      coalesce(nullif(new.especialidade, ''), 'Subempreitada'),
      v_fornecedor,
      'subempreitada',
      case when v_inicio is not null and v_fim is not null then v_fim - v_inicio end,
      v_inicio,
      v_fim,
      case
        when v_estado in ('concluido', 'concluida') then 'concluido'
        when v_estado = 'em_execucao' then 'em_execucao'
        else 'por_iniciar'
      end
    )
    on conflict (subempreitada_id) where subempreitada_id is not null
    do update set
      fase_id = excluded.fase_id,
      descricao = excluded.descricao,
      responsavel = excluded.responsavel,
      executado_por = excluded.executado_por,
      duracao_dias = excluded.duracao_dias,
      data_inicio_prevista = coalesce(excluded.data_inicio_prevista, planeamento_itens.data_inicio_prevista),
      data_fim_prevista = coalesce(excluded.data_fim_prevista, planeamento_itens.data_fim_prevista),
      estado = excluded.estado;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sincronizar_subempreitada_planeamento on public.subempreitadas;
create trigger trg_sincronizar_subempreitada_planeamento
after insert or update on public.subempreitadas
for each row execute function public.fn_sincronizar_subempreitada_planeamento();

grant select, update (especialidade_id, executado_por) on public.planeamento_itens to authenticated;

commit;
