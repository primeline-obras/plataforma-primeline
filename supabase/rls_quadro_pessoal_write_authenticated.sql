-- Primeline | Edição do quadro de pessoal
-- Executar manualmente no SQL Editor do Supabase.
-- Todos os utilizadores autenticados podem editar. O papel anon permanece sem acesso.

revoke all on table public.quadro_pessoal_alocacao from anon;
grant select, insert, update, delete on table public.quadro_pessoal_alocacao to authenticated;

drop policy if exists quadro_pessoal_insert_authenticated on public.quadro_pessoal_alocacao;
create policy quadro_pessoal_insert_authenticated
on public.quadro_pessoal_alocacao
for insert
to authenticated
with check (auth.uid() is not null);

drop policy if exists quadro_pessoal_update_authenticated on public.quadro_pessoal_alocacao;
create policy quadro_pessoal_update_authenticated
on public.quadro_pessoal_alocacao
for update
to authenticated
using (auth.uid() is not null)
with check (auth.uid() is not null);

drop policy if exists quadro_pessoal_delete_authenticated on public.quadro_pessoal_alocacao;
create policy quadro_pessoal_delete_authenticated
on public.quadro_pessoal_alocacao
for delete
to authenticated
using (auth.uid() is not null);
