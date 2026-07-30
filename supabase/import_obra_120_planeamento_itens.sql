-- PRIMELINE — importação do planeamento detalhado da Obra 120
-- Fonte: OBRA 120 - PAINEL FINANCEIRO (25).xlsx / 5b_Planeamento_Efectivo
-- Importa 70 tarefas em planeamento_itens e 0 dependências.
-- Não altera planeamento_fases_resumo.
-- F02.3: início corrigido para 2026-02-19 por confirmação da utilizadora.
-- subempreitada_id permanece NULL: o ficheiro não fornece uma relação individual
-- inequívoca e a mesma subempreitada/empresa pode corresponder a várias tarefas.

begin;

-- Bloqueia a importação caso a auditoria preexistente deixe de estar limpa.
do $$
begin
  if exists (select 1 from public.fn_auditar_ciclos_planeamento()) then
    raise exception 'Importação cancelada: existem dependências circulares no planeamento.';
  end if;
end
$$;

create temporary table tmp_obra_120_planeamento (
  fase_codigo text not null,
  codigo text not null,
  descricao text not null,
  responsavel text,
  duracao_dias numeric not null,
  data_inicio_prevista date not null,
  data_fim_prevista date not null,
  data_fim_real date,
  peso_percentual numeric not null,
  percentual_executado numeric not null,
  percentual_ponderado numeric not null,
  estado text not null,
  causa_atraso text,
  impacto text
) on commit drop;

insert into tmp_obra_120_planeamento (
  fase_codigo, codigo, descricao, responsavel, duracao_dias,
  data_inicio_prevista, data_fim_prevista, data_fim_real,
  peso_percentual, percentual_executado, percentual_ponderado,
  estado, causa_atraso, impacto
)
values
    (
      'F01', 'F01.1', 'Montagem do estaleiro',
      'Primeline', 5, date '2026-02-11',
      date '2026-02-16', null,
      15, 100, 15, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F01', 'F01.2', 'Exploração e manutenção do estaleiro',
      'Primeline', 296, date '2026-03-16',
      date '2027-01-06', null,
      70, 51, 35.7, 'em_execucao',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F01', 'F01.3', 'Andaime para pintura de fachada',
      'Primeline', 38, date '2026-07-10',
      date '2026-08-17', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F01', 'F01.4', 'Desmontagem do estaleiro',
      'Primeline', 3, date '2027-01-06',
      date '2027-01-09', null,
      5, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.1', 'Desmontagem e remoção de louças sanitárias',
      'Primeline', 6, date '2026-02-12',
      date '2026-02-18', null,
      10, 100, 10, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.2', 'Desmontagem e remoção de cozinha',
      'Primeline', 6, date '2026-02-19',
      date '2026-02-25', null,
      8, 100, 8, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.3', 'Desmontagem e remoção de móveis de lavandaria',
      'Primeline', 6, date '2026-02-19',
      date '2026-02-25', null,
      5, 100, 5, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.4', 'Demolição de paredes de compartimentação interior',
      'Primeline', 6, date '2026-04-02',
      date '2026-04-08', null,
      15, 100, 15, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.5', 'Desmontagem de vãos de portas interiores em madeira',
      'Primeline', 1, date '2026-03-11',
      date '2026-03-12', null,
      10, 100, 10, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.6', 'Remoção de aquecedores existentes',
      'Primeline', 6, date '2026-03-19',
      date '2026-03-25', null,
      10, 100, 10, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.8', 'Desmontagem de armários embutidos',
      'Primeline', 6, date '2026-03-26',
      date '2026-04-01', null,
      5, 100, 5, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.9', 'Picagem de pavimento interior',
      'Primeline', 13, date '2026-04-09',
      date '2026-04-22', null,
      20, 100, 20, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F02', 'F02.10', 'Abertura de roços para infraestrutura',
      'Primeline', 6, date '2026-04-23',
      date '2026-04-29', null,
      17, 100, 17, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F03', 'F03.1', 'Remoção de pavimento em calçada e abertura de vala',
      'RADU', 18, date '2026-05-04',
      date '2026-05-22', null,
      30, 100, 30, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F03', 'F03.2', 'Transporte de terras sobrantes a vazadouro',
      'RADU', 18, date '2026-05-04',
      date '2026-05-22', null,
      20, 100, 20, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F03', 'F03.3', 'Fornecimento e aplicação de betão de limpeza',
      'Primeline', 7, date '2026-05-25',
      date '2026-06-01', null,
      15, 100, 15, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F03', 'F03.4', 'Fornecimento e aplicação de tela asfáltica',
      'Primeline', 24, date '2026-06-01',
      date '2026-06-25', null,
      15, 100, 15, 'concluido',
      'Atraso interno', 'Faturação'
    ),
    (
      'F03', 'F03.5', 'Manta geotextil, tubo geodreno, brita e massame (Flintkote)',
      'Primeline', 15, date '2026-06-25',
      date '2026-07-10', null,
      20, 100, 20, 'concluido',
      'Atraso interno', 'Faturação'
    ),
    (
      'F04', 'F04.1', 'Execução de paredes em alvenaria de tijolo',
      'Primeline', 14, date '2026-05-18',
      date '2026-06-01', null,
      15, 100, 15, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F04', 'F04.2', 'Forra em gesso cartonado (paredes exteriores)',
      'Primeline', 11, date '2026-06-29',
      date '2026-07-10', null,
      12, 90, 10.8, 'em_execucao',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F04', 'F04.3', 'Execução de reboco e barramento em paredes',
      'Primeline', 18, date '2026-07-20',
      date '2026-08-07', null,
      15, 80, 12, 'em_execucao',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F04', 'F04.4', 'Reparações pontuais de estuque e enchimentos',
      'Primeline', 4, date '2026-08-03',
      date '2026-08-07', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F04', 'F04.5', 'Fechamento de roços',
      'Primeline', 11, date '2026-06-01',
      date '2026-06-12', null,
      10, 100, 10, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F04', 'F04.6', 'Impermeabilização em betonilha do piso 0',
      'Primeline', 13, date '2026-04-23',
      date '2026-05-06', null,
      12, 100, 12, 'concluido',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F04', 'F04.7', 'Execução de betonilha (máx. 5cm) com manga plástica',
      'Primeline', 8, date '2026-05-07',
      date '2026-05-15', null,
      15, 85, 12.75, 'em_execucao',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F04', 'F04.8', 'Autonivelante como preparação para pavimento flutuante',
      'Primeline', 6, date '2026-07-13',
      date '2026-07-19', null,
      5, 0, 0, 'por_iniciar',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F04', 'F04.9', 'Demolição paredes/coberturas + estrutura Telha Sanduiche',
      'Primeline', 18, date '2026-04-23',
      date '2026-05-11', null,
      3, 20, 0.6, 'em_execucao',
      'Atraso interno', 'Prazo + Faturação'
    ),
    (
      'F04', 'F04.10', 'Placa OSB + XPS + Telha Sanduiche + Tecto falso hidrofugo',
      'Primeline', 14, date '2026-05-05',
      date '2026-05-19', null,
      3, 0, 0, 'por_iniciar',
      'Atraso interno', 'Prazo + Faturação'
    ),
    (
      'F05', 'F05.1', 'Execução de nova rede de águas quentes, frias e esgotos',
      'SERGIO', 19, date '2026-04-30',
      date '2026-05-19', null,
      15, 100, 15, 'concluido',
      null, null
    ),
    (
      'F05', 'F05.2', 'Instalação de elementos encastráveis (hidráulica)',
      'SERGIO', 7, date '2026-10-15',
      date '2026-10-22', null,
      5, 100, 5, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F05', 'F05.3', 'Instalação de sistema de aquecimento',
      'SERGIO', 7, date '2026-10-15',
      date '2026-10-22', null,
      5, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F05', 'F05.4', 'Instalação de louças e metais (hidráulica)',
      'SERGIO', 7, date '2026-10-15',
      date '2026-10-22', null,
      5, 15, 0.75, 'em_execucao',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F05', 'F05.5', 'Troca de cablagem existente por nova cablagem',
      'FLUXION', 7, date '2026-04-30',
      date '2026-05-07', null,
      20, 100, 20, 'concluido',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F05', 'F05.6', 'Instalação de aparelhagem elétrica',
      'FLUXION', 2, date '2026-06-15',
      date '2026-06-17', null,
      10, 0, 0, 'por_iniciar',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F05', 'F05.7', 'Instalação de acabamento elétrico',
      'FLUXION', 3, date '2026-10-26',
      date '2026-10-29', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F05', 'F05.8', 'Rede de Gás | Gas Network',
      'A adjudicar', 5, date '2026-04-30',
      date '2026-05-05', null,
      5, 0, 0, 'por_iniciar',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F05', 'F05.9', 'VMC — Pré-instalação',
      'SOLIUS', 7, date '2026-05-06',
      date '2026-05-13', null,
      8, 100, 8, 'concluido',
      'Indefinição DO', 'Faturação'
    ),
    (
      'F05', 'F05.10', 'VMC — Instalação AC',
      'FLUXION', 10, date '2026-10-26',
      date '2026-11-05', null,
      7, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F05', 'F05.11', 'Testes de tubagem e carga',
      'SERGIO / FLUXION', 6, date '2026-05-21',
      date '2026-05-27', null,
      10, 0, 0, 'por_iniciar',
      'Indefinição DO', 'Prazo + Custo + Faturação'
    ),
    (
      'F06', 'F06.1', 'Aplicação de pavimento flutuante',
      'Primeline', 19, date '2026-08-17',
      date '2026-09-05', null,
      22, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.2', 'Aplicação de pavimento cerâmico',
      'Primeline', 11, date '2026-09-07',
      date '2026-09-18', null,
      18, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.3', 'Aplicação de pavimento em pedra',
      'A confirmar', 6, date '2026-09-21',
      date '2026-09-27', null,
      9, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.4', 'Fornecimento e pintura de paredes (primário incluído)',
      'A adjudicar', 25, date '2026-09-28',
      date '2026-10-23', null,
      18, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.5', 'Assentamento de revestimento cerâmico',
      'Primeline', 10, date '2026-09-28',
      date '2026-10-08', null,
      14, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.6', 'Assentamento de revestimento em pedra',
      'A confirmar', 7, date '2026-10-08',
      date '2026-10-15', null,
      9, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.7', 'Rodapé SX156 HIGH HEELS — zona em piso madeira',
      'Primeline', 14, date '2026-11-26',
      date '2026-12-10', null,
      5, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F06', 'F06.8', 'Rodapé cerâmico — zona molhada',
      'Primeline', 14, date '2026-10-26',
      date '2026-11-09', null,
      5, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F07', 'F07.1', 'Tectos falsos em cozinha, lavandaria e WC''s',
      'Primeline', 11, date '2026-08-10',
      date '2026-08-21', null,
      20, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F07', 'F07.2', 'Sanca em gesso com iluminação LED',
      'Primeline', 8, date '2026-08-24',
      date '2026-09-01', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F07', 'F07.3', 'Pintura de tectos',
      'A adjudicar', 14, date '2026-10-26',
      date '2026-11-09', null,
      30, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F07', 'F07.4', 'Vigas falsas em sala de estar e cozinha',
      'Primeline', 7, date '2026-11-26',
      date '2026-12-03', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F07', 'F07.5', 'Fachada — Reconstrução de soco e barramento',
      'Primeline', 22, date '2026-06-18',
      date '2026-07-10', null,
      15, 30, 4.5, 'em_execucao',
      'Atraso interno', 'Prazo + Faturação'
    ),
    (
      'F07', 'F07.6', 'Fachada — Pintura exterior (primário + 2 demãos)',
      'A adjudicar', 14, date '2026-07-10',
      date '2026-07-24', null,
      15, 0, 0, 'por_iniciar',
      'Atraso interno', 'Prazo + Faturação'
    ),
    (
      'F08', 'F08.1', 'Vãos interiores',
      'A adjudicar', 6, date '2026-11-26',
      date '2026-12-02', null,
      20, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F08', 'F08.2', 'Roupeiros e moveis w.c.',
      'A adjudicar', 2, date '2026-12-02',
      date '2026-12-04', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F08', 'F08.3', 'Porta de correr (cozinha)',
      'A adjudicar', 4, date '2026-12-04',
      date '2026-12-08', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F08', 'F08.4', 'Lacagem das portas interiores existentes',
      'A adjudicar', 21, date '2026-11-05',
      date '2026-11-26', null,
      35, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F08', 'F08.5', 'Lacagem da porta de entrada',
      'A adjudicar', 6, date '2026-11-26',
      date '2026-12-02', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F09', 'F09.1', 'Desenho técnico das caixilharias',
      'A adjudicar', 21, date '2026-05-18',
      date '2026-06-08', null,
      10, 100, 10, 'concluido',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F09', 'F09.2', 'Produção de caixilharia CORTIZO',
      'A adjudicar', 76, date '2026-07-10',
      date '2026-09-24', null,
      40, 15, 6, 'em_execucao',
      null, null
    ),
    (
      'F09', 'F09.3', 'Retirada das caixilharias existentes',
      'Primeline', 3, date '2026-09-16',
      date '2026-09-19', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F09', 'F09.4', 'Recuperação de alvenaria ao redor',
      'Primeline', 7, date '2026-09-21',
      date '2026-09-28', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F09', 'F09.5', 'Instalação de soleira',
      'A adjudicar', 4, date '2026-09-24',
      date '2026-09-28', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F09', 'F09.6', 'Fornecimento e instalação de nova caixilharia CORTIZO',
      'A adjudicar', 10, date '2026-09-28',
      date '2026-10-08', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.1', 'Louças e metais — instalação final (sanitários)',
      'SERGIO', 7, date '2026-10-15',
      date '2026-10-22', null,
      25, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.2', 'Louças e metais — cozinha',
      'A adjudicar', 2, date '2026-10-06',
      date '2026-10-08', null,
      20, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.3', 'Radiadores — instalação final',
      'A adjudicar', 11, date '2026-11-05',
      date '2026-11-16', null,
      15, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.4', 'Diversos | Others (última fase)',
      'Primeline', 29, date '2026-12-10',
      date '2027-01-08', null,
      20, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.5', 'Limpeza final de obra',
      'Primeline', 4, date '2027-01-11',
      date '2027-01-15', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    ),
    (
      'F10', 'F10.6', 'Vistoria final e entrega ao Dono de Obra',
      'Primeline', 0, date '2027-01-15',
      date '2027-01-15', null,
      10, 0, 0, 'por_iniciar',
      'Sem desvio', 'Sem impacto'
    );

-- Pré-condições: exatamente 70 tarefas válidas, 10 fases e nenhuma tarefa anterior.
do $$
declare
  v_obra_id uuid;
  v_total_fases integer;
  v_total_existente integer;
begin
  select id into v_obra_id
  from public.obras
  where numero::text = '120';

  if v_obra_id is null then
    raise exception 'Importação cancelada: Obra 120 não encontrada.';
  end if;

  if (select count(*) from tmp_obra_120_planeamento) <> 70 then
    raise exception 'Importação cancelada: a origem não contém exatamente 70 tarefas.';
  end if;

  if exists (
    select 1
    from tmp_obra_120_planeamento
    where data_fim_prevista < data_inicio_prevista
       or duracao_dias <> data_fim_prevista - data_inicio_prevista
       or percentual_executado not between 0 and 100
  ) then
    raise exception 'Importação cancelada: datas, durações ou percentagens inválidas.';
  end if;

  select count(*) into v_total_fases
  from public.fases
  where obra_id = v_obra_id
    and codigo in ('F01','F02','F03','F04','F05','F06','F07','F08','F09','F10');

  if v_total_fases <> 10 then
    raise exception
      'Importação cancelada: esperadas 10 fases F01–F10; encontradas %.',
      v_total_fases;
  end if;

  select count(*) into v_total_existente
  from public.planeamento_itens pi
  join public.fases f on f.id = pi.fase_id
  where f.obra_id = v_obra_id;

  if v_total_existente <> 0 then
    raise exception
      'Importação cancelada: já existem % tarefas de planeamento na Obra 120.',
      v_total_existente;
  end if;
end
$$;

insert into public.planeamento_itens (
  fase_id,
  subempreitada_id,
  codigo,
  descricao,
  responsavel,
  duracao_dias,
  data_inicio_prevista,
  data_fim_prevista,
  data_fim_real,
  peso_percentual,
  percentual_executado,
  percentual_ponderado,
  estado,
  causa_atraso,
  impacto
)
select
  f.id,
  null,
  origem.codigo,
  origem.descricao,
  origem.responsavel,
  origem.duracao_dias,
  origem.data_inicio_prevista,
  origem.data_fim_prevista,
  origem.data_fim_real,
  origem.peso_percentual,
  origem.percentual_executado,
  origem.percentual_ponderado,
  origem.estado,
  origem.causa_atraso,
  origem.impacto
from tmp_obra_120_planeamento origem
join public.obras o on o.numero::text = '120'
join public.fases f
  on f.obra_id = o.id
 and f.codigo = origem.fase_codigo
order by origem.fase_codigo, origem.codigo;

-- Pós-condições: 70 tarefas, nenhuma dependência e nenhum ciclo.
do $$
declare
  v_obra_id uuid;
  v_total_itens integer;
  v_total_dependencias integer;
begin
  select id into v_obra_id
  from public.obras
  where numero::text = '120';

  select count(*) into v_total_itens
  from public.planeamento_itens pi
  join public.fases f on f.id = pi.fase_id
  where f.obra_id = v_obra_id;

  select count(*) into v_total_dependencias
  from public.planeamento_itens_dependencias d
  join public.planeamento_itens pi on pi.id = d.item_id
  join public.fases f on f.id = pi.fase_id
  where f.obra_id = v_obra_id;

  if v_total_itens <> 70 then
    raise exception
      'Importação cancelada: esperadas 70 tarefas após o INSERT; encontradas %.',
      v_total_itens;
  end if;

  if v_total_dependencias <> 0 then
    raise exception
      'Importação cancelada: esperadas 0 dependências; encontradas %.',
      v_total_dependencias;
  end if;

  if exists (select 1 from public.fn_auditar_ciclos_planeamento()) then
    raise exception 'Importação cancelada: a auditoria final encontrou ciclos.';
  end if;
end
$$;

commit;

-- Resultado final para conferência no SQL Editor.
select
  count(*) as tarefas_importadas,
  min(pi.data_inicio_prevista) as primeira_data,
  max(pi.data_fim_prevista) as ultima_data,
  count(*) filter (where pi.estado = 'concluido') as concluidas,
  count(*) filter (where pi.estado = 'em_execucao') as em_execucao,
  count(*) filter (where pi.estado = 'por_iniciar') as por_iniciar,
  count(*) filter (where pi.subempreitada_id is not null) as ligadas_subempreitada
from public.planeamento_itens pi
join public.fases f on f.id = pi.fase_id
join public.obras o on o.id = f.obra_id
where o.numero::text = '120';
