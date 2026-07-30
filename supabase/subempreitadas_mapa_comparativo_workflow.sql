-- PRIMELINE — mapa comparativo, adjudicação e conclusão de subempreitadas
-- Executar no SQL Editor do Supabase como owner.
-- Pressupõe que planeamento_detalhado.sql já foi executado.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.subempreitadas'::regclass
      and tgname = 'trg_sincronizar_subempreitada_planeamento'
      and not tgisinternal
      and tgenabled <> 'D'
  ) then
    raise exception
      'Falta o trigger ativo trg_sincronizar_subempreitada_planeamento. Execute primeiro planeamento_detalhado.sql.';
  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.subempreitadas'::regclass
      and tgname = 'trg_bloquear_conclusao'
      and not tgisinternal
      and tgenabled <> 'D'
  ) then
    raise exception
      'Falta o trigger ativo trg_bloquear_conclusao. A migração foi interrompida por segurança.';
  end if;
end
$$;

alter table public.subempreitadas
  add column if not exists data_inicio_prevista date,
  add column if not exists data_fim_prevista date,
  add column if not exists condicao_pagamento text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'subempreitadas_datas_previstas_check'
      and conrelid = 'public.subempreitadas'::regclass
  ) then
    alter table public.subempreitadas
      add constraint subempreitadas_datas_previstas_check
      check (
        data_inicio_prevista is null
        or data_fim_prevista is null
        or data_fim_prevista >= data_inicio_prevista
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'subempreitadas_condicao_pagamento_check'
      and conrelid = 'public.subempreitadas'::regclass
  ) then
    alter table public.subempreitadas
      add constraint subempreitadas_condicao_pagamento_check
      check (
        condicao_pagamento is null
        or condicao_pagamento = any (
          array['imediato'::text, '15_dias'::text, '30_dias'::text]
        )
      );
  end if;
end
$$;

-- Valor único e fácil de alterar quando a política interna mudar.
create or replace function public.fn_limite_contrato_subempreitada()
returns numeric
language sql
immutable
set search_path = public
as $$
  select 5000::numeric;
$$;

revoke all on function public.fn_limite_contrato_subempreitada() from public;
grant execute on function public.fn_limite_contrato_subempreitada() to authenticated;
grant execute on function public.fn_pode_editar_obra(uuid) to authenticated;

-- Adjudica o candidato dentro de uma transação, cria/atualiza a subempreitada
-- e deixa o trigger já existente sincronizar planeamento_itens.
create or replace function public.fn_adjudicar_candidato_subempreitada(
  p_candidato_id uuid,
  p_data_inicio_prevista date,
  p_data_fim_prevista date,
  p_condicao_pagamento text
)
returns public.subempreitadas
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_candidato public.consultas_subempreitada_candidatos%rowtype;
  v_consulta public.consultas_subempreitada%rowtype;
  v_subempreitada public.subempreitadas%rowtype;
begin
  if p_data_inicio_prevista is null or p_data_fim_prevista is null then
    raise exception using
      errcode = '23514',
      message = 'As datas previstas de início e fim são obrigatórias.';
  end if;

  if p_data_fim_prevista < p_data_inicio_prevista then
    raise exception using
      errcode = '23514',
      message = 'A data prevista de fim não pode ser anterior ao início.';
  end if;

  if p_condicao_pagamento is null
     or p_condicao_pagamento not in ('imediato', '15_dias', '30_dias') then
    raise exception using
      errcode = '23514',
      message = 'Condição de pagamento inválida.';
  end if;

  select * into v_candidato
  from public.consultas_subempreitada_candidatos
  where id = p_candidato_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Candidato não encontrado.';
  end if;

  select * into v_consulta
  from public.consultas_subempreitada
  where id = v_candidato.consulta_subempreitada_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Consulta não encontrada.';
  end if;

  if not public.fn_pode_editar_obra(v_consulta.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para adjudicar nesta obra.';
  end if;

  if v_consulta.fase_id is null then
    raise exception using
      errcode = '23514',
      message = 'A consulta precisa de estar associada a uma fase antes da adjudicação.';
  end if;

  if v_candidato.valor_total is null or v_candidato.valor_total < 0 then
    raise exception using
      errcode = '23514',
      message = 'O candidato precisa de ter um valor total válido.';
  end if;

  update public.consultas_subempreitada_candidatos
  set escolhido = (id = p_candidato_id)
  where consulta_subempreitada_id = v_consulta.id;

  select * into v_subempreitada
  from public.subempreitadas
  where consulta_id = v_consulta.id
  order by criado_em
  limit 1
  for update;

  if found then
    update public.subempreitadas
    set
      obra_id = v_consulta.obra_id,
      fase_id = v_consulta.fase_id,
      fornecedor_id = v_candidato.fornecedor_id,
      especialidade = v_consulta.trabalho,
      valor_adjudicado = v_candidato.valor_total,
      estado = 'em_execucao',
      data_inicio_prevista = p_data_inicio_prevista,
      data_fim_prevista = p_data_fim_prevista,
      condicao_pagamento = p_condicao_pagamento
    where id = v_subempreitada.id
    returning * into v_subempreitada;
  else
    insert into public.subempreitadas (
      obra_id,
      fase_id,
      consulta_id,
      fornecedor_id,
      especialidade,
      valor_adjudicado,
      estado,
      data_inicio_prevista,
      data_fim_prevista,
      condicao_pagamento
    )
    values (
      v_consulta.obra_id,
      v_consulta.fase_id,
      v_consulta.id,
      v_candidato.fornecedor_id,
      v_consulta.trabalho,
      v_candidato.valor_total,
      'em_execucao',
      p_data_inicio_prevista,
      p_data_fim_prevista,
      p_condicao_pagamento
    )
    returning * into v_subempreitada;
  end if;

  update public.consultas_subempreitada
  set
    fornecedor_id = v_candidato.fornecedor_id,
    estado = 'adjudicado',
    data_contrato = coalesce(data_contrato, current_date)
  where id = v_consulta.id;

  return v_subempreitada;
end;
$$;

revoke all on function public.fn_adjudicar_candidato_subempreitada(uuid, date, date, text) from public;
grant execute on function public.fn_adjudicar_candidato_subempreitada(uuid, date, date, text) to authenticated;

-- Grava a avaliação antes de mudar o estado. O trigger de bloqueio existente
-- encontra então a avaliação e autoriza a conclusão.
create or replace function public.fn_concluir_subempreitada_com_avaliacao(
  p_subempreitada_id uuid,
  p_qualidade integer,
  p_cumprimento_prazo integer,
  p_seguranca integer,
  p_comunicacao integer,
  p_observacoes text default null
)
returns public.subempreitadas
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_subempreitada public.subempreitadas%rowtype;
  v_utilizador_id uuid;
begin
  select * into v_subempreitada
  from public.subempreitadas
  where id = p_subempreitada_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Subempreitada não encontrada.';
  end if;

  if not public.fn_pode_editar_obra(v_subempreitada.obra_id) then
    raise exception using errcode = '42501', message = 'Sem permissão para concluir nesta obra.';
  end if;

  if p_qualidade is null
     or p_cumprimento_prazo is null
     or p_seguranca is null
     or p_comunicacao is null
     or p_qualidade not between 1 and 5
     or p_cumprimento_prazo not between 1 and 5
     or p_seguranca not between 1 and 5
     or p_comunicacao not between 1 and 5 then
    raise exception using
      errcode = '23514',
      message = 'Todos os critérios da avaliação devem estar entre 1 e 5.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();

  delete from public.avaliacoes_subempreiteiro
  where subempreitada_id = v_subempreitada.id;

  insert into public.avaliacoes_subempreiteiro (
    obra_id,
    subempreitada_id,
    fornecedor_id,
    qualidade,
    cumprimento_prazo,
    seguranca,
    comunicacao,
    observacoes,
    avaliado_por
  )
  values (
    v_subempreitada.obra_id,
    v_subempreitada.id,
    v_subempreitada.fornecedor_id,
    p_qualidade,
    p_cumprimento_prazo,
    p_seguranca,
    p_comunicacao,
    nullif(trim(p_observacoes), ''),
    v_utilizador_id
  );

  update public.subempreitadas
  set estado = 'concluido'
  where id = v_subempreitada.id
  returning * into v_subempreitada;

  return v_subempreitada;
end;
$$;

revoke all on function public.fn_concluir_subempreitada_com_avaliacao(uuid, integer, integer, integer, integer, text) from public;
grant execute on function public.fn_concluir_subempreitada_com_avaliacao(uuid, integer, integer, integer, integer, text) to authenticated;

alter table public.consultas_subempreitada enable row level security;
alter table public.consultas_subempreitada_itens enable row level security;
alter table public.consultas_subempreitada_candidatos enable row level security;
alter table public.consultas_subempreitada_candidatos_itens enable row level security;
alter table public.subempreitadas enable row level security;
alter table public.avaliacoes_subempreiteiro enable row level security;

revoke all on table
  public.consultas_subempreitada,
  public.consultas_subempreitada_itens,
  public.consultas_subempreitada_candidatos,
  public.consultas_subempreitada_candidatos_itens,
  public.subempreitadas,
  public.avaliacoes_subempreiteiro
from anon;

grant select, insert, update, delete on table
  public.consultas_subempreitada,
  public.consultas_subempreitada_itens,
  public.consultas_subempreitada_candidatos,
  public.consultas_subempreitada_candidatos_itens
to authenticated;

grant select, insert, update on table
  public.subempreitadas,
  public.avaliacoes_subempreiteiro
to authenticated;

drop policy if exists consultas_subempreitada_select on public.consultas_subempreitada;
drop policy if exists consultas_subempreitada_authenticated_select on public.consultas_subempreitada;
create policy consultas_subempreitada_select
on public.consultas_subempreitada for select to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists consultas_subempreitada_write on public.consultas_subempreitada;
create policy consultas_subempreitada_write
on public.consultas_subempreitada for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists consultas_subempreitada_itens_select on public.consultas_subempreitada_itens;
create policy consultas_subempreitada_itens_select
on public.consultas_subempreitada_itens for select to authenticated
using (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_ver_obra(c.obra_id)
  )
);

drop policy if exists consultas_subempreitada_itens_write on public.consultas_subempreitada_itens;
create policy consultas_subempreitada_itens_write
on public.consultas_subempreitada_itens for all to authenticated
using (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_editar_obra(c.obra_id)
  )
)
with check (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_editar_obra(c.obra_id)
  )
);

drop policy if exists consultas_candidatos_select on public.consultas_subempreitada_candidatos;
create policy consultas_candidatos_select
on public.consultas_subempreitada_candidatos for select to authenticated
using (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_ver_obra(c.obra_id)
  )
);

drop policy if exists consultas_candidatos_write on public.consultas_subempreitada_candidatos;
create policy consultas_candidatos_write
on public.consultas_subempreitada_candidatos for all to authenticated
using (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_editar_obra(c.obra_id)
  )
)
with check (
  exists (
    select 1 from public.consultas_subempreitada c
    where c.id = consulta_subempreitada_id
      and public.fn_pode_editar_obra(c.obra_id)
  )
);

drop policy if exists consultas_candidatos_itens_select on public.consultas_subempreitada_candidatos_itens;
create policy consultas_candidatos_itens_select
on public.consultas_subempreitada_candidatos_itens for select to authenticated
using (
  exists (
    select 1
    from public.consultas_subempreitada_candidatos candidato
    join public.consultas_subempreitada consulta
      on consulta.id = candidato.consulta_subempreitada_id
    where candidato.id = consultas_subempreitada_candidatos_itens.candidato_id
      and public.fn_pode_ver_obra(consulta.obra_id)
  )
);

drop policy if exists consultas_candidatos_itens_write on public.consultas_subempreitada_candidatos_itens;
create policy consultas_candidatos_itens_write
on public.consultas_subempreitada_candidatos_itens for all to authenticated
using (
  exists (
    select 1
    from public.consultas_subempreitada_candidatos candidato
    join public.consultas_subempreitada consulta
      on consulta.id = candidato.consulta_subempreitada_id
    where candidato.id = consultas_subempreitada_candidatos_itens.candidato_id
      and public.fn_pode_editar_obra(consulta.obra_id)
  )
)
with check (
  exists (
    select 1
    from public.consultas_subempreitada_candidatos candidato
    join public.consultas_subempreitada consulta
      on consulta.id = candidato.consulta_subempreitada_id
    where candidato.id = consultas_subempreitada_candidatos_itens.candidato_id
      and public.fn_pode_editar_obra(consulta.obra_id)
  )
);

drop policy if exists subempreitadas_insert on public.subempreitadas;
create policy subempreitadas_insert
on public.subempreitadas for insert to authenticated
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists subempreitadas_update on public.subempreitadas;
create policy subempreitadas_update
on public.subempreitadas for update to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists avaliacoes_subempreiteiro_select on public.avaliacoes_subempreiteiro;
create policy avaliacoes_subempreiteiro_select
on public.avaliacoes_subempreiteiro for select to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists avaliacoes_subempreiteiro_insert on public.avaliacoes_subempreiteiro;
create policy avaliacoes_subempreiteiro_insert
on public.avaliacoes_subempreiteiro for insert to authenticated
with check (
  qualidade between 1 and 5
  and cumprimento_prazo between 1 and 5
  and seguranca between 1 and 5
  and comunicacao between 1 and 5
  and avaliado_por = public.fn_utilizador_atual_id()
  and exists (
    select 1
    from public.subempreitadas s
    where s.id = avaliacoes_subempreiteiro.subempreitada_id
      and s.obra_id = avaliacoes_subempreiteiro.obra_id
      and s.fornecedor_id = avaliacoes_subempreiteiro.fornecedor_id
      and public.fn_pode_editar_obra(s.obra_id)
  )
);

drop policy if exists avaliacoes_subempreiteiro_update on public.avaliacoes_subempreiteiro;
create policy avaliacoes_subempreiteiro_update
on public.avaliacoes_subempreiteiro for update to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (
  qualidade between 1 and 5
  and cumprimento_prazo between 1 and 5
  and seguranca between 1 and 5
  and comunicacao between 1 and 5
  and avaliado_por = public.fn_utilizador_atual_id()
  and exists (
    select 1
    from public.subempreitadas s
    where s.id = avaliacoes_subempreiteiro.subempreitada_id
      and s.obra_id = avaliacoes_subempreiteiro.obra_id
      and s.fornecedor_id = avaliacoes_subempreiteiro.fornecedor_id
      and public.fn_pode_editar_obra(s.obra_id)
  )
);

commit;

-- Confirmação pós-migração.
select
  (select count(*) from pg_trigger
   where not tgisinternal
     and tgname = 'trg_sincronizar_subempreitada_planeamento') as trigger_planeamento,
  (select count(*) from pg_trigger
   where not tgisinternal
     and tgname = 'trg_bloquear_conclusao') as trigger_bloqueio,
  public.fn_limite_contrato_subempreitada() as limite_contrato;
