begin;

-- Adjunto pertence à Equipa Técnica e deve conservar, por obra associada,
-- o mesmo acesso operacional que existia para Diretor de Obra e Preparador.
create or replace function public.fn_pode_ver_obra(p_obra_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo()
    or exists (
      select 1
      from public.obra_responsaveis r
      join public.utilizadores u on u.id = r.utilizador_id
      where r.obra_id = p_obra_id
        and r.utilizador_id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'adjunto', 'preparador')
        and r.papel in ('diretor_obra', 'adjunto', 'preparador')
        and coalesce(u.ativo, true)
    );
$$;

create or replace function public.fn_pode_editar_obra(p_obra_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_admin()
    or exists (
      select 1
      from public.obra_responsaveis r
      join public.utilizadores u on u.id = r.utilizador_id
      where r.obra_id = p_obra_id
        and r.utilizador_id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'adjunto', 'preparador')
        and r.papel in ('diretor_obra', 'adjunto', 'preparador')
        and coalesce(u.ativo, true)
    );
$$;

revoke all on function public.fn_pode_ver_obra(uuid) from public, anon;
revoke all on function public.fn_pode_editar_obra(uuid) from public, anon;
grant execute on function public.fn_pode_ver_obra(uuid) to authenticated;
grant execute on function public.fn_pode_editar_obra(uuid) to authenticated;

commit;
