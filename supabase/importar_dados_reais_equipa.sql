-- PRIMELINE | Importação idempotente de dados reais de Equipa.
-- Fontes recebidas em 03/08/2026:
--   - Mapa VIATURAS FROTA.xlsx (Folha1)
--   - MEDICINA NO TRABALHO.xlsx (Ordem alfabética / MESETRAB)
--   - MAPA DOS ANIVERSÁRIOS.xlsx
--
-- Decisões de normalização:
--   1. A folha MESETRAB é a fonte atual de medicina e datas de nascimento.
--   2. O ano 2025 indicado como nascimento de Adilson no mapa de aniversários
--      é substituído por 1987, confirmado pela folha de medicina.
--   3. Alessandro fica associado ao nome "Alessandro Passos Silva" da folha
--      de medicina; o mapa de aniversários contém "Passos Pires".
--   4. "Março 2026" (revisão do Peugeot AS-78-JS) é guardado como 2026-03-01,
--      convenção já usada para datas conhecidas apenas ao mês.
--   5. "04/09/2027" (inspeção do Smart) é interpretado em formato português:
--      4 de setembro de 2027.
--   6. OFICINA, ESCRITÓRIO, ARO e NRO não são colaboradores: a atribuição fica null.
--
-- Segurança: o script não cria colaboradores. Se algum nome não tiver exatamente
-- uma correspondência, a transação inteira falha antes de alterar dados.

begin;

create temporary table _pl_medicina_real (
  nome text primary key,
  data_nascimento date not null,
  data_ultima_consulta date,
  resultado text,
  data_proxima_consulta date
) on commit drop;

insert into _pl_medicina_real values
  ('Adilson de Jesus Pires Semedo', '1987-09-25', '2025-06-11', 'Ficha Aptidão válida', '2027-06-01'),
  ('Alessandro Passos Silva', '1975-10-15', '2025-11-24', 'Ficha Aptidão válida', '2026-11-01'),
  ('Ana Carolina Alves Saraiva', '1996-03-24', '2026-07-22', 'Ficha Aptidão válida', '2028-07-01'),
  ('António João Rosa de Sousa Oliveira', '1966-09-19', '2025-10-23', 'Ficha Aptidão válida', '2026-10-01'),
  ('Belmira Maria Godinho Quental', '1966-03-22', '2026-04-23', 'Ficha Aptidão válida', '2027-04-01'),
  ('Bonifácio Té', '1998-03-05', '2025-09-30', 'Ficha Aptidão válida', '2027-09-01'),
  ('Clayton de Souza Oliveira', '2002-12-10', '2025-05-21', 'Ficha Aptidão válida', '2027-05-01'),
  ('Fernando José dos Santos Silva', '1981-11-09', '2025-09-30', 'Ficha Aptidão válida', '2027-09-01'),
  ('Genito Nanque', '1998-05-16', '2025-02-05', 'Ficha Aptidão válida', '2027-02-01'),
  ('Gilson Alves de Lima', '1960-07-15', '2025-09-30', 'Ficha Aptidão válida', '2026-09-01'),
  ('Helder Lima Gonçalves', '1996-02-21', '2025-04-02', 'Ficha Aptidão válida', '2027-04-01'),
  ('Henrique Bogéa Gomes', '1996-02-28', '2024-10-17', 'Ficha Aptidão válida', '2026-10-01'),
  ('Iluska Sathler Calili', '1979-04-07', '2025-10-23', 'Ficha Aptidão válida', '2027-10-01'),
  ('Inês dos Santos Rosa de Oliveira', '2000-01-12', '2026-07-22', 'Ficha Aptidão válida', '2028-07-01'),
  ('João Mendes Afonso', '1991-12-27', '2026-01-13', 'Ficha Aptidão válida', '2028-02-01'),
  ('João Mendes Borges', '1973-04-02', '2026-03-05', 'Ficha Aptidão válida', '2027-03-01'),
  ('Jordane Vieira Silvestre', '1994-10-23', '2025-03-05', 'Ficha Aptidão válida', '2027-03-01'),
  ('Jose Ignacio Diaz Travi', '1997-02-18', '2026-07-22', 'Ficha Aptidão válida', '2028-07-01'),
  ('Júlio Natalício Silva Varela Andrade', '1990-12-25', '2024-11-11', 'Ficha Aptidão válida', '2026-11-01'),
  ('Kamila Batista Gutterres', '1994-03-10', '2026-07-22', 'Ficha Aptidão válida', '2028-07-01'),
  ('Luís Miguel da Costa Gonçalves', '1996-10-17', '2026-03-05', 'Ficha Aptidão válida', '2028-03-01'),
  ('Manuel António Gama Costa', '1966-07-05', '2026-04-23', 'Ficha Aptidão válida', '2027-04-01'),
  ('Maria da Luz dos Santos Narciso', '1973-09-29', '2026-07-22', 'Ficha Aptidão válida', '2027-07-01'),
  ('Mateus António Hebreus', '1992-03-16', '2026-04-23', 'Ficha Aptidão válida', '2027-04-01'),
  ('Mauro Amoriz Dias', '1996-09-27', '2026-03-05', 'Ficha Aptidão válida', '2028-03-01'),
  ('Natércia da Conceição Santos I. Rosa Oliveira', '1967-05-09', '2025-10-23', 'Ficha Aptidão válida', '2026-10-01'),
  ('Paulo Manuel de Almeida Natividade', '1970-08-27', '2025-10-23', 'Ficha Aptidão válida', '2026-09-01'),
  ('Rafael Monteiro Barra Pires', '1979-02-14', '2025-02-19', 'Ficha Aptidão válida', '2027-02-01'),
  ('Regivaldo Rios de Oliveira', '1978-10-29', '2026-03-05', 'Ficha Aptidão válida', '2028-03-01'),
  ('Ricardo Augusto Brito Martins', '1969-05-10', '2026-03-05', 'Ficha Aptidão válida', '2027-03-01'),
  ('Rogério Angelim Frazão', '1972-03-09', '2025-09-30', 'Ficha Aptidão válida', '2026-09-01'),
  ('Vitor Manuel Almeida Lopes', '1973-06-15', '2026-04-23', 'Ficha Aptidão válida', '2027-04-01'),
  ('Wanderson Marinho de Oliveira', '1990-02-04', '2026-03-05', 'Ficha Aptidão válida', '2027-03-01'),
  ('William Lemes Coimbra', '1987-04-19', '2026-07-02', 'Ficha Aptidão válida', '2027-07-01');

create temporary table _pl_viaturas_reais (
  marca_modelo text not null,
  matricula text primary key,
  numero_interno integer,
  colaborador_nome text,
  cartao_frota_venc date,
  iuc_liquidacao date,
  seguro_data date,
  seguro_seguradora text,
  data_revisao date,
  kms_revisao text,
  data_inspecao_proxima date,
  kms_inspecao text,
  chaves_estado text
) on commit drop;

insert into _pl_viaturas_reais values
  ('CITROEN BERLINGO', 'CF-14-MJ', null, 'Regivaldo Rios de Oliveira', null, null, '2027-04-18', 'TRANQUILIDADE', null, null, '2026-09-29', null, 'OK'),
  ('CITROEN C3', 'BQ-34-AQ', 16, 'Ana Carolina Alves Saraiva', null, null, '2027-06-25', 'TRANQUILIDADE', null, null, null, null, 'OK'),
  ('CITROEN JUMPER', 'AF-05-GR', 7, 'Júlio Natalício Silva Varela Andrade', '2027-07-01', null, '2026-09-19', 'FIDELIDADE', '2025-07-18', null, '2027-02-02', '128.364 KM', 'OK'),
  ('FIAT DOBLO', 'AF-08-JG', 4, 'Manuel António Gama Costa', '2027-07-01', null, '2026-09-07', 'TRANQUILIDADE', '2025-06-16', null, '2027-02-12', '116.717 KM', 'OK'),
  ('FIAT DOBLO MERCADORIAS', '42-SB-11', 6, null, '2025-05-01', '2025-10-31', '2027-05-29', 'TRANQUILIDADE', '2025-02-03', null, '2026-10-31', '143.401 KM', 'OK'),
  ('FIAT FIORINO', '79-VO-20', 5, 'Vitor Manuel Almeida Lopes', '2027-07-01', '2025-10-31', '2026-10-10', 'TRANQUILIDADE', '2025-06-16', null, '2026-10-30', '68.687 KM', 'OK'),
  ('FIAT TIPO LOUNGE', '86-XS-01', 3, 'Jose Ignacio Diaz Travi', '2027-11-01', null, '2026-11-18', 'FIDELIDADE', '2025-06-18', '113.752 km', '2027-06-19', '113.745 KM', 'OK'),
  ('FIAT TIPO STATION WAGON', 'AR-65-SI', 2, 'Pedro Albuquerque', '2026-09-01', null, '2026-09-24', 'MAFRE', '2026-03-25', '59.980 km', '2028-06-29', '63.452 KM', 'OK'),
  ('FORD TRANSIT', 'AA-11-BF', null, null, null, null, '2027-04-26', 'TRANQUILIDADE', null, null, null, null, null),
  ('HYUNDAI', '74-17-TV', 9, 'William Lemes Coimbra', '2026-09-01', '2026-07-01', '2027-02-21', 'FIDELIDADE', '2025-07-16', '318.479 km', '2027-07-23', '328.070 km', 'OK'),
  ('LAND ROVER', 'BV-38-VB', null, 'Inês dos Santos Rosa de Oliveira', null, null, '2026-07-01', 'TRANQUILIDADE', null, null, '2029-08-01', null, null),
  ('MAZDA BT 50', '17-FP-06', 10, 'Paulo Manuel de Almeida Natividade', '2027-07-01', '2025-04-29', '2026-07-28', 'TRANQUILIDADE', '2025-04-21', '332.963 km', '2027-04-22', '343 206 km', 'OK'),
  ('OPEL CORSA', '80-AJ-98', 11, null, '2027-02-01', '2025-08-28', '2027-04-18', 'FIDELIDADE', null, null, '2026-08-29', '30.943 km', 'OK'),
  ('PEUGEOT ELETRICO', 'AS-78-JS', 8, 'Luís Miguel da Costa Gonçalves', null, null, '2026-09-10', 'MAFRE', '2026-03-01', null, '2028-07-28', '53.195 km', 'OK'),
  ('PEUGEOT 308', 'AS-11-FN', 12, 'Henrique Bogéa Gomes', '2027-10-01', '2026-07-01', '2027-07-25', 'TRANQUILIDADE', '2026-07-03', '63.924 km', '2028-07-21', '63.924 km', 'OK'),
  ('SMART', 'BZ-95-RU', 13, 'Kamila Batista Gutterres', '2027-11-01', null, '2026-11-02', 'CARAVELA', null, '140.000km', '2027-09-04', '149.058 km', 'OK'),
  ('VOLKSWAGEN ID. 3 PRO', 'CE-67-PT', null, 'Rafael Monteiro Barra Pires', null, null, '2027-04-01', 'TRANQUILIDADE', null, null, '2027-09-23', '91.083 km', 'OK(2)'),
  ('MERCEDES E300', 'AJ-57-MQ', null, null, null, null, '2027-05-11', 'TRANQUILIDADE', null, null, '2026-12-07', '97.826 km', null),
  ('MINI - ARO', '73-UC-07', null, null, null, null, '2027-02-16', 'TRANQUILIDADE', null, null, '2027-01-15', '76.314 km', null),
  ('TOYOTA', '77-HS-93', null, null, null, '2025-07-16', '2026-11-28', 'ZURICH', null, null, '2026-06-01', '223.546 KM', null),
  ('PORSCHE', 'AA-03-AP', null, null, null, '2026-03-30', '2027-07-31', 'TRANQUILIDADE', null, null, '2028-03-03', '119.856 Km', null);

do $$
declare
  v_invalidos text;
begin
  select string_agg(s.nome, ', ' order by s.nome)
  into v_invalidos
  from _pl_medicina_real s
  where (select count(*) from public.colaboradores c where lower(trim(c.nome)) = lower(trim(s.nome))) <> 1;

  if v_invalidos is not null then
    raise exception 'Importação cancelada. Colaboradores de medicina sem correspondência única: %', v_invalidos;
  end if;

  select string_agg(v.colaborador_nome, ', ' order by v.colaborador_nome)
  into v_invalidos
  from _pl_viaturas_reais v
  where v.colaborador_nome is not null
    and (select count(*) from public.colaboradores c where lower(trim(c.nome)) = lower(trim(v.colaborador_nome))) <> 1;

  if v_invalidos is not null then
    raise exception 'Importação cancelada. Atribuições de viaturas sem correspondência única: %', v_invalidos;
  end if;
end $$;

update public.colaboradores c
set data_nascimento = s.data_nascimento
from _pl_medicina_real s
where lower(trim(c.nome)) = lower(trim(s.nome))
  and c.data_nascimento is distinct from s.data_nascimento;

update public.medicina_trabalho m
set data_ultima_consulta = s.data_ultima_consulta,
    resultado = s.resultado,
    data_proxima_consulta = s.data_proxima_consulta
from _pl_medicina_real s
join public.colaboradores c on lower(trim(c.nome)) = lower(trim(s.nome))
where m.colaborador_id = c.id;

insert into public.medicina_trabalho (
  colaborador_id, data_ultima_consulta, resultado, data_proxima_consulta
)
select c.id, s.data_ultima_consulta, s.resultado, s.data_proxima_consulta
from _pl_medicina_real s
join public.colaboradores c on lower(trim(c.nome)) = lower(trim(s.nome))
where not exists (
  select 1 from public.medicina_trabalho m where m.colaborador_id = c.id
);

insert into public.viaturas (
  empresa_id, marca_modelo, matricula, numero_interno, colaborador_atribuido_id,
  cartao_frota_venc, iuc_liquidacao, seguro_data, seguro_seguradora,
  data_revisao, kms_revisao, data_inspecao_proxima, kms_inspecao, chaves_estado
)
select
  '73fb13c8-d29f-4192-a506-4ca243343add'::uuid,
  v.marca_modelo,
  v.matricula,
  v.numero_interno,
  c.id,
  v.cartao_frota_venc,
  v.iuc_liquidacao,
  v.seguro_data,
  v.seguro_seguradora,
  v.data_revisao,
  v.kms_revisao,
  v.data_inspecao_proxima,
  v.kms_inspecao,
  v.chaves_estado
from _pl_viaturas_reais v
left join public.colaboradores c on lower(trim(c.nome)) = lower(trim(v.colaborador_nome))
on conflict (matricula) do update set
  empresa_id = excluded.empresa_id,
  marca_modelo = excluded.marca_modelo,
  numero_interno = excluded.numero_interno,
  colaborador_atribuido_id = excluded.colaborador_atribuido_id,
  cartao_frota_venc = excluded.cartao_frota_venc,
  iuc_liquidacao = excluded.iuc_liquidacao,
  seguro_data = excluded.seguro_data,
  seguro_seguradora = excluded.seguro_seguradora,
  data_revisao = excluded.data_revisao,
  kms_revisao = excluded.kms_revisao,
  data_inspecao_proxima = excluded.data_inspecao_proxima,
  kms_inspecao = excluded.kms_inspecao,
  chaves_estado = excluded.chaves_estado;

select
  (select count(*) from _pl_medicina_real) as fonte_medicina,
  (select count(*)
   from public.medicina_trabalho m
   join public.colaboradores c on c.id = m.colaborador_id
   join _pl_medicina_real s on lower(trim(s.nome)) = lower(trim(c.nome))) as medicina_gravada,
  (select count(*) from _pl_viaturas_reais) as fonte_viaturas,
  (select count(*) from public.viaturas v join _pl_viaturas_reais s on s.matricula = v.matricula) as viaturas_gravadas,
  (select count(*)
   from public.colaboradores c
   join _pl_medicina_real s on lower(trim(s.nome)) = lower(trim(c.nome))
   where c.data_nascimento = s.data_nascimento) as aniversarios_gravados;

commit;
