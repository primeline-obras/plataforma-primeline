-- PRIMELINE - leituras adicionais para o módulo Obras
-- Executar no SQL Editor com privilégios de owner.
-- Não concede qualquer acesso ao papel anon e não altera dados.

begin;

alter table public.contratos enable row level security;
alter table public.fases enable row level security;
alter table public.autos_medicao enable row level security;

revoke all on table
  public.contratos,
  public.fases,
  public.autos_medicao
from anon;

grant select on table
  public.contratos,
  public.fases,
  public.autos_medicao
to authenticated;

drop policy if exists contratos_authenticated_select on public.contratos;
create policy contratos_authenticated_select
on public.contratos for select
to authenticated
using (true);

drop policy if exists fases_authenticated_select on public.fases;
create policy fases_authenticated_select
on public.fases for select
to authenticated
using (true);

drop policy if exists autos_medicao_authenticated_select on public.autos_medicao;
create policy autos_medicao_authenticated_select
on public.autos_medicao for select
to authenticated
using (true);

commit;
