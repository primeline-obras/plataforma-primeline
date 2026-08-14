-- PRIMELINE | Pedidos de orçamento — estados finais e prioridade
-- Idempotente. Enquanto existirem registos legados com estado='perdido',
-- estes ficam disponíveis para revisão manual e não são classificados por suposição.

begin;

alter table public.pedidos_orcamento
  add column if not exists prioritario boolean not null default false;

alter table public.pedidos_orcamento
  drop constraint if exists pedidos_orcamento_estado_check;

do $migration$
begin
  if exists (select 1 from public.pedidos_orcamento where estado = 'perdido') then
    alter table public.pedidos_orcamento
      add constraint pedidos_orcamento_estado_check
      check (estado = any (array[
        'em_curso'::text, 'enviado'::text, 'aguarda_resposta'::text,
        'adjudicado'::text, 'recusado'::text, 'cancelado'::text, 'perdido'::text
      ]));
  else
    alter table public.pedidos_orcamento
      add constraint pedidos_orcamento_estado_check
      check (estado = any (array[
        'em_curso'::text, 'enviado'::text, 'aguarda_resposta'::text,
        'adjudicado'::text, 'recusado'::text, 'cancelado'::text
      ]));
  end if;
end
$migration$;

commit;

select id, cliente_nome, cliente_contacto, descricao_trabalho,
       data_limite_entrega, situacao_atual, criado_em
from public.pedidos_orcamento
where estado = 'perdido'
order by criado_em;
