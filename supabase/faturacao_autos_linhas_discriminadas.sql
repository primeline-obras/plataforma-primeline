-- PRIMELINE — discriminação das linhas do rascunho de faturação por Auto
-- Migração aditiva e retrocompatível. Executar no SQL Editor do Supabase.

begin;

alter table public.faturacao_autos_medicao
  add column if not exists tipo_auto text,
  add column if not exists referencia_auto text,
  add column if not exists valor_linha numeric(14,2);

update public.faturacao_autos_medicao ligacao
set
  tipo_auto = coalesce(ligacao.tipo_auto, auto.tipo, 'contratual'),
  referencia_auto = coalesce(
    ligacao.referencia_auto,
    'AUTO ' || case when auto.tipo = 'adicional' then 'TEE' else 'CONTRATUAL' end || ' ' || coalesce(auto.numero_auto, 'SEM NÚMERO')
  ),
  valor_linha = coalesce(ligacao.valor_linha, auto.valor_a_faturar, 0)
from public.autos_medicao auto
where auto.id = ligacao.auto_medicao_id
  and (ligacao.tipo_auto is null or ligacao.referencia_auto is null or ligacao.valor_linha is null);

alter table public.faturacao_autos_medicao
  drop constraint if exists faturacao_autos_medicao_valor_linha_check;

alter table public.faturacao_autos_medicao
  add constraint faturacao_autos_medicao_valor_linha_check
  check (valor_linha is null or valor_linha >= 0);

grant select, insert (
  faturacao_id, auto_medicao_id, tipo_auto, referencia_auto, valor_linha
) on public.faturacao_autos_medicao to authenticated;

comment on column public.faturacao_autos_medicao.tipo_auto is
  'Snapshot do tipo do Auto incluído no rascunho: contratual ou adicional.';
comment on column public.faturacao_autos_medicao.referencia_auto is
  'Designação comunicada ao Financeiro, por exemplo AUTO TEE 05_REV00.';
comment on column public.faturacao_autos_medicao.valor_linha is
  'Valor individual do Auto no momento da criação do rascunho.';

commit;
