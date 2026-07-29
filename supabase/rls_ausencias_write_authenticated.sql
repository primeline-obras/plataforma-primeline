-- Primeline | Registo de férias através do quadro de pessoal
-- Todos os utilizadores autenticados podem inserir e remover ausências.
-- O papel anon permanece sem acesso.

revoke all on table public.ausencias from anon;
grant select, insert, delete on table public.ausencias to authenticated;

drop policy if exists ausencias_insert_authenticated on public.ausencias;
create policy ausencias_insert_authenticated
on public.ausencias
for insert
to authenticated
with check (auth.uid() is not null);

drop policy if exists ausencias_delete_authenticated on public.ausencias;
create policy ausencias_delete_authenticated
on public.ausencias
for delete
to authenticated
using (auth.uid() is not null);
