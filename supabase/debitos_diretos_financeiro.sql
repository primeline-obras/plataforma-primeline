-- PRIMELINE | Débitos diretos no Financeiro e no cash flow por obra.
-- Não altera o schema: consolida apenas privilégios e políticas RLS.

begin;

alter table public.debitos_diretos enable row level security;
alter table public.debitos_diretos_lancamentos enable row level security;

revoke all on table public.debitos_diretos from anon;
revoke all on table public.debitos_diretos_lancamentos from anon;
grant select, insert on table public.debitos_diretos to authenticated;
grant select, insert on table public.debitos_diretos_lancamentos to authenticated;

drop policy if exists debitos_diretos_select on public.debitos_diretos;
drop policy if exists debitos_diretos_write on public.debitos_diretos;
drop policy if exists pl_debitos_diretos_select on public.debitos_diretos;
drop policy if exists pl_debitos_diretos_insert on public.debitos_diretos;

create policy pl_debitos_diretos_select
on public.debitos_diretos for select to authenticated
using (
  public.fn_e_administrativo()
  or public.fn_e_financeiro()
  or (obra_id is not null and public.fn_pode_ver_obra(obra_id))
);

create policy pl_debitos_diretos_insert
on public.debitos_diretos for insert to authenticated
with check (
  public.fn_e_administrativo()
  or public.fn_e_financeiro()
);

drop policy if exists debitos_diretos_lancamentos_select on public.debitos_diretos_lancamentos;
drop policy if exists debitos_diretos_lancamentos_write on public.debitos_diretos_lancamentos;
drop policy if exists pl_debitos_lancamentos_select on public.debitos_diretos_lancamentos;
drop policy if exists pl_debitos_lancamentos_insert on public.debitos_diretos_lancamentos;

create policy pl_debitos_lancamentos_select
on public.debitos_diretos_lancamentos for select to authenticated
using (
  exists (
    select 1
    from public.debitos_diretos d
    where d.id = debitos_diretos_lancamentos.debito_direto_id
      and (
        public.fn_e_administrativo()
        or public.fn_e_financeiro()
        or (d.obra_id is not null and public.fn_pode_ver_obra(d.obra_id))
      )
  )
);

create policy pl_debitos_lancamentos_insert
on public.debitos_diretos_lancamentos for insert to authenticated
with check (
  public.fn_e_administrativo()
  or public.fn_e_financeiro()
);

commit;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('debitos_diretos', 'debitos_diretos_lancamentos')
order by tablename, cmd, policyname;
