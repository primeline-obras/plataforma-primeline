-- PRIMELINE — fluxo Auto enviado > Fatura emitida > Pago
-- Alteração de schema autorizada em 27/07/2026.
-- Executar no SQL Editor do Supabase com privilégios de owner.

begin;

create table if not exists public.faturacao_autos_medicao (
  faturacao_id uuid not null
    references public.faturacao(id) on delete cascade,
  auto_medicao_id uuid not null
    references public.autos_medicao(id) on delete restrict,
  criado_em timestamptz not null default now(),
  primary key (faturacao_id, auto_medicao_id),
  unique (auto_medicao_id)
);

alter table public.faturacao_autos_medicao enable row level security;
alter table public.faturacao enable row level security;
alter table public.documentos enable row level security;

revoke all on table
  public.faturacao_autos_medicao,
  public.faturacao,
  public.documentos
from anon;

grant select, insert on table public.faturacao_autos_medicao to authenticated;
grant select on table public.faturacao, public.documentos to authenticated;

grant insert (
  obra_id, contrato_id, numero_fatura, descricao_auto,
  data_emissao_auto, data_emissao_fatura, valor, estado
) on public.faturacao to authenticated;

grant update (
  data_recebimento, valor_recebido
) on public.faturacao to authenticated;

grant insert (
  empresa_id, entidade_tipo, entidade_id, tipo_documento,
  nome_arquivo, url_arquivo, data_emissao
) on public.documentos to authenticated;

grant insert (
  obra_id, mes_referencia, numero_auto, tipo, medido_por,
  data_medicao, estado, registado_por, valor_bruto_medido,
  valor_retencao_garantia, valor_deduzido_adiantamento
) on public.autos_medicao to authenticated;

grant update (
  estado, data_envio_cliente, data_aprovacao_cliente
) on public.autos_medicao to authenticated;

drop policy if exists faturacao_autos_authenticated_select on public.faturacao_autos_medicao;
create policy faturacao_autos_authenticated_select
on public.faturacao_autos_medicao for select to authenticated using (true);

drop policy if exists faturacao_autos_authenticated_insert on public.faturacao_autos_medicao;
create policy faturacao_autos_authenticated_insert
on public.faturacao_autos_medicao for insert to authenticated with check (true);

drop policy if exists faturacao_authenticated_select on public.faturacao;
create policy faturacao_authenticated_select
on public.faturacao for select to authenticated using (true);

drop policy if exists faturacao_authenticated_insert on public.faturacao;
create policy faturacao_authenticated_insert
on public.faturacao for insert to authenticated with check (true);

drop policy if exists faturacao_authenticated_payment_update on public.faturacao;
create policy faturacao_authenticated_payment_update
on public.faturacao for update to authenticated using (true) with check (true);

drop policy if exists documentos_authenticated_select on public.documentos;
create policy documentos_authenticated_select
on public.documentos for select to authenticated
using (empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid);

drop policy if exists documentos_authenticated_insert on public.documentos;
create policy documentos_authenticated_insert
on public.documentos for insert to authenticated
with check (empresa_id = '73fb13c8-d29f-4192-a506-4ca243343add'::uuid);

drop policy if exists autos_medicao_authenticated_insert on public.autos_medicao;
create policy autos_medicao_authenticated_insert
on public.autos_medicao for insert to authenticated
with check (estado = 'rascunho');

drop policy if exists autos_medicao_authenticated_update on public.autos_medicao;
create policy autos_medicao_authenticated_update
on public.autos_medicao for update to authenticated
using (true)
with check (estado in ('rascunho', 'enviado_cliente', 'aprovado_cliente', 'recusado_cliente'));

commit;
