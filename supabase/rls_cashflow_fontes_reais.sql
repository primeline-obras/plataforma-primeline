-- PRIMELINE | Fontes reais e previsão mensal do cash flow
-- Migração idempotente. Executar no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.previsao_financeira_mensal enable row level security;

revoke all on table public.previsao_financeira_mensal from anon;
grant select on table public.previsao_financeira_mensal to authenticated;

drop policy if exists pl_previsao_financeira_mensal_select
  on public.previsao_financeira_mensal;
create policy pl_previsao_financeira_mensal_select
on public.previsao_financeira_mensal
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

-- O financeiro consulta os recebimentos reais de todas as obras, sempre em leitura.
drop policy if exists pl_faturacao_select on public.faturacao;
create policy pl_faturacao_select
on public.faturacao
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

commit;
