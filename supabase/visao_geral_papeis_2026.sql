-- PRIMELINE | complemento RLS para a Visão Geral por papel
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

-- O Financeiro só pode consultar RNCs já fechadas e ligadas a uma
-- subempreitada. A política é aditiva e não concede escrita.
grant select on table public.rnc to authenticated;

drop policy if exists rnc_select_financeiro_avaliacao on public.rnc;
create policy rnc_select_financeiro_avaliacao
on public.rnc
for select
to authenticated
using (
  public.fn_e_financeiro()
  and estado = 'fechado'
  and subempreitada_id is not null
);

commit;
