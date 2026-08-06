-- Bloco 4 - Horas extraordinarias. Preserva a tabela e os registos existentes.
alter table public.horas_extraordinarias
  add column if not exists motivo text,
  add column if not exists autorizado_por uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.horas_extraordinarias'::regclass and conname = 'horas_extraordinarias_autorizado_por_fkey') then
    alter table public.horas_extraordinarias add constraint horas_extraordinarias_autorizado_por_fkey foreign key (autorizado_por) references public.utilizadores(id);
  end if;
end $$;

create or replace function public.fn_pode_gerir_horas_extra(p_obra_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.fn_e_administrativo() or exists (
    select 1 from public.obra_responsaveis r
    join public.utilizadores u on u.id = r.utilizador_id
    where r.obra_id = p_obra_id
      and r.utilizador_id = public.fn_utilizador_atual_id()
      and r.papel in ('diretor_obra', 'adjunto', 'preparador')
      and coalesce(u.ativo, true)
  );
$$;

create or replace function public.fn_validar_autorizacao_horas_extra()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.obra_id is null then raise exception 'A obra e obrigatoria para registar horas extraordinarias.'; end if;
  if new.horas <= 0 then raise exception 'O numero de horas extraordinarias deve ser superior a zero.'; end if;
  if new.autorizado_por is not null and not exists (
    select 1 from public.obra_responsaveis r
    join public.utilizadores u on u.id = r.utilizador_id
    where r.obra_id = new.obra_id and r.utilizador_id = new.autorizado_por
      and r.papel in ('diretor_obra', 'adjunto', 'preparador') and coalesce(u.ativo, true)
  ) then raise exception 'A pessoa indicada nao e diretor, adjunto ou preparador desta obra.'; end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_autorizacao_horas_extra on public.horas_extraordinarias;
create trigger trg_validar_autorizacao_horas_extra before insert or update of obra_id, horas, autorizado_por
on public.horas_extraordinarias for each row execute function public.fn_validar_autorizacao_horas_extra();

drop policy if exists horas_extraordinarias_insert on public.horas_extraordinarias;
drop policy if exists horas_extraordinarias_select_tecnica on public.horas_extraordinarias;
drop policy if exists horas_extraordinarias_insert_tecnica on public.horas_extraordinarias;
create policy horas_extraordinarias_select_tecnica on public.horas_extraordinarias for select to authenticated using (public.fn_pode_gerir_horas_extra(obra_id));
create policy horas_extraordinarias_insert_tecnica on public.horas_extraordinarias for insert to authenticated with check (public.fn_pode_gerir_horas_extra(obra_id));

grant select, insert on public.horas_extraordinarias to authenticated;
revoke all on public.horas_extraordinarias from anon;
grant execute on function public.fn_pode_gerir_horas_extra(uuid) to authenticated;
revoke all on function public.fn_pode_gerir_horas_extra(uuid) from anon;

select to_regprocedure('public.fn_pode_gerir_horas_extra(uuid)') is not null as funcao_permissao,
 count(*) filter (where policyname = 'horas_extraordinarias_select_tecnica') as politica_select,
 count(*) filter (where policyname = 'horas_extraordinarias_insert_tecnica') as politica_insert
from pg_policies where schemaname = 'public' and tablename = 'horas_extraordinarias';
