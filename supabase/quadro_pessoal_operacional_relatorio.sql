-- PRIMELINE GO | Quadro de Pessoal operacional e relatório mensal de horas.
-- Diretores de Obra e Encarregados consultam o quadro global para perceberem
-- a disponibilidade, mas só alteram alocações das obras sob sua responsabilidade.

begin;

create or replace function public.fn_pode_consultar_quadro()
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.fn_e_administrativo()
    or exists (
      select 1 from public.utilizadores u
      where u.id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'encarregado')
        and coalesce(u.ativo, true)
    );
$function$;

create or replace function public.fn_pode_gerir_quadro(p_obra_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.fn_e_administrativo()
    or (
      p_obra_id is not null
      and exists (
        select 1 from public.utilizadores u
        where u.id = public.fn_utilizador_atual_id()
          and u.funcao = 'diretor_obra'
          and coalesce(u.ativo, true)
      )
      and public.fn_pode_ver_obra(p_obra_id)
    )
    or (
      p_obra_id is not null
      and public.fn_e_encarregado_da_obra(p_obra_id)
    );
$function$;

revoke all on function public.fn_pode_consultar_quadro() from public, anon;
revoke all on function public.fn_pode_gerir_quadro(uuid) from public, anon;
grant execute on function public.fn_pode_consultar_quadro() to authenticated;
grant execute on function public.fn_pode_gerir_quadro(uuid) to authenticated;

alter table public.quadro_pessoal_alocacao enable row level security;
grant select, insert, update, delete on public.quadro_pessoal_alocacao to authenticated;
revoke all on public.quadro_pessoal_alocacao from anon;

do $policies$
declare v_policy record;
begin
  for v_policy in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'quadro_pessoal_alocacao'
  loop
    execute format('drop policy if exists %I on public.quadro_pessoal_alocacao', v_policy.policyname);
  end loop;
end;
$policies$;

create policy quadro_pessoal_operacional_select
on public.quadro_pessoal_alocacao for select to authenticated
using (public.fn_pode_consultar_quadro());

create policy quadro_pessoal_operacional_insert
on public.quadro_pessoal_alocacao for insert to authenticated
with check (
  public.fn_pode_gerir_quadro(obra_id)
  and criado_por = public.fn_utilizador_atual_id()
);

create policy quadro_pessoal_operacional_update
on public.quadro_pessoal_alocacao for update to authenticated
using (public.fn_pode_gerir_quadro(obra_id))
with check (public.fn_pode_gerir_quadro(obra_id));

create policy quadro_pessoal_operacional_delete
on public.quadro_pessoal_alocacao for delete to authenticated
using (public.fn_pode_gerir_quadro(obra_id));

create table if not exists public.quadro_pessoal_movimentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  alocacao_id uuid,
  colaborador_id uuid not null references public.colaboradores(id) on delete restrict,
  data date not null,
  periodo text,
  acao text not null check (acao in ('adicionada', 'alterada', 'retirada')),
  obra_origem_id uuid references public.obras(id) on delete set null,
  obra_destino_id uuid references public.obras(id) on delete set null,
  tipo_origem text,
  tipo_destino text,
  descricao_origem text,
  descricao_destino text,
  alterado_por uuid references public.utilizadores(id) on delete set null,
  alterado_em timestamptz not null default now()
);

create index if not exists quadro_pessoal_movimentos_data_idx
  on public.quadro_pessoal_movimentos(empresa_id, data desc);
create index if not exists quadro_pessoal_movimentos_colaborador_idx
  on public.quadro_pessoal_movimentos(colaborador_id, alterado_em desc);

create or replace function public.fn_registar_movimento_quadro()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_colaborador_id uuid; v_empresa_id uuid;
begin
  v_colaborador_id := coalesce(new.colaborador_id, old.colaborador_id);
  select c.empresa_id into v_empresa_id
  from public.colaboradores c where c.id = v_colaborador_id;

  if tg_op = 'INSERT' then
    insert into public.quadro_pessoal_movimentos(
      empresa_id, alocacao_id, colaborador_id, data, periodo, acao,
      obra_destino_id, tipo_destino, descricao_destino, alterado_por
    ) values (
      v_empresa_id, new.id, new.colaborador_id, new.data, new.periodo, 'adicionada',
      new.obra_id, new.tipo_alocacao, new.descricao_livre, public.fn_utilizador_atual_id()
    );
  elsif tg_op = 'UPDATE' and old is distinct from new then
    insert into public.quadro_pessoal_movimentos(
      empresa_id, alocacao_id, colaborador_id, data, periodo, acao,
      obra_origem_id, obra_destino_id, tipo_origem, tipo_destino,
      descricao_origem, descricao_destino, alterado_por
    ) values (
      v_empresa_id, new.id, new.colaborador_id, new.data, new.periodo, 'alterada',
      old.obra_id, new.obra_id, old.tipo_alocacao, new.tipo_alocacao,
      old.descricao_livre, new.descricao_livre, public.fn_utilizador_atual_id()
    );
  elsif tg_op = 'DELETE' then
    insert into public.quadro_pessoal_movimentos(
      empresa_id, alocacao_id, colaborador_id, data, periodo, acao,
      obra_origem_id, tipo_origem, descricao_origem, alterado_por
    ) values (
      v_empresa_id, old.id, old.colaborador_id, old.data, old.periodo, 'retirada',
      old.obra_id, old.tipo_alocacao, old.descricao_livre, public.fn_utilizador_atual_id()
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

drop trigger if exists trg_quadro_pessoal_movimentos on public.quadro_pessoal_alocacao;
create trigger trg_quadro_pessoal_movimentos
after insert or update or delete on public.quadro_pessoal_alocacao
for each row execute function public.fn_registar_movimento_quadro();

alter table public.quadro_pessoal_movimentos enable row level security;
revoke all on public.quadro_pessoal_movimentos from anon;
grant select on public.quadro_pessoal_movimentos to authenticated;

do $policies$
declare v_policy record;
begin
  for v_policy in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'quadro_pessoal_movimentos'
  loop
    execute format('drop policy if exists %I on public.quadro_pessoal_movimentos', v_policy.policyname);
  end loop;
end;
$policies$;

create policy quadro_pessoal_movimentos_select
on public.quadro_pessoal_movimentos for select to authenticated
using (
  public.fn_e_administrativo()
  or public.fn_pode_gerir_quadro(obra_origem_id)
  or public.fn_pode_gerir_quadro(obra_destino_id)
);

create or replace function public.fn_relatorio_mensal_ponto(p_mes date)
returns table (
  colaborador_id uuid,
  colaborador text,
  funcao text,
  obra_id uuid,
  obra_numero text,
  obra_nome text,
  horas numeric,
  dias_com_ponto bigint,
  faltas_com_justificacao bigint,
  faltas_sem_justificacao bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare v_atual public.utilizadores; v_inicio date; v_fim date;
begin
  if not public.fn_e_administrativo() then
    raise exception 'O relatório mensal está reservado ao Administrativo e à Gestão.' using errcode = '42501';
  end if;
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and ativo is true;
  if v_atual.id is null then raise exception 'Utilizador sem perfil ativo.'; end if;
  if p_mes is null then raise exception 'Indique o mês de referência.'; end if;
  v_inicio := date_trunc('month', p_mes)::date;
  v_fim := (v_inicio + interval '1 month')::date;

  return query
  select
    c.id,
    c.nome,
    c.funcao,
    o.id,
    o.numero::text,
    o.nome,
    round(coalesce(sum(p.horas), 0), 2),
    count(distinct p.data),
    count(*) filter (where p.estado = 'falta_com_justificacao'),
    count(*) filter (where p.estado = 'falta_sem_justificacao')
  from public.ponto_pessoal_obra p
  join public.colaboradores c on c.id = p.colaborador_id
  join public.obras o on o.id = p.obra_id
  where p.empresa_id = v_atual.empresa_id
    and p.data >= v_inicio and p.data < v_fim
  group by c.id, c.nome, c.funcao, o.id, o.numero, o.nome
  order by lower(c.nome), o.numero::text, lower(o.nome);
end;
$function$;

revoke all on function public.fn_relatorio_mensal_ponto(date) from public, anon;
grant execute on function public.fn_relatorio_mensal_ponto(date) to authenticated;

commit;

select
  to_regprocedure('public.fn_pode_consultar_quadro()') is not null as quadro_visivel_operacional,
  to_regclass('public.quadro_pessoal_movimentos') is not null as historico_movimentos_ativo,
  to_regprocedure('public.fn_relatorio_mensal_ponto(date)') is not null as relatorio_mensal_ativo;
