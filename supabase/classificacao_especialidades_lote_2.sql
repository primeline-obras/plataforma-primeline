-- Lote 2: 18 classificações confirmadas diretamente pela Jordane.
-- Domintegra, Lda permanece fora deste lote até decisão sobre a categoria.

begin;

create temp table lote_2_classificacao (
  fornecedor_nome text not null,
  especialidade_nome text not null
) on commit drop;

insert into lote_2_classificacao (fornecedor_nome, especialidade_nome)
values
  ('Adulai Embalo', 'CONSTRUÇÃO CIVIL GERAL'),
  ('Algo Moderno Unip., Lda', 'COBERTURAS'),
  ('Alicerce Peculiar Unip., Lda', 'CONSTRUÇÃO CIVIL GERAL'),
  ('Almabarão', 'SERRALHARIAS'),
  ('Antonio Manuel Ferreira Gomes, Unipessoal, Lda', 'CARPINTARIAS'),
  ('Aristides Tete Unipessoal, Lda', 'CONSTRUÇÃO CIVIL GERAL'),
  ('Arménio Ramos, Unipessoal Lda', 'IMPERMEABILIZAÇÕES'),
  ('Aspilusa Portugal, Lda', 'AVAC / CLIMATIZAÇÃO'),
  ('Battistuta Caetano, Lda - Moss n Art', 'JARDINAGEM E PAISAGISMO'),
  ('Beringela-Sociedade Unipessoal, Lda', 'AVAC / CLIMATIZAÇÃO'),
  ('Carriço & Filhos 2, Lda', 'IMPERMEABILIZAÇÕES'),
  ('Celson Lourenço Espindola, Unip,', 'CONSTRUÇÃO CIVIL GERAL'),
  ('CITAC', 'INSTALAÇÕES ELÉTRICAS'),
  ('D & D, Lda', 'CANALIZAÇÃO E HIDRÁULICA'),
  ('Davide & Filhos, Lda', 'EQUIPAMENTOS DE COZINHA'),
  ('Desafio Ótimo, Lda', 'MUDANÇAS'),
  ('Diálogo Celestial, Lda (Altamiro)', 'PINTURAS'),
  ('Ecoreflexus, Lda', 'INSTALAÇÕES ELÉTRICAS');

do $$
begin
  if (select count(*) from lote_2_classificacao) <> 18 then
    raise exception 'Lote 2 inválido: eram esperadas 18 classificações.';
  end if;

  if exists (
    select 1 from lote_2_classificacao
    where lower(trim(fornecedor_nome)) = lower('Domintegra, Lda')
  ) then
    raise exception 'Lote 2 inválido: Domintegra deve permanecer pendente.';
  end if;
end $$;

insert into public.especialidades (nome)
select distinct l.especialidade_nome
from lote_2_classificacao l
where not exists (
  select 1
  from public.especialidades e
  where upper(trim(e.nome)) = upper(trim(l.especialidade_nome))
);

update public.especialidades
set aplicavel_subempreiteiro = true
where upper(trim(nome)) in (
  select upper(trim(especialidade_nome))
  from lote_2_classificacao
);

create temp table lote_2_resolvido on commit drop as
select
  l.fornecedor_nome,
  l.especialidade_nome,
  f.id as fornecedor_id,
  e.id as especialidade_id
from lote_2_classificacao l
left join public.fornecedores f
  on lower(regexp_replace(trim(f.nome), '\s+', ' ', 'g'))
   = lower(regexp_replace(trim(l.fornecedor_nome), '\s+', ' ', 'g'))
left join public.especialidades e
  on upper(trim(e.nome)) = upper(trim(l.especialidade_nome));

do $$
declare
  problemas text;
begin
  select string_agg(descricao, E'\n' order by descricao)
  into problemas
  from (
    select 'Fornecedor não encontrado: ' || fornecedor_nome as descricao
    from lote_2_resolvido
    where fornecedor_id is null

    union

    select 'Especialidade não encontrada: ' || especialidade_nome
    from lote_2_resolvido
    where especialidade_id is null

    union

    select 'Fornecedor ambíguo na base: ' || fornecedor_nome
    from lote_2_resolvido
    where fornecedor_id is not null
    group by fornecedor_nome, especialidade_nome
    having count(distinct fornecedor_id) > 1
  ) erros;

  if problemas is not null then
    raise exception E'Lote 2 não aplicado. Corrija primeiro:\n%', problemas;
  end if;

  if (select count(*) from lote_2_resolvido) <> 18 then
    raise exception 'Lote 2 inválido: eram esperadas 18 relações resolvidas.';
  end if;
end $$;

insert into public.fornecedores_especialidades
  (fornecedor_id, especialidade_id, origem)
select distinct fornecedor_id, especialidade_id, 'manual'
from lote_2_resolvido
on conflict (fornecedor_id, especialidade_id) do nothing;

select
  18 as fornecedores_no_lote,
  18 as relacoes_no_lote,
  count(*) as relacoes_presentes_na_base,
  (
    select count(*)
    from public.especialidades
    where upper(trim(nome)) = 'MUDANÇAS'
      and aplicavel_subempreiteiro = true
  ) as categoria_mudancas_ativa
from public.fornecedores_especialidades fe
join (
  select distinct fornecedor_id, especialidade_id
  from lote_2_resolvido
) lote using (fornecedor_id, especialidade_id);

commit;
