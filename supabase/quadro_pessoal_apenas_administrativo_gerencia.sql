-- PRIMELINE | Quadro de Pessoal reservado a Administrativo e Gerência
-- Preserva todas as alocações existentes e substitui políticas permissivas antigas.

begin;

create or replace function public.fn_pode_gerir_quadro(p_obra_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo();
$$;

revoke all on function public.fn_pode_gerir_quadro(uuid) from public, anon;
grant execute on function public.fn_pode_gerir_quadro(uuid) to authenticated;

alter table public.quadro_pessoal_alocacao enable row level security;
grant select, insert, update, delete on public.quadro_pessoal_alocacao to authenticated;
revoke all on public.quadro_pessoal_alocacao from anon;

-- As políticas RLS são permissivas por OR; por isso é necessário remover todas
-- as políticas anteriores desta tabela antes de instalar a regra final.
do $$
declare
  v_policy record;
begin
  for v_policy in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'quadro_pessoal_alocacao'
  loop
    execute format(
      'drop policy if exists %I on public.quadro_pessoal_alocacao',
      v_policy.policyname
    );
  end loop;
end;
$$;

create policy quadro_pessoal_rh_select
on public.quadro_pessoal_alocacao for select to authenticated
using (public.fn_e_administrativo());

create policy quadro_pessoal_rh_insert
on public.quadro_pessoal_alocacao for insert to authenticated
with check (
  public.fn_e_administrativo()
  and criado_por = public.fn_utilizador_atual_id()
);

create policy quadro_pessoal_rh_update
on public.quadro_pessoal_alocacao for update to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

create policy quadro_pessoal_rh_delete
on public.quadro_pessoal_alocacao for delete to authenticated
using (public.fn_e_administrativo());

-- Esta RPC expunha o quadro global aos encarregados. Deixa de ser invocável
-- pelos utilizadores da aplicação; o mapa de férias usa a consulta própria.
revoke all on function public.fn_quadro_ferias_encarregado_global(date, date)
from public, anon, authenticated;

commit;

select
  (select count(*) from public.quadro_pessoal_alocacao) as alocacoes_preservadas,
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'quadro_pessoal_alocacao') as politicas_ativas,
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'quadro_pessoal_alocacao'
      and policyname in (
        'quadro_pessoal_rh_select',
        'quadro_pessoal_rh_insert',
        'quadro_pessoal_rh_update',
        'quadro_pessoal_rh_delete'
      )
  ) as acesso_restrito,
  not has_function_privilege(
    'authenticated',
    'public.fn_quadro_ferias_encarregado_global(date,date)',
    'EXECUTE'
  ) as rpc_global_bloqueada;
