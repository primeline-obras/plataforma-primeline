-- Executar no SQL Editor. Só cria fornecedores; não importa lançamentos.
-- Campos desconhecidos permanecem vazios. Sem classificação ou avaliação inventada.
begin;
select pg_advisory_xact_lock(hashtextextended('mgo-fornecedores-20260924',0));
with fonte(nome,nota) as (values
 ('TransMendes Lda',''),
 ('Automatismos Luis e Romão Lda',''),
 ('EASYtainer, Lda',''),
 ('Dynamic Appointment (Luis Centeno)',''),
 ('Eugenio João Neves','Possível correspondência com Eugénio das Neves, Lda. Rever NIF antes de mesclar; nenhuma fusão realizada.')
), criados as (
 insert into public.fornecedores(empresa_id,nome,tipo_entidade,estado_confianca,notas)
 select '73fb13c8-d29f-4192-a506-4ca243343add'::uuid,s.nome,null,'nao_avaliado',
   'Criado a pedido da Gestão a partir de Mapa_Gestao_Obras_118_120_122_128.xlsx. Cadastro por rever. '||s.nota
 from fonte s
 where not exists(select 1 from public.fornecedores f
   where f.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'::uuid
     and lower(btrim(f.nome))=lower(btrim(s.nome)))
 and not exists(select 1 from public.fornecedores_aliases a
   where a.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'::uuid
     and lower(btrim(a.nome))=lower(btrim(s.nome)))
 on conflict (empresa_id,nome) do nothing
 returning id,nome
)
select count(*) as fornecedores_criados,
 coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',nome)),'[]'::jsonb) as detalhes
from criados;
commit;
