-- PRIMELINE | Arquivo privado de RH e viaturas.
-- Executar no SQL Editor com uma conta owner, depois de rls_permissoes_finais.sql.

begin;

-- A tabela já existe e é polimórfica. Mantemos os fluxos atuais e permitimos
-- novos tipos de entidade/documento sem criar um catálogo rígido.
alter table public.documentos
  drop constraint if exists documentos_entidade_tipo_check;
alter table public.documentos
  add constraint documentos_entidade_tipo_check
  check (btrim(entidade_tipo) <> '') not valid;
alter table public.documentos
  validate constraint documentos_entidade_tipo_check;

alter table public.documentos
  drop constraint if exists documentos_tipo_documento_check;
alter table public.documentos
  add constraint documentos_tipo_documento_check
  check (btrim(tipo_documento) <> '') not valid;
alter table public.documentos
  validate constraint documentos_tipo_documento_check;

create index if not exists documentos_entidade_idx
  on public.documentos (entidade_tipo, entidade_id, criado_em desc);
create index if not exists documentos_validade_idx
  on public.documentos (data_validade)
  where data_validade is not null;

alter table public.documentos enable row level security;
revoke all on table public.documentos from anon;
grant select, insert, update, delete on table public.documentos to authenticated;

drop policy if exists pl_documentos_rh on public.documentos;
create policy pl_documentos_rh
on public.documentos for all to authenticated
using (
  entidade_tipo in ('colaborador', 'viatura')
  and public.fn_e_administrativo()
)
with check (
  entidade_tipo in ('colaborador', 'viatura')
  and public.fn_e_administrativo()
);

-- Um alerta é criado desde logo com data_gatilho 30 dias antes da validade.
-- A interface só apresenta alertas cuja data_gatilho já chegou.
create or replace function public.fn_sincronizar_alerta_validade_documento()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome_entidade text;
begin
  if tg_op = 'DELETE' then
    delete from public.alertas
    where tipo = 'validade_documento'
      and entidade_tipo = 'documentos'
      and entidade_id = old.id
      and estado = 'pendente';
    return old;
  end if;

  delete from public.alertas
  where tipo = 'validade_documento'
    and entidade_tipo = 'documentos'
    and entidade_id = new.id
    and estado = 'pendente';

  if new.entidade_tipo not in ('colaborador', 'viatura') or new.data_validade is null then
    return new;
  end if;

  if new.entidade_tipo = 'colaborador' then
    select nome into v_nome_entidade
    from public.colaboradores
    where id = new.entidade_id;
  else
    select concat_ws(' · ', nullif(marca_modelo, ''), nullif(matricula, ''))
      into v_nome_entidade
    from public.viaturas
    where id = new.entidade_id;
  end if;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  ) values (
    new.empresa_id,
    'validade_documento',
    'documentos',
    new.id,
    'Documento a vencer: ' || coalesce(v_nome_entidade, new.nome_arquivo, 'registo'),
    coalesce(new.tipo_documento, 'Documento') || ' · validade em ' || to_char(new.data_validade, 'DD/MM/YYYY'),
    new.data_validade,
    30,
    new.data_validade - 30,
    'administrativo',
    'pendente'
  );

  return new;
end;
$$;

revoke all on function public.fn_sincronizar_alerta_validade_documento() from public, anon;

drop trigger if exists trg_alerta_validade_documento on public.documentos;
create trigger trg_alerta_validade_documento
after insert or update of data_validade, tipo_documento, nome_arquivo, entidade_tipo, entidade_id
or delete on public.documentos
for each row execute function public.fn_sincronizar_alerta_validade_documento();

-- Backfill seguro para documentos com validade já existentes.
insert into public.alertas (
  empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
  data_evento_referencia, antecedencia_dias, data_gatilho,
  destinatario_role, estado
)
select
  d.empresa_id,
  'validade_documento',
  'documentos',
  d.id,
  'Documento a vencer: ' || coalesce(
    case when d.entidade_tipo = 'colaborador' then c.nome end,
    case when d.entidade_tipo = 'viatura' then concat_ws(' · ', nullif(v.marca_modelo, ''), nullif(v.matricula, '')) end,
    d.nome_arquivo,
    'registo'
  ),
  d.tipo_documento || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
  d.data_validade,
  30,
  d.data_validade - 30,
  'administrativo',
  'pendente'
from public.documentos d
left join public.colaboradores c
  on d.entidade_tipo = 'colaborador' and c.id = d.entidade_id
left join public.viaturas v
  on d.entidade_tipo = 'viatura' and v.id = d.entidade_id
where d.entidade_tipo in ('colaborador', 'viatura')
  and d.data_validade is not null
  and not exists (
    select 1 from public.alertas a
    where a.tipo = 'validade_documento'
      and a.entidade_tipo = 'documentos'
      and a.entidade_id = d.id
      and a.estado = 'pendente'
  );

-- O alerta global de RH fica reservado ao Administrativo/Gerência.
drop policy if exists pl_alertas_select on public.alertas;
create policy pl_alertas_select
on public.alertas for select to authenticated
using (
  public.fn_e_administrativo()
  or (
    public.fn_e_financeiro()
    and destinatario_role in ('financeiro', 'tesouraria')
  )
  or (obra_id is not null and public.fn_pode_ver_obra(obra_id))
);

-- O bucket privado já é usado pelos documentos das obras; apenas alargamos os
-- MIME types e acrescentamos políticas para a pasta rh/.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documentos',
  'documentos',
  false,
  26214400,
  array[
    'application/pdf',
    'image/jpeg', 'image/png', 'image/webp', 'image/heic',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv', 'application/csv',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-project', 'application/x-msproject',
    'application/acad', 'application/x-acad', 'image/vnd.dwg', 'image/vnd.dxf',
    'application/zip', 'text/plain', 'application/octet-stream'
  ]::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists documentos_rh_storage_select on storage.objects;
create policy documentos_rh_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] in ('colaborador', 'viatura')
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

drop policy if exists documentos_rh_storage_insert on storage.objects;
create policy documentos_rh_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] in ('colaborador', 'viatura')
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

commit;

select
  (select count(*) from pg_trigger where tgname = 'trg_alerta_validade_documento' and not tgisinternal) as trigger_alerta_ativo,
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'documentos' and policyname = 'pl_documentos_rh') as politica_documentos_rh,
  (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname in ('documentos_rh_storage_select', 'documentos_rh_storage_insert')) as politicas_storage_rh;
