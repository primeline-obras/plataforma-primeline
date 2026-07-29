-- Leituras necessárias ao cash flow real da Reunião Semanal de Produção.
-- Executar no SQL Editor do Supabase como owner.

do $$
begin
  if to_regclass('public.lancamentos_mao_obra') is not null then
    execute 'grant select on public.lancamentos_mao_obra to authenticated';
    execute 'alter table public.lancamentos_mao_obra enable row level security';
    execute 'drop policy if exists lancamentos_mao_obra_authenticated_select on public.lancamentos_mao_obra';
    execute $policy$
      create policy lancamentos_mao_obra_authenticated_select
      on public.lancamentos_mao_obra
      for select
      to authenticated
      using (public.fn_pode_ver_obra(obra_id))
    $policy$;
  end if;

  if to_regclass('public.despesas_estaleiro') is not null then
    execute 'grant select on public.despesas_estaleiro to authenticated';
    execute 'alter table public.despesas_estaleiro enable row level security';
    execute 'drop policy if exists despesas_estaleiro_authenticated_select on public.despesas_estaleiro';
    execute $policy$
      create policy despesas_estaleiro_authenticated_select
      on public.despesas_estaleiro
      for select
      to authenticated
      using (public.fn_pode_ver_obra(obra_id))
    $policy$;
  end if;
end
$$;
