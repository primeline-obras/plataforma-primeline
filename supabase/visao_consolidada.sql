-- PRIMELINE | autorização da Visão Consolidada
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

create or replace function public.fn_pode_ver_visao_consolidada()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.fn_e_admin();
$$;

revoke all on function public.fn_pode_ver_visao_consolidada() from public;
revoke all on function public.fn_pode_ver_visao_consolidada() from anon;
grant execute on function public.fn_pode_ver_visao_consolidada() to authenticated;

commit;
