-- PRIMELINE | Distingue a última revisão da próxima revisão programada.
-- Executar no SQL Editor do Supabase com uma conta owner.

begin;

alter table public.viaturas
  add column if not exists data_proxima_revisao date;

comment on column public.viaturas.data_revisao is
  'Data da última revisão realizada; não representa uma validade.';

comment on column public.viaturas.data_proxima_revisao is
  'Data prevista para a próxima revisão, usada para avisos futuros.';

grant select, insert, update, delete on table public.viaturas to authenticated;

commit;

select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'viaturas'
  and column_name in ('data_revisao', 'data_proxima_revisao')
order by column_name;
