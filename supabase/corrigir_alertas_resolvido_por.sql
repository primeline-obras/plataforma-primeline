-- Primeline | Corrige o autor da resolução dos alertas.
-- resolvido_por identifica a conta interna da plataforma (utilizadores.id),
-- nunca a ficha de RH em colaboradores.

begin;

alter table public.alertas
  drop constraint if exists alertas_resolvido_por_fkey;

-- Referências antigas provenientes da FK incorreta não podem ser atribuídas
-- com segurança a uma conta. Preserva o alerta e a data, removendo só o ID
-- incompatível antes de validar a FK correta.
update public.alertas a
set resolvido_por = null
where a.resolvido_por is not null
  and not exists (
    select 1
    from public.utilizadores u
    where u.id = a.resolvido_por
  );

alter table public.alertas
  add constraint alertas_resolvido_por_fkey
  foreign key (resolvido_por)
  references public.utilizadores(id)
  on delete set null;

drop function if exists public.fn_resolver_alerta(uuid);
create function public.fn_resolver_alerta(p_alerta_id uuid)
returns public.alertas
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerta public.alertas;
  v_utilizador_id uuid;
begin
  v_utilizador_id := public.fn_utilizador_atual_id();

  if v_utilizador_id is null then
    raise exception 'Sessão autenticada sem utilizador associado.';
  end if;

  select *
  into v_alerta
  from public.alertas
  where id = p_alerta_id
  for update;

  if not found then
    raise exception 'Alerta não encontrado.';
  end if;

  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
    or (
      public.fn_e_financeiro()
      and v_alerta.destinatario_role in ('financeiro', 'tesouraria')
    )
    or (
      v_alerta.obra_id is not null
      and public.fn_pode_editar_obra(v_alerta.obra_id)
    )
  ) then
    raise exception 'Sem permissão para resolver este alerta.';
  end if;

  if v_alerta.estado <> 'resolvido' then
    update public.alertas
    set estado = 'resolvido',
        resolvido_por = v_utilizador_id,
        resolvido_em = now()
    where id = p_alerta_id
    returning * into v_alerta;
  end if;

  return v_alerta;
end;
$$;

revoke all on function public.fn_resolver_alerta(uuid) from public, anon;
grant execute on function public.fn_resolver_alerta(uuid) to authenticated;

commit;

select
  tc.constraint_name,
  ccu.table_name as tabela_referenciada,
  ccu.column_name as coluna_referenciada,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.constraint_column_usage ccu
  on ccu.constraint_schema = tc.constraint_schema
 and ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_schema = tc.constraint_schema
 and rc.constraint_name = tc.constraint_name
where tc.table_schema = 'public'
  and tc.table_name = 'alertas'
  and tc.constraint_name = 'alertas_resolvido_por_fkey';
