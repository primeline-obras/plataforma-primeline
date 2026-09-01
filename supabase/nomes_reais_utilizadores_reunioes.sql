-- PRIMELINE | Nomes reais dos utilizadores nas Salas de Reunião
-- Correção idempotente e limitada aos dois emails operacionais confirmados.
begin;

update public.utilizadores
set nome = case lower(btrim(email))
  when 'geral@primeline.pt' then 'Belmira Maria Godinho Quental'
  when 'financeiro@primeline.pt' then 'Natércia da Conceição Santos I. Rosa Oliveira'
  else nome
end
where lower(btrim(email)) in ('geral@primeline.pt', 'financeiro@primeline.pt')
  and nome is distinct from case lower(btrim(email))
    when 'geral@primeline.pt' then 'Belmira Maria Godinho Quental'
    when 'financeiro@primeline.pt' then 'Natércia da Conceição Santos I. Rosa Oliveira'
    else nome
  end;

commit;

select email, nome
from public.utilizadores
where lower(btrim(email)) in ('geral@primeline.pt', 'financeiro@primeline.pt')
order by email;
