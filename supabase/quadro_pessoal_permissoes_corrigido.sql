-- Bloco 5 - preserva as alocacoes existentes e separa leitura de escrita.
create or replace function public.fn_pode_gerir_quadro(p_obra_id uuid)
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

drop policy if exists quadro_pessoal_select_authenticated on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_insert_authenticated on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_update_authenticated on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_delete_authenticated on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_alocacao_insert on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_alocacao_select on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_alocacao_update on public.quadro_pessoal_alocacao;
drop policy if exists quadro_pessoal_alocacao_delete on public.quadro_pessoal_alocacao;

create policy quadro_pessoal_alocacao_select on public.quadro_pessoal_alocacao
for select to authenticated using (true);
create policy quadro_pessoal_alocacao_insert on public.quadro_pessoal_alocacao
for insert to authenticated with check (public.fn_pode_gerir_quadro(obra_id) and criado_por = public.fn_utilizador_atual_id());
create policy quadro_pessoal_alocacao_update on public.quadro_pessoal_alocacao
for update to authenticated using (public.fn_pode_gerir_quadro(obra_id))
with check (public.fn_pode_gerir_quadro(obra_id) and criado_por = public.fn_utilizador_atual_id());
create policy quadro_pessoal_alocacao_delete on public.quadro_pessoal_alocacao
for delete to authenticated using (public.fn_pode_gerir_quadro(obra_id));

grant select, insert, update, delete on public.quadro_pessoal_alocacao to authenticated;
revoke all on public.quadro_pessoal_alocacao from anon;
grant execute on function public.fn_pode_gerir_quadro(uuid) to authenticated;
revoke all on function public.fn_pode_gerir_quadro(uuid) from anon;

select (select count(*) from public.quadro_pessoal_alocacao) as alocacoes_preservadas,
 to_regprocedure('public.fn_pode_gerir_quadro(uuid)') is not null as funcao_permissao,
 count(*) filter (where policyname = 'quadro_pessoal_alocacao_select') as politica_select,
 count(*) filter (where policyname = 'quadro_pessoal_alocacao_insert') as politica_insert,
 count(*) filter (where policyname = 'quadro_pessoal_alocacao_update') as politica_update,
 count(*) filter (where policyname = 'quadro_pessoal_alocacao_delete') as politica_delete
from pg_policies where schemaname = 'public' and tablename = 'quadro_pessoal_alocacao';
