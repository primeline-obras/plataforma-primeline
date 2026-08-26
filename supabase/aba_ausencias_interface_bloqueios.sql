-- PRIMELINE | Aba de Ausências, permissões e bloqueios cruzados
-- Migração incremental: não elimina dados existentes.

begin;

create or replace function public.fn_pode_gerir_ausencias()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo()
    or exists (
      select 1
      from public.utilizadores u
      where u.id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'adjunto', 'preparador')
        and coalesce(u.ativo, true)
    );
$$;

revoke all on function public.fn_pode_gerir_ausencias() from public, anon;
grant execute on function public.fn_pode_gerir_ausencias() to authenticated;

alter table public.ausencias enable row level security;
grant select, insert, update on table public.ausencias to authenticated;
revoke all on table public.ausencias from anon;

drop policy if exists ausencias_equipa_select on public.ausencias;
drop policy if exists ausencias_equipa_insert on public.ausencias;
drop policy if exists ausencias_equipa_update on public.ausencias;

create policy ausencias_equipa_select
on public.ausencias for select to authenticated
using (public.fn_pode_gerir_ausencias());

create policy ausencias_equipa_insert
on public.ausencias for insert to authenticated
with check (public.fn_pode_gerir_ausencias());

create policy ausencias_equipa_update
on public.ausencias for update to authenticated
using (public.fn_pode_gerir_ausencias())
with check (public.fn_pode_gerir_ausencias());

alter table public.ausencias_anexos enable row level security;
grant select, insert, update on table public.ausencias_anexos to authenticated;
revoke all on table public.ausencias_anexos from anon;

drop policy if exists ausencias_anexos_equipa_select on public.ausencias_anexos;
drop policy if exists ausencias_anexos_equipa_insert on public.ausencias_anexos;
drop policy if exists ausencias_anexos_equipa_update on public.ausencias_anexos;

create policy ausencias_anexos_equipa_select
on public.ausencias_anexos for select to authenticated
using (public.fn_pode_gerir_ausencias());

create policy ausencias_anexos_equipa_insert
on public.ausencias_anexos for insert to authenticated
with check (public.fn_pode_gerir_ausencias());

create policy ausencias_anexos_equipa_update
on public.ausencias_anexos for update to authenticated
using (public.fn_pode_gerir_ausencias())
with check (public.fn_pode_gerir_ausencias());

-- Comprovativos privados: documentos/rh/ausencia/<ausencia_id>/<ficheiro>.
drop policy if exists documentos_ausencias_equipa_select on storage.objects;
drop policy if exists documentos_ausencias_equipa_insert on storage.objects;

create policy documentos_ausencias_equipa_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] = 'ausencia'
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_pode_gerir_ausencias()
);

create policy documentos_ausencias_equipa_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] = 'rh'
  and (storage.foldername(name))[2] = 'ausencia'
  and (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  and public.fn_pode_gerir_ausencias()
);

-- O mesmo bloqueio é aplicado aos três locais onde se registam trabalho/horas.
create or replace function public.fn_bloquear_registo_em_ausencia()
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

revoke all on function public.fn_bloquear_registo_em_ausencia() from public, anon, authenticated;

drop trigger if exists trg_bloquear_quadro_pessoal_ausencia on public.quadro_pessoal_alocacao;
create trigger trg_bloquear_quadro_pessoal_ausencia
before insert or update of colaborador_id, data
on public.quadro_pessoal_alocacao
for each row execute function public.fn_bloquear_registo_em_ausencia();

drop trigger if exists trg_bloquear_mao_obra_ausencia on public.lancamentos_mao_obra;
create trigger trg_bloquear_mao_obra_ausencia
before insert or update of colaborador_id, data
on public.lancamentos_mao_obra
for each row execute function public.fn_bloquear_registo_em_ausencia();

drop trigger if exists trg_bloquear_horas_extra_ausencia on public.horas_extraordinarias;
create trigger trg_bloquear_horas_extra_ausencia
before insert or update of colaborador_id, data
on public.horas_extraordinarias
for each row execute function public.fn_bloquear_registo_em_ausencia();

commit;

select
  to_regprocedure('public.fn_pode_gerir_ausencias()') is not null as permissao_ativa,
  (select count(*) from pg_trigger where tgname in (
    'trg_bloquear_quadro_pessoal_ausencia',
    'trg_bloquear_mao_obra_ausencia',
    'trg_bloquear_horas_extra_ausencia'
  ) and not tgisinternal) as bloqueios_ativos,
  (select count(*) from pg_policies where schemaname = 'public'
    and policyname like 'ausencias%equipa%') as politicas_ativas;
