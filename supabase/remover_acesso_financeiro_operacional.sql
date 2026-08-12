-- Primeline | Financeiro sem acesso a Subempreitadas, TEEs e Planeamento.
-- A policy RESTRICTIVE é uma barreira adicional, mesmo perante policies
-- permissivas antigas (incluindo policies USING (true)).

begin;

do $$
declare
  v_table text;
  v_tables text[] := array[
    'subempreitadas',
    'pagamentos_subempreitada',
    'consultas_subempreitada',
    'consultas_subempreitada_itens',
    'consultas_subempreitada_candidatos',
    'consultas_subempreitada_candidatos_itens',
    'alteracoes_tee',
    'alteracoes_tee_itens',
    'planeamento_fases_resumo',
    'planeamento_itens',
    'planeamento_itens_dependencias'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass('public.' || v_table) is not null then
      execute format(
        'drop policy if exists bloquear_financeiro_operacional on public.%I',
        v_table
      );
      execute format(
        'create policy bloquear_financeiro_operacional on public.%I as restrictive for select to authenticated using (not public.fn_e_financeiro() or public.fn_e_admin())',
        v_table
      );
    end if;
  end loop;
end;
$$;

commit;

select tablename, policyname, permissive, cmd
from pg_policies
where schemaname = 'public'
  and policyname = 'bloquear_financeiro_operacional'
order by tablename;
