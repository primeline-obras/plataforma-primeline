-- PRIMELINE | Ausências e Horas Extra apenas para Administrativo/Gerência
-- Mantém a consulta de férias, mas retira faltas, anexos e horas à Equipa Técnica.

begin;

create or replace function public.fn_pode_gerir_ausencias()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo();
$$;

revoke all on function public.fn_pode_gerir_ausencias() from public, anon;
grant execute on function public.fn_pode_gerir_ausencias() to authenticated;

do $$
declare
  v_tabela text;
  v_policy record;
begin
  foreach v_tabela in array array['ausencias', 'ausencias_anexos', 'horas_extraordinarias'] loop
    for v_policy in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = v_tabela
    loop
      execute format('drop policy if exists %I on public.%I', v_policy.policyname, v_tabela);
    end loop;
  end loop;
end;
$$;

-- Férias continuam visíveis no Mapa de Férias. As restantes ausências
-- são informação RH e ficam reservadas ao Administrativo/Gerência.
create policy ausencias_ferias_select
on public.ausencias for select to authenticated
using (tipo = 'ferias' or public.fn_e_administrativo());

create policy ausencias_rh_insert
on public.ausencias for insert to authenticated
with check (public.fn_e_administrativo());

create policy ausencias_rh_update
on public.ausencias for update to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

create policy ausencias_rh_delete
on public.ausencias for delete to authenticated
using (public.fn_e_administrativo());

create policy ausencias_anexos_rh
on public.ausencias_anexos for all to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

create policy horas_extra_rh
on public.horas_extraordinarias for all to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

grant select, insert, update, delete on public.ausencias to authenticated;
grant select, insert, update, delete on public.ausencias_anexos to authenticated;
grant select, insert, update, delete on public.horas_extraordinarias to authenticated;
revoke all on public.ausencias, public.ausencias_anexos, public.horas_extraordinarias from anon;

-- Remove também o acesso aos comprovativos privados de ausências no Storage.
drop policy if exists documentos_ausencias_equipa_select on storage.objects;
drop policy if exists documentos_ausencias_equipa_insert on storage.objects;

commit;

select
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ausencias') as politicas_ausencias,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ausencias_anexos') as politicas_anexos,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'horas_extraordinarias') as politicas_horas_extra,
  public.fn_pode_gerir_ausencias() as utilizador_atual_pode_gerir;
