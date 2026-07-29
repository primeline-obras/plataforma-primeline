-- Primeline | Correção para permitir vários dias na mesma semana
-- Executar no SQL Editor do Supabase.

alter table public.quadro_pessoal_alocacao
  drop constraint if exists quadro_pessoal_alocacao_colaborador_id_semana_inicio_key;

create unique index if not exists quadro_pessoal_alocacao_colaborador_data_periodo_key
  on public.quadro_pessoal_alocacao (colaborador_id, data, periodo);
