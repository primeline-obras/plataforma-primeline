-- PRIMELINE | Definições e administração da plataforma
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

-- Um administrador da plataforma continua independente da funcao, mas respeita
-- o estado ativo do respetivo utilizador.
create or replace function public.fn_e_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.administradores_plataforma a
    join public.utilizadores u on u.id = a.utilizador_id
    where a.utilizador_id = public.fn_utilizador_atual_id()
      and coalesce(u.ativo, true)
  )
  or exists (
    select 1
    from public.utilizadores u
    where u.id = public.fn_utilizador_atual_id()
      and u.funcao = 'gerencia'
      and coalesce(u.ativo, true)
  );
$$;

alter table public.empresas add column if not exists morada text;
alter table public.empresas add column if not exists nif text;

alter table public.empresas enable row level security;
alter table public.utilizadores enable row level security;
alter table public.obra_responsaveis enable row level security;
alter table public.administradores_plataforma enable row level security;

revoke all on table public.empresas from anon;
revoke all on table public.utilizadores from anon;
revoke all on table public.obra_responsaveis from anon;
revoke all on table public.administradores_plataforma from anon;

grant select, update on table public.empresas to authenticated;
grant select, insert, update on table public.utilizadores to authenticated;
grant select, insert, delete on table public.obra_responsaveis to authenticated;
grant select, insert, delete on table public.administradores_plataforma to authenticated;

drop policy if exists settings_empresas_admin on public.empresas;
create policy settings_empresas_admin
on public.empresas for all to authenticated
using (public.fn_e_admin())
with check (public.fn_e_admin());

drop policy if exists settings_utilizadores_admin_insert on public.utilizadores;
create policy settings_utilizadores_admin_insert
on public.utilizadores for insert to authenticated
with check (public.fn_e_admin());

drop policy if exists settings_utilizadores_admin_update on public.utilizadores;
create policy settings_utilizadores_admin_update
on public.utilizadores for update to authenticated
using (public.fn_e_admin())
with check (public.fn_e_admin());

drop policy if exists settings_responsaveis_admin_insert on public.obra_responsaveis;
create policy settings_responsaveis_admin_insert
on public.obra_responsaveis for insert to authenticated
with check (public.fn_e_admin());

drop policy if exists settings_responsaveis_admin_delete on public.obra_responsaveis;
create policy settings_responsaveis_admin_delete
on public.obra_responsaveis for delete to authenticated
using (public.fn_e_admin());

drop policy if exists settings_administradores_admin_insert on public.administradores_plataforma;
create policy settings_administradores_admin_insert
on public.administradores_plataforma for insert to authenticated
with check (public.fn_e_admin());

drop policy if exists settings_administradores_admin_delete on public.administradores_plataforma;
create policy settings_administradores_admin_delete
on public.administradores_plataforma for delete to authenticated
using (public.fn_e_admin());

commit;

-- Verificação: deve devolver quatro linhas com RLS ativo.
select relname as tabela, relrowsecurity as rls_ativo
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('empresas', 'utilizadores', 'obra_responsaveis', 'administradores_plataforma')
order by relname;
