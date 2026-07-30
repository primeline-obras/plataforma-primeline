-- PRIMELINE - planeamento detalhado por tarefa
-- Executar no SQL Editor do Supabase como owner.
--
-- IMPORTANTE PARA IMPORTACOES:
-- 1. carregar primeiro os itens e dependencias sem ativar recálculos;
-- 2. executar select * from public.fn_auditar_ciclos_planeamento();
-- 3. corrigir todos os ciclos devolvidos;
-- 4. só depois ativar/confiar no recálculo automático.

create table if not exists public.planeamento_itens (
  id uuid primary key default gen_random_uuid(),
  fase_id uuid not null references public.fases(id),
  subempreitada_id uuid references public.subempreitadas(id),
  codigo text,
  descricao text not null,
  responsavel text,
  duracao_dias numeric,
  data_inicio_prevista date,
  data_fim_prevista date,
  data_fim_real date,
  peso_percentual numeric,
  percentual_executado numeric not null default 0,
  percentual_ponderado numeric,
  estado text,
  causa_atraso text,
  impacto text,
  recalculado_automaticamente boolean not null default false,
  recalculado_em timestamptz,
  recalculado_por_item_id uuid references public.planeamento_itens(id) on delete set null,
  criado_em timestamptz not null default now(),
  constraint planeamento_itens_estado_check
    check (estado is null or estado = any (array['concluido'::text, 'em_execucao'::text, 'por_iniciar'::text])),
  constraint planeamento_itens_percentual_check
    check (percentual_executado between 0 and 100),
  constraint planeamento_itens_datas_check
    check (data_fim_prevista is null or data_inicio_prevista is null or data_fim_prevista >= data_inicio_prevista),
  constraint planeamento_itens_duracao_check
    check (duracao_dias is null or duracao_dias >= 0)
);

create unique index if not exists planeamento_itens_subempreitada_uidx
  on public.planeamento_itens (subempreitada_id)
  where subempreitada_id is not null;

create index if not exists planeamento_itens_fase_idx
  on public.planeamento_itens (fase_id);

create table if not exists public.planeamento_itens_dependencias (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.planeamento_itens(id) on delete cascade,
  depende_de_item_id uuid not null references public.planeamento_itens(id) on delete cascade,
  tipo text not null default 'fim_inicio'
    check (tipo = any (array['fim_inicio'::text, 'inicio_inicio'::text, 'fim_fim'::text, 'inicio_fim'::text])),
  atraso_dias integer not null default 0,
  criado_em timestamptz not null default now(),
  check (item_id <> depende_de_item_id),
  unique (item_id, depende_de_item_id)
);

create index if not exists planeamento_dependencias_predecessora_idx
  on public.planeamento_itens_dependencias (depende_de_item_id);

-- Recusa A -> B quando B já depende, direta ou indiretamente, de A.
create or replace function public.fn_validar_dependencia_planeamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caminho uuid[];
begin
  with recursive predecessoras as (
    select
      new.depende_de_item_id as item_id,
      array[new.item_id, new.depende_de_item_id]::uuid[] as caminho
    union all
    select
      d.depende_de_item_id,
      p.caminho || d.depende_de_item_id
    from predecessoras p
    join public.planeamento_itens_dependencias d on d.item_id = p.item_id
    where (tg_op <> 'UPDATE' or d.id <> new.id)
      and (
        d.depende_de_item_id = new.item_id
        or not d.depende_de_item_id = any(p.caminho)
      )
  )
  select caminho
    into v_caminho
  from predecessoras
  where item_id = new.item_id
  limit 1;

  if v_caminho is not null then
    raise exception using
      errcode = '23514',
      message = 'Dependência circular recusada.',
      detail = 'Caminho de itens: ' || array_to_string(v_caminho, ' -> '),
      hint = 'Remova ou reorganize uma das predecessoras antes de gravar esta dependência.';
  end if;

  return new;
end;
$$;

revoke all on function public.fn_validar_dependencia_planeamento() from public;
revoke all on function public.fn_validar_dependencia_planeamento() from authenticated;

drop trigger if exists trg_validar_dependencia_planeamento
  on public.planeamento_itens_dependencias;
create trigger trg_validar_dependencia_planeamento
before insert or update of item_id, depende_de_item_id
on public.planeamento_itens_dependencias
for each row execute function public.fn_validar_dependencia_planeamento();

-- Auditoria independente para correr antes de qualquer importação de dados.
create or replace function public.fn_auditar_ciclos_planeamento()
returns table (item_origem uuid, caminho uuid[])
language sql
stable
set search_path = public
as $$
  with recursive caminhos as (
    select
      d.item_id as item_origem,
      d.depende_de_item_id as item_atual,
      array[d.item_id, d.depende_de_item_id]::uuid[] as caminho,
      d.item_id = d.depende_de_item_id as ciclo
    from public.planeamento_itens_dependencias d
    union all
    select
      c.item_origem,
      d.depende_de_item_id,
      c.caminho || d.depende_de_item_id,
      d.depende_de_item_id = c.item_origem
    from caminhos c
    join public.planeamento_itens_dependencias d on d.item_id = c.item_atual
    where not c.ciclo
      and (
        d.depende_de_item_id = c.item_origem
        or not d.depende_de_item_id = any(c.caminho)
      )
  )
  select distinct on (item_origem) item_origem, caminho
  from caminhos
  where ciclo
  order by item_origem, cardinality(caminho);
$$;

-- Empurra apenas tarefas ainda não concluídas e apenas para a frente.
create or replace function public.fn_recalcular_planeamento_cascata(p_item_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_atualizadas integer := 0;
  v_total_itens integer;
begin
  if exists (select 1 from public.fn_auditar_ciclos_planeamento()) then
    raise exception using
      errcode = '23514',
      message = 'Recálculo recusado: existem dependências circulares no planeamento.',
      hint = 'Execute select * from public.fn_auditar_ciclos_planeamento() e corrija os ciclos.';
  end if;

  select count(*) into v_total_itens from public.planeamento_itens;

  perform set_config('primeline.recalculo_cascata', 'ativo', true);

  with recursive propagacao as (
    select
      sucessora.id as item_id,
      raiz.id as origem_id,
      greatest(
        sucessora.data_inicio_prevista,
        coalesce(raiz.data_fim_real, raiz.data_fim_prevista) + dependencia.atraso_dias
      )::date as inicio_calculado,
      array[raiz.id, sucessora.id]::uuid[] as caminho,
      1 as profundidade
    from public.planeamento_itens raiz
    join public.planeamento_itens_dependencias dependencia
      on dependencia.depende_de_item_id = raiz.id
     and dependencia.tipo = 'fim_inicio'
    join public.planeamento_itens sucessora on sucessora.id = dependencia.item_id
    where raiz.id = p_item_id
      and coalesce(raiz.data_fim_real, raiz.data_fim_prevista) is not null
      and sucessora.data_inicio_prevista is not null
      and sucessora.data_fim_real is null
      and coalesce(raiz.data_fim_real, raiz.data_fim_prevista) + dependencia.atraso_dias
          > sucessora.data_inicio_prevista

    union all

    select
      sucessora.id,
      p.origem_id,
      greatest(
        sucessora.data_inicio_prevista,
        (
          p.inicio_calculado
          + ceil(coalesce(predecessora.duracao_dias,
              predecessora.data_fim_prevista - predecessora.data_inicio_prevista, 0))::integer
          + dependencia.atraso_dias
        )::date
      )::date,
      p.caminho || sucessora.id,
      p.profundidade + 1
    from propagacao p
    join public.planeamento_itens predecessora on predecessora.id = p.item_id
    join public.planeamento_itens_dependencias dependencia
      on dependencia.depende_de_item_id = predecessora.id
     and dependencia.tipo = 'fim_inicio'
    join public.planeamento_itens sucessora on sucessora.id = dependencia.item_id
    where sucessora.data_inicio_prevista is not null
      and sucessora.data_fim_real is null
      and not sucessora.id = any(p.caminho)
      and p.profundidade <= greatest(v_total_itens, 1)
      and (
        p.inicio_calculado
        + ceil(coalesce(predecessora.duracao_dias,
            predecessora.data_fim_prevista - predecessora.data_inicio_prevista, 0))::integer
        + dependencia.atraso_dias
      )::date > sucessora.data_inicio_prevista
  ),
  datas as (
    select item_id, max(inicio_calculado) as novo_inicio
    from propagacao
    group by item_id
  )
  update public.planeamento_itens item
  set
    data_inicio_prevista = datas.novo_inicio,
    data_fim_prevista = datas.novo_inicio
      + ceil(coalesce(item.duracao_dias,
          item.data_fim_prevista - item.data_inicio_prevista, 0))::integer,
    recalculado_automaticamente = true,
    recalculado_em = now(),
    recalculado_por_item_id = p_item_id
  from datas
  where item.id = datas.item_id
    and datas.novo_inicio > item.data_inicio_prevista;

  get diagnostics v_atualizadas = row_count;
  return v_atualizadas;
end;
$$;

revoke all on function public.fn_recalcular_planeamento_cascata(uuid) from public;
revoke all on function public.fn_recalcular_planeamento_cascata(uuid) from authenticated;

create or replace function public.fn_disparar_recalculo_planeamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fim_anterior date := coalesce(old.data_fim_real, old.data_fim_prevista);
  v_fim_novo date := coalesce(new.data_fim_real, new.data_fim_prevista);
begin
  if current_setting('primeline.recalculo_cascata', true) = 'ativo' then
    return new;
  end if;
  if v_fim_novo is not null and (v_fim_anterior is null or v_fim_novo > v_fim_anterior) then
    perform public.fn_recalcular_planeamento_cascata(new.id);
  end if;
  return new;
end;
$$;

revoke all on function public.fn_disparar_recalculo_planeamento() from public;
revoke all on function public.fn_disparar_recalculo_planeamento() from authenticated;

drop trigger if exists trg_recalcular_planeamento
  on public.planeamento_itens;
create trigger trg_recalcular_planeamento
after update of data_fim_real, data_fim_prevista
on public.planeamento_itens
for each row execute function public.fn_disparar_recalculo_planeamento();

-- Cria/atualiza a tarefa ligada a uma subempreitada adjudicada.
-- to_jsonb permite instalar já este trigger mesmo antes de as colunas de datas
-- serem acrescentadas a subempreitadas.
create or replace function public.fn_sincronizar_subempreitada_planeamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
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

  insert into public.planeamento_itens (
    fase_id, subempreitada_id, descricao, responsavel, duracao_dias,
    data_inicio_prevista, data_fim_prevista, estado
  )
  values (
    new.fase_id,
    new.id,
    coalesce(nullif(new.especialidade, ''), 'Subempreitada'),
    v_fornecedor,
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
    duracao_dias = excluded.duracao_dias,
    data_inicio_prevista = coalesce(excluded.data_inicio_prevista, planeamento_itens.data_inicio_prevista),
    data_fim_prevista = coalesce(excluded.data_fim_prevista, planeamento_itens.data_fim_prevista),
    estado = excluded.estado;

  return new;
end;
$$;

revoke all on function public.fn_sincronizar_subempreitada_planeamento() from public;
revoke all on function public.fn_sincronizar_subempreitada_planeamento() from authenticated;

drop trigger if exists trg_sincronizar_subempreitada_planeamento
  on public.subempreitadas;
create trigger trg_sincronizar_subempreitada_planeamento
after insert or update
on public.subempreitadas
for each row execute function public.fn_sincronizar_subempreitada_planeamento();

grant select, insert, update, delete on public.planeamento_itens to authenticated;
grant select, insert, update, delete on public.planeamento_itens_dependencias to authenticated;
grant execute on function public.fn_auditar_ciclos_planeamento() to authenticated;

alter table public.planeamento_itens enable row level security;
alter table public.planeamento_itens_dependencias enable row level security;

drop policy if exists planeamento_itens_select on public.planeamento_itens;
create policy planeamento_itens_select
on public.planeamento_itens for select to authenticated
using (
  exists (
    select 1 from public.fases f
    where f.id = fase_id and public.fn_pode_ver_obra(f.obra_id)
  )
);

drop policy if exists planeamento_itens_write on public.planeamento_itens;
create policy planeamento_itens_write
on public.planeamento_itens for all to authenticated
using (
  exists (
    select 1 from public.fases f
    where f.id = fase_id and public.fn_pode_editar_obra(f.obra_id)
  )
)
with check (
  exists (
    select 1 from public.fases f
    where f.id = fase_id and public.fn_pode_editar_obra(f.obra_id)
  )
);

drop policy if exists planeamento_dependencias_select on public.planeamento_itens_dependencias;
create policy planeamento_dependencias_select
on public.planeamento_itens_dependencias for select to authenticated
using (
  exists (
    select 1
    from public.planeamento_itens i
    join public.fases f on f.id = i.fase_id
    where i.id = item_id and public.fn_pode_ver_obra(f.obra_id)
  )
);

drop policy if exists planeamento_dependencias_write on public.planeamento_itens_dependencias;
create policy planeamento_dependencias_write
on public.planeamento_itens_dependencias for all to authenticated
using (
  exists (
    select 1
    from public.planeamento_itens i
    join public.fases f on f.id = i.fase_id
    where i.id = item_id and public.fn_pode_editar_obra(f.obra_id)
  )
  and exists (
    select 1
    from public.planeamento_itens predecessora
    join public.fases f on f.id = predecessora.fase_id
    where predecessora.id = depende_de_item_id and public.fn_pode_editar_obra(f.obra_id)
  )
)
with check (
  exists (
    select 1
    from public.planeamento_itens i
    join public.fases f on f.id = i.fase_id
    where i.id = item_id and public.fn_pode_editar_obra(f.obra_id)
  )
  and exists (
    select 1
    from public.planeamento_itens predecessora
    join public.fases f on f.id = predecessora.fase_id
    where predecessora.id = depende_de_item_id and public.fn_pode_editar_obra(f.obra_id)
  )
);
