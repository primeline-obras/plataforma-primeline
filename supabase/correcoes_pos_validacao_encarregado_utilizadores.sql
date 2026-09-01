-- PRIMELINE | Correções pós-validação: Encarregado e utilizadores ativos
-- Idempotente: pode ser executada novamente sem duplicar dados.
begin;

-- O Plano de Ação do Encarregado passa a ser estritamente de leitura.
-- A função histórica é preservada para auditoria da migração anterior,
-- mas deixa de poder ser executada por sessões autenticadas.
revoke all on function public.fn_atualizar_tarefa_encarregado(uuid, boolean, boolean, text)
  from authenticated;

-- A lista operacional das Salas de Reunião aceita apenas perfis ativos.
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
    and utilizadores.ativo is true;

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
    and u.ativo is true
    and u.auth_user_id is not null
  order by u.nome;
end;
$function$;

revoke all on function public.fn_listar_participantes_reuniao() from public, anon;
grant execute on function public.fn_listar_participantes_reuniao() to authenticated;

commit;

select
  not has_function_privilege(
    'authenticated',
    'public.fn_atualizar_tarefa_encarregado(uuid, boolean, boolean, text)',
    'EXECUTE'
  ) as encarregado_planeamento_so_leitura,
  position(
    'u.ativo is true' in
    pg_get_functiondef('public.fn_listar_participantes_reuniao()'::regprocedure)
  ) > 0 as participantes_apenas_ativos;
