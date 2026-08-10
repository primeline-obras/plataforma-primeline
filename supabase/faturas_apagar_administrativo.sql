begin;

-- As relações dependentes passam a ser eliminadas pela própria base de dados.
do $block$
declare
  v_tabela text;
  v_constraint record;
begin
  foreach v_tabela in array array['faturas_itens', 'faturas_anexos', 'faturas_guias'] loop
    for v_constraint in
      select c.conname
      from pg_constraint c
      where c.conrelid = format('public.%I', v_tabela)::regclass
        and c.contype = 'f'
        and c.confrelid = 'public.faturas'::regclass
    loop
      execute format('alter table public.%I drop constraint %I', v_tabela, v_constraint.conname);
    end loop;

    execute format(
      'alter table public.%I add constraint %I foreign key (fatura_id) references public.faturas(id) on delete cascade not valid',
      v_tabela,
      v_tabela || '_fatura_id_fkey'
    );
  end loop;
end;
$block$;

revoke delete on table public.faturas from authenticated;
revoke delete on table public.faturas_itens, public.faturas_anexos, public.faturas_guias from authenticated;

create or replace function public.fn_apagar_fatura_administrativo(p_fatura_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fatura public.faturas;
  v_tem_trigger_auditoria boolean;
begin
  -- fn_e_administrativo() inclui administradores; aqui a regra é mais estrita:
  -- apenas um utilizador com funcao='administrativo' e sem acesso de admin.
  if public.fn_e_admin()
     or not exists (
       select 1
       from public.utilizadores u
       where u.id = public.fn_utilizador_atual_id()
         and u.funcao = 'administrativo'
         and coalesce(u.ativo, true)
     ) then
    raise exception 'Só o papel Administrativo pode apagar faturas.';
  end if;

  select *
  into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found then
    raise exception 'A fatura selecionada já não existe.';
  end if;

  select exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.faturas'::regclass
      and t.tgname = 'trg_auditoria_faturas'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) into v_tem_trigger_auditoria;

  -- Instalações antigas sem o trigger geral recebem igualmente um log explícito.
  if not v_tem_trigger_auditoria then
    insert into public.log_auditoria (
      tabela_afetada,
      registo_id,
      campo,
      valor_anterior,
      valor_novo,
      utilizador_id,
      criado_em
    ) values (
      'public.faturas',
      v_fatura.id,
      '__DELETE__',
      jsonb_build_object(
        'id', v_fatura.id,
        'numero_doc', v_fatura.numero_doc,
        'obra_id', v_fatura.obra_id,
        'fornecedor_id', v_fatura.fornecedor_id,
        'valor', v_fatura.valor
      )::text,
      null,
      public.fn_utilizador_atual_id(),
      now()
    );
  end if;

  delete from public.faturas
  where id = v_fatura.id;

  return jsonb_build_object(
    'id', v_fatura.id,
    'numero_doc', v_fatura.numero_doc,
    'apagada', true
  );
end;
$$;

revoke all on function public.fn_apagar_fatura_administrativo(uuid) from public, anon, authenticated;
grant execute on function public.fn_apagar_fatura_administrativo(uuid) to authenticated;

commit;

select
  p.proname as funcao,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_pode_executar
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fn_apagar_fatura_administrativo';

