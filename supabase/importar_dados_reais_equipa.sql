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
-- Segurança: o script não cria colaboradores. Os nomes completos das folhas são
-- ligados aos UUIDs confirmados pela auditoria da base de 03/08/2026. A transação
-- inteira falha antes de alterar dados se algum UUID deixar de existir.

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

-- Correspondências confirmadas pelos registos já ligados em medicina_trabalho e
-- viaturas. João Mendes Afonso é o único colaborador ainda sem linha de medicina.
create temporary table _pl_colaborador_mapa (
  nome_fonte text primary key,
  colaborador_id uuid not null unique
) on commit drop;

insert into _pl_colaborador_mapa values
  ('Adilson de Jesus Pires Semedo', '0cfb12da-556a-4476-8fc7-46ced62ef9a8'),
  ('Alessandro Passos Silva', 'bef14c45-e884-4203-a3a4-a0db204a9c4f'),
  ('Ana Carolina Alves Saraiva', '24fbf97b-bbe3-42b7-b15b-a7500b68e1fe'),
  ('António João Rosa de Sousa Oliveira', '261b017a-49c1-4f30-811f-046690ca3a4c'),
  ('Belmira Maria Godinho Quental', 'beeb3b0e-ff3c-4f20-98d5-619572d1dd80'),
  ('Bonifácio Té', '743fed71-cd3b-447d-ad69-5f5010a2380f'),
  ('Clayton de Souza Oliveira', 'cc5a58cc-d2ec-47bd-b64b-0952916b2526'),
  ('Fernando José dos Santos Silva', '4839f1e5-96d9-4706-8d7c-91c784963a77'),
  ('Genito Nanque', '2195300f-685e-4e60-97e7-a30631d63b71'),
  ('Gilson Alves de Lima', 'c6bd3641-367d-463c-a01a-ae60ed93c253'),
  ('Helder Lima Gonçalves', 'daed6a73-4566-4e16-8ee0-2e94cf36e2bf'),
  ('Henrique Bogéa Gomes', '84e08ca6-35d0-4cdb-914d-6685dd234a04'),
  ('Iluska Sathler Calili', '60c8a7bf-38c4-4cef-ac86-192f1e8661f7'),
  ('Inês dos Santos Rosa de Oliveira', '5e04954d-cd4a-4e12-afc0-c1e38896175f'),
  ('João Mendes Afonso', '81a195a3-d75f-4504-87a7-4060078b9f9e'),
  ('João Mendes Borges', '0d6af694-8edb-41e0-b405-ad9f27feddc0'),
  ('Jordane Vieira Silvestre', 'e5476812-ed97-48f7-bb78-2deca9c1f9d5'),
  ('Jose Ignacio Diaz Travi', '5cde6a7c-323d-4411-99fb-10bb90692bfe'),
  ('Júlio Natalício Silva Varela Andrade', '1b57c47e-5e3c-4346-97f7-498a68bf74cf'),
  ('Kamila Batista Gutterres', 'aab9beef-64bd-402f-b82e-e5333e99ebe2'),
  ('Luís Miguel da Costa Gonçalves', '898ac1af-5445-489d-af30-8cf0a0ed8cb7'),
  ('Manuel António Gama Costa', 'ed5674f3-b89f-4b86-b3c6-ff16f471b497'),
  ('Maria da Luz dos Santos Narciso', '11df5f21-883b-4316-9835-986aa2e6816c'),
  ('Mateus António Hebreus', 'f12ff7f5-61b8-44ee-a419-d29acd319cc3'),
  ('Mauro Amoriz Dias', 'a441f83a-8de3-4618-94bf-6126326eacf6'),
  ('Natércia da Conceição Santos I. Rosa Oliveira', 'a18c5ddf-a8f2-4f18-8249-bc477cc50caf'),
  ('Paulo Manuel de Almeida Natividade', '2654abc0-42f4-43f0-abcb-9d1e91d3709f'),
  ('Pedro Albuquerque', '449c0089-f152-4ad8-a5f0-99f636072ff5'),
  ('Rafael Monteiro Barra Pires', '965e746b-7e6e-400b-9a8e-7fb324a3cefc'),
  ('Regivaldo Rios de Oliveira', '0d271a1c-91f8-47ae-9566-84f1fbc213f3'),
  ('Ricardo Augusto Brito Martins', '344aaf41-8c6e-4b0e-ad80-09eeff3c8119'),
  ('Rogério Angelim Frazão', 'd83fe502-135c-4ca2-a6b2-910adfc1c706'),
  ('Vitor Manuel Almeida Lopes', '5733cf4b-eb73-438f-9f4e-ea237ad496cc'),
  ('Wanderson Marinho de Oliveira', 'ae4df908-5847-4fcd-bf14-f0fbb441cb74'),
  ('William Lemes Coimbra', 'b147a0a5-d83d-4cf7-b868-a912a3227700');

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
  left join _pl_colaborador_mapa x on x.nome_fonte = s.nome
  left join public.colaboradores c on c.id = x.colaborador_id
  where c.id is null or c.data_saida is not null;

  if v_invalidos is not null then
    raise exception 'Importação cancelada. Colaboradores de medicina sem correspondência única: %', v_invalidos;
  end if;

  select string_agg(v.colaborador_nome, ', ' order by v.colaborador_nome)
  into v_invalidos
  from _pl_viaturas_reais v
  left join _pl_colaborador_mapa x on x.nome_fonte = v.colaborador_nome
  left join public.colaboradores c on c.id = x.colaborador_id
  where v.colaborador_nome is not null
    and (c.id is null or c.data_saida is not null);

  if v_invalidos is not null then
    raise exception 'Importação cancelada. Atribuições de viaturas sem correspondência única: %', v_invalidos;
  end if;
end $$;

update public.colaboradores c
set data_nascimento = s.data_nascimento
from _pl_medicina_real s
join _pl_colaborador_mapa x on x.nome_fonte = s.nome
where c.id = x.colaborador_id
  and c.data_nascimento is distinct from s.data_nascimento;

update public.medicina_trabalho m
set data_ultima_consulta = s.data_ultima_consulta,
    resultado = s.resultado,
    data_proxima_consulta = s.data_proxima_consulta
from _pl_medicina_real s
join _pl_colaborador_mapa x on x.nome_fonte = s.nome
where m.colaborador_id = x.colaborador_id;

insert into public.medicina_trabalho (
  colaborador_id, data_ultima_consulta, resultado, data_proxima_consulta
)
select x.colaborador_id, s.data_ultima_consulta, s.resultado, s.data_proxima_consulta
from _pl_medicina_real s
join _pl_colaborador_mapa x on x.nome_fonte = s.nome
where not exists (
  select 1 from public.medicina_trabalho m where m.colaborador_id = x.colaborador_id
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
  x.colaborador_id,
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
left join _pl_colaborador_mapa x on x.nome_fonte = v.colaborador_nome
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
   join _pl_colaborador_mapa x on x.colaborador_id = m.colaborador_id
   join _pl_medicina_real s on s.nome = x.nome_fonte) as medicina_gravada,
  (select count(*) from _pl_viaturas_reais) as fonte_viaturas,
  (select count(*) from public.viaturas v join _pl_viaturas_reais s on s.matricula = v.matricula) as viaturas_gravadas,
  (select count(*)
   from public.colaboradores c
   join _pl_colaborador_mapa x on x.colaborador_id = c.id
   join _pl_medicina_real s on s.nome = x.nome_fonte
   where c.data_nascimento = s.data_nascimento) as aniversarios_gravados;

commit;
