-- Documentos institucionais da empresa.
-- A tabela, a constraint entidade_tipo='empresa' e os alertas 15/7/3 dias já
-- existem. Esta migração acrescenta apenas o acesso aos metadados e à pasta
-- privada usada pelo frontend: documentos/empresa/<empresa_id>/...

begin;

alter table public.documentos enable row level security;
revoke all on table public.documentos from anon;
grant select, insert on table public.documentos to authenticated;

drop policy if exists pl_documentos_empresa_select on public.documentos;
create policy pl_documentos_empresa_select
on public.documentos for select to authenticated
using (
  entidade_tipo = 'empresa'
  and entidade_id = empresa_id
  and public.fn_e_administrativo()
);

drop policy if exists pl_documentos_empresa_insert on public.documentos;
create policy pl_documentos_empresa_insert
on public.documentos for insert to authenticated
with check (
  entidade_tipo = 'empresa'
  and entidade_id = empresa_id
  and public.fn_e_administrativo()
);

drop policy if exists documentos_empresa_storage_select on storage.objects;
create policy documentos_empresa_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'empresa'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

drop policy if exists documentos_empresa_storage_insert on storage.objects;
create policy documentos_empresa_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'empresa'
  and (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

commit;

select
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'documentos' and policyname in ('pl_documentos_empresa_select', 'pl_documentos_empresa_insert')) as politicas_metadados,
  (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('documentos_empresa_storage_select', 'documentos_empresa_storage_insert')) as politicas_storage;
