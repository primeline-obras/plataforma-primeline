-- Diretório global de subempreiteiros: leitura transversal para authenticated.
-- Não concede qualquer escrita adicional e mantém anon sem acesso.

begin;

alter table public.subempreitadas enable row level security;
alter table public.avaliacoes_subempreiteiro enable row level security;

revoke all on table
  public.subempreitadas,
  public.avaliacoes_subempreiteiro
from anon;

grant select on table
  public.subempreitadas,
  public.avaliacoes_subempreiteiro
to authenticated;

drop policy if exists subempreitadas_select on public.subempreitadas;
create policy subempreitadas_select
on public.subempreitadas
for select
to authenticated
using (true);

drop policy if exists avaliacoes_subempreiteiro_select on public.avaliacoes_subempreiteiro;
create policy avaliacoes_subempreiteiro_select
on public.avaliacoes_subempreiteiro
for select
to authenticated
using (true);

commit;

select
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  qual
from pg_policies
where schemaname = 'public'
  and tablename in ('subempreitadas', 'avaliacoes_subempreiteiro')
  and cmd = 'SELECT'
order by tablename, policyname;
