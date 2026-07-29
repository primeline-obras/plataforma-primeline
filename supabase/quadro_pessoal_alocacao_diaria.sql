-- Primeline | Evolução do quadro semanal para planeamento diário
-- Executar no SQL Editor ANTES de publicar o frontend correspondente.

alter table public.quadro_pessoal_alocacao
  add column if not exists data date,
  add column if not exists periodo text;

-- Preserva eventuais alocações semanais já existentes como dia inteiro na segunda-feira.
update public.quadro_pessoal_alocacao
set
  data = coalesce(data, semana_inicio),
  periodo = coalesce(periodo, 'dia_inteiro')
where data is null or periodo is null;

alter table public.quadro_pessoal_alocacao
  alter column data set default current_date,
  alter column data set not null,
  alter column periodo set default 'dia_inteiro',
  alter column periodo set not null;

alter table public.quadro_pessoal_alocacao
  drop constraint if exists quadro_pessoal_alocacao_periodo_check;

alter table public.quadro_pessoal_alocacao
  add constraint quadro_pessoal_alocacao_periodo_check
  check (periodo in ('manha', 'tarde', 'dia_inteiro'));

-- A antiga unicidade semanal impedia que a mesma pessoa trabalhasse em dias diferentes.
alter table public.quadro_pessoal_alocacao
  drop constraint if exists quadro_pessoal_alocacao_colaborador_id_semana_inicio_key;

create index if not exists quadro_pessoal_alocacao_data_idx
  on public.quadro_pessoal_alocacao (data);

create index if not exists quadro_pessoal_alocacao_colaborador_data_idx
  on public.quadro_pessoal_alocacao (colaborador_id, data);

create unique index if not exists quadro_pessoal_alocacao_colaborador_data_periodo_key
  on public.quadro_pessoal_alocacao (colaborador_id, data, periodo);
