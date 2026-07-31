-- Políticas dos módulos Segurança, índices documentais e preços de materiais.
-- As tabelas funcionais já devem existir. Executar com uma conta owner.

begin;

-- O schema existente guarda valor_unitario/valor_total, mas ainda não tinha a
-- unidade pedida pelo formulário de materiais.
alter table public.faturas_itens
  add column if not exists unidade text;

alter table public.seguranca_incidentes enable row level security;
alter table public.seguranca_inspecoes enable row level security;
alter table public.epis enable row level security;
alter table public.desenhos enable row level security;
alter table public.rfis enable row level security;
alter table public.faturas_itens enable row level security;

revoke all on table public.seguranca_incidentes from anon;
revoke all on table public.seguranca_inspecoes from anon;
revoke all on table public.epis from anon;
revoke all on table public.desenhos from anon;
revoke all on table public.rfis from anon;
revoke all on table public.faturas_itens from anon;

grant select, insert, update on table public.seguranca_incidentes to authenticated;
grant select, insert, update on table public.seguranca_inspecoes to authenticated;
grant select, insert, update, delete on table public.epis to authenticated;
grant select on table public.desenhos to authenticated;
grant select on table public.rfis to authenticated;
grant select, insert on table public.faturas_itens to authenticated;

drop policy if exists pl_seguranca_incidentes_select on public.seguranca_incidentes;
drop policy if exists pl_seguranca_incidentes_write on public.seguranca_incidentes;
create policy pl_seguranca_incidentes_select
on public.seguranca_incidentes for select to authenticated
using (public.fn_pode_ver_obra(obra_id));
create policy pl_seguranca_incidentes_write
on public.seguranca_incidentes for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists pl_seguranca_inspecoes_select on public.seguranca_inspecoes;
drop policy if exists pl_seguranca_inspecoes_write on public.seguranca_inspecoes;
create policy pl_seguranca_inspecoes_select
on public.seguranca_inspecoes for select to authenticated
using (public.fn_pode_ver_obra(obra_id));
create policy pl_seguranca_inspecoes_write
on public.seguranca_inspecoes for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));

drop policy if exists pl_epis_rh on public.epis;
create policy pl_epis_rh
on public.epis for all to authenticated
using (public.fn_e_administrativo())
with check (public.fn_e_administrativo());

-- Os índices são alimentados pelo trigger fn_sincronizar_indice_documento.
drop policy if exists pl_desenhos_select on public.desenhos;
drop policy if exists pl_rfis_select on public.rfis;
create policy pl_desenhos_select
on public.desenhos for select to authenticated
using (public.fn_pode_ver_obra(obra_id));
create policy pl_rfis_select
on public.rfis for select to authenticated
using (public.fn_pode_ver_obra(obra_id));

drop policy if exists pl_faturas_itens_select on public.faturas_itens;
drop policy if exists pl_faturas_itens_insert on public.faturas_itens;
create policy pl_faturas_itens_select
on public.faturas_itens for select to authenticated
using (exists (
  select 1
  from public.faturas f
  where f.id = fatura_id
    and (
      public.fn_pode_ver_obra(f.obra_id)
      or public.fn_e_administrativo()
      or public.fn_e_financeiro()
    )
));
create policy pl_faturas_itens_insert
on public.faturas_itens for insert to authenticated
with check (exists (
  select 1
  from public.faturas f
  where f.id = fatura_id
    and f.tipo_origem = 'material'
    and public.fn_e_administrativo()
));

-- Diretores/preparadores precisam dos nomes dos colaboradores para os registos
-- de segurança, sem ganhar acesso às restantes tabelas de RH.
drop policy if exists pl_colaboradores_seguranca_select on public.colaboradores;
create policy pl_colaboradores_seguranca_select
on public.colaboradores for select to authenticated
using (
  data_saida is null
  and (
    public.fn_e_administrativo()
    or exists (
      select 1
      from public.obra_responsaveis r
      where r.utilizador_id = public.fn_utilizador_atual_id()
    )
  )
);

commit;
