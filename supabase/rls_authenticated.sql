-- PRIMELINE — políticas mínimas para o módulo de Faturas
-- Executar no SQL Editor do projeto Primeline-Obras com privilégios de owner.
-- Resultado esperado: comandos concluídos sem erro, 0 linhas de dados alteradas.
-- Não concede qualquer privilégio ao papel anon.

begin;

alter table public.obras enable row level security;
alter table public.fornecedores enable row level security;
alter table public.subempreitadas enable row level security;
alter table public.faturas enable row level security;

revoke all on table
  public.obras,
  public.fornecedores,
  public.subempreitadas,
  public.faturas
from anon;

grant select on table
  public.obras,
  public.fornecedores,
  public.subempreitadas,
  public.faturas
to authenticated;

grant insert (
  obra_id,
  tipo_origem,
  fornecedor_id,
  subempreitada_id,
  numero_doc,
  data_fatura,
  valor,
  arquivo_url
) on public.faturas to authenticated;

grant update (
  estado_aprovacao,
  aprovado_por,
  data_aprovacao
) on public.faturas to authenticated;

drop policy if exists obras_authenticated_select on public.obras;
create policy obras_authenticated_select
on public.obras for select
to authenticated
using (true);

drop policy if exists fornecedores_authenticated_select on public.fornecedores;
create policy fornecedores_authenticated_select
on public.fornecedores for select
to authenticated
using (true);

drop policy if exists subempreitadas_authenticated_select on public.subempreitadas;
create policy subempreitadas_authenticated_select
on public.subempreitadas for select
to authenticated
using (true);

drop policy if exists faturas_authenticated_select on public.faturas;
create policy faturas_authenticated_select
on public.faturas for select
to authenticated
using (true);

drop policy if exists faturas_authenticated_insert on public.faturas;
create policy faturas_authenticated_insert
on public.faturas for insert
to authenticated
with check (
  estado_aprovacao = 'pendente'
  and (
    (tipo_origem = 'subempreitada' and subempreitada_id is not null)
    or (tipo_origem in ('material', 'estaleiro') and subempreitada_id is null)
  )
);

drop policy if exists faturas_authenticated_update_pending on public.faturas;
create policy faturas_authenticated_update_pending
on public.faturas for update
to authenticated
using (estado_aprovacao = 'pendente')
with check (estado_aprovacao in ('aprovado', 'recusado'));

commit;
