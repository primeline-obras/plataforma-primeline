-- PRIMELINE — atualização idempotente do planeamento da Obra 120
-- Fonte: Planilha sem título (7).xlsx / 5b_Planeamento_Efectivo
-- Atualiza ou cria somente as 66 tarefas presentes na fonte.
-- Não elimina tarefas, dependências ou dados técnicos que não constem no ficheiro.

begin;

create temporary table tmp_obra_120_planeamento_atual (
  fase_codigo text not null,
  codigo text not null,
  descricao text not null,
  responsavel text,
  duracao_dias numeric,
  data_inicio_prevista date,
  data_fim_prevista date,
  data_fim_real date,
  peso_percentual numeric,
  percentual_executado numeric,
  percentual_ponderado numeric,
  estado text,
  causa_atraso text,
  impacto text
) on commit drop;

insert into tmp_obra_120_planeamento_atual (
  fase_codigo, codigo, descricao, responsavel, duracao_dias,
  data_inicio_prevista, data_fim_prevista, data_fim_real,
  peso_percentual, percentual_executado, percentual_ponderado,
  estado, causa_atraso, impacto
)
values
('F01', 'F01.1', 'Montagem do estaleiro', 'Primeline', 5, date '2026-02-11', date '2026-02-16', null, 15, 100, 15, 'concluido', 'Sem desvio', 'Sem impacto'),
('F01', 'F01.2', 'Exploração e manutenção do estaleiro', 'Primeline', 296, date '2026-03-16', date '2027-01-06', null, 70, 51, 35.7, 'em_execucao', 'Sem desvio', 'Sem impacto'),
('F01', 'F01.3', 'Andaime para pintura de fachada', 'Primeline', 35, date '2026-10-05', date '2026-11-09', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F01', 'F01.4', 'Desmontagem do estaleiro', 'Primeline', 3, date '2027-01-06', date '2027-01-09', null, 5, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.1', 'Desmontagem e remoção de louças sanitárias', 'Primeline', 6, date '2026-02-12', date '2026-02-18', null, 10, 100, 10, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.2', 'Desmontagem e remoção de cozinha', 'Primeline', 6, date '2026-02-19', date '2026-02-25', null, 8, 100, 8, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.3', 'Desmontagem e remoção de móveis de lavandaria', 'Primeline', 6, date '2026-02-19', date '2026-02-25', null, 5, 100, 5, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.4', 'Demolição de paredes de compartimentação interior', 'Primeline', 6, date '2026-04-02', date '2026-04-08', null, 15, 100, 15, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.5', 'Desmontagem de vãos de portas interiores em madeira', 'Primeline', 1, date '2026-03-11', date '2026-03-12', null, 10, 100, 10, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.6', 'Remoção de aquecedores existentes', 'Primeline', 6, date '2026-03-19', date '2026-03-25', null, 10, 100, 10, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.8', 'Desmontagem de armários embutidos', 'Primeline', 6, date '2026-03-26', date '2026-04-01', null, 5, 100, 5, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.9', 'Picagem de pavimento interior', 'Primeline', 13, date '2026-04-09', date '2026-04-22', null, 20, 100, 20, 'concluido', 'Sem desvio', 'Sem impacto'),
('F02', 'F02.10', 'Abertura de roços para infraestrutura', 'Primeline', 6, date '2026-04-23', date '2026-04-29', null, 17, 100, 17, 'concluido', 'Sem desvio', 'Sem impacto'),
('F03', 'F03.1', 'Remoção de pavimento em calçada e abertura de vala', 'RADU', 18, date '2026-05-04', date '2026-05-22', null, 30, 100, 30, 'concluido', 'Sem desvio', 'Sem impacto'),
('F03', 'F03.2', 'Transporte de terras sobrantes a vazadouro', 'RADU', 18, date '2026-05-04', date '2026-05-22', null, 20, 100, 20, 'concluido', 'Sem desvio', 'Sem impacto'),
('F03', 'F03.3', 'Fornecimento e aplicação de betão de limpeza', 'Primeline', 7, date '2026-05-25', date '2026-06-01', null, 15, 100, 15, 'concluido', 'Sem desvio', 'Sem impacto'),
('F03', 'F03.4', 'Fornecimento e aplicação de tela asfáltica', 'Primeline', 24, date '2026-06-01', date '2026-06-25', null, 15, 100, 15, 'concluido', 'Atraso interno', 'Faturação'),
('F03', 'F03.5', 'Manta geotextil, tubo geodreno, brita e massame (Flintkote)', 'Primeline', 15, date '2026-06-25', date '2026-07-10', null, 20, 100, 20, 'concluido', 'Atraso interno', 'Faturação'),
('F04', 'F04.1', 'Execução de paredes em alvenaria de tijolo', 'Primeline', 14, date '2026-05-18', date '2026-06-01', null, 15, 100, 15, 'concluido', 'Sem desvio', 'Sem impacto'),
('F04', 'F04.2', 'Forra em gesso cartonado (paredes exteriores)', 'Primeline', 11, date '2026-06-29', date '2026-07-10', null, 12, 100, 12, 'concluido', 'Sem desvio', 'Sem impacto'),
('F04', 'F04.3', 'Execução de reboco e barramento em paredes', 'Primeline', 18, date '2026-07-20', date '2026-08-07', null, 15, 100, 15, 'concluido', 'Indefinição DO', 'Prazo + Faturação'),
('F04', 'F04.4', 'Reparações pontuais de estuque e enchimentos', 'Primeline', 11, date '2026-08-03', date '2026-08-14', null, 10, 50, 5, 'em_execucao', 'Indefinição DO', 'Prazo + Faturação'),
('F04', 'F04.5', 'Fechamento de roços', 'Primeline', 11, date '2026-06-01', date '2026-06-12', null, 10, 100, 10, 'concluido', 'Sem desvio', 'Sem impacto'),
('F04', 'F04.6', 'Impermeabilização em betonilha do piso 0', 'Primeline', 13, date '2026-04-23', date '2026-05-06', null, 12, 100, 12, 'concluido', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F04', 'F04.7', 'Execução de betonilha (máx. 5cm) com manga plástica', 'Primeline', 92, date '2026-05-07', date '2026-08-07', null, 15, 95, 14.25, 'em_execucao', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F04', 'F04.8', 'Autonivelante como preparação para pavimento flutuante', 'Primeline', 4, date '2026-08-17', date '2026-08-21', null, 5, 0, 0, 'por_iniciar', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F04', 'F04.9', 'Demolição paredes/coberturas + estrutura Telha Sanduiche', 'Primeline', 148, date '2026-04-23', date '2026-09-18', null, 3, 20, 0.6, 'em_execucao', 'Atraso interno', 'Prazo + Faturação'),
('F04', 'F04.10', 'Placa OSB + XPS + Telha Sanduiche + Tecto falso hidrofugo', 'Primeline', 136, date '2026-05-05', date '2026-09-18', null, 3, 0, 0, 'por_iniciar', 'Atraso interno', 'Prazo + Faturação'),
('F05', 'F05.1', 'Execução de nova rede de águas quentes, frias e esgotos', 'SERGIO', 19, date '2026-04-30', date '2026-05-19', null, 15, 100, 15, 'concluido', null, null),
('F05', 'F05.2', 'Instalação de elementos encastráveis (hidráulica)', 'SERGIO', 7, date '2026-10-15', date '2026-10-22', null, 5, 100, 5, 'concluido', 'Sem desvio', 'Sem impacto'),
('F05', 'F05.4', 'Instalação de louças e metais (hidráulica)', 'SERGIO', 7, date '2026-10-15', date '2026-10-22', null, 5, 100, 5, 'concluido', 'Sem desvio', 'Sem impacto'),
('F05', 'F05.5', 'Troca de cablagem existente por nova cablagem', 'FLUXION', 7, date '2026-04-30', date '2026-05-07', null, 20, 100, 20, 'concluido', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F05', 'F05.6', 'Instalação de acabamento elétrico', 'FLUXION', 3, date '2026-10-26', date '2026-10-29', null, 25, 0, 0, 'por_iniciar', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F05', 'F05.8', 'Rede de Gás | Gas Network', 'A adjudicar', 2, date '2026-08-05', date '2026-08-07', null, 5, 100, 5, 'concluido', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F05', 'F05.9', 'VMC — Pré-instalação', 'SOLIUS', 7, date '2026-05-06', date '2026-05-13', null, 8, 100, 8, 'concluido', 'Indefinição DO', 'Faturação'),
('F05', 'F05.10', 'VMC — Instalação AC', 'FLUXION', 10, date '2026-10-26', date '2026-11-05', null, 7, 95, 6.65, 'em_execucao', 'Sem desvio', 'Sem impacto'),
('F05', 'F05.11', 'Testes de tubagem e carga', 'SERGIO / FLUXION', 6, date '2026-05-21', date '2026-05-27', null, 10, 100, 10, 'concluido', 'Indefinição DO', 'Prazo + Custo + Faturação'),
('F06', 'F06.1', 'Aplicação de pavimento flutuante', 'Primeline', 12, date '2026-08-24', date '2026-09-05', null, 32, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F06', 'F06.3', 'Aplicação de pavimento em pedra', 'A confirmar', 6, date '2026-09-21', date '2026-09-27', null, 13, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F06', 'F06.4', 'Fornecimento e pintura de paredes (primário incluído)', 'A adjudicar', 25, date '2026-09-28', date '2026-10-23', null, 27, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F06', 'F06.6', 'Assentamento de revestimento em pedra', 'A confirmar', 7, date '2026-10-08', date '2026-10-15', null, 13, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F06', 'F06.7', 'Rodapé SX156 HIGH HEELS — zona em piso madeira', 'Primeline', 14, date '2026-11-26', date '2026-12-10', null, 8, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F06', 'F06.8', 'Rodapé cerâmico — zona molhada', 'Primeline', 14, date '2026-10-26', date '2026-11-09', null, 7, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F07', 'F07.1', 'Tectos falsos em cozinha, lavandaria e WC''s', 'Primeline', 11, date '2026-08-10', date '2026-08-21', null, 20, 100, 20, 'concluido', 'Sem desvio', 'Sem impacto'),
('F07', 'F07.2', 'Sanca em gesso com iluminação LED', 'Primeline', 8, date '2026-08-24', date '2026-09-01', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F07', 'F07.3', 'Pintura de tectos', 'A adjudicar', 14, date '2026-10-26', date '2026-11-09', null, 30, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F07', 'F07.4', 'Vigas falsas na master suíte', 'Primeline', 7, date '2026-11-26', date '2026-12-03', null, 10, 10, 1, 'em_execucao', 'Sem desvio', 'Sem impacto'),
('F07', 'F07.5', 'Fachada — Reconstrução de soco e barramento', 'Primeline', 22, date '2026-06-18', date '2026-07-10', null, 15, 100, 15, 'concluido', 'Atraso interno', 'Prazo + Faturação'),
('F07', 'F07.6', 'Fachada — Pintura exterior (primário + 2 demãos)', 'A adjudicar', 35, date '2026-10-05', date '2026-11-09', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F08', 'F08.1', 'Vãos interiores', 'A adjudicar', 6, date '2026-11-26', date '2026-12-02', null, 20, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F08', 'F08.2', 'Roupeiros e moveis w.c.', 'A adjudicar', 126, date '2026-07-31', date '2026-12-04', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F08', 'F08.3', 'Porta de correr (cozinha)', 'A adjudicar', 4, date '2026-12-04', date '2026-12-08', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F08', 'F08.4', 'Lacagem das portas interiores existentes', 'A adjudicar', 21, date '2026-11-05', date '2026-11-26', null, 35, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F08', 'F08.5', 'Lacagem da porta de entrada', 'A adjudicar', 6, date '2026-11-26', date '2026-12-02', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F09', 'F09.1', 'Desenho técnico das caixilharias', 'A adjudicar', 21, date '2026-05-18', date '2026-06-08', null, 10, 100, 10, 'concluido', 'Sem desvio', 'Sem impacto'),
('F09', 'F09.2', 'Produção de caixilharia CORTIZO', 'A adjudicar', 115, date '2026-07-10', date '2026-11-02', null, 40, 0, 0, 'por_iniciar', 'Indefinição DO', 'Prazo'),
('F09', 'F09.3', 'Retirada das caixilharias existentes', 'Primeline', 3, date '2026-09-16', date '2026-09-19', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F09', 'F09.4', 'Recuperação de alvenaria ao redor', 'Primeline', 7, date '2026-09-21', date '2026-09-28', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F09', 'F09.5', 'Instalação de soleira', 'A adjudicar', 4, date '2026-09-24', date '2026-09-28', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F09', 'F09.6', 'Fornecimento e instalação de nova caixilharia CORTIZO', 'A adjudicar', 10, date '2026-09-28', date '2026-10-08', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.1', 'Louças e metais — instalação final (sanitários)', 'SERGIO', 7, date '2026-10-15', date '2026-10-22', null, 25, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.2', 'Louças e metais — cozinha', 'A adjudicar', 2, date '2026-10-06', date '2026-10-08', null, 20, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.3', 'Radiadores — instalação final', 'A adjudicar', 11, date '2026-11-05', date '2026-11-16', null, 15, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.4', 'Diversos | Others (última fase)', 'Primeline', 29, date '2026-12-10', date '2027-01-08', null, 20, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.5', 'Limpeza final de obra', 'Primeline', 4, date '2027-01-11', date '2027-01-15', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto'),
('F10', 'F10.6', 'Vistoria final e entrega ao Dono de Obra', 'Primeline', 0, date '2027-01-15', date '2027-01-15', null, 10, 0, 0, 'por_iniciar', 'Sem desvio', 'Sem impacto');

do $$
declare
  v_obra_id uuid;
  v_total_fases integer;
begin
  select id into v_obra_id
  from public.obras
  where numero::text = '120';

  if v_obra_id is null then
    raise exception 'Atualização cancelada: Obra 120 não encontrada.';
  end if;

  if (select count(*) from tmp_obra_120_planeamento_atual) <> 66 then
    raise exception 'Atualização cancelada: a fonte não contém exatamente 66 tarefas.';
  end if;

  if exists (
    select 1
    from tmp_obra_120_planeamento_atual
    group by lower(trim(codigo))
    having count(*) > 1
  ) then
    raise exception 'Atualização cancelada: existem códigos repetidos na fonte.';
  end if;

  if exists (
    select 1
    from tmp_obra_120_planeamento_atual
    where data_inicio_prevista is null
       or data_fim_prevista is null
       or data_fim_prevista < data_inicio_prevista
       or percentual_executado not between 0 and 100
       or peso_percentual < 0
       or abs(percentual_ponderado - (peso_percentual * percentual_executado / 100)) > 0.0001
  ) then
    raise exception 'Atualização cancelada: datas, pesos ou percentagens inválidos.';
  end if;

  select count(*) into v_total_fases
  from public.fases
  where obra_id = v_obra_id
    and codigo in ('F01','F02','F03','F04','F05','F06','F07','F08','F09','F10');

  if v_total_fases <> 10 then
    raise exception 'Atualização cancelada: esperadas 10 fases F01-F10; encontradas %.', v_total_fases;
  end if;

  if exists (
    select 1
    from public.planeamento_itens pi
    join public.fases f on f.id = pi.fase_id
    join tmp_obra_120_planeamento_atual origem
      on lower(trim(origem.codigo)) = lower(trim(pi.codigo))
    where f.obra_id = v_obra_id
    group by lower(trim(pi.codigo))
    having count(*) > 1
  ) then
    raise exception 'Atualização cancelada: existem códigos repetidos no planeamento atual da Obra 120.';
  end if;
end
$$;

update public.planeamento_itens pi
set
  fase_id = f.id,
  descricao = origem.descricao,
  responsavel = origem.responsavel,
  duracao_dias = origem.duracao_dias,
  data_inicio_prevista = origem.data_inicio_prevista,
  data_fim_prevista = origem.data_fim_prevista,
  data_fim_real = coalesce(origem.data_fim_real, pi.data_fim_real),
  peso_percentual = origem.peso_percentual,
  percentual_executado = origem.percentual_executado,
  percentual_ponderado = origem.percentual_ponderado,
  estado = origem.estado,
  causa_atraso = origem.causa_atraso,
  impacto = origem.impacto
from tmp_obra_120_planeamento_atual origem
join public.obras o on o.numero::text = '120'
join public.fases f
  on f.obra_id = o.id
 and f.codigo = origem.fase_codigo
where pi.fase_id in (select id from public.fases where obra_id = o.id)
  and lower(trim(pi.codigo)) = lower(trim(origem.codigo));

insert into public.planeamento_itens (
  fase_id, codigo, descricao, responsavel, duracao_dias,
  data_inicio_prevista, data_fim_prevista, data_fim_real,
  peso_percentual, percentual_executado, percentual_ponderado,
  estado, causa_atraso, impacto
)
select
  f.id, origem.codigo, origem.descricao, origem.responsavel, origem.duracao_dias,
  origem.data_inicio_prevista, origem.data_fim_prevista, origem.data_fim_real,
  origem.peso_percentual, origem.percentual_executado, origem.percentual_ponderado,
  origem.estado, origem.causa_atraso, origem.impacto
from tmp_obra_120_planeamento_atual origem
join public.obras o on o.numero::text = '120'
join public.fases f
  on f.obra_id = o.id
 and f.codigo = origem.fase_codigo
where not exists (
  select 1
  from public.planeamento_itens pi
  join public.fases fase_atual on fase_atual.id = pi.fase_id
  where fase_atual.obra_id = o.id
    and lower(trim(pi.codigo)) = lower(trim(origem.codigo))
);

do $$
declare
  v_obra_id uuid;
  v_aplicadas integer;
  v_divergentes integer;
begin
  select id into v_obra_id from public.obras where numero::text = '120';

  select count(*) into v_aplicadas
  from tmp_obra_120_planeamento_atual origem
  join public.fases f
    on f.obra_id = v_obra_id
   and f.codigo = origem.fase_codigo
  join public.planeamento_itens pi
    on pi.fase_id = f.id
   and lower(trim(pi.codigo)) = lower(trim(origem.codigo));

  if v_aplicadas <> 66 then
    raise exception 'Validação cancelada: esperadas 66 tarefas aplicadas; encontradas %.', v_aplicadas;
  end if;

  select count(*) into v_divergentes
  from tmp_obra_120_planeamento_atual origem
  join public.fases f
    on f.obra_id = v_obra_id
   and f.codigo = origem.fase_codigo
  join public.planeamento_itens pi
    on pi.fase_id = f.id
   and lower(trim(pi.codigo)) = lower(trim(origem.codigo))
  where pi.descricao is distinct from origem.descricao
     or pi.responsavel is distinct from origem.responsavel
     or pi.duracao_dias is distinct from origem.duracao_dias
     or pi.data_inicio_prevista is distinct from origem.data_inicio_prevista
     or pi.data_fim_prevista is distinct from origem.data_fim_prevista
     or pi.peso_percentual is distinct from origem.peso_percentual
     or pi.percentual_executado is distinct from origem.percentual_executado
     or pi.percentual_ponderado is distinct from origem.percentual_ponderado
     or pi.estado is distinct from origem.estado
     or pi.causa_atraso is distinct from origem.causa_atraso
     or pi.impacto is distinct from origem.impacto;

  if v_divergentes <> 0 then
    raise exception 'Validação cancelada: % tarefas ficaram divergentes da fonte.', v_divergentes;
  end if;
end
$$;

select
  66 as tarefas_fonte,
  count(*) filter (
    where exists (
      select 1
      from tmp_obra_120_planeamento_atual origem
      where lower(trim(origem.codigo)) = lower(trim(pi.codigo))
    )
  ) as tarefas_aplicadas,
  count(*) as total_tarefas_obra_120
from public.planeamento_itens pi
join public.fases f on f.id = pi.fase_id
join public.obras o on o.id = f.obra_id
where o.numero::text = '120';

commit;

