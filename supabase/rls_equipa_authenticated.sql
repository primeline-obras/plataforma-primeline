-- Primeline | Equipa e quadro de pessoal
-- Executar manualmente no SQL Editor do Supabase.
-- Leitura apenas para utilizadores autenticados; o papel anon não recebe acesso.

alter table public.colaboradores enable row level security;
alter table public.quadro_pessoal_alocacao enable row level security;
alter table public.ausencias enable row level security;
alter table public.colaboradores_contratos enable row level security;
alter table public.horas_extraordinarias enable row level security;

revoke all on table public.colaboradores from anon;
revoke all on table public.quadro_pessoal_alocacao from anon;
revoke all on table public.ausencias from anon;
revoke all on table public.colaboradores_contratos from anon;
revoke all on table public.horas_extraordinarias from anon;

grant select on table public.colaboradores to authenticated;
grant select on table public.quadro_pessoal_alocacao to authenticated;
grant select on table public.ausencias to authenticated;
grant select on table public.colaboradores_contratos to authenticated;
grant select on table public.horas_extraordinarias to authenticated;

drop policy if exists colaboradores_select_authenticated on public.colaboradores;
create policy colaboradores_select_authenticated
on public.colaboradores for select to authenticated
using (true);

drop policy if exists quadro_pessoal_select_authenticated on public.quadro_pessoal_alocacao;
create policy quadro_pessoal_select_authenticated
on public.quadro_pessoal_alocacao for select to authenticated
using (true);

drop policy if exists ausencias_select_authenticated on public.ausencias;
create policy ausencias_select_authenticated
on public.ausencias for select to authenticated
using (true);

drop policy if exists colaboradores_contratos_select_authenticated on public.colaboradores_contratos;
create policy colaboradores_contratos_select_authenticated
on public.colaboradores_contratos for select to authenticated
using (true);

drop policy if exists horas_extraordinarias_select_authenticated on public.horas_extraordinarias;
create policy horas_extraordinarias_select_authenticated
on public.horas_extraordinarias for select to authenticated
using (true);
