-- Primeline | Corrige a leitura de TEEs na RSP.
-- Mantém o Financeiro sem acesso operacional e garante leitura à Gerência,
-- Administrativo, equipa técnica responsável e Encarregado da obra.

begin;

drop policy if exists pl_tees_select on public.alteracoes_tee;
create policy pl_tees_select
on public.alteracoes_tee
for select
to authenticated
using (
  public.fn_e_admin()
  or public.fn_pode_ver_obra(obra_id)
  or public.fn_e_encarregado_da_obra(obra_id)
);

commit;

select
  policyname,
  permissive,
  cmd,
  qual
from pg_policies
where schemaname = 'public'
  and tablename = 'alteracoes_tee'
order by policyname;
