-- Lista segura dos utilizadores ativos com login da mesma empresa para reservas.
begin;

create or replace function public.fn_listar_participantes_reuniao()
returns table (
  id uuid,
  nome text,
  funcao text
)
language plpgsql
security definer
set search_path = public
stable
as $function$
declare
  v_atual public.utilizadores;
begin
  select * into v_atual
  from public.utilizadores
  where utilizadores.id = public.fn_utilizador_atual_id()
    and coalesce(utilizadores.ativo, true);

  if not found then
    raise exception 'Utilizador autenticado sem perfil ativo.';
  end if;

  if v_atual.funcao = 'encarregado' then
    raise exception 'O Encarregado não tem acesso às Salas de Reunião.';
  end if;

  return query
  select u.id, u.nome, u.funcao
  from public.utilizadores u
  where u.empresa_id = v_atual.empresa_id
    and coalesce(u.ativo, true)
    and u.auth_user_id is not null
  order by u.nome;
end;
$function$;

revoke all on function public.fn_listar_participantes_reuniao() from public, anon;
grant execute on function public.fn_listar_participantes_reuniao() to authenticated;

commit;

select
  to_regprocedure('public.fn_listar_participantes_reuniao()') is not null
    as rpc_lista_participantes;
