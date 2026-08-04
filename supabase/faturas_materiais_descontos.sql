-- PRIMELINE | Descontos por artigo em faturas de material
-- Executar integralmente no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.faturas_itens
  add column if not exists desconto_percentual numeric,
  add column if not exists valor_desconto numeric;

comment on column public.faturas_itens.desconto_percentual is
  'Percentagem de desconto aplicada à linha; nullable quando não indicada.';
comment on column public.faturas_itens.valor_desconto is
  'Valor total do desconto aplicado à linha; nullable quando não indicado.';
comment on column public.faturas_itens.valor_unitario is
  'Preço unitário bruto, antes de desconto.';
comment on column public.faturas_itens.valor_total is
  'Total líquido da linha, depois do desconto e antes do total final da fatura.';

commit;
