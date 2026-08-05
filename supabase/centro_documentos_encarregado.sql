-- Centro documental por obra: grupos operacionais visíveis ao encarregado.
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

drop policy if exists documentos_obra_select on public.documentos_obra;
drop policy if exists pl_documentos_obra_select on public.documentos_obra;
create policy pl_documentos_obra_select
on public.documentos_obra
for select
to authenticated
using (
  public.fn_pode_ver_obra(obra_id)
  or (
    public.fn_e_encarregado_da_obra(obra_id)
    and tipo in (
      'articulado_original',
      'articulado_tee',
      'desenho',
      'desenhos_preparacao',
      'plantas_projeto',
      'pdes_rfis',
      'pames',
      'atas_reuniao'
    )
  )
);

drop policy if exists documentos_storage_select on storage.objects;
create policy documentos_storage_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid)
  )
);

commit;
