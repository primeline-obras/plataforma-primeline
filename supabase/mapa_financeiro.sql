-- PRIMELINE | Mapa Financeiro anual e ajustes mensais.

begin;

alter table public.debitos_diretos
  drop constraint if exists debitos_diretos_categoria_check;

alter table public.debitos_diretos
  add constraint debitos_diretos_categoria_check
  check (categoria = any (array[
    'renda'::text,
    'seguro'::text,
    'software'::text,
    'emprestimo'::text,
    'servico_publico'::text,
    'remuneracoes_sede'::text,
    'despesas_sede'::text,
    'despesas_armazem'::text,
    'outro'::text
  ]));

create table if not exists public.mapa_financeiro_ajustes (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  ano integer not null check (ano between 2000 and 2200),
  mes integer not null check (mes between 1 and 12),
  valor_calculado_referencia numeric,
  valor_ajustado numeric not null,
  motivo text,
  atualizado_por uuid references public.utilizadores(id),
  atualizado_em timestamptz not null default now(),
  unique (obra_id, ano, mes)
);

-- Mantém a migração repetível caso a tabela tenha sido criada parcialmente.
alter table public.mapa_financeiro_ajustes
  add column if not exists valor_calculado_referencia numeric;

alter table public.mapa_financeiro_ajustes enable row level security;

revoke all on public.mapa_financeiro_ajustes from anon;
grant select, insert, update, delete on public.mapa_financeiro_ajustes to authenticated;

drop policy if exists mapa_financeiro_ajustes_select on public.mapa_financeiro_ajustes;
create policy mapa_financeiro_ajustes_select
on public.mapa_financeiro_ajustes for select to authenticated
using (public.fn_e_admin() or public.fn_e_financeiro());

drop policy if exists mapa_financeiro_ajustes_insert on public.mapa_financeiro_ajustes;
create policy mapa_financeiro_ajustes_insert
on public.mapa_financeiro_ajustes for insert to authenticated
with check (public.fn_e_admin() or public.fn_e_financeiro());

drop policy if exists mapa_financeiro_ajustes_update on public.mapa_financeiro_ajustes;
create policy mapa_financeiro_ajustes_update
on public.mapa_financeiro_ajustes for update to authenticated
using (public.fn_e_admin() or public.fn_e_financeiro())
with check (public.fn_e_admin() or public.fn_e_financeiro());

drop policy if exists mapa_financeiro_ajustes_delete on public.mapa_financeiro_ajustes;
create policy mapa_financeiro_ajustes_delete
on public.mapa_financeiro_ajustes for delete to authenticated
using (public.fn_e_admin() or public.fn_e_financeiro());

commit;

select
  to_regclass('public.mapa_financeiro_ajustes') is not null as tabela_ajustes,
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.debitos_diretos'::regclass
      and conname = 'debitos_diretos_categoria_check'
      and pg_get_constraintdef(oid) like '%remuneracoes_sede%'
  ) as categorias_despesas_fixas,
  count(*) filter (where cmd = 'SELECT') as politicas_select,
  count(*) filter (where cmd = 'INSERT') as politicas_insert,
  count(*) filter (where cmd = 'UPDATE') as politicas_update,
  count(*) filter (where cmd = 'DELETE') as politicas_delete
from pg_policies
where schemaname = 'public'
  and tablename = 'mapa_financeiro_ajustes';
