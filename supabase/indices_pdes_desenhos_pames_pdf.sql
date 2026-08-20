-- PRIMELINE | Índices PDE, Desenhos de Preparação e PAME
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.
-- Migração aditiva e idempotente; não elimina dados nem revisões existentes.

begin;

alter table public.rfis
  add column if not exists revisao text,
  add column if not exists data_emissao date,
  add column if not exists notas text,
  add column if not exists documento_obra_id uuid references public.documentos_obra(id) on delete set null;

comment on column public.rfis.estado is
  'Texto livre. Estados operacionais: Não enviado, Enviado ao DO, Respondido, Discutido em Reunião, Em elaboração, Cancelado.';

alter table public.desenhos
  add column if not exists data_envio_do date,
  add column if not exists data_resposta_do date,
  add column if not exists notas text,
  add column if not exists documento_obra_id uuid references public.documentos_obra(id) on delete set null;

comment on table public.desenhos is
  'Índice de desenhos de preparação. Cada documento/revisão é uma linha própria; o mesmo número pode repetir-se.';
comment on column public.desenhos.estado is
  'Texto livre. Estados operacionais: Em elaboração, Pedido de revisão, Emitido, Analisado em reunião, Apresentado em reunião.';

create table if not exists public.pames (
  id uuid primary key default gen_random_uuid(),
  obra_id uuid not null references public.obras(id) on delete cascade,
  numero text not null,
  descricao text,
  revisao text,
  data_emissao date,
  data_envio date,
  data_resposta date,
  estado text,
  notas text,
  documento_obra_id uuid references public.documentos_obra(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

comment on table public.pames is
  'Pedidos de Aprovação de Materiais e Equipamentos; cada revisão corresponde a uma linha do índice.';

alter table public.documentos_obra
  add column if not exists descricao text,
  add column if not exists data_emissao date,
  add column if not exists data_resposta_indice date,
  add column if not exists estado_indice text,
  add column if not exists notas text;

create index if not exists idx_rfis_obra_numero_revisao
  on public.rfis (obra_id, numero, revisao, data_emissao);
create index if not exists idx_desenhos_obra_numero_revisao
  on public.desenhos (obra_id, numero, revisao, data_emissao);
create index if not exists idx_pames_obra_numero_revisao
  on public.pames (obra_id, numero, revisao, data_emissao);

alter table public.pames enable row level security;
revoke all on table public.pames from anon;
grant select, insert, update, delete on table public.pames to authenticated;

drop policy if exists pl_pames_select on public.pames;
drop policy if exists pl_pames_write on public.pames;
create policy pl_pames_select on public.pames
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_pames_write on public.pames
for all to authenticated
using (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo())
with check (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo());

create or replace function public.fn_sincronizar_indices_documento_obra()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_numero text := coalesce(nullif(btrim(new.numero_documento), ''), new.nome_arquivo);
  v_data_envio date := coalesce(new.enviado_em::date, new.criado_em::date);
begin
  if new.tipo = 'desenhos_preparacao' then
    update public.desenhos set
      obra_id = new.obra_id, numero = v_numero, descricao = new.descricao,
      revisao = new.revisao, data_emissao = new.data_emissao,
      data_envio_do = v_data_envio, data_resposta_do = new.data_resposta_indice,
      estado = new.estado_indice, notas = new.notas
    where documento_obra_id = new.id;
    if not found then
      insert into public.desenhos
        (obra_id, numero, descricao, revisao, data_emissao, data_envio_do,
         data_resposta_do, estado, notas, documento_obra_id)
      values
        (new.obra_id, v_numero, new.descricao, new.revisao, new.data_emissao,
         v_data_envio, new.data_resposta_indice, new.estado_indice, new.notas, new.id);
    end if;
  elsif new.tipo = 'pdes_rfis' then
    update public.rfis set
      obra_id = new.obra_id, numero = v_numero, descricao = new.descricao,
      revisao = new.revisao, data_emissao = new.data_emissao,
      data_envio = v_data_envio, data_resposta = new.data_resposta_indice,
      estado = new.estado_indice, notas = new.notas
    where documento_obra_id = new.id;
    if not found then
      insert into public.rfis
        (obra_id, numero, descricao, revisao, data_emissao, data_envio,
         data_resposta, estado, notas, documento_obra_id)
      values
        (new.obra_id, v_numero, new.descricao, new.revisao, new.data_emissao,
         v_data_envio, new.data_resposta_indice, new.estado_indice, new.notas, new.id);
    end if;
  elsif new.tipo = 'pames' then
    update public.pames set
      obra_id = new.obra_id, numero = v_numero, descricao = new.descricao,
      revisao = new.revisao, data_emissao = new.data_emissao,
      data_envio = v_data_envio, data_resposta = new.data_resposta_indice,
      estado = new.estado_indice, notas = new.notas, atualizado_em = now()
    where documento_obra_id = new.id;
    if not found then
      insert into public.pames
        (obra_id, numero, descricao, revisao, data_emissao, data_envio,
         data_resposta, estado, notas, documento_obra_id)
      values
        (new.obra_id, v_numero, new.descricao, new.revisao, new.data_emissao,
         v_data_envio, new.data_resposta_indice, new.estado_indice, new.notas, new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sincronizar_indices_documento_obra on public.documentos_obra;
create trigger trg_sincronizar_indices_documento_obra
after insert or update of tipo, numero_documento, revisao, descricao, data_emissao,
  enviado_em, data_resposta_indice, estado_indice, notas
on public.documentos_obra
for each row execute function public.fn_sincronizar_indices_documento_obra();

-- Completa os índices para documentos já existentes sem alterar o arquivo.
update public.documentos_obra
set numero_documento = numero_documento
where tipo in ('desenhos_preparacao', 'pdes_rfis', 'pames');

commit;
