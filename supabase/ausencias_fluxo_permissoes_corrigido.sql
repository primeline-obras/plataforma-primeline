-- PRIMELINE | Bloco 3: ausências, justificações e anexos
-- Migração incremental: preserva todos os registos já existentes.

begin;

-- Combinações válidas do fluxo de negócio.
alter table public.ausencias
  drop constraint if exists ausencias_fluxo_check;

alter table public.ausencias
  add constraint ausencias_fluxo_check check (
    (tipo in ('ferias', 'falta_justificada_com_remuneracao') and estado = 'confirmada')
    or
    (tipo in ('falta_injustificada', 'falta_justificada_sem_remuneracao')
      and estado in ('ausente_pendente', 'justificada'))
  );

alter table public.ausencias
  drop constraint if exists ausencias_justificacao_comentario_check;

alter table public.ausencias
  add constraint ausencias_justificacao_comentario_check check (
    estado <> 'justificada' or nullif(btrim(comentario), '') is not null
  );

-- Define o estado inicial no servidor para não depender apenas do frontend.
create or replace function public.fn_normalizar_estado_ausencia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.tipo in ('ferias', 'falta_justificada_com_remuneracao') then
      new.estado := 'confirmada';
    elsif new.tipo in ('falta_injustificada', 'falta_justificada_sem_remuneracao') then
      new.estado := 'ausente_pendente';
    end if;
  end if;

  if new.estado = 'justificada' and nullif(btrim(new.comentario), '') is null then
    raise exception 'Para justificar a ausência é obrigatório preencher o comentário.';
  end if;

  return new;
end;
$$;

revoke all on function public.fn_normalizar_estado_ausencia() from public, anon, authenticated;

drop trigger if exists trg_normalizar_estado_ausencia on public.ausencias;
create trigger trg_normalizar_estado_ausencia
before insert or update of tipo, estado, comentario
on public.ausencias
for each row execute function public.fn_normalizar_estado_ausencia();

-- Os bloqueios precisam contornar a RLS para funcionarem igualmente para
-- qualquer papel autorizado a editar o Quadro ou lançar mão de obra.
create or replace function public.fn_bloquear_alocacao_em_ausencia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.ausencias a
    where a.colaborador_id = new.colaborador_id
      and a.data = new.data
  ) then
    raise exception 'Este colaborador está de férias/ausente nesta data.';
  end if;
  return new;
end;
$$;

create or replace function public.fn_bloquear_mao_obra_em_ausencia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.ausencias a
    where a.colaborador_id = new.colaborador_id
      and a.data = new.data
  ) then
    raise exception 'Este colaborador está de férias/ausente nesta data.';
  end if;
  return new;
end;
$$;

revoke all on function public.fn_bloquear_alocacao_em_ausencia() from public, anon, authenticated;
revoke all on function public.fn_bloquear_mao_obra_em_ausencia() from public, anon, authenticated;

drop trigger if exists trg_bloquear_quadro_pessoal_ausencia on public.quadro_pessoal_alocacao;
create trigger trg_bloquear_quadro_pessoal_ausencia
before insert or update of colaborador_id, data
on public.quadro_pessoal_alocacao
for each row execute function public.fn_bloquear_alocacao_em_ausencia();

drop trigger if exists trg_bloquear_mao_obra_ausencia on public.lancamentos_mao_obra;
create trigger trg_bloquear_mao_obra_ausencia
before insert or update of colaborador_id, data
on public.lancamentos_mao_obra
for each row execute function public.fn_bloquear_mao_obra_em_ausencia();

-- Um responsável vê a ausência quando o colaborador estava distribuído para
-- uma das suas obras nessa data. Administrativo/Gerência vê tudo.
create or replace function public.fn_pode_ver_ausencia(
  p_colaborador_id uuid,
  p_data date
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo()
    or exists (
      select 1
      from public.quadro_pessoal_alocacao q
      where q.colaborador_id = p_colaborador_id
        and q.data = p_data
        and q.obra_id is not null
        and (
          public.fn_pode_ver_obra(q.obra_id)
          or public.fn_e_encarregado_da_obra(q.obra_id)
        )
    );
$$;

revoke all on function public.fn_pode_ver_ausencia(uuid, date) from public, anon;
grant execute on function public.fn_pode_ver_ausencia(uuid, date) to authenticated;

grant select on table public.ausencias to authenticated;
revoke insert, update, delete, truncate on table public.ausencias from anon;

drop policy if exists ausencias_responsaveis_select on public.ausencias;
create policy ausencias_responsaveis_select
on public.ausencias for select to authenticated
using (public.fn_pode_ver_ausencia(colaborador_id, data));

-- Os comprovativos podem conter informação pessoal: ficam restritos ao RH.
alter table public.ausencias_anexos enable row level security;
grant select, insert, update, delete on table public.ausencias_anexos to authenticated;
revoke all on table public.ausencias_anexos from anon;

drop policy if exists ausencias_anexos_select on public.ausencias_anexos;
drop policy if exists ausencias_anexos_insert on public.ausencias_anexos;
drop policy if exists ausencias_anexos_rh on public.ausencias_anexos;
create policy ausencias_anexos_rh
on public.ausencias_anexos for all to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

-- Pasta privada: documentos/rh/ausencia/<ausencia_id>/<ficheiro>.
drop policy if exists documentos_rh_storage_select on storage.objects;
create policy documentos_rh_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] in ('colaborador', 'viatura', 'ausencia')
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

drop policy if exists documentos_rh_storage_insert on storage.objects;
create policy documentos_rh_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] in ('colaborador', 'viatura', 'ausencia')
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

drop policy if exists documentos_rh_storage_delete on storage.objects;
create policy documentos_rh_storage_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] in ('colaborador', 'viatura', 'ausencia')
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_e_administrativo()
);

-- A tabela foi criada depois da ativação geral da auditoria.
drop trigger if exists trg_auditoria_ausencias_anexos on public.ausencias_anexos;
create trigger trg_auditoria_ausencias_anexos
after insert or update or delete on public.ausencias_anexos
for each row execute function public.fn_registar_log_auditoria('id');

commit;

select
  (select count(*) from public.ausencias) as ausencias_preservadas,
  to_regprocedure('public.fn_pode_ver_ausencia(uuid,date)') is not null as funcao_visibilidade,
  (select count(*) from pg_trigger where tgname in (
    'trg_normalizar_estado_ausencia',
    'trg_bloquear_quadro_pessoal_ausencia',
    'trg_bloquear_mao_obra_ausencia',
    'trg_auditoria_ausencias_anexos'
  ) and not tgisinternal) as triggers_ativos,
  (select count(*) from pg_policies where schemaname = 'public'
    and tablename in ('ausencias', 'ausencias_anexos')
    and policyname in ('ausencias_responsaveis_select', 'ausencias_anexos_rh')) as politicas_novas;
