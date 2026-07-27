-- PRIMELINE - leituras para o separador Subempreitadas
-- Executar no SQL Editor com privilégios de owner.
-- Não concede acesso ao papel anon e não altera dados.

begin;

alter table public.pagamentos_subempreitada enable row level security;
alter table public.consultas_subempreitada enable row level security;

revoke all on table
  public.pagamentos_subempreitada,
  public.consultas_subempreitada
from anon;

grant select on table
  public.pagamentos_subempreitada,
  public.consultas_subempreitada
to authenticated;

drop policy if exists pagamentos_subempreitada_authenticated_select on public.pagamentos_subempreitada;
create policy pagamentos_subempreitada_authenticated_select
on public.pagamentos_subempreitada for select
to authenticated
using (true);

drop policy if exists consultas_subempreitada_authenticated_select on public.consultas_subempreitada;
create policy consultas_subempreitada_authenticated_select
on public.consultas_subempreitada for select
to authenticated
using (true);

commit;
