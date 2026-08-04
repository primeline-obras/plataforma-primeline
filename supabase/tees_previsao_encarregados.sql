-- PRIMELINE | TEEs, previsão financeira e acesso dos encarregados
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.
-- Migração idempotente: documenta também complementos já aplicados diretamente.

begin;

-- ---------------------------------------------------------------------------
-- 0. Sincronização do schema já existente na base de dados
-- ---------------------------------------------------------------------------

alter table public.desenhos
  add column if not exists numero text,
  add column if not exists descricao text,
  add column if not exists revisao text,
  add column if not exists data_emissao date,
  add column if not exists estado text;

alter table public.rfis
  add column if not exists desenho_id uuid references public.desenhos(id),
  add column if not exists numero text,
  add column if not exists descricao text,
  add column if not exists data_envio date,
  add column if not exists data_resposta date,
  add column if not exists estado text;

alter table public.previsao_financeira_mensal
  add column if not exists entradas_reais numeric default 0,
  add column if not exists entradas_previstas numeric default 0,
  add column if not exists fechado boolean not null default false,
  add column if not exists fechado_por uuid references public.utilizadores(id),
  add column if not exists fechado_em timestamptz;

drop policy if exists previsao_financeira_mensal_update
  on public.previsao_financeira_mensal;
create policy previsao_financeira_mensal_update
on public.previsao_financeira_mensal
for update to authenticated
using (public.fn_pode_editar_obra(obra_id) and fechado = false);

-- ---------------------------------------------------------------------------
-- 1. TEEs no planeamento detalhado
-- ---------------------------------------------------------------------------

alter table public.alteracoes_tee
  add column if not exists data_inicio_execucao date,
  add column if not exists data_fim_execucao date;

alter table public.planeamento_itens
  add column if not exists tee_id uuid
  references public.alteracoes_tee(id) on delete set null;

create unique index if not exists planeamento_itens_tee_uidx
  on public.planeamento_itens (tee_id)
  where tee_id is not null;

create or replace function public.fn_sincronizar_tee_planeamento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado_aprovacao_cliente is distinct from 'aprovado'
     or new.fase_id is null
     or new.data_inicio_execucao is null
     or new.data_fim_execucao is null then
    return new;
  end if;

  if new.data_fim_execucao < new.data_inicio_execucao then
    raise exception 'A data de fim da execução do TEE não pode ser anterior à data de início.';
  end if;

  insert into public.planeamento_itens (
    fase_id,
    tee_id,
    descricao,
    responsavel,
    duracao_dias,
    data_inicio_prevista,
    data_fim_prevista,
    estado
  )
  values (
    new.fase_id,
    new.id,
    coalesce(nullif(new.descricao, ''), 'TEE ' || coalesce(new.numero, '')),
    'TEE ' || coalesce(new.numero, ''),
    new.data_fim_execucao - new.data_inicio_execucao,
    new.data_inicio_execucao,
    new.data_fim_execucao,
    case
      when new.data_fim_execucao < current_date then 'concluido'
      when new.data_inicio_execucao <= current_date then 'em_execucao'
      else 'por_iniciar'
    end
  )
  on conflict (tee_id) where tee_id is not null
  do update set
    fase_id = excluded.fase_id,
    descricao = excluded.descricao,
    responsavel = excluded.responsavel,
    duracao_dias = excluded.duracao_dias,
    data_inicio_prevista = excluded.data_inicio_prevista,
    data_fim_prevista = excluded.data_fim_prevista,
    estado = excluded.estado;

  return new;
end;
$$;

drop trigger if exists trg_sincronizar_tee_planeamento
  on public.alteracoes_tee;
create trigger trg_sincronizar_tee_planeamento
after insert or update of estado_aprovacao_cliente, fase_id,
  data_inicio_execucao, data_fim_execucao, numero, descricao
on public.alteracoes_tee
for each row execute function public.fn_sincronizar_tee_planeamento();

-- ---------------------------------------------------------------------------
-- 2. Subempreitadas e TEEs na previsão financeira mensal
-- ---------------------------------------------------------------------------

create or replace function public.fn_ajustar_saida_prevista_mensal(
  p_obra_id uuid,
  p_mes date,
  p_variacao numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_linhas integer := 0;
begin
  if p_obra_id is null or p_mes is null or coalesce(p_variacao, 0) = 0 then
    return;
  end if;

  -- Um mês fechado é histórico e nunca é reaberto por automação.
  if exists (
    select 1
    from public.previsao_financeira_mensal p
    where p.obra_id = p_obra_id
      and p.mes = v_mes
      and p.tipo = 'previsao'
      and coalesce(p.fechado, false)
  ) then
    return;
  end if;

  update public.previsao_financeira_mensal p
  set
    saidas_previstas_sem_iva = greatest(0, coalesce(p.saidas_previstas_sem_iva, 0) + p_variacao),
    -- Enquanto a origem não guardar uma taxa de IVA própria, o mesmo compromisso
    -- é refletido nos dois totais para não desaparecer do cash flow previsto.
    saidas_previstas_com_iva = greatest(0, coalesce(p.saidas_previstas_com_iva, 0) + p_variacao)
  where p.obra_id = p_obra_id
    and p.mes = v_mes
    and p.tipo = 'previsao'
    and coalesce(p.fechado, false) = false;

  get diagnostics v_linhas = row_count;
  if v_linhas > 0 or p_variacao < 0 then
    return;
  end if;

  begin
    insert into public.previsao_financeira_mensal (
      obra_id, mes,
      subempreitadas_real, materiais_real, mao_obra_real, estaleiro_real,
      saidas_reais_sem_iva, saidas_reais_com_iva,
      saidas_previstas_sem_iva, saidas_previstas_com_iva,
      tipo, entradas_reais, entradas_previstas, fechado
    )
    values (
      p_obra_id, v_mes,
      0, 0, 0, 0,
      0, 0,
      greatest(0, p_variacao), greatest(0, p_variacao),
      'previsao', 0, 0, false
    );
  exception when unique_violation then
    update public.previsao_financeira_mensal p
    set
      saidas_previstas_sem_iva = greatest(0, coalesce(p.saidas_previstas_sem_iva, 0) + p_variacao),
      saidas_previstas_com_iva = greatest(0, coalesce(p.saidas_previstas_com_iva, 0) + p_variacao)
    where p.obra_id = p_obra_id
      and p.mes = v_mes
      and p.tipo = 'previsao'
      and coalesce(p.fechado, false) = false;
  end;
end;
$$;

create or replace function public.fn_sincronizar_subempreitada_previsao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado_antigo text;
  v_estado_novo text;
begin
  if tg_op <> 'INSERT' then
    v_estado_antigo := lower(coalesce(old.estado, ''));
    if v_estado_antigo in ('adjudicado', 'adjudicada', 'em_execucao', 'concluido', 'concluida')
       and old.data_inicio_prevista is not null
       and old.data_fim_prevista is not null then
      perform public.fn_ajustar_saida_prevista_mensal(
        old.obra_id,
        old.data_inicio_prevista,
        -coalesce(old.valor_adjudicado, 0)
      );
    end if;
  end if;

  if tg_op <> 'DELETE' then
    v_estado_novo := lower(coalesce(new.estado, ''));
    if v_estado_novo in ('adjudicado', 'adjudicada', 'em_execucao', 'concluido', 'concluida')
       and new.data_inicio_prevista is not null
       and new.data_fim_prevista is not null then
      perform public.fn_ajustar_saida_prevista_mensal(
        new.obra_id,
        new.data_inicio_prevista,
        coalesce(new.valor_adjudicado, 0)
      );
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sincronizar_subempreitada_previsao
  on public.subempreitadas;
create trigger trg_sincronizar_subempreitada_previsao
after insert or update or delete
on public.subempreitadas
for each row execute function public.fn_sincronizar_subempreitada_previsao();

create or replace function public.fn_sincronizar_tee_previsao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'INSERT'
     and old.estado_aprovacao_cliente = 'aprovado'
     and old.data_inicio_execucao is not null
     and old.data_fim_execucao is not null then
    perform public.fn_ajustar_saida_prevista_mensal(
      old.obra_id,
      old.data_inicio_execucao,
      -coalesce(old.preco_custo, 0)
    );
  end if;

  if tg_op <> 'DELETE'
     and new.estado_aprovacao_cliente = 'aprovado'
     and new.data_inicio_execucao is not null
     and new.data_fim_execucao is not null then
    perform public.fn_ajustar_saida_prevista_mensal(
      new.obra_id,
      new.data_inicio_execucao,
      coalesce(new.preco_custo, 0)
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sincronizar_tee_previsao
  on public.alteracoes_tee;
create trigger trg_sincronizar_tee_previsao
after insert or update or delete
on public.alteracoes_tee
for each row execute function public.fn_sincronizar_tee_previsao();

-- ---------------------------------------------------------------------------
-- 3. Encarregados: leitura limitada às obras atribuídas
-- ---------------------------------------------------------------------------

create or replace function public.fn_e_encarregado_da_obra(p_obra_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.obra_responsaveis r
    join public.utilizadores u on u.id = r.utilizador_id
    where r.obra_id = p_obra_id
      and r.utilizador_id = public.fn_utilizador_atual_id()
      and r.papel = 'encarregado'
      and u.funcao = 'encarregado'
      and coalesce(u.ativo, true)
  );
$$;

revoke all on function public.fn_e_encarregado_da_obra(uuid) from public, anon;
grant execute on function public.fn_e_encarregado_da_obra(uuid) to authenticated;

grant select on table public.obras, public.fases, public.documentos_obra,
  public.itens_orcamento, public.alteracoes_tee, public.planeamento_itens,
  public.reunioes_atas, public.desenhos, public.rfis to authenticated;

alter table public.reunioes_atas enable row level security;

drop policy if exists pl_obras_select on public.obras;
create policy pl_obras_select on public.obras for select to authenticated
using (
  public.fn_pode_ver_obra(id)
  or public.fn_e_financeiro()
  or public.fn_e_encarregado_da_obra(id)
);

drop policy if exists pl_fases_select on public.fases;
create policy pl_fases_select on public.fases for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_financeiro()
  or public.fn_e_encarregado_da_obra(obra_id)
);

drop policy if exists documentos_obra_select on public.documentos_obra;
drop policy if exists pl_documentos_obra_select on public.documentos_obra;
create policy pl_documentos_obra_select
on public.documentos_obra for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or (
    public.fn_e_encarregado_da_obra(obra_id)
    and tipo in ('desenho', 'desenhos_preparacao', 'plantas_projeto')
  )
);

drop policy if exists pl_itens_orcamento_select on public.itens_orcamento;
create policy pl_itens_orcamento_select
on public.itens_orcamento for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (
      public.fn_pode_ver_obra(f.obra_id)
      or public.fn_e_financeiro()
      or public.fn_e_encarregado_da_obra(f.obra_id)
    )
));

drop policy if exists pl_tees_select on public.alteracoes_tee;
create policy pl_tees_select
on public.alteracoes_tee for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_financeiro()
  or public.fn_e_encarregado_da_obra(obra_id)
);

drop policy if exists planeamento_itens_select on public.planeamento_itens;
drop policy if exists pl_planeamento_itens_select on public.planeamento_itens;
create policy pl_planeamento_itens_select
on public.planeamento_itens for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (
      public.fn_pode_ver_obra(f.obra_id)
      or public.fn_e_financeiro()
      or public.fn_e_encarregado_da_obra(f.obra_id)
    )
));

drop policy if exists reunioes_atas_select on public.reunioes_atas;
drop policy if exists pl_reunioes_atas_select on public.reunioes_atas;
create policy pl_reunioes_atas_select
on public.reunioes_atas for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_encarregado_da_obra(obra_id)
);

drop policy if exists pl_desenhos_select on public.desenhos;
create policy pl_desenhos_select
on public.desenhos for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_encarregado_da_obra(obra_id)
);

drop policy if exists pl_rfis_select on public.rfis;
create policy pl_rfis_select
on public.rfis for select to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or public.fn_e_encarregado_da_obra(obra_id)
);

-- A leitura do objeto no Storage respeita também o tipo do documento.
drop policy if exists documentos_storage_select on storage.objects;
create policy documentos_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (
    public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
    or exists (
      select 1
      from public.documentos_obra d
      where d.obra_id = ((storage.foldername(name))[1])::uuid
        and d.arquivo_url = name
        and d.tipo in ('desenho', 'desenhos_preparacao', 'plantas_projeto')
        and public.fn_e_encarregado_da_obra(d.obra_id)
    )
  )
);

commit;
