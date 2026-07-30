-- Documentos privados por obra.
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.documentos_obra enable row level security;

revoke all on table public.documentos_obra from anon;
grant select, insert on table public.documentos_obra to authenticated;

drop policy if exists documentos_obra_select on public.documentos_obra;
create policy documentos_obra_select
on public.documentos_obra
for select
to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists documentos_obra_insert on public.documentos_obra;
create policy documentos_obra_insert
on public.documentos_obra
for insert
to authenticated
with check (
  (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo())
  and enviado_por = public.fn_utilizador_atual_id()
);

create or replace function public.fn_pode_editar_documentos_obra(p_obra_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select public.fn_pode_editar_obra(p_obra_id)
    or public.fn_e_administrativo();
$$;

revoke all on function public.fn_pode_editar_documentos_obra(uuid) from public, anon;
grant execute on function public.fn_pode_editar_documentos_obra(uuid) to authenticated;

create or replace function public.fn_registar_documento_obra(
  p_obra_id uuid,
  p_tipo text,
  p_nome_arquivo text,
  p_arquivo_url text
)
returns public.documentos_obra
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_documento public.documentos_obra;
  v_utilizador_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sessão autenticada obrigatória.';
  end if;

  if not (public.fn_pode_editar_obra(p_obra_id) or public.fn_e_administrativo()) then
    raise exception 'Sem permissão para enviar documentos para esta obra.';
  end if;

  if p_tipo is null or p_tipo not in (
    'contrato',
    'orcamento',
    'plantas_projeto',
    'desenhos_preparacao',
    'atas_reuniao',
    'pdes_rfis',
    'pames',
    'licencas',
    'planeamento_detalhado',
    'outro'
  ) then
    raise exception 'Tipo de documento inválido.';
  end if;

  if nullif(btrim(p_nome_arquivo), '') is null then
    raise exception 'O nome do ficheiro é obrigatório.';
  end if;

  if nullif(btrim(p_arquivo_url), '') is null
     or p_arquivo_url not like p_obra_id::text || '/%' then
    raise exception 'O caminho do documento não pertence à obra indicada.';
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();
  if v_utilizador_id is null then
    raise exception 'O utilizador autenticado não está associado a public.utilizadores.';
  end if;

  insert into public.documentos_obra (
    obra_id,
    tipo,
    nome_arquivo,
    arquivo_url,
    enviado_por
  )
  values (
    p_obra_id,
    p_tipo,
    btrim(p_nome_arquivo),
    p_arquivo_url,
    v_utilizador_id
  )
  returning * into v_documento;

  return v_documento;
end;
$$;

revoke all on function public.fn_registar_documento_obra(uuid, text, text, text) from public, anon;
grant execute on function public.fn_registar_documento_obra(uuid, text, text, text) to authenticated;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'documentos',
  'documentos',
  false,
  26214400,
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-project',
    'application/x-msproject',
    'application/acad',
    'application/x-acad',
    'image/vnd.dwg',
    'image/vnd.dxf',
    'application/zip',
    'text/plain',
    'application/octet-stream'
  ]::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists documentos_storage_select on storage.objects;
create policy documentos_storage_select
on storage.objects
for select
to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
);

drop policy if exists documentos_storage_insert on storage.objects;
create policy documentos_storage_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (
    public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_administrativo()
  )
);

commit;
