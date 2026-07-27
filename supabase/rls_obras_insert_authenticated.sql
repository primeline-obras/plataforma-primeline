-- PRIMELINE — criação de obras por utilizadores autenticados.
-- Executar o conteúdo deste ficheiro no SQL Editor do Supabase.
-- Não altera a estrutura das tabelas e não concede acesso ao papel anon.

begin;

revoke all on table public.colaboradores from anon;

grant select on table public.colaboradores to authenticated;

grant insert (
  empresa_id,
  numero,
  nome,
  cliente,
  morada,
  tipo,
  modalidade,
  diretor_obra_id,
  situacao,
  data_inicio,
  data_fim_prevista
) on public.obras to authenticated;

drop policy if exists colaboradores_authenticated_select
  on public.colaboradores;

create policy colaboradores_authenticated_select
on public.colaboradores
for select
to authenticated
using (empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid);

drop policy if exists obras_authenticated_insert
  on public.obras;

create policy obras_authenticated_insert
on public.obras
for insert
to authenticated
with check (empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid);

commit;
